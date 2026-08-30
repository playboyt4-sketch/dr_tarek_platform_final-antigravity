import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/bookmarks_remote_data_source.dart';
import '../../data/repositories/bookmarks_repository_impl.dart';
import '../../domain/entities/bookmark.dart';
import '../../domain/repositories/bookmarks_repository.dart';

final bookmarksRemoteDataSourceProvider =
    Provider<BookmarksRemoteDataSource>((ref) {
  return BookmarksRemoteDataSource();
});

final bookmarksRepositoryProvider = Provider<BookmarksRepository>((ref) {
  final dataSource = ref.watch(bookmarksRemoteDataSourceProvider);
  return BookmarksRepositoryImpl(remoteDataSource: dataSource);
});

final lectureBookmarksStreamProvider = StreamProvider.family<List<Bookmark>,
    ({String studentId, String lectureId})>(
  (ref, arg) {
    final repo = ref.watch(bookmarksRepositoryProvider);
    return repo.watchBookmarksForLecture(
      studentId: arg.studentId,
      lectureId: arg.lectureId,
    );
  },
);

final studentBookmarksStreamProvider =
    StreamProvider.family<List<Bookmark>, String>((ref, studentId) {
  final repo = ref.watch(bookmarksRepositoryProvider);
  return repo.watchBookmarksForStudent(studentId: studentId);
});