/// Saved bookmark location (video timestamp or PDF page).
/// Distinct from Resume Learning (which is system auto-tracking).
class Bookmark {
  final String id;
  final String studentId;
  final String subjectId;
  final String lectureId;
  final String title;
  final int? videoTimestampSeconds;
  final int? pdfPageNumber;
  final DateTime createdAt;

  const Bookmark({
    required this.id,
    required this.studentId,
    required this.subjectId,
    required this.lectureId,
    required this.title,
    this.videoTimestampSeconds,
    this.pdfPageNumber,
    required this.createdAt,
  });
}
