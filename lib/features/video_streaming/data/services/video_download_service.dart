import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/bunny_playback_headers.dart';
import '../../../../core/device/device_identity_store.dart';
import '../../../lecture/data/datasources/pdf_remote_data_source.dart';
import '../../../membership/domain/entities/membership_entities.dart';
import '../../../membership/presentation/providers/membership_providers.dart';
import '../../../pdf_viewer/presentation/providers/pdf_viewer_providers.dart';
import '../../../subject_navigation/domain/entities/subject_learning_entities.dart';
import '../../domain/entities/playback_entities.dart';
import '../../presentation/components/video_documents_sheet.dart';
import '../../presentation/providers/video_streaming_providers.dart';

/// Shared state for a single lecture's offline download, observed by both the
/// external lecture card button and the in-player download toolbar button.
@immutable
class LectureDownloadState {
  final bool isDownloading;
  final bool isDownloaded;
  final double progress;
  final String? resourceId;
  final String? subjectId;
  final bool isVideo;

  const LectureDownloadState({
    this.isDownloading = false,
    this.isDownloaded = false,
    this.progress = 0.0,
    this.resourceId,
    this.subjectId,
    this.isVideo = false,
  });

  LectureDownloadState copyWith({
    bool? isDownloading,
    bool? isDownloaded,
    double? progress,
    String? resourceId,
    String? subjectId,
    bool? isVideo,
  }) {
    return LectureDownloadState(
      isDownloading: isDownloading ?? this.isDownloading,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      progress: progress ?? this.progress,
      resourceId: resourceId ?? this.resourceId,
      subjectId: subjectId ?? this.subjectId,
      isVideo: isVideo ?? this.isVideo,
    );
  }
}

@immutable
class VideoDownloadActionOutcome {
  final bool success;
  final String message;

  const VideoDownloadActionOutcome({
    required this.success,
    required this.message,
  });
}

/// Checks whether the student's active plan enables video offline downloads.
bool isVideoDownloadFeatureEnabled(List<PlanFeature> features) {
  return features.any(
    (item) => item.featureKey == 'video.download' && item.enabled == true,
  );
}

/// Checks whether the student's active plan allows offline document downloads.
bool isPdfDownloadFeatureEnabled(List<PlanFeature> features) {
  return features.any(
    (item) =>
        (item.featureKey == 'pdf.download' || item.featureKey == 'pdf.offline') &&
        item.enabled == true,
  );
}

/// Returns the configured max downloaded videos cap (0 means unlimited).
int resolveVideoDownloadMaxCount(List<PlanFeature> features) {
  final feature = features.cast<PlanFeature?>().firstWhere(
    (item) =>
        item?.featureKey == 'video.download.max_count' &&
        item?.enabled == true,
    orElse: () => null,
  );
  if (feature == null) return 0;
  final raw = feature.featureValue;
  if (raw is int && raw > 0) return raw;
  if (raw is num && raw > 0) return raw.toInt();
  if (raw is String) {
    final parsed = int.tryParse(raw.trim());
    if (parsed != null && parsed > 0) return parsed;
  }
  return 0;
}

/// Builds the ordered list of Bunny MP4 quality candidates (capped at 1080p)
/// permitted by the student's plan so fallback works cleanly if one rendition
/// is missing on older Bunny uploads.
List<VideoQuality> resolveDownloadQualityCandidates({
  required List<PlanFeature> features,
  VideoQuality? preferredQuality,
}) {
  const ordered = <VideoQuality>[
    VideoQuality.q1080,
    VideoQuality.q720,
    VideoQuality.q480,
    VideoQuality.q360,
    VideoQuality.q240,
    VideoQuality.q144,
  ];
  final allowed = <VideoQuality>{};
  for (final feature in features) {
    if (!feature.enabled || !feature.featureKey.startsWith('video.quality.')) {
      continue;
    }
    if (feature.featureKey == 'video.quality.max') {
      final cap = VideoQuality.fromBackend(feature.featureValue);
      if (cap != VideoQuality.auto) {
        for (final q in ordered) {
          if (q.rank <= cap.rank) allowed.add(q);
        }
      }
      continue;
    }
    final parsed = VideoQuality.fromFeatureKey(feature.featureKey);
    if (parsed != VideoQuality.auto && parsed.rank <= VideoQuality.q1080.rank) {
      allowed.add(parsed);
    }
  }

  final pool = allowed.isEmpty
      ? <VideoQuality>[VideoQuality.q720, VideoQuality.q480, VideoQuality.q360]
      : ordered.where(allowed.contains).toList();

  if (preferredQuality != null &&
      preferredQuality != VideoQuality.auto &&
      preferredQuality.rank <= VideoQuality.q1080.rank &&
      (allowed.isEmpty || allowed.contains(preferredQuality))) {
    return <VideoQuality>[
      preferredQuality,
      ...pool.where((q) => q != preferredQuality),
    ];
  }
  return pool;
}

/// Manages local private-sandbox video and document offline downloads, ensuring
/// zero OOM buffering (streams MP4 bytes via IOSink) and live state syncing
/// across lecture cards and the video player toolbar.
class VideoDownloadController extends Notifier<Map<String, LectureDownloadState>> {
  static const String _prefPrefix = 'offline_lecture_';
  static const String _resourcePrefPrefix = 'offline_lecture_res_';
  static const String _kindPrefPrefix = 'offline_lecture_kind_';
  static const String _relPathPrefPrefix = 'offline_lecture_vrel_';
  static const String _expiryPrefPrefix = 'offline_lecture_vexp_';
  static const String _subjectPrefPrefix = 'offline_lecture_vsubj_';
  static const String _vaultDirName = '.dr_tarek_vault';
  static const String _videosDirName = 'videos';

  final Map<String, Future<VideoDownloadActionOutcome>> _inFlight =
      <String, Future<VideoDownloadActionOutcome>>{};

  @override
  Map<String, LectureDownloadState> build() => const <String, LectureDownloadState>{};

  static Future<Directory> _getVideosRoot() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, _vaultDirName, _videosDirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Resolves a valid, non-expired offline MP4 file path for [lectureId],
  /// returning `null` (and cleaning stale metadata) when missing or expired.
  static Future<String?> resolveValidOfflineVideoPath({
    required String subjectId,
    required String lectureId,
  }) async {
    if (kIsWeb) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final downloaded = prefs.getBool('$_prefPrefix$lectureId') ?? false;
      final kind = prefs.getString('$_kindPrefPrefix$lectureId');
      final relPath = prefs.getString('$_relPathPrefPrefix$lectureId');
      if (!downloaded || kind != 'video' || relPath == null || relPath.isEmpty) {
        return null;
      }
      final storedSubject = prefs.getString('$_subjectPrefPrefix$lectureId');
      if (storedSubject != null && storedSubject != subjectId) {
        return null;
      }

      final expiryStr = prefs.getString('$_expiryPrefPrefix$lectureId');
      if (expiryStr != null) {
        final expiry = DateTime.tryParse(expiryStr);
        if (expiry != null && DateTime.now().isAfter(expiry)) {
          await _purgeVideoFilesForLecture(prefs, lectureId);
          return null;
        }
      }

      final root = await _getVideosRoot();
      final file = File(p.join(root.path, relPath));
      if (!await file.exists() || await file.length() <= 0) {
        await _purgeVideoFilesForLecture(prefs, lectureId);
        return null;
      }
      return file.path;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _purgeVideoFilesForLecture(
    SharedPreferences prefs,
    String lectureId,
  ) async {
    final relPath = prefs.getString('$_relPathPrefPrefix$lectureId');
    if (relPath != null && relPath.isNotEmpty) {
      try {
        final root = await _getVideosRoot();
        final file = File(p.join(root.path, relPath));
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
    await prefs.remove('$_prefPrefix$lectureId');
    await prefs.remove('$_resourcePrefPrefix$lectureId');
    await prefs.remove('$_kindPrefPrefix$lectureId');
    await prefs.remove('$_relPathPrefPrefix$lectureId');
    await prefs.remove('$_expiryPrefPrefix$lectureId');
    await prefs.remove('$_subjectPrefPrefix$lectureId');
  }

  Future<void> syncLectureStatus({
    required String subjectId,
    required String lectureId,
  }) async {
    if (state[lectureId]?.isDownloading == true) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final downloaded = prefs.getBool('$_prefPrefix$lectureId') ?? false;
      final resId = prefs.getString('$_resourcePrefPrefix$lectureId');
      final kind = prefs.getString('$_kindPrefPrefix$lectureId');

      if (!downloaded || resId == null) {
        _setLectureState(
          lectureId,
          const LectureDownloadState(isDownloaded: false),
        );
        return;
      }

      if (kind == 'video') {
        final path = await resolveValidOfflineVideoPath(
          subjectId: subjectId,
          lectureId: lectureId,
        );
        _setLectureState(
          lectureId,
          LectureDownloadState(
            isDownloaded: path != null,
            resourceId: path != null ? resId : null,
            subjectId: path != null ? subjectId : null,
            isVideo: path != null,
          ),
        );
        return;
      }

      final drmRepo = await ref.read(drmRepositoryProvider.future);
      final hasPdf = await drmRepo.hasEncryptedFile(
        subjectId: subjectId,
        resourceId: resId,
      );
      _setLectureState(
        lectureId,
        LectureDownloadState(
          isDownloaded: hasPdf,
          resourceId: hasPdf ? resId : null,
          subjectId: hasPdf ? subjectId : null,
          isVideo: false,
        ),
      );
    } catch (_) {}
  }

  void _setLectureState(String lectureId, LectureDownloadState next) {
    state = <String, LectureDownloadState>{
      ...state,
      lectureId: next,
    };
  }

  Future<VideoDownloadActionOutcome> downloadLecture({
    required String userId,
    required String subjectId,
    required LectureSummary lecture,
    VideoQuality preferredQuality = VideoQuality.q720,
  }) {
    final existing = _inFlight[lecture.id];
    if (existing != null) return existing;
    final task = _performDownload(
      userId: userId,
      subjectId: subjectId,
      lecture: lecture,
      preferredQuality: preferredQuality,
    ).whenComplete(() => _inFlight.remove(lecture.id));
    _inFlight[lecture.id] = task;
    return task;
  }

  Future<VideoDownloadActionOutcome> _performDownload({
    required String userId,
    required String subjectId,
    required LectureSummary lecture,
    required VideoQuality preferredQuality,
  }) async {
    if (kIsWeb) {
      return const VideoDownloadActionOutcome(
        success: false,
        message: 'التحميل أوفلاين متاح في تطبيق الهاتف فقط.',
      );
    }
    if (lecture.isLocked) {
      return const VideoDownloadActionOutcome(
        success: false,
        message: 'المحاضرة مقفلة، يرجى تفعيل الاشتراك أولاً.',
      );
    }

    _setLectureState(
      lecture.id,
      LectureDownloadState(
        isDownloading: true,
        progress: 0.0,
        subjectId: subjectId,
      ),
    );

    try {
      final subscription = await ref.read(
        activeSubscriptionProvider((
          studentId: userId,
          subjectId: subjectId,
        )).future,
      );
      if (subscription == null ||
          (subscription.status != 'active' && subscription.status != 'trial') ||
          !subscription.isWithinAcademicTerm) {
        _setLectureState(lecture.id, const LectureDownloadState());
        return const VideoDownloadActionOutcome(
          success: false,
          message: 'يرجى التأكد من وجود اشتراك نشط للمادة قبل التحميل.',
        );
      }

      final features = await ref.read(
        planFeaturesProvider(subscription.planId).future,
      );

      final resolver = ref.read(videoSourceResolverProvider);
      final resources = await resolver.loadResources(lecture.id);
      final videoResource = resources
          .cast<VideoResource?>()
          .firstWhere(
            (r) => r != null && r.isVideo && r.bunnyVideoId != null,
            orElse: () => null,
          );

      if (videoResource != null) {
        if (!isVideoDownloadFeatureEnabled(features)) {
          _setLectureState(lecture.id, const LectureDownloadState());
          return const VideoDownloadActionOutcome(
            success: false,
            message:
                'تحميل الفيديوهات أوفلاين متاح في باقتي Pro و Max فقط.',
          );
        }

        final prefs = await SharedPreferences.getInstance();
        final maxCount = resolveVideoDownloadMaxCount(features);
        if (maxCount > 0) {
          final downloadedCount = prefs
              .getKeys()
              .where(
                (k) =>
                    k.startsWith(_kindPrefPrefix) &&
                    prefs.getString(k) == 'video' &&
                    k != '$_kindPrefPrefix${lecture.id}',
              )
              .length;
          if (downloadedCount >= maxCount) {
            _setLectureState(lecture.id, const LectureDownloadState());
            return VideoDownloadActionOutcome(
              success: false,
              message:
                  'تم الوصول للحد الأقصى للتنزيلات في باقتك ($maxCount محاضرة). احذف محاضرة أولاً.',
            );
          }
        }

        final candidates = resolveDownloadQualityCandidates(
          features: features,
          preferredQuality: preferredQuality,
        );
        final functions = FirebaseFunctions.instance;
        final deviceId = await const DeviceIdentityStore().getOrCreate();

        final root = await _getVideosRoot();
        final relPath = p.join(
          subjectId,
          '${lecture.id}_${videoResource.id}.mp4',
        );
        final finalFile = File(p.join(root.path, relPath));
        await finalFile.parent.create(recursive: true);
        final partFile = File('${finalFile.path}.part');

        bool downloadedOk = false;
        Object? lastError;

        for (final quality in candidates) {
          try {
            final response = await functions
                .httpsCallable('generateBunnySignedUrl')
                .call(<String, dynamic>{
                  'videoId': videoResource.bunnyVideoId!,
                  'quality': quality.backendValue,
                  'subjectId': subjectId,
                  'lectureId': lecture.id,
                  if (videoResource.bunnyLibraryId != null)
                    'libraryId': videoResource.bunnyLibraryId,
                  'format': 'mp4',
                  'deviceId': deviceId,
                });
            final data = Map<String, dynamic>.from(response.data as Map);
            final rawUrl = data['url'] as String?;
            if (rawUrl == null || rawUrl.isEmpty) continue;

            final httpOk = await _streamUrlToFile(
              url: Uri.parse(rawUrl),
              targetPartFile: partFile,
              finalFile: finalFile,
              headers: bunnyPlaybackHttpHeaders,
              onProgress: (pVal) {
                _setLectureState(
                  lecture.id,
                  LectureDownloadState(
                    isDownloading: true,
                    progress: pVal,
                    resourceId: videoResource.id,
                    subjectId: subjectId,
                    isVideo: true,
                  ),
                );
              },
            );
            if (httpOk) {
              downloadedOk = true;
              break;
            }
          } catch (e) {
            lastError = e;
            // Try next fallback quality unless explicitly forbidden/denied.
            if (e is FirebaseFunctionsException &&
                (e.code == 'permission-denied' ||
                    e.code == 'resource-exhausted')) {
              rethrow;
            }
          }
        }

        if (!downloadedOk) {
          if (await partFile.exists()) await partFile.delete();
          throw lastError ?? Exception('Failed to download MP4 rendition.');
        }

        final expiry =
            subscription.endDate ?? DateTime.now().add(const Duration(days: 30));
        await prefs.setBool('$_prefPrefix${lecture.id}', true);
        await prefs.setString(
          '$_resourcePrefPrefix${lecture.id}',
          videoResource.id,
        );
        await prefs.setString('$_kindPrefPrefix${lecture.id}', 'video');
        await prefs.setString('$_relPathPrefPrefix${lecture.id}', relPath);
        await prefs.setString(
          '$_expiryPrefPrefix${lecture.id}',
          expiry.toIso8601String(),
        );
        await prefs.setString('$_subjectPrefPrefix${lecture.id}', subjectId);

        _setLectureState(
          lecture.id,
          LectureDownloadState(
            isDownloading: false,
            isDownloaded: true,
            progress: 1.0,
            resourceId: videoResource.id,
            subjectId: subjectId,
            isVideo: true,
          ),
        );
        return VideoDownloadActionOutcome(
          success: true,
          message:
              'تم تحميل فيديو «${lecture.title}» بنجاح ومتاح للمشاهدة بدون إنترنت.',
        );
      }

      // Fallback for document-only lectures (no video attached).
      final documents = LectureDocuments.fromResources(resources);
      if (documents.isEmpty) {
        _setLectureState(lecture.id, const LectureDownloadState());
        return const VideoDownloadActionOutcome(
          success: false,
          message: 'لا توجد ملفات أو فيديوهات قابلة للتحميل لهذه المحاضرة.',
        );
      }
      if (!isPdfDownloadFeatureEnabled(features)) {
        _setLectureState(lecture.id, const LectureDownloadState());
        return const VideoDownloadActionOutcome(
          success: false,
          message: 'التحميل أوفلاين غير متاح في باقتك الحالية.',
        );
      }

      final doc = documents.first;
      final result = await PdfRemoteDataSource().getDownloadUrl(
        doc.resourceId,
        storageProvider: doc.storageProvider,
      );
      final bytes = await _downloadSmallBytes(
        Uri.parse(result.url),
        onProgress: (pVal) {
          _setLectureState(
            lecture.id,
            LectureDownloadState(
              isDownloading: true,
              progress: pVal,
              resourceId: doc.resourceId,
              subjectId: subjectId,
              isVideo: false,
            ),
          );
        },
      );
      final drmRepo = await ref.read(drmRepositoryProvider.future);
      await drmRepo.saveEncryptedFile(
        subjectId: subjectId,
        resourceId: doc.resourceId,
        plaintextBytes: bytes,
        userId: userId,
        expiresAt: result.expiresAt,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_prefPrefix${lecture.id}', true);
      await prefs.setString('$_resourcePrefPrefix${lecture.id}', doc.resourceId);
      await prefs.setString('$_kindPrefPrefix${lecture.id}', 'pdf');
      await prefs.setString('$_subjectPrefPrefix${lecture.id}', subjectId);

      _setLectureState(
        lecture.id,
        LectureDownloadState(
          isDownloading: false,
          isDownloaded: true,
          progress: 1.0,
          resourceId: doc.resourceId,
          subjectId: subjectId,
          isVideo: false,
        ),
      );
      return VideoDownloadActionOutcome(
        success: true,
        message:
            'تم تحميل «${lecture.title}» بنجاح ومتاحة للمذاكرة بدون إنترنت.',
      );
    } on FirebaseFunctionsException catch (e) {
      _setLectureState(lecture.id, const LectureDownloadState());
      final msg = (e.message != null && e.message!.trim().isNotEmpty)
          ? e.message!
          : 'تعذر تحميل المحاضرة حالياً.';
      return VideoDownloadActionOutcome(success: false, message: msg);
    } catch (_) {
      _setLectureState(lecture.id, const LectureDownloadState());
      return const VideoDownloadActionOutcome(
        success: false,
        message: 'تعذر تحميل المحاضرة. يرجى التحقق من الاتصال والمحاولة مرة أخرى.',
      );
    }
  }

  Future<void> deleteDownloadedLecture({
    required String subjectId,
    required String lectureId,
  }) async {
    final current = state[lectureId];
    final prefs = await SharedPreferences.getInstance();
    final resId =
        current?.resourceId ?? prefs.getString('$_resourcePrefPrefix$lectureId');
    final kind = prefs.getString('$_kindPrefPrefix$lectureId');

    if (kind == 'video' || current?.isVideo == true) {
      await _purgeVideoFilesForLecture(prefs, lectureId);
    } else {
      if (resId != null) {
        try {
          final drmRepo = await ref.read(drmRepositoryProvider.future);
          await drmRepo.deleteEncryptedFile(
            subjectId: subjectId,
            resourceId: resId,
          );
        } catch (_) {}
      }
      await prefs.remove('$_prefPrefix$lectureId');
      await prefs.remove('$_resourcePrefPrefix$lectureId');
      await prefs.remove('$_kindPrefPrefix$lectureId');
      await prefs.remove('$_subjectPrefPrefix$lectureId');
    }

    _setLectureState(lectureId, const LectureDownloadState(isDownloaded: false));
  }

  static Future<bool> _streamUrlToFile({
    required Uri url,
    required File targetPartFile,
    required File finalFile,
    required Map<String, String> headers,
    required void Function(double progress) onProgress,
  }) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(url);
      headers.forEach(req.headers.set);
      final response = await req.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        return false;
      }

      if (await targetPartFile.exists()) {
        await targetPartFile.delete();
      }
      final sink = targetPartFile.openWrite();
      final total = response.contentLength;
      var received = 0;

      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            onProgress((received / total).clamp(0.0, 1.0));
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (received <= 0) {
        if (await targetPartFile.exists()) await targetPartFile.delete();
        return false;
      }

      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await targetPartFile.rename(finalFile.path);
      return true;
    } finally {
      client.close(force: true);
    }
  }

  static Future<List<int>> _downloadSmallBytes(
    Uri url, {
    required void Function(double progress) onProgress,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(url);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}', uri: url);
      }
      final total = response.contentLength;
      var received = 0;
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
        received += chunk.length;
        if (total > 0) {
          onProgress((received / total).clamp(0.0, 1.0));
        }
      }
      return bytes;
    } finally {
      client.close(force: true);
    }
  }
}

final videoDownloadControllerProvider =
    NotifierProvider<VideoDownloadController, Map<String, LectureDownloadState>>(
  VideoDownloadController.new,
);
