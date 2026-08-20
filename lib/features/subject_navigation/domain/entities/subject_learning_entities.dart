class LearningSection {
  final String id;
  final String title;
  final int displayOrder;
  final bool isVisible;
  final bool isLocked;

  const LearningSection({
    required this.id,
    required this.title,
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
  });
}
