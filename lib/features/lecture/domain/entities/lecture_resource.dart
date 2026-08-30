enum LectureResourceType {
  video,
  pdf,
  attachment,
  externalLink,
}

class LectureResource {
  final String id;
  final String lectureId;
  final LectureResourceType resourceType;
  final String resourceUrl;
  final String? bunnyVideoId;
  final String? thumbnail;

  /// Dual-provider key (FINAL_DECISIONS §15): "bunny" | "firebase".
  /// Routed by the Data layer only; Presentation never branches on it.
  final String storageProvider;
  final int? duration;
  final bool visibility;

  const LectureResource({
    required this.id,
    required this.lectureId,
    required this.resourceType,
    required this.resourceUrl,
    required this.bunnyVideoId,
    required this.thumbnail,
    this.storageProvider = 'firebase',
    required this.duration,
    required this.visibility,
  });
}
