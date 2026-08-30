import '../entities/note.dart';

abstract class NotesRepository {
  Future<List<Note>> getNotesForLecture({
    required String studentId,
    required String lectureId,
  });

  Future<List<Note>> getNotesForSubject({
    required String studentId,
    required String subjectId,
  });

  Future<Note> createNote({
    required String studentId,
    required String subjectId,
    required String lectureId,
    required String content,
    int? videoTimestampSeconds,
    int? pdfPageNumber,
  });

  Future<void> updateNote({
    required String noteId,
    required String content,
  });

  Future<void> deleteNote({
    required String noteId,
  });

  Stream<List<Note>> watchNotesForStudent({required String studentId});

  Future<Note> createQuickNote({required String studentId, required String title, required String content});

  Stream<List<Note>> watchNotesForLecture({
    required String studentId,
    required String lectureId,
  });
}
