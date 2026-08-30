import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/notes_remote_data_source.dart';
import '../../data/repositories/notes_repository_impl.dart';
import '../../domain/entities/note.dart';
import '../../domain/repositories/notes_repository.dart';

final notesRemoteDataSourceProvider = Provider<NotesRemoteDataSource>((ref) {
  return NotesRemoteDataSource();
});

final notesRepositoryProvider = Provider<NotesRepository>((ref) {
  final dataSource = ref.watch(notesRemoteDataSourceProvider);
  return NotesRepositoryImpl(remoteDataSource: dataSource);
});

final lectureNotesStreamProvider =
    StreamProvider.family<List<Note>, ({String studentId, String lectureId})>(
  (ref, arg) {
    final repo = ref.watch(notesRepositoryProvider);
    return repo.watchNotesForLecture(
      studentId: arg.studentId,
      lectureId: arg.lectureId,
    );
  },
);

final studentNotesStreamProvider =
    StreamProvider.family<List<Note>, String>((ref, studentId) {
  final repo = ref.watch(notesRepositoryProvider);
  return repo.watchNotesForStudent(studentId: studentId);
});