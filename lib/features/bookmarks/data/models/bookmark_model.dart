import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/bookmark.dart';

class BookmarkModel extends Bookmark {
  const BookmarkModel({
    required super.id,
    required super.studentId,
    required super.subjectId,
    required super.lectureId,
    required super.title,
    super.videoTimestampSeconds,
    super.pdfPageNumber,
    required super.createdAt,
  });

  factory BookmarkModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return BookmarkModel.fromMap(doc.id, data);
  }

  factory BookmarkModel.fromMap(String id, Map<String, dynamic> data) {
    final createdTimestamp = data['created_at'] as Timestamp?;

    return BookmarkModel(
      id: id,
      studentId: (data['student_id'] as String?) ?? '',
      subjectId: (data['subject_id'] as String?) ?? '',
      lectureId: (data['lecture_id'] as String?) ?? '',
      title: (data['title'] as String?) ?? '',
      videoTimestampSeconds: data['video_timestamp_seconds'] as int?,
      pdfPageNumber: data['pdf_page_number'] as int?,
      createdAt: createdTimestamp?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'student_id': studentId,
      'subject_id': subjectId,
      'lecture_id': lectureId,
      'title': title,
      if (videoTimestampSeconds != null)
        'video_timestamp_seconds': videoTimestampSeconds,
      if (pdfPageNumber != null) 'pdf_page_number': pdfPageNumber,
      'created_at': FieldValue.serverTimestamp(),
    };
  }
}
