import '../../domain/entities/bookmark.dart';
import '../../domain/repositories/bookmarks_repository.dart';
import '../datasources/bookmarks_remote_data_source.dart';

class BookmarksRepositoryImpl implements BookmarksRepository {
  final BookmarksRemoteDataSource remoteDataSource;

  BookmarksRepositoryImpl({required this.remoteDataSource});

  @override
  Future<List<Bookmark>> getBookmarksForLecture({
    required String studentId,
    required String lectureId,
  }) {
    return remoteDataSource.getBookmarksForLecture(
      studentId: studentId,
      lectureId: lectureId,
    );
  }

  @override
  Future<List<Bookmark>> getBookmarksForSubject({
    required String studentId,
    required String subjectId,
  }) {
    return remoteDataSource.getBookmarksForSubject(
      studentId: studentId,
      subjectId: subjectId,
    );
  }

  @override
  Future<Bookmark> createBookmark({
    required String studentId,
    required String subjectId,
    required String lectureId,
    required String title,
    int? videoTimestampSeconds,
    int? pdfPageNumber,
  }) {
    return remoteDataSource.createBookmark(
      studentId: studentId,
      subjectId: subjectId,
      lectureId: lectureId,
      title: title,
      videoTimestampSeconds: videoTimestampSeconds,
      pdfPageNumber: pdfPageNumber,
    );
  }

  @override
  Future<void> deleteBookmark({
    required String bookmarkId,
  }) {
    return remoteDataSource.deleteBookmark(bookmarkId: bookmarkId);
  }

  @override
  Stream<List<Bookmark>> watchBookmarksForLecture({
    required String studentId,
    required String lectureId,
  }) {
    return remoteDataSource.watchBookmarksForLecture(
      studentId: studentId,
      lectureId: lectureId,
    );
  }
}
