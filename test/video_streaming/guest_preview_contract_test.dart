import 'package:flutter_test/flutter_test.dart';

import 'package:dr_tarek_platform/features/content_authoring/data/datasources/admin_content_remote_data_source_impl.dart'
    show guestPreviewFromLectureMap;
import 'package:dr_tarek_platform/features/lecture/domain/entities/lecture.dart';
import 'package:dr_tarek_platform/features/video_streaming/data/services/video_source_resolver.dart'
    show guestPreviewFromResponse, parsePreviewAudience;
import 'package:dr_tarek_platform/features/video_streaming/domain/entities/playback_entities.dart';

/// Phase 2A Guest preview contract verification (FINAL_DECISIONS §11):
/// backend emits `guestPreview`; lecture docs carry `guest_enabled` /
/// `guest_preview_minutes`. Behavior is unchanged — only terminology moved.
void main() {
  group('guestPreviewFromResponse — callable contract', () {
    test('canonical guestPreview key is parsed', () {
      final parsed = guestPreviewFromResponse({
        'guestPreview': {'previewLimitSeconds': 300},
        'resources': [],
      });
      expect(parsed, {'previewLimitSeconds': 300});
    });

    test('parser does not require the legacy key for normal operation', () {
      // No publicFreePreview present at all — canonical path suffices.
      final parsed = guestPreviewFromResponse({
        'guestPreview': {'previewLimitSeconds': 120},
      });
      expect(parsed?['previewLimitSeconds'], 120);
    });

    test('absent preview means no gate (normal subscriber)', () {
      expect(guestPreviewFromResponse({'resources': []}), isNull);
    });

    test('legacy alias still honored during transition', () {
      final parsed = guestPreviewFromResponse({
        'publicFreePreview': {'previewLimitSeconds': 60},
      });
      expect(parsed?['previewLimitSeconds'], 60);
    });

    test('canonical key wins when both are present', () {
      final parsed = guestPreviewFromResponse({
        'guestPreview': {'previewLimitSeconds': 300},
        'publicFreePreview': {'previewLimitSeconds': 60},
      });
      expect(parsed?['previewLimitSeconds'], 300);
    });
  });

  group('guestPreviewFromLectureMap — Firestore field mapping', () {
    test('canonical guest_* fields map correctly', () {
      final preview = guestPreviewFromLectureMap({
        'guest_enabled': true,
        'guest_preview_minutes': 5,
      });
      expect(preview.guestEnabled, isTrue);
      expect(preview.guestPreviewMinutes, 5);
    });

    test('absent fields deny by default', () {
      final preview = guestPreviewFromLectureMap({});
      expect(preview.guestEnabled, isFalse);
      expect(preview.guestPreviewMinutes, isNull);
    });

    test('legacy fields honored during transition', () {
      final preview = guestPreviewFromLectureMap({
        'public_free_enabled': true,
        'public_free_preview_minutes': 4,
      });
      expect(preview.guestEnabled, isTrue);
      expect(preview.guestPreviewMinutes, 4);
    });

    test('canonical fields win over legacy when both present', () {
      final preview = guestPreviewFromLectureMap({
        'guest_enabled': false,
        'guest_preview_minutes': 9,
        'public_free_enabled': true,
        'public_free_preview_minutes': 4,
      });
      expect(preview.guestEnabled, isFalse);
      expect(preview.guestPreviewMinutes, 9);
    });
  });

  group('Guest preview end-to-end semantics (unchanged behavior)', () {
    test('guest + guest plan + enabled lecture stamps a capped preview', () {
      final gate = guestPreviewFromResponse({
        'guestPreview': {'previewLimitSeconds': 300},
      });
      const base = VideoResource(
        id: 'r',
        title: 't',
        resourceType: 'video',
        bunnyVideoId: '44444444-4444-4444-8444-444444444444',
      );
      final stamped = VideoResource(
        id: base.id,
        title: base.title,
        resourceType: base.resourceType,
        bunnyVideoId: base.bunnyVideoId,
        thumbnailUrl: base.thumbnailUrl,
        storageProvider: base.storageProvider,
        thumbnailProvider: base.thumbnailProvider,
        duration: base.duration,
        isGuestPreview: gate != null,
        guestPreviewSeconds:
            (gate?['previewLimitSeconds'] as num?)?.toInt(),
      );
      expect(stamped.isGuestPreview, isTrue);
      expect(
        PreviewCapPolicy.capFor(stamped),
        const Duration(minutes: 5),
      );
    });

    test('lecture entity carries guest preview state', () {
      const lecture = Lecture(
        id: 'l1',
        sectionId: 's1',
        title: 't',
        description: 'd',
        displayOrder: 1,
        publishDate: null,
        status: LectureStatus.published,
        guestEnabled: true,
        guestPreviewMinutes: 5,
      );
      expect(lecture.guestEnabled, isTrue);
      expect(lecture.guestPreviewMinutes, 5);
    });

    test('previewAudience travels inside the verdict map when present', () {
      final gate = guestPreviewFromResponse({
        'guestPreview': {'previewLimitSeconds': 0, 'previewAudience': 'guest'},
      });
      expect(parsePreviewAudience(gate?['previewAudience']), 'guest');
    });

    test('lecture entity defaults deny preview (no whole-subject access)', () {
      const lecture = Lecture(
        id: 'l1',
        sectionId: 's1',
        title: 't',
        description: 'd',
        displayOrder: 1,
        publishDate: null,
        status: LectureStatus.published,
      );
      expect(lecture.guestEnabled, isFalse);
      expect(lecture.guestPreviewMinutes, isNull);
    });
  });
}
