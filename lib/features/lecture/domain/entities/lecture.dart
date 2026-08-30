enum LectureStatus {
  draft,
  published,
  archived,
}

class Lecture {
  final String id;
  final String sectionId;
  final String title;
  final String description;
  final int displayOrder;
  final DateTime? publishDate;
  final LectureStatus status;

  /// FINAL_DECISIONS §11: per-lecture Public Free availability. Defaults
  /// preserve every existing constructor call site.
  final bool publicFreeEnabled;

  /// Minutes allowed for THIS lecture for Public Free students
  /// (independent per lecture); null = fall back to the plan default.
  final int? publicFreePreviewMinutes;

  const Lecture({
    required this.id,
    required this.sectionId,
    required this.title,
    required this.description,
    required this.displayOrder,
    required this.publishDate,
    required this.status,
    this.publicFreeEnabled = false,
    this.publicFreePreviewMinutes,
  });
}
