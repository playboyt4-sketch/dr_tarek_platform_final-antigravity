import '../entities/bookmark.dart';

abstract class BookmarksRepository {
  Future<List<Bookmark>> getBookmarksForLecture({
    required String studentId,
    required String lectureId,
  });

  Future<List<Bookmark>> getBookmarksForSubject({
    required String studentId,
    required String subjectId,
  });

  Future<Bookmark> createBookmark({
    required String studentId,
    required String subjectId,
    required String lectureId,
    required String title,
    int? videoTimestampSeconds,
    int? pdfPageNumber,
  });

  Future<void> deleteBookmark({
    required String bookmarkId,
  });

  Stream<List<Bookmark>> watchBookmarksForStudent({required String studentId});

  Stream<List<Bookmark>> watchBookmarksForLecture({
    required String studentId,
    required String lectureId,
  });
}
