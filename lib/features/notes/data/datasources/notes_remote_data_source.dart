import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/note_model.dart';

class NotesRemoteDataSource {
  final FirebaseFirestore _firestore;

  NotesRemoteDataSource({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _notesRef =>
      _firestore.collection('notes');

  Future<List<NoteModel>> getNotesForLecture({
    required String studentId,
    required String lectureId,
  }) async {
    final snap = await _notesRef
        .where('student_id', isEqualTo: studentId)
        .where('lecture_id', isEqualTo: lectureId)
        .get();
    return snap.docs.map(NoteModel.fromFirestore).toList();
  }

  Future<List<NoteModel>> getNotesForSubject({
    required String studentId,
    required String subjectId,
  }) async {
    final snap = await _notesRef
        .where('student_id', isEqualTo: studentId)
        .where('subject_id', isEqualTo: subjectId)
        .get();
    return snap.docs.map(NoteModel.fromFirestore).toList();
  }

  Future<NoteModel> createNote({
    required String studentId,
    required String subjectId,
    required String lectureId,
    required String content,
    int? videoTimestampSeconds,
    int? pdfPageNumber,
  }) async {
    final docRef = _notesRef.doc();
    final model = NoteModel(
      id: docRef.id,
      studentId: studentId,
      subjectId: subjectId,
      lectureId: lectureId,
      content: content,
      videoTimestampSeconds: videoTimestampSeconds,
      pdfPageNumber: pdfPageNumber,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await docRef.set(model.toMap());
    return model;
  }

  Future<void> updateNote({
    required String noteId,
    required String content,
  }) async {
    await _notesRef.doc(noteId).update({
      'content': content,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteNote({
    required String noteId,
  }) async {
    await _notesRef.doc(noteId).delete();
  }

  Stream<List<NoteModel>> watchNotesForLecture({
    required String studentId,
    required String lectureId,
  }) {
    return _notesRef
        .where('student_id', isEqualTo: studentId)
        .where('lecture_id', isEqualTo: lectureId)
        .snapshots()
        .map((snap) => snap.docs.map(NoteModel.fromFirestore).toList());
  }

  /// Student-level notes list (all lectures) — powers the hub Notes screen.
  Stream<List<NoteModel>> watchNotesForStudent({required String studentId}) {
    return _notesRef
        .where('student_id', isEqualTo: studentId)
        .snapshots()
        .map((snap) => snap.docs.map(NoteModel.fromFirestore).toList());
  }

  /// Quick note without lecture/subject context (hub-level capture).
  /// Preserves the exact document shape historically written by the app.
  Future<NoteModel> createQuickNote({
    required String studentId,
    required String title,
    required String content,
  }) async {
    final docRef = _notesRef.doc();
    final data = <String, dynamic>{
      'student_id': studentId,
      'title': title,
      'content': content,
      'created_at': FieldValue.serverTimestamp(),
    };
    await docRef.set(data);
    return NoteModel(
      id: docRef.id,
      studentId: studentId,
      subjectId: '',
      lectureId: '',
      title: title,
      content: content,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }
}