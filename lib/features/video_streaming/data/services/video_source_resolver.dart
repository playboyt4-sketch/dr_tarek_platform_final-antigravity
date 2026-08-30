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

class VideoSourceResolver implements VideoSourceGateway {
  static const _deviceIdKey = 'video_device_id';
  static const _secureStorage = FlutterSecureStorage();
  static const _uuid = Uuid();

  final FirebaseFunctions functions;
  final Future<String> Function()? deviceIdProvider;

  const VideoSourceResolver({required this.functions, this.deviceIdProvider});

  @override
  Future<List<VideoResource>> loadResources(String lectureId) async {
    final response = await functions.httpsCallable('getLectureResources').call({
      'lectureId': lectureId,
    });
    final data = Map<String, dynamic>.from(response.data as Map);
    // FINAL_DECISIONS §11: server-computed Public Free per-lecture gate.
    final publicFree = data['publicFreePreview'] == null
        ? null
        : Map<String, dynamic>.from(data['publicFreePreview'] as Map);
    final raw = (data['resources'] as List<dynamic>? ?? const <dynamic>[]);
    return raw.map((item) {
      final resource = VideoResource.fromCallablePayload(
        Map<String, dynamic>.from(item as Map),
      );
      // Public Free is per-STUDENT+lecture state computed by the callable,
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
        isPublicFreePreview: publicFree != null,
        publicFreePreviewSeconds:
            (publicFree?['previewLimitSeconds'] as num?)?.toInt(),
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
      return ResolvedVideoSource(
        url: Uri.parse(rawUrl),
        expiresAt: expiresAt,
        selectedQuality: selected,
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

  Future<String> _deviceId() async {
    final custom = deviceIdProvider;
    if (custom != null) return custom();
    final existing = await _secureStorage.read(key: _deviceIdKey);
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
      final v5 = _uuid.v5(Namespace.url.value, hardwareId);
      created = v5.replaceRange(14, 15, '4');
    } else {
      created = _uuid.v4();
    }
    
    await _secureStorage.write(key: _deviceIdKey, value: created);
    return created;
  }

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

/// FINAL_DECISIONS §12: generateBunnySignedUrl refused to start a different
/// video while the caller's Center Free rolling 24-hour window is active.
/// Carries the server-provided expiry so the UI can show a live countdown
/// and the upgrade CTA BEFORE any playback is attempted.
class CenterFreeWindowBlockedException extends VideoSourceException {
  final int? windowExpiresAtMs;
  final String? activeLectureId;

  const CenterFreeWindowBlockedException({
    required String message,
    this.windowExpiresAtMs,
    this.activeLectureId,
  }) : super(message);
}

/// Stable sentinel echoed by functions/src/index.ts
/// (CENTER_FREE_WINDOW_BLOCKED_MESSAGE) and mapped in failure.dart.
const String kCenterFreeWindowBlockedMessage =
    'A Center Free 24-hour video window is already active for another video.';

/// Pure mapping of a callable failure into the typed video-source
/// exception hierarchy. Kept side-effect-free and top-level so the §12
/// contract is unit-testable without Firebase platform channels.
VideoSourceException classifyVideoSourceError(
  String code,
  String? message,
  Object? details,
) {
  if (message?.trim() == kCenterFreeWindowBlockedMessage) {
    int? expiresAtMs;
    String? activeLectureId;
    if (details is Map) {
      final rawExpiry = details['windowExpiresAtMs'];
      if (rawExpiry is num) expiresAtMs = rawExpiry.toInt();
      final rawLecture = details['activeLectureId'];
      if (rawLecture is String) activeLectureId = rawLecture;
    }
    return CenterFreeWindowBlockedException(
      message: 'باقتك المجانية تسمح بمشاهدة فيديو واحد كل ٢٤ ساعة.',
      windowExpiresAtMs: expiresAtMs,
      activeLectureId: activeLectureId,
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
