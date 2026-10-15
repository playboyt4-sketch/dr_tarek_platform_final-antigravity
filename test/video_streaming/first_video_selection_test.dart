import 'package:flutter_test/flutter_test.dart';
import 'package:dr_tarek_platform/features/video_streaming/domain/entities/playback_entities.dart';
import 'package:dr_tarek_platform/features/subject_navigation/domain/entities/subject_learning_entities.dart';

VideoResource _video(
  String id,
  int order, {
  String? bunnyVideoId,
  String type = 'video',
}) {
  return VideoResource(
    id: id,
    title: 'مورد $id',
    resourceType: type,
    bunnyVideoId: bunnyVideoId,
    displayOrder: order,
  );
}

// VIDEO-ID-ONLY fixtures: bare Bunny GUIDs.
const String _guid1 = '11111111-1111-4111-8111-111111111111';
const String _guid2 = '22222222-2222-4222-8222-222222222222';
const String _guid5 = '55555555-5555-4555-8555-555555555555';
const String _guid9 = '99999999-9999-4999-8999-999999999999';
const String _guidA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const String _guidB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

void main() {
  group('firstPlayableVideo (canonical client fallback selection)', () {
    test('single eligible video wins', () {
      final winner = firstPlayableVideo([
        _video('v1', 1, bunnyVideoId: _guid1),
      ]);

      expect(winner?.id, 'v1');
    });

    test('no videos yields null', () {
      expect(firstPlayableVideo(const []), isNull);
      expect(
        firstPlayableVideo([
          _video('p1', 0, type: 'pdf'),
          _video('a1', 1, type: 'attachment'),
        ]),
        isNull,
      );
    });

    test('lowest display_order wins regardless of input order', () {
      final winner = firstPlayableVideo([
        _video('v-high', 9, bunnyVideoId: _guid9),
        _video('v-low', 2, bunnyVideoId: _guid2),
        _video('v-mid', 5, bunnyVideoId: _guid5),
      ]);

      expect(winner?.id, 'v-low');
    });

    test('document id ascending breaks display_order ties', () {
      final winner = firstPlayableVideo([
        _video('v-b', 3, bunnyVideoId: _guidB),
        _video('v-a', 3, bunnyVideoId: _guidA),
      ]);

      expect(winner?.id, 'v-a');
    });

    test('non-video types are ignored even at order zero', () {
      final winner = firstPlayableVideo([
        _video('p0', 0, type: 'pdf'),
        _video('v1', 4, bunnyVideoId: _guid1),
      ]);

      expect(winner?.id, 'v1');
    });

    test('missing bunny_video_id is ignored', () {
      final winner = firstPlayableVideo([
        _video('v-noid', 0),
        _video('v1', 7, bunnyVideoId: _guid1),
      ]);

      expect(winner?.id, 'v1');
    });

    test('empty or blank bunny_video_id is ignored', () {
      // Blank ids sanitize to null on the real payload path
      // (VideoResource._sanitizeBunnyId trims), so they never qualify.
      VideoResource viaPayload(String id, int order, String? bunny) {
        return VideoResource.fromCallablePayload({
          'id': id,
          'resourceType': 'video',
          'bunnyVideoId': bunny,
          'displayOrder': order,
        });
      }

      final winner = firstPlayableVideo([
        viaPayload('v-empty', 0, ''),
        viaPayload('v-blank', 1, '   '),
        viaPayload('v1', 8, _guid1),
      ]);

      expect(winner?.id, 'v1');
    });

    test('player/share URLs are ignored (VIDEO-ID-ONLY)', () {
      VideoResource viaPayload(String id, int order, String? bunny) {
        return VideoResource.fromCallablePayload({
          'id': id,
          'resourceType': 'video',
          'bunnyVideoId': bunny,
          'displayOrder': order,
        });
      }

      final winner = firstPlayableVideo([
        viaPayload('v-url', 0,
            'https://iframe.mediadelivery.net/embed/12345/$_guid1'),
        viaPayload('v-id', 5, _guid2),
      ]);

      // The URL row is not playable, so the bare-ID row wins despite
      // the higher display_order.
      expect(winner?.id, 'v-id');
    });
  });

  group('VideoResource displayOrder mapping', () {
    test('callable displayOrder maps, defaulting to zero', () {
      final mapped = VideoResource.fromCallablePayload({
        'id': 'v1',
        'resourceType': 'video',
        'bunnyVideoId': _guid1,
        'displayOrder': 4,
      });
      expect(mapped.displayOrder, 4);

      final legacy = VideoResource.fromCallablePayload({
        'id': 'v2',
        'resourceType': 'video',
        'bunnyVideoId': _guid2,
      });
      expect(legacy.displayOrder, 0);
    });

    test('isValidBunnyVideoId accepts bare GUIDs and rejects URLs', () {
      expect(VideoResource.isValidBunnyVideoId(_guid1), isTrue);
      expect(
          VideoResource.isValidBunnyVideoId(
              'https://iframe.mediadelivery.net/embed/1/$_guid1'),
          isFalse);
      expect(VideoResource.isValidBunnyVideoId(''), isFalse);
      expect(VideoResource.isValidBunnyVideoId(null), isFalse);
    });
  });

  group('FirstVideoRef.fromLectureData (null-safe contract parse)', () {
    test('malformed maps fall back to null', () {
      expect(FirstVideoRef.fromLectureData(const {}), isNull);
      expect(
        FirstVideoRef.fromLectureData({
          'first_video': 'not-a-map',
        }),
        isNull,
      );
      expect(
        FirstVideoRef.fromLectureData({
          'first_video': {'title': 'orphan'},
        }),
        isNull,
      );
      expect(
        FirstVideoRef.fromLectureData({
          'first_video': {'resource_id': '  ', 'bunny_video_id': ''},
        }),
        isNull,
      );
    });

    test('valid map parses with reserved poster keys', () {
      final ref = FirstVideoRef.fromLectureData({
        'first_video': {
          'resource_id': 'res-1',
          'bunny_video_id': _guid1,
          'title': 'الفيديو الأول',
          'display_order': 2,
          'thumbnail_path': 'thumbs/res-1.jpg',
          'thumbnail_storage_provider': 'firebase',
        },
      });

      expect(ref, isNotNull);
      expect(ref?.resourceId, 'res-1');
      expect(ref?.bunnyVideoId, _guid1);
      expect(ref?.title, 'الفيديو الأول');
      expect(ref?.displayOrder, 2);
      expect(ref?.thumbnailPath, 'thumbs/res-1.jpg');
      expect(ref?.thumbnailStorageProvider, 'firebase');
    });
  });
}
