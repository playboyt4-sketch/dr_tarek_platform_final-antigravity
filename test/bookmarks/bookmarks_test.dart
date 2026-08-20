import 'package:flutter_test/flutter_test.dart';
import 'package:dr_tarek_platform/features/bookmarks/data/models/bookmark_model.dart';
import 'package:dr_tarek_platform/features/bookmarks/domain/entities/bookmark.dart';
import 'package:dr_tarek_platform/features/bookmarks/domain/repositories/bookmarks_repository.dart';

class InMemoryBookmarksRepository implements BookmarksRepository {
  final List<Bookmark> _bookmarks = [];

  @override
  Future<Bookmark> createBookmark({
    required String studentId,
    required String subjectId,
    required String lectureId,
    required String title,
    int? videoTimestampSeconds,
    int? pdfPageNumber,
  }) async {
    final bookmark = Bookmark(
      id: 'bm_${_bookmarks.length + 1}',
      studentId: studentId,
      subjectId: subjectId,
      lectureId: lectureId,
      title: title,
      videoTimestampSeconds: videoTimestampSeconds,
      pdfPageNumber: pdfPageNumber,
      createdAt: DateTime.now(),
    );
    _bookmarks.add(bookmark);
    return bookmark;
  }

  @override
  Future<void> deleteBookmark({required String bookmarkId}) async {
    _bookmarks.removeWhere((b) => b.id == bookmarkId);
  }

  @override
  Future<List<Bookmark>> getBookmarksForLecture({
    required String studentId,
    required String lectureId,
  }) async {
    return _bookmarks
        .where((b) => b.studentId == studentId && b.lectureId == lectureId)
        .toList();
  }

  @override
  Future<List<Bookmark>> getBookmarksForSubject({
    required String studentId,
    required String subjectId,
  }) async {
    return _bookmarks
        .where((b) => b.studentId == studentId && b.subjectId == subjectId)
        .toList();
  }

  @override
  Stream<List<Bookmark>> watchBookmarksForLecture({
    required String studentId,
    required String lectureId,
  }) {
    return Stream.value(
      _bookmarks
          .where((b) => b.studentId == studentId && b.lectureId == lectureId)
          .toList(),
    );
  }
}

void main() {
  group('Bookmarks Feature Tests', () {
    test('BookmarkModel correctly parses video timestamp and PDF page', () {
      final map = {
        'student_id': 'student_123',
        'subject_id': 'subject_456',
        'lecture_id': 'lecture_789',
        'title': 'Start of Chapter 2',
        'video_timestamp_seconds': 450,
        'pdf_page_number': 14,
      };

      final bm = BookmarkModel.fromMap('bm_1', map);
      expect(bm.id, 'bm_1');
      expect(bm.title, 'Start of Chapter 2');
      expect(bm.videoTimestampSeconds, 450);
      expect(bm.pdfPageNumber, 14);
    });

    test('BookmarksRepository creates and lists bookmarks independently',
        () async {
      final repo = InMemoryBookmarksRepository();

      final b1 = await repo.createBookmark(
        studentId: 'student_1',
        subjectId: 'sub_1',
        lectureId: 'lec_1',
        title: 'Formula derivation',
        videoTimestampSeconds: 620,
      );

      final b2 = await repo.createBookmark(
        studentId: 'student_1',
        subjectId: 'sub_1',
        lectureId: 'lec_1',
        title: 'Summary table in PDF',
        pdfPageNumber: 22,
      );

      final list = await repo.getBookmarksForLecture(
        studentId: 'student_1',
        lectureId: 'lec_1',
      );
      expect(list.length, 2);
      expect(list[0].id, b1.id);
      expect(list[1].id, b2.id);

      await repo.deleteBookmark(bookmarkId: b1.id);
      final remaining = await repo.getBookmarksForLecture(
        studentId: 'student_1',
        lectureId: 'lec_1',
      );
      expect(remaining.length, 1);
      expect(remaining.first.id, b2.id);
    });
  });
}
