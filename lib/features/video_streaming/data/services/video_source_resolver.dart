import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../../../membership/domain/repositories/membership_repository.dart';
import '../../domain/entities/playback_entities.dart';

abstract interface class VideoSourceGateway {
  Future<List<VideoResource>> loadResources(String lectureId);

  Future<ResolvedVideoSource> resolve({
    required VideoResource resource,
    required VideoQuality quality,
    String? subjectId,
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
    final response =
        await functions.httpsCallable('getVideoWatchWindow').call();
    final data = Map<String, dynamic>.from(response.data as Map);
    if (data['active'] != true) return const WatchWindowSnapshot(active: false);
    final expiresMs = (data['windowExpiresAtMs'] as num?)?.toInt();
    return WatchWindowSnapshot(
      active: true,
      activeLectureId: data['activeLectureId'] as String?,
      expiresAt: expiresMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(expiresMs),
    );
  }
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

/// Shared local device-identity resolution (stable hardware id when
/// available, generated install id otherwise, cached in Secure Storage).
/// Identity material only — never authorization proof.
Future<String> resolveLocalDeviceId({
  Future<String> Function()? override,
  FlutterSecureStorage? secureStorage,
}) async {
  const deviceIdKey = 'video_device_id';
  final storage = secureStorage ?? const FlutterSecureStorage();
  if (override != null) return override();
  final existing = await storage.read(key: deviceIdKey);
  if (existing != null && existing.isNotEmpty) return existing;

  String? hardwareId;
  try {
    final plugin = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      hardwareId = (await plugin.androidInfo).id;
    } else if (Platform.isIOS) {
      hardwareId = (await plugin.iosInfo).identifierForVendor;
    }
  } catch (_) {}

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
  return created;
}

class VideoSourceResolver implements VideoSourceGateway {
  final FirebaseFunctions functions;
  final Future<String> Function()? deviceIdProvider;

  const VideoSourceResolver({required this.functions, this.deviceIdProvider});

  @override
  Future<List<VideoResource>> loadResources(String lectureId) async {
    final response = await functions.httpsCallable('getLectureResources').call({
      'lectureId': lectureId,
    });
    final data = Map<String, dynamic>.from(response.data as Map);
    // FINAL_DECISIONS §11: server-computed Guest per-lecture preview gate.
    final guestPreview = guestPreviewFromResponse(data);
    final raw = (data['resources'] as List<dynamic>? ?? const <dynamic>[]);
    return raw.map((item) {
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
        duration: resource.duration,
        isGuestPreview: guestPreview != null,
        guestPreviewSeconds:
            (guestPreview?['previewLimitSeconds'] as num?)?.toInt(),
      );
    }).toList();
  }

  @override
  Future<ResolvedVideoSource> resolve({
    required VideoResource resource,
    required VideoQuality quality,
    String? subjectId,
  }) async {
    final bunnyId = resource.bunnyVideoId;
    if (!resource.isVideo || bunnyId == null) {
      throw const VideoSourceException('مصدر الفيديو غير متاح لهذه المحاضرة.');
    }

    final payload = <String, dynamic>{'videoId': bunnyId};
    if (quality.backendValue != null) payload['quality'] = quality.backendValue;
    if (subjectId != null) payload['subjectId'] = subjectId;
    payload['deviceId'] = await _deviceId();

    try {
      final response = await functions
          .httpsCallable('generateBunnySignedUrl')
          .call(payload);
      final data = Map<String, dynamic>.from(response.data as Map);
      final rawUrl = data['url'] as String?;
      if (rawUrl == null || Uri.tryParse(rawUrl) == null) {
        throw const VideoSourceException('تعذر الحصول على مصدر فيديو صالح.');
      }
      final selected = VideoQuality.fromBackend(data['quality'] as String?);
      final expiresAt = _dateFromEpoch(data['expiresAt']);
      final sessionToken = data['sessionToken'] as String?;
      final sessionPosition =
          (data['positionSeconds'] as num?)?.toInt();
      final heartbeatMs = (data['heartbeatIntervalMs'] as num?)?.toInt();
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
      );
    } on FirebaseFunctionsException catch (error) {
      throw classifyVideoSourceError(error.code, error.message, error.details);
    } catch (error) {
      if (error is VideoSourceException) rethrow;
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
      throw _mapSessionError(error);
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
      throw _mapSessionError(error);
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

/// Stable sentinel echoed by functions/src/index.ts
/// (FREE_WINDOW_BLOCKED_MESSAGE) and mapped in failure.dart.
const String kFreeWindowBlockedMessage =
    'A Center Free 24-hour video window is already active for another video.';

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
  return VideoSourceException(_staticMessageFor(code));
}

String _staticMessageFor(String code) {
  return switch (code) {
    'permission-denied' =>
      'لا تملك صلاحية مشاهدة هذا الفيديو أو انتهى اشتراكك.',
    'unauthenticated' => 'يجب تسجيل الدخول لمشاهدة هذا الفيديو.',
    'not-found' => 'الفيديو غير متاح حاليًا.',
    'deadline-exceeded' ||
    'unavailable' => 'تعذر الاتصال بخدمة الفيديو. حاول مرة أخرى.',
    _ => 'تعذر تحميل الفيديو. حاول مرة أخرى.',
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
    final subscription = await membershipRepository.getSubscription(
      studentId: userId,
      subjectId: subjectId,
    );
    if (subscription == null ||
        subscription.status != 'active' ||
        subscription.endDate == null ||
        !subscription.isWithinAcademicTerm) {
      return const VideoEntitlement.denied(
        'الاشتراك غير متاح ضمن الفترة الأكاديمية الحالية.',
      );
    }
    final features = await membershipRepository.getPlanFeatures(
      planId: subscription.planId,
    );
    final access = features
        .where((item) => item.featureKey == 'video.access')
        .firstOrNull;
    if (access?.enabled != true) {
      return const VideoEntitlement.denied(
        'الفيديو غير متاح ضمن اشتراكك الحالي.',
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
        'لم يتم إعداد أي جودة فيديو لهذا الاشتراك.',
      );
    }
    return VideoEntitlement(allowed: true, allowedQualities: allowedQualities);
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
