import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/bookmark_model.dart';

class BookmarksRemoteDataSource {
  final FirebaseFirestore _firestore;

  BookmarksRemoteDataSource({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _bookmarksRef =>
      _firestore.collection('bookmarks');

  Future<List<BookmarkModel>> getBookmarksForLecture({
    required String studentId,
    required String lectureId,
  }) async {
    final snap = await _bookmarksRef
        .where('student_id', isEqualTo: studentId)
        .where('lecture_id', isEqualTo: lectureId)
        .get();
    return snap.docs.map(BookmarkModel.fromFirestore).toList();
  }

  Future<List<BookmarkModel>> getBookmarksForSubject({
    required String studentId,
    required String subjectId,
  }) async {
    final snap = await _bookmarksRef
        .where('student_id', isEqualTo: studentId)
        .where('subject_id', isEqualTo: subjectId)
        .get();
    return snap.docs.map(BookmarkModel.fromFirestore).toList();
  }

  Future<BookmarkModel> createBookmark({
    required String studentId,
    required String subjectId,
    required String lectureId,
    required String title,
    int? videoTimestampSeconds,
    int? pdfPageNumber,
  }) async {
    final docRef = _bookmarksRef.doc();
    final model = BookmarkModel(
      id: docRef.id,
      studentId: studentId,
      subjectId: subjectId,
      lectureId: lectureId,
      title: title,
      videoTimestampSeconds: videoTimestampSeconds,
      pdfPageNumber: pdfPageNumber,
      createdAt: DateTime.now(),
    );
    await docRef.set(model.toMap());
    return model;
  }

  Future<void> deleteBookmark({
    required String bookmarkId,
  }) async {
    await _bookmarksRef.doc(bookmarkId).delete();
  }

  Stream<List<BookmarkModel>> watchBookmarksForLecture({
    required String studentId,
    required String lectureId,
  }) {
    return _bookmarksRef
        .where('student_id', isEqualTo: studentId)
        .where('lecture_id', isEqualTo: lectureId)
        .snapshots()
        .map((snap) => snap.docs.map(BookmarkModel.fromFirestore).toList());
  }

  /// Student-level bookmarks list — powers the hub Bookmarks screen.
  Stream<List<BookmarkModel>> watchBookmarksForStudent({required String studentId}) {
    return _bookmarksRef
        .where('student_id', isEqualTo: studentId)
        .snapshots()
        .map((snap) => snap.docs.map(BookmarkModel.fromFirestore).toList());
  }
}
