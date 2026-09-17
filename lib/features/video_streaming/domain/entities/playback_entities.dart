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

  /// FINAL_DECISIONS §11: non-null ONLY when the server armed the Guest
  /// per-lecture preview gate for THIS student+lecture; the value is the
  /// exact number of seconds allowed. Zero = wall immediately.
  final bool isGuestPreview;
  final int? guestPreviewSeconds;

  const VideoResource({
    required this.id,
    required this.title,
    required this.resourceType,
    this.bunnyVideoId,
    this.thumbnailUrl,
    this.storageProvider = 'firebase',
    this.thumbnailProvider,
    this.duration,
    this.isGuestPreview = false,
    this.guestPreviewSeconds,
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
      isGuestPreview: false,
      guestPreviewSeconds: null,
    );
  }

  static Duration? _durationFromMap(Object? value) {
    if (value is! num || value <= 0) return null;
    return Duration(seconds: value.round());
  }
}

/// Pure policy for the per-lecture Guest preview minute cap
/// (FINAL_DECISIONS §11). Kept side-effect-free so it is unit-testable
/// without a video engine.
class PreviewCapPolicy {
  /// Effective cap for the active resource; null = unlimited.
  static Duration? capFor(VideoResource? resource) {
    if (resource == null || !resource.isGuestPreview) return null;
    final seconds = resource.guestPreviewSeconds ?? 0;
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

  /// Max Subject active-session attachment (ADR-004 follow-up). Present
  /// ONLY when the server ran the begin-or-takeover transaction for a
  /// 2-allowance Subject; null on Free/Pro/Guest paths, whose behavior is
  /// unchanged. The token is runtime state, never persisted as authority.
  final String? sessionToken;
  final int? sessionPositionSeconds;
  final bool sessionTakeover;
  final int? heartbeatIntervalMs;

  const ResolvedVideoSource({
    required this.url,
    required this.expiresAt,
    required this.selectedQuality,
    this.allowedQualities = const {},
    this.sessionToken,
    this.sessionPositionSeconds,
    this.sessionTakeover = false,
    this.heartbeatIntervalMs,
  });

  bool get hasActiveSession => sessionToken != null && sessionToken!.isNotEmpty;
}

/// Lifecycle state of one Subject-scoped playback session. Every value is
/// a projection of the last server verdict — never decided locally.
enum PlaybackSessionState {
  /// No session adopted (non-Max Subject, Guest preview, or not started).
  none,

  /// Server confirmed this device owns the live session.
  active,

  /// Server reported another device took over (heartbeat/begin rejected).
  superseded,

  /// Server lease lapsed or session ended.
  expired,

  /// Session rejected for any other authorization reason.
  invalid,
}

/// A server-owned active playback session for one Student + Subject.
/// Tokens are opaque runtime handles: held in memory, never persisted,
/// never generated client-side, never used across Subjects.
@immutable
class PlaybackSession {
  final String subjectId;
  final String? lectureId;
  final String? videoId;
  final String sessionToken;
  final Duration position;
  final bool takeover;
  final DateTime? leaseExpiresAt;
  final Duration heartbeatInterval;
  final PlaybackSessionState state;

  const PlaybackSession({
    required this.subjectId,
    this.lectureId,
    this.videoId,
    required this.sessionToken,
    this.position = Duration.zero,
    this.takeover = false,
    this.leaseExpiresAt,
    this.heartbeatInterval = const Duration(seconds: 30),
    this.state = PlaybackSessionState.active,
  });

  PlaybackSession copyWith({
    Duration? position,
    bool? takeover,
    DateTime? leaseExpiresAt,
    Duration? heartbeatInterval,
    PlaybackSessionState? state,
  }) {
    return PlaybackSession(
      subjectId: subjectId,
      lectureId: lectureId,
      videoId: videoId,
      sessionToken: sessionToken,
      position: position ?? this.position,
      takeover: takeover ?? this.takeover,
      leaseExpiresAt: leaseExpiresAt ?? this.leaseExpiresAt,
      heartbeatInterval: heartbeatInterval ?? this.heartbeatInterval,
      state: state ?? this.state,
    );
  }

  /// Builds a session ONLY from a server begin/takeover response payload.
  /// Returns null when the payload carries no session (non-Max/Guest path).
  static PlaybackSession? fromBeginPayload({
    required String subjectId,
    String? lectureId,
    String? videoId,
    required Map<String, dynamic> data,
  }) {
    final token = data['sessionToken'] as String?;
    if (token == null || token.isEmpty) return null;
    final positionSeconds = (data['positionSeconds'] as num?)?.toInt() ?? 0;
    final leaseMs = (data['leaseExpiresAtMs'] as num?)?.toInt();
    final beatMs = (data['heartbeatIntervalMs'] as num?)?.toInt();
    return PlaybackSession(
      subjectId: subjectId,
      lectureId: lectureId,
      videoId: videoId,
      sessionToken: token,
      position: Duration(seconds: positionSeconds.clamp(0, 24 * 60 * 60)),
      takeover: data['takeover'] == true,
      leaseExpiresAt: leaseMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(leaseMs),
      heartbeatInterval: beatMs != null && beatMs > 0
          ? Duration(milliseconds: beatMs)
          : const Duration(seconds: 30),
    );
  }
}

/// Server heartbeat verdict. The returned position is authoritative for the
/// session snapshot; durable progress stays with the progress repository.
@immutable
class HeartbeatResult {
  final Duration position;
  final DateTime? leaseExpiresAt;

  const HeartbeatResult({required this.position, this.leaseExpiresAt});

  factory HeartbeatResult.fromPayload(Map<String, dynamic> data) {
    final seconds = (data['positionSeconds'] as num?)?.toInt() ?? 0;
    final leaseMs = (data['leaseExpiresAtMs'] as num?)?.toInt();
    return HeartbeatResult(
      position: Duration(seconds: seconds.clamp(0, 24 * 60 * 60)),
      leaseExpiresAt: leaseMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(leaseMs),
    );
  }
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
