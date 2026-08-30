import 'package:flutter_test/flutter_test.dart';
import 'package:dr_tarek_platform/features/video_streaming/domain/entities/playback_entities.dart';

void main() {
  group('VideoResource.fromCallablePayload (storage-delivery Fix 2 shape)', () {
    test('prefers the server-resolved thumbnailUrl over the raw path', () {
      final resource = VideoResource.fromCallablePayload({
        'id': 'res-1',
        'title': 'محاضرة',
        'resourceType': 'video',
        'bunnyVideoId': 'vid-1',
        // Server now returns BOTH: legacy raw path and resolved URL.
        'thumbnail': 'lecture_resources/lec-1/res-1/poster.jpg',
        'thumbnailUrl':
            'https://storage.googleapis.com/b/lecture_resources%2Flec-1%2Fres-1%2Fposter.jpg?X-Goog-Signature=abc',
        'thumbnailProvider': 'firebase',
        'storageProvider': 'firebase',
      });

      expect(resource.thumbnailUrl, contains('X-Goog-Signature'));
      expect(resource.thumbnailUrl, isNot(contains('lecture_resources/')));
    });

    test('parses a resolved Bunny token URL unchanged', () {
      const bunnyUrl =
          'https://dr-tarek-resources.b-cdn.net/lecture_resources/lec-1/res-2/poster.jpg?token=tok&expires=1234';
      final resource = VideoResource.fromCallablePayload({
        'id': 'res-2',
        'title': 'مرفق',
        'resourceType': 'video',
        'bunnyVideoId': 'vid-2',
        'thumbnailUrl': bunnyUrl,
        'thumbnailProvider': 'bunny',
      });

      expect(resource.thumbnailUrl, bunnyUrl);
      expect(resource.thumbnailProvider, 'bunny');
    });

    test('legacy payloads without thumbnailUrl fall back to raw thumbnail', () {
      final resource = VideoResource.fromCallablePayload({
        'id': 'res-3',
        'resourceType': 'pdf',
        'thumbnail': 'https://legacy.example.com/poster.jpg',
      });

      expect(resource.thumbnailUrl, 'https://legacy.example.com/poster.jpg');
      expect(resource.storageProvider, 'firebase');
    });

    test('documents are flagged; only videos with ids are playable', () {
      final pdf = VideoResource.fromCallablePayload(
          {'id': 'p', 'resourceType': 'pdf'});
      final attachment = VideoResource.fromCallablePayload(
          {'id': 'a', 'resourceType': 'attachment'});
      final video = VideoResource.fromCallablePayload(
          {'id': 'v', 'resourceType': 'video', 'bunnyVideoId': 'x'});
      final videoNoId = VideoResource.fromCallablePayload(
          {'id': 'w', 'resourceType': 'video'});

      expect(pdf.isDocument, isTrue);
      expect(pdf.resourceType, 'pdf');
      expect(attachment.isDocument, isTrue);
      expect(attachment.resourceType, 'attachment');
      expect(video.isDocument, isFalse);
      expect(video.isVideo, isTrue);
      expect(videoNoId.isVideo, isFalse);
    });
  });
}
