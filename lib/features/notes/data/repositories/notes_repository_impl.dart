import '../../domain/entities/note.dart';
import '../../domain/repositories/notes_repository.dart';
import '../datasources/notes_remote_data_source.dart';

class NotesRepositoryImpl implements NotesRepository {
  final NotesRemoteDataSource remoteDataSource;

  NotesRepositoryImpl({required this.remoteDataSource});

  @override
  Future<List<Note>> getNotesForLecture({
    required String studentId,
    required String lectureId,
  }) {
    return remoteDataSource.getNotesForLecture(
      studentId: studentId,
      lectureId: lectureId,
    );
  }

  @override
  Future<List<Note>> getNotesForSubject({
    required String studentId,
    required String subjectId,
  }) {
    return remoteDataSource.getNotesForSubject(
      studentId: studentId,
      subjectId: subjectId,
    );
  }

  @override
  Future<Note> createNote({
    required String studentId,
    required String subjectId,
    required String lectureId,
    required String content,
    int? videoTimestampSeconds,
    int? pdfPageNumber,
  }) {
    return remoteDataSource.createNote(
      studentId: studentId,
      subjectId: subjectId,
      lectureId: lectureId,
      content: content,
      videoTimestampSeconds: videoTimestampSeconds,
      pdfPageNumber: pdfPageNumber,
    );
  }

  @override
  Future<void> updateNote({
    required String noteId,
    required String content,
  }) {
    return remoteDataSource.updateNote(
      noteId: noteId,
      content: content,
    );
  }

  @override
  Future<void> deleteNote({
    required String noteId,
  }) {
    return remoteDataSource.deleteNote(noteId: noteId);
  }

  @override
  Stream<List<Note>> watchNotesForLecture({
    required String studentId,
    required String lectureId,
  }) {
    return remoteDataSource.watchNotesForLecture(
      studentId: studentId,
      lectureId: lectureId,
    );
  }
}
