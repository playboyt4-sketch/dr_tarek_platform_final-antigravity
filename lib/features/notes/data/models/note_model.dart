import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/note.dart';

class NoteModel extends Note {
  const NoteModel({
    required super.id,
    required super.studentId,
    required super.subjectId,
    required super.lectureId,
    super.title,
    required super.content,
    super.videoTimestampSeconds,
    super.pdfPageNumber,
    required super.createdAt,
    required super.updatedAt,
  });

  factory NoteModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return NoteModel.fromMap(doc.id, data);
  }

  factory NoteModel.fromMap(String id, Map<String, dynamic> data) {
    final createdTimestamp = data['created_at'] as Timestamp?;
    final updatedTimestamp = data['updated_at'] as Timestamp?;

    return NoteModel(
      id: id,
      studentId: (data['student_id'] as String?) ?? '',
      subjectId: (data['subject_id'] as String?) ?? '',
      lectureId: (data['lecture_id'] as String?) ?? '',
      title: (data['title'] as String?) ?? '',
      content: (data['content'] as String?) ?? '',
      videoTimestampSeconds: data['video_timestamp_seconds'] as int?,
      pdfPageNumber: data['pdf_page_number'] as int?,
      createdAt: createdTimestamp?.toDate() ?? DateTime.now(),
      updatedAt: updatedTimestamp?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'student_id': studentId,
      'subject_id': subjectId,
      'lecture_id': lectureId,
      'content': content,
      if (videoTimestampSeconds != null)
        'video_timestamp_seconds': videoTimestampSeconds,
      if (pdfPageNumber != null) 'pdf_page_number': pdfPageNumber,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    };
  }
}
