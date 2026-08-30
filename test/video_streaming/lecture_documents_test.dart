import 'package:flutter_test/flutter_test.dart';
import 'package:dr_tarek_platform/features/video_streaming/domain/entities/playback_entities.dart';
import 'package:dr_tarek_platform/features/video_streaming/presentation/components/video_documents_sheet.dart';
import 'package:dr_tarek_platform/features/subject_navigation/domain/entities/subject_learning_entities.dart';

VideoResource _resource(String id, String type, {String? provider}) {
  return VideoResource(
    id: id,
    title: 'ملف $id',
    resourceType: type,
    storageProvider: provider ?? 'firebase',
  );
}

void main() {
  group('LectureDocuments.fromResources (storage-delivery Fix 1)', () {
    test('classifies pdf and attachment resources, skipping others', () {
      final documents = LectureDocuments.fromResources([
        _resource('v1', 'video', provider: 'firebase'),
        _resource('p1', 'pdf', provider: 'bunny'),
        _resource('a1', 'attachment', provider: 'bunny'),
        _resource('l1', 'external_link'),
        _resource('a2', 'attachment', provider: 'firebase'),
      ]);

      expect(documents.map((d) => d.resourceId).toList(), ['p1', 'a1', 'a2']);
      expect(documents.map((d) => d.isPdf).toList(), [true, false, false]);
      // Provider strings ride along opaquely for the Data layer.
      expect(documents.map((d) => d.storageProvider).toList(),
          ['bunny', 'bunny', 'firebase']);
    });

    test('empty lecture yields no openable documents', () {
      expect(LectureDocuments.fromResources(const []), isEmpty);
    });
  });

  group('LectureSummary.copyWith (Fix 2 thumbnail adoption)', () {
    test('replaces only the thumbnailUrl', () {
      const summary = LectureSummary(
        id: 'lec-1',
        title: 'محاضرة 1',
        status: 'published',
        displayOrder: 1,
        isLocked: false,
        sectionId: 'sec-1',
        duration: Duration(minutes: 10),
      );

      final updated = summary.copyWith(thumbnailUrl: 'https://signed/poster.jpg');

      expect(updated.thumbnailUrl, 'https://signed/poster.jpg');
      expect(updated.id, summary.id);
      expect(updated.title, summary.title);
      expect(updated.duration, summary.duration);
      expect(updated.sectionId, summary.sectionId);
    });

    test('keeps the existing url when copyWith receives null', () {
      const summary = LectureSummary(
        id: 'lec-2',
        title: 'محاضرة 2',
        status: 'published',
        displayOrder: 2,
        isLocked: false,
        thumbnailUrl: 'https://keep/me.jpg',
      );

      expect(summary.copyWith().thumbnailUrl, 'https://keep/me.jpg');
    });
  });
}
