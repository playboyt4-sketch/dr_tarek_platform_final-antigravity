// ADR-010 — Flutter parsing of additive Bunny library metadata.
//
// The client only ever DESERIALIZES the library id the server resolved. These
// tests lock: additive parsing, legacy payloads, malformed values degrading to
// the legacy path (never throwing), and the fast-lane `first_video` pointer.
import 'package:dr_tarek_platform/features/subject_navigation/domain/entities/subject_learning_entities.dart';
import 'package:dr_tarek_platform/features/video_streaming/domain/entities/playback_entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VideoResource.fromCallablePayload (ADR-010 additive field)', () {
    test('parses the library id alongside the video id', () {
      final VideoResource resource = VideoResource.fromCallablePayload(
        <String, dynamic>{
          'id': 'res-1',
          'title': 'المحاضرة الأولى',
          'resourceType': 'video',
          'bunnyVideoId': '7ddd0e6e-0000-0000-0000-000000000000',
          'bunnyLibraryId': '775315',
        },
      );
      expect(resource.bunnyVideoId, '7ddd0e6e-0000-0000-0000-000000000000');
      expect(resource.bunnyLibraryId, '775315');
      expect(resource.isVideo, isTrue);
    });

    test('legacy payload without the field still parses', () {
      final VideoResource resource = VideoResource.fromCallablePayload(
        <String, dynamic>{
          'id': 'res-legacy',
          'title': 'Legacy',
          'resourceType': 'video',
          'bunnyVideoId': '94710db9-0000-0000-0000-000000000000',
        },
      );
      expect(resource.bunnyLibraryId, isNull);
      expect(resource.isVideo, isTrue);
    });

    test('malformed library metadata degrades to null, never throws', () {
      for (final Object? raw in <Object?>['', '   ', 'library-a', 775315, <String>[]]) {
        final VideoResource resource = VideoResource.fromCallablePayload(
          <String, dynamic>{
            'id': 'res-bad',
            'resourceType': 'video',
            'bunnyVideoId': '4dd8a3b0-0000-0000-0000-000000000000',
            'bunnyLibraryId': raw,
          },
        );
        expect(resource.bunnyLibraryId, isNull, reason: 'raw=$raw');
      }
    });

    test('a non-string video id cannot break the listing', () {
      final VideoResource resource = VideoResource.fromCallablePayload(
        <String, dynamic>{'id': 'res-x', 'bunnyVideoId': 42},
      );
      expect(resource.bunnyVideoId, isNull);
      expect(resource.isVideo, isFalse);
    });
  });

  group('FirstVideoRef library metadata', () {
    test('reads bunny_library_id from the pointer', () {
      final FirstVideoRef? ref = FirstVideoRef.fromLectureData(
        <String, dynamic>{
          'first_video': <String, dynamic>{
            'resource_id': 'res-1',
            'bunny_video_id': '7ddd0e6e-0000-0000-0000-000000000000',
            'bunny_library_id': '775315',
            'title': 'المحاضرة الأولى',
            'display_order': 1,
          },
        },
      );
      expect(ref, isNotNull);
      expect(ref!.bunnyLibraryId, '775315');
    });

    test('legacy pointer without the field keeps a null library', () {
      final FirstVideoRef? ref = FirstVideoRef.fromLectureData(
        <String, dynamic>{
          'first_video': <String, dynamic>{
            'resource_id': 'res-2',
            'bunny_video_id': '94710db9-0000-0000-0000-000000000000',
          },
        },
      );
      expect(ref, isNotNull);
      expect(ref!.bunnyLibraryId, isNull);
    });
  });
}
