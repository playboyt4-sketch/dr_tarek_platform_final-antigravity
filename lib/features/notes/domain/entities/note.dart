/// Private student note attached to a video timestamp or PDF page.
class Note {
  final String id;
  final String studentId;
  final String subjectId;
  final String lectureId;
  final String title;
  final String content;
  final int? videoTimestampSeconds;
  final int? pdfPageNumber;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Note({
    required this.id,
    required this.studentId,
    required this.subjectId,
    required this.lectureId,
    this.title = '',
    required this.content,
    this.videoTimestampSeconds,
    this.pdfPageNumber,
    required this.createdAt,
    required this.updatedAt,
  });
}
