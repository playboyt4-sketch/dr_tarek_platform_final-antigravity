class LearningSection {
  final String id;
  final String title;

  /// Canonical section key (`explanation` / `revision` / `final_review`;
  /// custom sections carry `null`, legacy Online rows may carry `online`).
  /// Drives the 4 canonical tabs — never the free-text title.
  final String? sectionKey;

  /// Approved `is_system_section` flag (dashboard Feature 03).
  final bool isSystemSection;
  final int displayOrder;
  final bool isVisible;
  final bool isLocked;

  const LearningSection({
    required this.id,
    required this.title,
    required this.sectionKey,
    required this.isSystemSection,
    required this.displayOrder,
    required this.isVisible,
    required this.isLocked,
  });
}

class LectureSummary {
  final String id;
  final String title;
  final String? description;
  final String status;
  final int displayOrder;
  final bool isLocked;
  final String? subjectId;
  final String? sectionId;
  final String? thumbnailUrl;
  final Duration? duration;
  final Duration? skipIntroStart;
  final Duration? skipIntroEnd;

  /// Denormalized first playable video of the lecture (05 Database
  /// §lectures `first_video`). Written by content authoring whenever the
  /// lecture's resources change; read-only for student clients. Identity
  /// only — never a playback capability: starting playback still requires
  /// the existing entitlement + signed-URL issuance. Null when the lecture
  /// has no eligible video (callers keep the legacy tap-time path).
  final FirstVideoRef? firstVideo;

  const LectureSummary({
    required this.id,
    required this.title,
    this.description,
    required this.status,
    required this.displayOrder,
    required this.isLocked,
    this.subjectId,
    this.sectionId,
    this.thumbnailUrl,
    this.duration,
    this.skipIntroStart,
    this.skipIntroEnd,
    this.firstVideo,
  });

  /// Immutable update used by the playback controller to adopt the
  /// server-resolved resource thumbnail for the active episode.
  LectureSummary copyWith({String? thumbnailUrl, FirstVideoRef? firstVideo}) {
    return LectureSummary(
      id: id,
      title: title,
      description: description,
      status: status,
      displayOrder: displayOrder,
      isLocked: isLocked,
      subjectId: subjectId,
      sectionId: sectionId,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      duration: duration,
      skipIntroStart: skipIntroStart,
      skipIntroEnd: skipIntroEnd,
      firstVideo: firstVideo ?? this.firstVideo,
    );
  }
}

/// Denormalized pointer to a lecture's canonical first playable video.
///
/// Stored on `lectures/{lectureId}` as the `first_video` map
/// (`resource_id`, `bunny_video_id`, `title?`, `display_order`,
/// reserved `thumbnail_path?` / `thumbnail_storage_provider?`).
/// Carries no signed URL, secret, storage URL, or authorization verdict.
class FirstVideoRef {
  /// `lecture_resources` document id of the canonical first video.
  final String resourceId;

  /// Bunny Stream video id used as issuance input for the signed-URL path.
  final String bunnyVideoId;
  final String? title;
  final int displayOrder;

  /// Reserved poster keys, stored once thumbnail content exists.
  /// Raw paths only — never signed URLs.
  final String? thumbnailPath;
  final String? thumbnailStorageProvider;

  const FirstVideoRef({
    required this.resourceId,
    required this.bunnyVideoId,
    this.title,
    this.displayOrder = 0,
    this.thumbnailPath,
    this.thumbnailStorageProvider,
  });

  /// Null-safe parse of the `first_video` map on a `lectures/{id}` document.
  /// Returns null for a missing/malformed map or for empty ids, so callers
  /// fall back to the legacy tap-time resource path.
  static FirstVideoRef? fromLectureData(Map<String, dynamic> data) {
    final raw = data['first_video'];
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final resourceId = _nonEmpty(map['resource_id']);
    final bunnyVideoId = _nonEmpty(map['bunny_video_id']);
    if (resourceId == null || bunnyVideoId == null) return null;
    return FirstVideoRef(
      resourceId: resourceId,
      bunnyVideoId: bunnyVideoId,
      title: _nonEmpty(map['title']),
      displayOrder: (map['display_order'] as num?)?.toInt() ?? 0,
      thumbnailPath: _nonEmpty(map['thumbnail_path']),
      thumbnailStorageProvider:
          _nonEmpty(map['thumbnail_storage_provider']),
    );
  }

  static String? _nonEmpty(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;
}
