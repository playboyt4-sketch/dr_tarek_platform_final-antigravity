import 'package:flutter_test/flutter_test.dart';

import 'package:dr_tarek_platform/features/video_streaming/domain/entities/playback_entities.dart';

/// FINAL_DECISIONS §11: per-lecture Public Free preview cap policy.
void main() {
  group('PreviewCapPolicy — cap resolution', () {
    test('no cap when the gate is not armed (normal subscriber)', () {
      const resource = VideoResource(
        id: 'r',
        title: 't',
        resourceType: 'video',
        bunnyVideoId: 'b1',
      );
      expect(PreviewCapPolicy.capFor(resource), isNull);
    });

    test('zero cap when armed with 0 seconds — wall immediately', () {
      const resource = VideoResource(
        id: 'r',
        title: 't',
        resourceType: 'video',
        bunnyVideoId: 'b1',
        isPublicFreePreview: true,
        publicFreePreviewSeconds: 0,
      );
      expect(PreviewCapPolicy.capFor(resource), Duration.zero);
    });

    test('five-minute lecture cap resolves to a Duration', () {
      const resource = VideoResource(
        id: 'r',
        title: 't',
        resourceType: 'video',
        bunnyVideoId: 'b1',
        isPublicFreePreview: true,
        publicFreePreviewSeconds: 300,
      );
      expect(PreviewCapPolicy.capFor(resource), const Duration(minutes: 5));
    });
  });

  group('PreviewCapPolicy — enforcement predicates', () {
    test('shouldStop triggers exactly at/after the cap', () {
      const cap = Duration(minutes: 5);
      expect(PreviewCapPolicy.shouldStop(const Duration(minutes: 4, seconds: 59), cap),
          isFalse);
      expect(PreviewCapPolicy.shouldStop(cap, cap), isTrue);
      expect(PreviewCapPolicy.shouldStop(const Duration(minutes: 7), cap), isTrue);
      expect(PreviewCapPolicy.shouldStop(const Duration(hours: 2), null), isFalse);
    });

    test('seeking may never jump past the cap', () {
      const cap = Duration(minutes: 5);
      expect(
        PreviewCapPolicy.clampSeek(const Duration(minutes: 40), cap),
        cap,
      );
      expect(
        PreviewCapPolicy.clampSeek(const Duration(minutes: 2), cap),
        const Duration(minutes: 2),
      );
      // Unlimited playback fences nothing.
      expect(
        PreviewCapPolicy.clampSeek(const Duration(hours: 3), null),
        const Duration(hours: 3),
      );
    });
  });

  group('VideoResource wire defaults', () {
    test('storageProvider defaults to firebase for legacy payloads (§15)',
        () {
      const resource = VideoResource(id: 'r', title: 't', resourceType: 'pdf');
      expect(resource.storageProvider, 'firebase');
      expect(resource.isPublicFreePreview, isFalse);
    });
  });
}
