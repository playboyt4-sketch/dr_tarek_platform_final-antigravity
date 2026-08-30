import '../../domain/entities/note.dart';
import '../../domain/repositories/notes_repository.dart';
import '../datasources/notes_remote_data_source.dart';
import '../../../../core/errors/failure.dart';

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
    ).asFailureAware();
  }

  @override
  Future<List<Note>> getNotesForSubject({
    required String studentId,
    required String subjectId,
  }) {
    return remoteDataSource.getNotesForSubject(
      studentId: studentId,
      subjectId: subjectId,
    ).asFailureAware();
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
    ).asFailureAware();
  }

  @override
  Future<void> updateNote({
    required String noteId,
    required String content,
  }) {
    return remoteDataSource.updateNote(
      noteId: noteId,
      content: content,
    ).asFailureAware();
  }

  @override
  Future<void> deleteNote({
    required String noteId,
  }) {
    return remoteDataSource.deleteNote(noteId: noteId).asFailureAware();
  }

  @override
  Stream<List<Note>> watchNotesForStudent({required String studentId}) {
    return remoteDataSource.watchNotesForStudent(studentId: studentId);
  }

  @override
  Future<Note> createQuickNote({required String studentId, required String title, required String content}) {
    return remoteDataSource.createQuickNote(studentId: studentId, title: title, content: content).asFailureAware();
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
