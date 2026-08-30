import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// The playback states exposed by the engine and consumed by the UI.
enum PlayerPlaybackStatus {
  initial,
  loading,
  ready,
  playing,
  paused,
  buffering,
  seeking,
  completed,
  error,
  disposed,
}

enum PlayerUiState {
  controlsVisible,
  controlsHidden,
  qualityOpen,
  audioOpen,
  episodesOpen,
  resumePrompt,
  nextEpisodePrompt,
  locked,
  fullscreen,
  subscriptionLock,
}

enum ResumeAction { none, continueWatching, startOver }

class VideoEntitlement {
  final bool allowed;
  final Set<VideoQuality> allowedQualities;
  final String? message;

  const VideoEntitlement({
    required this.allowed,
    this.allowedQualities = const {},
    this.message,
  });

  const VideoEntitlement.denied(String reason)
    : allowed = false,
      allowedQualities = const {},
      message = reason;

  /// Compatibility projection for older consumers; authorization remains set-based.
  String? get maxQuality {
    if (allowedQualities.isEmpty) return null;
    final sorted = allowedQualities.toList()
      ..sort((left, right) => right.rank.compareTo(left.rank));
    return sorted.first.backendValue;
  }
}

enum VideoQuality {
  auto(null, 'تلقائي', 0),
  q4k('4k', '4K', 2160),
  q1440('1440p', '1440p', 1440),
  q1080('1080p', 'Full HD', 1080),
  q720('720p', 'جودة عالية', 720),
  q480('480p', 'جودة متوسطة', 480),
  q360('360p', 'جودة منخفضة', 360),
  q240('240p', '240p', 240),
  q144('144p', '144p', 144);

  final String? backendValue;
  final String label;
  final int rank;

  const VideoQuality(this.backendValue, this.label, this.rank);

  String? get featureKey =>
      backendValue == null ? null : 'video.quality.$backendValue';

  static VideoQuality fromBackend(String? value) {
    final normalized = value?.toLowerCase();
    return VideoQuality.values.firstWhere(
      (item) => item.backendValue == normalized,
      orElse: () => VideoQuality.auto,
    );
  }

  static VideoQuality fromFeatureKey(String? key) {
    if (key == null || !key.startsWith('video.quality.')) {
      return VideoQuality.auto;
    }
    return fromBackend(key.substring('video.quality.'.length));
  }

  bool isAllowedBy(Object entitlementOrQuality) {
    if (this == VideoQuality.auto) return true;
    if (entitlementOrQuality is VideoEntitlement) {
      return entitlementOrQuality.allowedQualities.contains(this);
    }
    if (entitlementOrQuality is String) {
      final limit = VideoQuality.fromBackend(entitlementOrQuality);
      return rank <= limit.rank;
    }
    return false;
  }
}

@immutable
class PlaybackProgressRecord {
  final String userId;
  final String lectureId;
  final String? subjectId;
  final String? sectionId;
  final String? lectureTitle;
  final String? thumbnailUrl;
  final Duration position;
  final Duration duration;
  final double progressPercent;
  final bool completed;
  final DateTime updatedAt;
  final int? pdfLastPage;
  final int? pdfTotalPages;

  const PlaybackProgressRecord({
    required this.userId,
    required this.lectureId,
    this.subjectId,
    this.sectionId,
    this.lectureTitle,
    this.thumbnailUrl,
    required this.position,
    required this.duration,
    required this.progressPercent,
    required this.completed,
    required this.updatedAt,
    this.pdfLastPage,
    this.pdfTotalPages,
  });

  PlaybackProgressRecord copyWith({
    Duration? position,
    Duration? duration,
    double? progressPercent,
    bool? completed,
    DateTime? updatedAt,
    String? lectureTitle,
    String? thumbnailUrl,
    String? subjectId,
    String? sectionId,
    int? pdfLastPage,
    int? pdfTotalPages,
  }) {
    return PlaybackProgressRecord(
      userId: userId,
      lectureId: lectureId,
      subjectId: subjectId ?? this.subjectId,
      sectionId: sectionId ?? this.sectionId,
      lectureTitle: lectureTitle ?? this.lectureTitle,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      progressPercent: progressPercent ?? this.progressPercent,
      completed: completed ?? this.completed,
      updatedAt: updatedAt ?? this.updatedAt,
      pdfLastPage: pdfLastPage ?? this.pdfLastPage,
      pdfTotalPages: pdfTotalPages ?? this.pdfTotalPages,
    );
  }

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'lectureId': lectureId,
    'subjectId': subjectId,
    'sectionId': sectionId,
    'lectureTitle': lectureTitle,
    'thumbnailUrl': thumbnailUrl,
    'positionSeconds': position.inMilliseconds / 1000,
    'durationSeconds': duration.inMilliseconds / 1000,
    'progressPercent': progressPercent,
    'completed': completed,
    'updatedAt': updatedAt.toIso8601String(),
    if (pdfLastPage != null) 'pdfLastPage': pdfLastPage,
    if (pdfTotalPages != null) 'pdfTotalPages': pdfTotalPages,
  };

  factory PlaybackProgressRecord.fromJson(Map<String, dynamic> json) {
    final position = _durationFrom(json['positionSeconds']);
    final duration = _durationFrom(json['durationSeconds']);
    return PlaybackProgressRecord(
      userId: json['userId'] as String? ?? '',
      lectureId: json['lectureId'] as String? ?? '',
      subjectId: json['subjectId'] as String?,
      sectionId: json['sectionId'] as String?,
      lectureTitle: json['lectureTitle'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      position: position,
      duration: duration,
      progressPercent: ProgressMath.percent(position, duration),
      completed: json['completed'] == true,
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      pdfLastPage: json['pdfLastPage'] as int?,
      pdfTotalPages: json['pdfTotalPages'] as int?,
    );
  }

  static Duration _durationFrom(Object? value) {
    final seconds = value is num
        ? value.toDouble()
        : double.tryParse('$value') ?? 0;
    return Duration(
      milliseconds: (seconds.clamp(0, 24 * 60 * 60) * 1000).round(),
    );
  }
}

@immutable
class VideoResource {
  final String id;
  final String title;
  final String resourceType;
  final String? bunnyVideoId;

  /// Renderable preview image for this resource. Since the storage-delivery
  /// completion, getLectureResources returns this as a SERVER-RESOLVED,
  /// short-lived signed URL (`thumbnailUrl`) for both providers — raw
  /// storage paths are never renderable because storage.rules deny all
  /// direct reads of lecture_resources/. Falls back to the legacy raw
  /// `thumbnail` value so older payloads still parse.
  final String? thumbnailUrl;

  /// Dual-provider key (FINAL_DECISIONS §15): which backend stores this
  /// resource's bytes ("bunny" | "firebase"). The Data layer routes signed
  /// URL requests by it; Presentation never branches on it.
  final String storageProvider;

  /// Provider that stores the THUMBNAIL bytes ("bunny" | "firebase").
  /// Metadata only: thumbnails arrive already resolved server-side, so the
  /// client deliberately does NOT dispatch on this.
  final String? thumbnailProvider;
  final Duration? duration;

  /// FINAL_DECISIONS §11: non-null ONLY when the server armed the Public
  /// Free per-lecture gate for THIS student+lecture; the value is the exact
  /// number of seconds allowed. Zero = wall immediately.
  final bool isPublicFreePreview;
  final int? publicFreePreviewSeconds;

  const VideoResource({
    required this.id,
    required this.title,
    required this.resourceType,
    this.bunnyVideoId,
    this.thumbnailUrl,
    this.storageProvider = 'firebase',
    this.thumbnailProvider,
    this.duration,
    this.isPublicFreePreview = false,
    this.publicFreePreviewSeconds,
  });

  bool get isVideo =>
      resourceType == 'video' && bunnyVideoId?.isNotEmpty == true;

  bool get isDocument =>
      resourceType == 'pdf' || resourceType == 'attachment';

  /// Pure mapping of one `getLectureResources` payload entry into an
  /// entity. Kept side-effect-free so the Data layer stays thin and the
  /// shape contract is unit-testable without Firebase mocks. Prefers the
  /// server-resolved [thumbnailUrl]; falls back to the legacy raw
  /// `thumbnail` string for payloads from older deployments.
  factory VideoResource.fromCallablePayload(Map<String, dynamic> map) {
    return VideoResource(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? 'مورد تعليمي',
      resourceType: map['resourceType'] as String? ?? 'attachment',
      bunnyVideoId: map['bunnyVideoId'] as String?,
      thumbnailUrl:
          (map['thumbnailUrl'] as String?) ?? map['thumbnail'] as String?,
      storageProvider: map['storageProvider'] as String? ?? 'firebase',
      thumbnailProvider: map['thumbnailProvider'] as String?,
      duration: _durationFromMap(map['duration']),
      isPublicFreePreview: false,
      publicFreePreviewSeconds: null,
    );
  }

  static Duration? _durationFromMap(Object? value) {
    if (value is! num || value <= 0) return null;
    return Duration(seconds: value.round());
  }
}

/// Pure policy for the per-lecture Public Free minute cap
/// (FINAL_DECISIONS §11). Kept side-effect-free so it is unit-testable
/// without a video engine.
class PreviewCapPolicy {
  /// Effective cap for the active resource; null = unlimited.
  static Duration? capFor(VideoResource? resource) {
    if (resource == null || !resource.isPublicFreePreview) return null;
    final seconds = resource.publicFreePreviewSeconds ?? 0;
    return seconds <= 0 ? Duration.zero : Duration(seconds: seconds);
  }

  /// Playback must stop once [position] reaches the cap.
  static bool shouldStop(Duration position, Duration? cap) {
    if (cap == null) return false;
    return position >= cap;
  }

  /// Seeking may never jump past the cap while a preview is active.
  static Duration clampSeek(Duration target, Duration? cap) {
    if (cap == null || target <= cap) return target;
    return cap;
  }
}

@immutable
class ResolvedVideoSource {
  final Uri url;
  final DateTime expiresAt;
  final VideoQuality selectedQuality;
  final Set<VideoQuality> allowedQualities;

  const ResolvedVideoSource({
    required this.url,
    required this.expiresAt,
    required this.selectedQuality,
    this.allowedQualities = const {},
  });
}

class ProgressMath {
  static const completionThreshold = .95;
  static const meaningfulProgressThreshold = .02;
  static const nearEndThreshold = .98;

  static double percent(Duration position, Duration duration) {
    if (duration <= Duration.zero) return 0;
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  static Duration clampPosition(Duration position, Duration duration) {
    if (duration <= Duration.zero) return Duration.zero;
    return Duration(
      milliseconds: math
          .min(position.inMilliseconds, duration.inMilliseconds)
          .clamp(0, duration.inMilliseconds),
    );
  }

  static bool isCompleted(Duration position, Duration duration) {
    final value = percent(position, duration);
    return duration > Duration.zero && value >= completionThreshold;
  }

  static bool hasMeaningfulProgress(PlaybackProgressRecord? record) {
    if (record == null ||
        record.completed ||
        record.duration <= Duration.zero) {
      return false;
    }
    final ratio = percent(record.position, record.duration);
    return ratio >= meaningfulProgressThreshold && ratio < nearEndThreshold;
  }

  static ResumeAction resumeAction(PlaybackProgressRecord? record) {
    if (!hasMeaningfulProgress(record)) return ResumeAction.none;
    return ResumeAction.continueWatching;
  }
}

class EpisodeNavigation {
  static int? nextIndex({required int currentIndex, required int count}) {
    final next = currentIndex + 1;
    return next < count ? next : null;
  }

  static int? previousIndex({required int currentIndex, required int count}) {
    final previous = currentIndex - 1;
    return previous >= 0 && previous < count ? previous : null;
  }
}
