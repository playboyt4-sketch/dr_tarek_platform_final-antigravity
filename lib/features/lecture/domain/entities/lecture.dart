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

  const Lecture({
    required this.id,
    required this.sectionId,
    required this.title,
    required this.description,
    required this.displayOrder,
    required this.publishDate,
    required this.status,
  });
}
