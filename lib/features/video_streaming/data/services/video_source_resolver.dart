import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../../../membership/domain/repositories/membership_repository.dart';
import '../../../membership/domain/entities/membership_entities.dart';
import '../../domain/entities/playback_entities.dart';

// DIAGNOSIS-ONLY (video playback permission-denied / callable 403):
// every Cloud Function call logs function name + payload summary +
// exception (code/message/details), then rethrows. No behavior change.
// Remove once the failing call is identified.
void _diagLogCallable(
  String function,
  String payloadSummary,
  Object error,
) {
  final extra = error is FirebaseFunctionsException
      ? ' code=${error.code} message=${error.message} details=${error.details}'
      : '';
  debugPrint(
    '[VIDEO-DIAG] callable function=$function payload=$payloadSummary '
    'errorType=${error.runtimeType} error=$error$extra',
  );
}

/// Classification of a signed video URL for the P1 playback root-cause log.
/// Pure and unit-testable: never contains the token value.
enum SignedVideoUrlType {
  /// HLS playlist (`.m3u8` in path or query) — needs hls.js on Flutter Web.
  hls,

  /// Direct progressive file (`.mp4` in path or query).
  mp4,

  /// Bunny HTML player page (`iframe.mediadelivery.net/embed/...`) — wrong
  /// URL type for a native `<video>` element, never playable by video_player.
  embed,

  /// Anything else (template misconfiguration surface).
  other,
}

/// Pure mapping of a signed URL string to its playback-relevant type.
/// Kept side-effect-free and top-level so the P1 contract is unit-testable.
SignedVideoUrlType classifySignedVideoUrl(String rawUrl) {
  final lower = rawUrl.toLowerCase();
  if (lower.contains('iframe.mediadelivery.net') || lower.contains('/embed/')) {
    return SignedVideoUrlType.embed;
  }
  if (lower.contains('.m3u8')) return SignedVideoUrlType.hls;
  if (lower.contains('.mp4')) return SignedVideoUrlType.mp4;
  return SignedVideoUrlType.other;
}

/// Masks secret-adjacent token values of a signed URL for safe logging:
/// every other character of the URL is preserved verbatim so the host,
/// path, extension and remaining params stay inspectable.
///
/// Two wire shapes are covered (see `generateBunnySignedUrl`):
/// - legacy query token (`?token=<sig>`);
/// - directory token carried in-path (`/bcdn_token=<sig>&token_path=...`),
///   whose signature would otherwise be logged verbatim by [logSignedVideoUrl].
/// The non-secret `token_path` scope and `expires` stay visible for diagnostics.
String maskSignedUrlToken(String rawUrl) {
  // In-path signature first (plain-string: the `&` separators live inside
  // the path, so query parsing must not touch them).
  var masked = rawUrl.replaceAllMapped(
    RegExp('bcdn_token=[^&\\s?#]+'),
    (_) => 'bcdn_token=MASKED',
  );
  final parsed = Uri.tryParse(masked);
  if (parsed == null || parsed.queryParameters['token'] == null) {
    return masked;
  }
  final query = Map<String, String>.from(parsed.queryParameters);
  // NOTE: the sentinel must stay URI-safe (no %-encoding) so the logged
  // line keeps the rest of the URL byte-identical.
  query['token'] = 'MASKED';
  return parsed.replace(queryParameters: query).toString();
}

/// P1 root-cause log: verbatim URL with ONLY the token masked, plus its
/// playback-relevant classification. Paste this line when reporting.
void logSignedVideoUrl(String rawUrl) {
  debugPrint(
    '[VIDEO-URL] verbatim=${maskSignedUrlToken(rawUrl)} '
    'type=${classifySignedVideoUrl(rawUrl).name}',
  );
}

abstract interface class VideoSourceGateway {
  Future<List<VideoResource>> loadResources(String lectureId);

  Future<ResolvedVideoSource> resolve({
    required VideoResource resource,
    required VideoQuality quality,
    String? subjectId,
    // Route lecture asserting the authorization identity. The server
    // verifies it (fail-closed) and uses it — not the video file — for
    // per-lecture checks. Null preserves the legacy (video-only) lookup.
    String? lectureId,
  });
}

/// FINAL_DECISIONS §12 self-read snapshot for UI niceties.
class WatchWindowSnapshot {
  final bool active;
  final String? activeLectureId;
  final DateTime? expiresAt;

  const WatchWindowSnapshot({
    required this.active,
    this.activeLectureId,
    this.expiresAt,
  });
}

abstract interface class WatchWindowGateway {
  Future<WatchWindowSnapshot> load();
}

/// Callable-backed §12 window reader (getVideoWatchWindow). The callable
/// itself returns active:false for any non-Center-Free caller.
class CallableWatchWindowGateway implements WatchWindowGateway {
  final FirebaseFunctions functions;

  CallableWatchWindowGateway({FirebaseFunctions? functions})
      : functions = functions ?? FirebaseFunctions.instance;

  @override
  Future<WatchWindowSnapshot> load() async {
    try {
      final response =
          await functions.httpsCallable('getVideoWatchWindow').call();
      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['active'] != true) {
        return const WatchWindowSnapshot(active: false);
      }
      final expiresMs = (data['windowExpiresAtMs'] as num?)?.toInt();
      return WatchWindowSnapshot(
        active: true,
        activeLectureId: data['activeLectureId'] as String?,
        expiresAt: expiresMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(expiresMs),
      );
    } catch (error) {
      _diagLogCallable('getVideoWatchWindow', '{}', error);
      rethrow;
    }
  }
}

/// Pure, unit-testable projection of the server `previewAudience`
/// discriminator. Accepts only the two contract literals (defined in
/// playback_entities); anything else degrades to the legacy generic wall —
/// never fabricated, never authorization logic.
String? parsePreviewAudience(Object? value) {
  if (value == kPreviewAudienceGuest) return kPreviewAudienceGuest;
  if (value == kPreviewAudienceCenter) return kPreviewAudienceCenter;
  return null;
}

/// Phase 1 Guest preview contract reader (FINAL_DECISIONS §11).
/// Canonical key is `guestPreview`; the legacy `publicFreePreview` key is
/// honored only as a bounded fallback until the backend compatibility alias
/// is removed after full validation.
/// TODO(PHASE2C): drop the legacy key once backend cleanup lands.
Map<String, dynamic>? guestPreviewFromResponse(Map<String, dynamic> data) {
  if (data['guestPreview'] != null) {
    return Map<String, dynamic>.from(data['guestPreview'] as Map);
  }
  if (data['publicFreePreview'] != null) {
    return Map<String, dynamic>.from(data['publicFreePreview'] as Map);
  }
  return null;
}

/// Process-wide memo of the resolved device identity: the value is a
/// per-device constant, so repeat issuances (startup resolve + session
/// adoption + prefetch + silent refresh) must not re-hit Secure Storage
/// and the DeviceInfo platform channel every time. Explicit `override`
/// callers (tests, injected identities) always bypass the memo.
String? _memoizedVideoDeviceId;

/// Shared local device-identity resolution (stable hardware id when
/// available, generated install id otherwise, cached in Secure Storage).
/// Identity material only — never authorization proof.
Future<String> resolveLocalDeviceId({
  Future<String> Function()? override,
  FlutterSecureStorage? secureStorage,
}) async {
  if (override != null) return override();
  final memoized = _memoizedVideoDeviceId;
  if (memoized != null && memoized.isNotEmpty) return memoized;
  const deviceIdKey = 'video_device_id';
  final storage = secureStorage ?? const FlutterSecureStorage();
  final existing = await storage.read(key: deviceIdKey);
  if (existing != null && existing.isNotEmpty) {
    _memoizedVideoDeviceId = existing;
    return existing;
  }

  String? hardwareId;
  // dart:io Platform is unavailable on web — guard it so web callers fall
  // through to a generated install id instead of throwing UnsupportedError
  // (which surfaced as a generic player-init failure on web builds).
  if (!kIsWeb) {
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        hardwareId = (await plugin.androidInfo).id;
      } else if (Platform.isIOS) {
        hardwareId = (await plugin.iosInfo).identifierForVendor;
      }
    } catch (_) {}
  }

  String created;
  if (hardwareId != null && hardwareId.isNotEmpty) {
    // Deterministically generate a UUIDv5, then force the version nibble to '4'
    // so it passes strict backend UUIDv4 regex checks.
    final v5 = const Uuid().v5(Namespace.url.value, hardwareId);
    created = v5.replaceRange(14, 15, '4');
  } else {
    created = const Uuid().v4();
  }

  await storage.write(key: deviceIdKey, value: created);
  _memoizedVideoDeviceId = created;
  return created;
}

class VideoSourceResolver implements VideoSourceGateway {
  final FirebaseFunctions functions;
  final Future<String> Function()? deviceIdProvider;

  const VideoSourceResolver({required this.functions, this.deviceIdProvider});

  @override
  Future<List<VideoResource>> loadResources(String lectureId) async {
    final stopwatch = Stopwatch()..start();
    try {
      final response =
          await functions.httpsCallable('getLectureResources').call({
        'lectureId': lectureId,
      });
      final data = Map<String, dynamic>.from(response.data as Map);
    // FINAL_DECISIONS §11: server-computed Guest per-lecture preview gate.
    final guestPreview = guestPreviewFromResponse(data);
    final raw = (data['resources'] as List<dynamic>? ?? const <dynamic>[]);
    final parsed = raw.map((item) {
      final resource = VideoResource.fromCallablePayload(
        Map<String, dynamic>.from(item as Map),
      );
      // Guest preview is per-STUDENT+lecture state computed by the callable,
      // not a property of the resource document — stamped here.
      return VideoResource(
        id: resource.id,
        title: resource.title,
        resourceType: resource.resourceType,
        bunnyVideoId: resource.bunnyVideoId,
        thumbnailUrl: resource.thumbnailUrl,
        storageProvider: resource.storageProvider,
        thumbnailProvider: resource.thumbnailProvider,
        previewUrl: resource.previewUrl,
        duration: resource.duration,
        displayOrder: resource.displayOrder,
        isGuestPreview: guestPreview != null,
        guestPreviewSeconds:
            (guestPreview?['previewLimitSeconds'] as num?)?.toInt(),
        previewAudience:
            parsePreviewAudience(guestPreview?['previewAudience']),
      );
    }).toList();
      debugPrint(
        '[VIDEO-TIMING] loadResources lectureId=$lectureId '
        'count=${parsed.length} elapsedMs=${stopwatch.elapsedMilliseconds}',
      );
      return parsed;
    } catch (error) {
      _diagLogCallable(
          'getLectureResources', 'lectureId=$lectureId', error);
      rethrow;
    }
  }

  @override
  Future<ResolvedVideoSource> resolve({
    required VideoResource resource,
    required VideoQuality quality,
    String? subjectId,
    String? lectureId,
  }) async {
    final bunnyId = resource.bunnyVideoId;
    if (!resource.isVideo || bunnyId == null) {
      throw const VideoSourceException('مصدر الفيديو غير متاح لهذه المحاضرة.');
    }
    // VIDEO-ID-ONLY: URLs/embed links are invalid even if they contain a
    // GUID segment. Fail closed before any backend call so a pasted URL
    // can never play.
    if (!VideoResource.isValidBunnyVideoId(bunnyId)) {
      throw const VideoSourceException(
        'معرّف الفيديو غير صالح — الصق الـ Video ID فقط وليس رابط المشاهدة.',
      );
    }

    final payload = <String, dynamic>{'videoId': bunnyId};
    if (quality.backendValue != null) payload['quality'] = quality.backendValue;
    if (subjectId != null) payload['subjectId'] = subjectId;
    // Identity fix: assert the route lecture so the server authorizes the
    // lecture the student actually opened (fail-closed on mismatch).
    if (lectureId != null && lectureId.isNotEmpty) {
      payload['lectureId'] = lectureId;
    }
    // Web receives the signed HLS playlist (same as mobile). On Flutter Web
    // the video_player_web_hls backend attaches hls.js to the <video>
    // element and feeds it this URL unmodified — no MP4 rewrite, so the
    // token always covers the exact requested path.
    payload['deviceId'] = await _deviceId();

    final stopwatch = Stopwatch()..start();
    try {
      final response = await functions
          .httpsCallable('generateBunnySignedUrl')
          .call(payload);
      debugPrint(
        '[VIDEO-TIMING] generateBunnySignedUrl videoId=$bunnyId lectureId=$lectureId '
        'elapsedMs=${stopwatch.elapsedMilliseconds}',
      );
      final data = Map<String, dynamic>.from(response.data as Map);
      final rawUrl = data['url'] as String?;
      if (rawUrl == null || Uri.tryParse(rawUrl) == null) {
        throw const VideoSourceException('تعذر الحصول على مصدر فيديو صالح.');
      }
      // P1 root-cause line: verbatim URL, token masked, type classified.
      logSignedVideoUrl(rawUrl);
      if (classifySignedVideoUrl(rawUrl) == SignedVideoUrlType.embed) {
        throw const VideoSourceException(
          'Video source is an embed page, not a playable file. '
          'Please contact support. [urlType=embed]',
        );
      }
      final selected = VideoQuality.fromBackend(data['quality'] as String?);
      final expiresAt = _dateFromEpoch(data['expiresAt']);
      final sessionToken = data['sessionToken'] as String?;
      final sessionPosition =
          (data['positionSeconds'] as num?)?.toInt();
      final heartbeatMs = (data['heartbeatIntervalMs'] as num?)?.toInt();
      // Guest structural preview verdict (FINAL_DECISIONS §11): present
      // only on Guest issuance; the controller enforces it exactly like
      // the listing-stamped cap. Never fabricated client-side.
      final previewLimitSeconds =
          (data['previewLimitSeconds'] as num?)?.toInt();
      return ResolvedVideoSource(
        url: Uri.parse(rawUrl),
        expiresAt: expiresAt,
        selectedQuality: selected,
        sessionToken: (sessionToken != null && sessionToken.isNotEmpty)
            ? sessionToken
            : null,
        sessionPositionSeconds: sessionPosition,
        sessionTakeover: data['takeover'] == true,
        heartbeatIntervalMs: heartbeatMs,
        previewLimitSeconds: previewLimitSeconds,
        previewAudience: parsePreviewAudience(data['previewAudience']),
      );
    } on FirebaseFunctionsException catch (error) {
      final keys = payload.keys.join(',');
      _diagLogCallable('generateBunnySignedUrl',
          'keys=[$keys] videoId=$bunnyId subjectId=$subjectId lectureId=$lectureId quality=${quality.backendValue}',
          error);
      throw classifyVideoSourceError(error.code, error.message, error.details);
    } catch (error) {
      if (error is VideoSourceException) rethrow;
      final keys = payload.keys.join(',');
      _diagLogCallable('generateBunnySignedUrl',
          'keys=[$keys] videoId=$bunnyId subjectId=$subjectId lectureId=$lectureId', error);
      throw VideoSourceException(
        'تعذر تحميل الفيديو. تحقق من الاتصال ثم حاول مرة أخرى.',
      );
    }
  }

  Future<String> _deviceId() =>
      resolveLocalDeviceId(override: deviceIdProvider);

  DateTime _dateFromEpoch(Object? value) {
    final seconds = value is num ? value.toInt() : 0;
    return seconds > 0
        ? DateTime.fromMillisecondsSinceEpoch(seconds * 1000)
        : DateTime.now().add(const Duration(minutes: 4));
  }
}

class VideoSourceException implements Exception {
  final String message;

  const VideoSourceException(this.message);

  @override
  String toString() => message;
}

/// Terminal session failure: the server no longer recognizes this device as
/// the session owner (takeover, expiry, revocation). Never retried
/// automatically — continuation requires explicit user intent (a new begin,
/// which the server alone decides).
class PlaybackSessionInvalidatedException implements Exception {
  final String message;

  const PlaybackSessionInvalidatedException([this.message = '']);
}

/// Transport-level failure (deadline, unavailable): safe to retry on a
/// bounded schedule. Never treated as invalidation.
class PlaybackSessionTransportException implements Exception {
  final String message;

  const PlaybackSessionTransportException([this.message = '']);
}

/// Data-layer contract for Max Subject playback sessions. All Firebase
/// callable access stays here; widgets and the controller never call
/// Functions directly. `subjectId` is mandatory on every operation and is
/// never inferred from global state.
abstract interface class PlaybackSessionGateway {
  Future<PlaybackSession> begin({
    required String studentId,
    required String subjectId,
    required String deviceId,
    String? lectureId,
    String? videoId,
  });

  Future<HeartbeatResult> heartbeat({
    required String studentId,
    required String subjectId,
    required String deviceId,
    required String sessionToken,
    required Duration position,
  });
}

class CallablePlaybackSessionGateway implements PlaybackSessionGateway {
  final FirebaseFunctions functions;
  final Future<String> Function()? deviceIdProvider;

  const CallablePlaybackSessionGateway({
    required this.functions,
    this.deviceIdProvider,
  });

  Future<String> deviceId() =>
      resolveLocalDeviceId(override: deviceIdProvider);

  @override
  Future<PlaybackSession> begin({
    required String studentId,
    required String subjectId,
    required String deviceId,
    String? lectureId,
    String? videoId,
  }) async {
    try {
      final payload = <String, dynamic>{
        'studentId': studentId,
        'subjectId': subjectId,
        'deviceId': deviceId,
      };
      if (lectureId != null) payload['lectureId'] = lectureId;
      if (videoId != null) payload['videoId'] = videoId;
      final response = await functions
          .httpsCallable('beginOrTakeoverPlayback')
          .call(payload);
      final data = Map<String, dynamic>.from(response.data as Map);
      final session = PlaybackSession.fromBeginPayload(
        subjectId: subjectId,
        lectureId: lectureId,
        videoId: videoId,
        data: data,
      );
      if (session == null) {
        throw const PlaybackSessionInvalidatedException();
      }
      return session;
    } on FirebaseFunctionsException catch (error) {
      _diagLogCallable('beginOrTakeoverPlayback',
          'studentId=$studentId subjectId=$subjectId lectureId=$lectureId videoId=$videoId',
          error);
      throw _mapSessionError(error);
    } catch (error) {
      _diagLogCallable('beginOrTakeoverPlayback',
          'studentId=$studentId subjectId=$subjectId lectureId=$lectureId videoId=$videoId',
          error);
      rethrow;
    }
  }

  @override
  Future<HeartbeatResult> heartbeat({
    required String studentId,
    required String subjectId,
    required String deviceId,
    required String sessionToken,
    required Duration position,
  }) async {
    try {
      final response = await functions
          .httpsCallable('heartbeatPlayback')
          .call({
        'studentId': studentId,
        'subjectId': subjectId,
        'deviceId': deviceId,
        'sessionToken': sessionToken,
        'positionSeconds': position.inSeconds,
      });
      final data = Map<String, dynamic>.from(response.data as Map);
      return HeartbeatResult.fromPayload(data);
    } on FirebaseFunctionsException catch (error) {
      _diagLogCallable('heartbeatPlayback',
          'studentId=$studentId subjectId=$subjectId sessionTokenLen=${sessionToken.length} positionS=${position.inSeconds}',
          error);
      throw _mapSessionError(error);
    } catch (error) {
      _diagLogCallable('heartbeatPlayback',
          'studentId=$studentId subjectId=$subjectId', error);
      rethrow;
    }
  }

  Exception _mapSessionError(FirebaseFunctionsException error) =>
      mapSessionGatewayError(error.code, error.message);
}

/// Pure mapping of session-callable failures. Terminal authorization
/// verdicts invalidate; everything else is a retriable transport fault.
/// Top-level and side-effect-free so it is unit-testable.
Exception mapSessionGatewayError(String code, String? message) {
  switch (code) {
    case 'permission-denied':
    case 'unauthenticated':
    case 'not-found':
    case 'failed-precondition':
      return PlaybackSessionInvalidatedException(message ?? '');
    default:
      return PlaybackSessionTransportException(message ?? '');
  }
}

/// FINAL_DECISIONS §12: generateBunnySignedUrl refused to start a different
/// video while the caller's Center Free rolling 24-hour window is active.
/// Carries the server-provided expiry so the UI can show a live countdown
/// and the upgrade CTA BEFORE any playback is attempted.
class FreeWindowBlockedException extends VideoSourceException {
  final int? windowExpiresAtMs;
  final String? activeLectureId;

  /// Watch-window length in hours echoed by the server
  /// (`video.rolling_window.hours`, defaults to 24).
  final int windowHours;

  const FreeWindowBlockedException({
    required String message,
    this.windowExpiresAtMs,
    this.activeLectureId,
    this.windowHours = 24,
  }) : super(message);
}

/// Stable sentinel echoed by functions/src/index.ts (generateBunnySignedUrl):
/// the device resolved to the Guest tier for this Subject (unauthorized
/// device / allowance exhausted) and the lecture has no Guest preview, so
/// no signed URL is issued. Pinned verbatim — the mapping below depends on
/// this exact string; if the backend rewords it, this falls back to the
/// generic permission-denied message (safe default, never a wrong wall).
const String kGuestPreviewNotEnabledMessage =
    'Guest preview is not enabled for this lecture.';

/// Stable sentinel echoed by functions/src/index.ts
/// (FREE_WINDOW_BLOCKED_MESSAGE) and mapped in failure.dart.
const String kFreeWindowBlockedMessage =
    'A Center Free 24-hour video window is already active for another video.';

/// The current device is not authorized for this Subject (Guest tier with
/// no preview). Routing-only: the controller surfaces the device wall
/// (contact the administration — never an upgrade CTA, since upgrading
/// cannot authorize a device). Never fabricated — only produced by the
/// exact server sentinel above.
class DeviceNotAuthorizedException extends VideoSourceException {
  const DeviceNotAuthorizedException([super.message = '']);
}

/// Pure mapping of a callable failure into the typed video-source
/// exception hierarchy. Kept side-effect-free and top-level so the §12
/// contract is unit-testable without Firebase platform channels.
VideoSourceException classifyVideoSourceError(
  String code,
  String? message,
  Object? details,
) {
  if (message?.trim() == kFreeWindowBlockedMessage) {
    int? expiresAtMs;
    String? activeLectureId;
    int windowHours = 24;
    if (details is Map) {
      final rawExpiry = details['windowExpiresAtMs'];
      if (rawExpiry is num) expiresAtMs = rawExpiry.toInt();
      final rawLecture = details['activeLectureId'];
      if (rawLecture is String) activeLectureId = rawLecture;
      final rawHours = details['windowHours'];
      if (rawHours is num && rawHours.toInt() > 0) {
        windowHours = rawHours.toInt();
      }
    }
    return FreeWindowBlockedException(
      message: windowHours == 24
          ? 'باقتك المجانية تسمح بمشاهدة فيديو واحد كل ٢٤ ساعة.'
          : 'باقتك تسمح بمشاهدة فيديو واحد كل $windowHours ساعة.',
      windowExpiresAtMs: expiresAtMs,
      activeLectureId: activeLectureId,
      windowHours: windowHours,
    );
  }
  // Device-blocked issuance (Guest tier, no preview for this lecture):
  // exact server sentinel only — anything else keeps the generic mapping.
  if (code == 'permission-denied' &&
      message?.trim() == kGuestPreviewNotEnabledMessage) {
    return const DeviceNotAuthorizedException(
      'جهازك الحالي غير مصرح له بمشاهدة هذا المحتوى — تواصل مع الإدارة لتفعيل الجهاز.',
    );
  }
  return VideoSourceException(_staticMessageFor(code));
}

String _staticMessageFor(String code) {
  return switch (code) {
    'permission-denied' =>
      'You do not have permission to watch this video, or your subscription has ended.',
    'unauthenticated' => 'Please sign in to watch this video.',
    'not-found' => 'This video is currently unavailable.',
    'failed-precondition' =>
      'Video playback is not configured. Please contact support.',
    'resource-exhausted' => 'You have reached the viewing limit. Please try again later.',
    'deadline-exceeded' ||
    'unavailable' => 'Could not reach the video service. Please try again.',
    _ => 'Could not load the video. Please try again.',
  };
}

abstract interface class VideoEntitlementGateway {
  Future<VideoEntitlement> resolve({
    required String userId,
    required String subjectId,
  });
}

class VideoEntitlementService implements VideoEntitlementGateway {
  final MembershipRepository membershipRepository;

  const VideoEntitlementService({required this.membershipRepository});

  @override
  Future<VideoEntitlement> resolve({
    required String userId,
    required String subjectId,
  }) async {
    debugPrint(
        '[VIDEO-DIAG] entitlement resolve start userId=$userId subjectId=$subjectId');
    late final MembershipSubscription? subscription;
    try {
      subscription = await membershipRepository.getSubscription(
        studentId: userId,
        subjectId: subjectId,
      );
    } catch (error) {
      debugPrint(
          '[VIDEO-DIAG] entitlement getSubscription FAILED userId=$userId subjectId=$subjectId errorType=${error.runtimeType} error=$error');
      rethrow;
    }
    // Null end_date = open-ended academic period (the backend backfills
    // it when the period ends): valid, matching EntitlementResolver and
    // the rules mirror. isWithinAcademicTerm already treats it as active.
    if (subscription == null ||
        subscription.status != 'active' ||
        !subscription.isWithinAcademicTerm) {
      return const VideoEntitlement.denied(
        'Your subscription is not active in the current academic term.',
        denialKind: VideoDenialKind.subscriptionInactive,
      );
    }
    late final List<PlanFeature> features;
    try {
      features = await membershipRepository.getPlanFeatures(
        planId: subscription.planId,
      );
    } catch (error) {
      debugPrint(
          '[VIDEO-DIAG] entitlement getPlanFeatures FAILED planId=${subscription.planId} userId=$userId subjectId=$subjectId errorType=${error.runtimeType} error=$error');
      rethrow;
    }
    final access = features
        .where((item) => item.featureKey == 'video.access')
        .firstOrNull;
    if (access?.enabled != true) {
      return const VideoEntitlement.denied(
        'Video is not included in your current subscription.',
        denialKind: VideoDenialKind.planUpsell,
      );
    }
    final allowedQualities = <VideoQuality>{};
    for (final feature in features) {
      if (!feature.enabled ||
          !feature.featureKey.startsWith('video.quality.')) {
        continue;
      }
      if (feature.featureKey == 'video.quality.max') {
        final cap = VideoQuality.fromBackend(feature.featureValue);
        if (cap != VideoQuality.auto) {
          allowedQualities.addAll(
            VideoQuality.values.where(
              (quality) =>
                  quality != VideoQuality.auto && quality.rank <= cap.rank,
            ),
          );
        }
        continue;
      }
      final quality = VideoQuality.fromFeatureKey(feature.featureKey);
      if (quality != VideoQuality.auto) allowedQualities.add(quality);
    }
    if (allowedQualities.isEmpty) {
      return const VideoEntitlement.denied(
        'No video quality is configured for this subscription.',
        denialKind: VideoDenialKind.configuration,
      );
    }
    return VideoEntitlement(allowed: true, allowedQualities: allowedQualities);
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
