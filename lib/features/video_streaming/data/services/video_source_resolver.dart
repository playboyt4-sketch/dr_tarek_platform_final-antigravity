import 'package:cloud_functions/cloud_functions.dart';
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
    final raw = (data['resources'] as List<dynamic>? ?? const <dynamic>[]);
    return raw.map((item) {
      final map = Map<String, dynamic>.from(item as Map);
      return VideoResource(
        id: map['id'] as String? ?? '',
        title: map['title'] as String? ?? 'مورد تعليمي',
        resourceType: map['resourceType'] as String? ?? 'attachment',
        bunnyVideoId: map['bunnyVideoId'] as String?,
        thumbnailUrl: map['thumbnail'] as String?,
        duration: _duration(map['duration']),
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
      throw VideoSourceException(_messageFor(error));
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
    final created = _uuid.v4();
    await _secureStorage.write(key: _deviceIdKey, value: created);
    return created;
  }

  Duration? _duration(Object? value) {
    if (value is! num || value <= 0) return null;
    return Duration(seconds: value.round());
  }

  DateTime _dateFromEpoch(Object? value) {
    final seconds = value is num ? value.toInt() : 0;
    return seconds > 0
        ? DateTime.fromMillisecondsSinceEpoch(seconds * 1000)
        : DateTime.now().add(const Duration(minutes: 4));
  }

  String _messageFor(FirebaseFunctionsException error) {
    return switch (error.code) {
      'permission-denied' =>
        'لا تملك صلاحية مشاهدة هذا الفيديو أو انتهى اشتراكك.',
      'unauthenticated' => 'يجب تسجيل الدخول لمشاهدة هذا الفيديو.',
      'not-found' => 'الفيديو غير متاح حاليًا.',
      'deadline-exceeded' ||
      'unavailable' => 'تعذر الاتصال بخدمة الفيديو. حاول مرة أخرى.',
      _ => 'تعذر تحميل الفيديو. حاول مرة أخرى.',
    };
  }
}

class VideoSourceException implements Exception {
  final String message;

  const VideoSourceException(this.message);

  @override
  String toString() => message;
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
