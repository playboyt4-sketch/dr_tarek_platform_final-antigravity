// ADR-010 — first-video metadata consistency (mobile authoring).
//
// The mobile `_syncLectureFirstVideo` writer must serialize the same
// `first_video` shape as the Dashboard and the server, including the additive
// `bunny_library_id` hint. The authoritative association remains the resource
// document; this projection must never drop or invent it.
import 'package:dr_tarek_platform/features/content_authoring/data/datasources/admin_content_remote_data_source_impl.dart'
    show lectureFirstVideoFields;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('lectureFirstVideoFields', () {
    test('carries the verified library hint', () {
      final Map<String, Object?> fields = lectureFirstVideoFields(
        resourceId: 'res-1',
        bunnyVideoId: '7ddd0e6e-a0ae-43f6-a11c-ff7ca5db1c31',
        bunnyLibraryId: '736742',
        title: 'Lecture 1',
        displayOrder: 2,
      );

      expect(fields['resource_id'], 'res-1');
      expect(
        fields['bunny_video_id'],
        '7ddd0e6e-a0ae-43f6-a11c-ff7ca5db1c31',
      );
      expect(fields['bunny_library_id'], '736742');
      expect(fields['title'], 'Lecture 1');
      expect(fields['display_order'], 2);
      expect(fields['thumbnail_path'], isNull);
      expect(fields['thumbnail_storage_provider'], isNull);
    });

    test('legacy rows keep a null library (default-library fallback)', () {
      final Map<String, Object?> fields = lectureFirstVideoFields(
        resourceId: 'res-legacy',
        bunnyVideoId: 'legacy-guid',
      );

      expect(fields['bunny_library_id'], isNull);
      expect(fields['title'], isNull);
      expect(fields['display_order'], 0);
    });

    test('exposes identity + display metadata only', () {
      final Map<String, Object?> fields = lectureFirstVideoFields(
        resourceId: 'res-2',
        bunnyVideoId: 'guid',
        bunnyLibraryId: '775315',
      );

      expect(
        fields.keys.toSet(),
        <String>{
          'resource_id',
          'bunny_video_id',
          'bunny_library_id',
          'title',
          'display_order',
          'thumbnail_path',
          'thumbnail_storage_provider',
        },
      );
      expect(
        fields.values
            .whereType<String>()
            .any((String value) => value.contains('http')),
        isFalse,
      );
    });
  });
}
