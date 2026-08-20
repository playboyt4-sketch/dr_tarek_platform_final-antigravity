import 'package:flutter_test/flutter_test.dart';
import 'package:dr_tarek_platform/features/notes/data/models/note_model.dart';
import 'package:dr_tarek_platform/features/notes/domain/entities/note.dart';
import 'package:dr_tarek_platform/features/notes/domain/repositories/notes_repository.dart';

class InMemoryNotesRepository implements NotesRepository {
  final List<Note> _notes = [];

  @override
  Future<Note> createNote({
    required String studentId,
    required String subjectId,
    required String lectureId,
    required String content,
    int? videoTimestampSeconds,
    int? pdfPageNumber,
  }) async {
    final note = Note(
      id: 'note_${_notes.length + 1}',
      studentId: studentId,
      subjectId: subjectId,
      lectureId: lectureId,
      content: content,
      videoTimestampSeconds: videoTimestampSeconds,
      pdfPageNumber: pdfPageNumber,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _notes.add(note);
    return note;
  }

  @override
  Future<void> deleteNote({required String noteId}) async {
    _notes.removeWhere((n) => n.id == noteId);
  }

  @override
  Future<List<Note>> getNotesForLecture({
    required String studentId,
    required String lectureId,
  }) async {
    return _notes
        .where((n) => n.studentId == studentId && n.lectureId == lectureId)
        .toList();
  }

  @override
  Future<List<Note>> getNotesForSubject({
    required String studentId,
    required String subjectId,
  }) async {
    return _notes
        .where((n) => n.studentId == studentId && n.subjectId == subjectId)
        .toList();
  }

  @override
  Future<void> updateNote({
    required String noteId,
    required String content,
  }) async {
    final index = _notes.indexWhere((n) => n.id == noteId);
    if (index != -1) {
      final old = _notes[index];
      _notes[index] = Note(
        id: old.id,
        studentId: old.studentId,
        subjectId: old.subjectId,
        lectureId: old.lectureId,
        content: content,
        videoTimestampSeconds: old.videoTimestampSeconds,
        pdfPageNumber: old.pdfPageNumber,
        createdAt: old.createdAt,
        updatedAt: DateTime.now(),
      );
    }
  }

  @override
  Stream<List<Note>> watchNotesForLecture({
    required String studentId,
    required String lectureId,
  }) {
    return Stream.value(
      _notes
          .where((n) => n.studentId == studentId && n.lectureId == lectureId)
          .toList(),
    );
  }
}

void main() {
  group('Notes Feature Tests', () {
    test('NoteModel serialization and deserialization', () {
      final map = {
        'student_id': 'student_123',
        'subject_id': 'subject_456',
        'lecture_id': 'lecture_789',
        'content': 'Important note at 5m',
        'video_timestamp_seconds': 300,
        'pdf_page_number': 3,
      };

      final note = NoteModel.fromMap('note_001', map);
      expect(note.id, 'note_001');
      expect(note.studentId, 'student_123');
      expect(note.content, 'Important note at 5m');
      expect(note.videoTimestampSeconds, 300);
      expect(note.pdfPageNumber, 3);
    });

    test('NotesRepository creates, lists, updates, and deletes notes for student',
        () async {
      final repo = InMemoryNotesRepository();

      final note1 = await repo.createNote(
        studentId: 'student_1',
        subjectId: 'sub_1',
        lectureId: 'lec_1',
        content: 'Review for final exam',
        videoTimestampSeconds: 120,
      );

      expect(note1.id, isNotEmpty);
      expect(note1.content, 'Review for final exam');

      final list = await repo.getNotesForLecture(
        studentId: 'student_1',
        lectureId: 'lec_1',
      );
      expect(list.length, 1);
      expect(list.first.id, note1.id);

      await repo.updateNote(noteId: note1.id, content: 'Updated note content');
      final updatedList = await repo.getNotesForLecture(
        studentId: 'student_1',
        lectureId: 'lec_1',
      );
      expect(updatedList.first.content, 'Updated note content');

      await repo.deleteNote(noteId: note1.id);
      final emptyList = await repo.getNotesForLecture(
        studentId: 'student_1',
        lectureId: 'lec_1',
      );
      expect(emptyList, isEmpty);
    });
  });
}
