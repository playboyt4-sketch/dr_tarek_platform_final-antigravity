import 'package:dr_tarek_platform/features/video_streaming/domain/entities/playback_entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProgressMath', () {
    test('calculates a stable percentage and clamps overflow', () {
      expect(
        ProgressMath.percent(
          const Duration(seconds: 30),
          const Duration(minutes: 2),
        ),
        .25,
      );
      expect(
        ProgressMath.percent(
          const Duration(minutes: 3),
          const Duration(minutes: 2),
        ),
        1,
      );
      expect(ProgressMath.percent(Duration.zero, Duration.zero), 0);
    });

    test('marks playback complete at the configured threshold', () {
      expect(
        ProgressMath.isCompleted(
          const Duration(seconds: 95),
          const Duration(seconds: 100),
        ),
        isTrue,
      );
      expect(
        ProgressMath.isCompleted(
          const Duration(seconds: 94),
          const Duration(seconds: 100),
        ),
        isFalse,
      );
    });

    test('offers resume only for meaningful non-complete progress', () {
      final record = PlaybackProgressRecord(
        userId: 'student-1',
        lectureId: 'episode-1',
        position: const Duration(minutes: 3, seconds: 24),
        duration: const Duration(minutes: 20),
        progressPercent: .17,
        completed: false,
        updatedAt: DateTime(2026, 1, 1),
      );
      expect(ProgressMath.resumeAction(record), ResumeAction.continueWatching);
      expect(
        ProgressMath.resumeAction(record.copyWith(completed: true)),
        ResumeAction.none,
      );
      expect(
        ProgressMath.resumeAction(
          record.copyWith(position: const Duration(seconds: 1)),
        ),
        ResumeAction.none,
      );
    });

    test('clamps seek to the media duration', () {
      expect(
        ProgressMath.clampPosition(
          const Duration(seconds: 999),
          const Duration(minutes: 2),
        ),
        const Duration(minutes: 2),
      );
      expect(
        ProgressMath.clampPosition(
          const Duration(seconds: -1),
          const Duration(minutes: 2),
        ),
        Duration.zero,
      );
    });
  });

  group('VideoQuality', () {
    test('enforces the backend maximum quality locally for UX', () {
      expect(VideoQuality.q1080.isAllowedBy('720p'), isFalse);
      expect(VideoQuality.q720.isAllowedBy('720p'), isTrue);
      expect(VideoQuality.auto.isAllowedBy('360p'), isTrue);
    });
  });

  group('EpisodeNavigation', () {
    test('returns next and previous episode only inside bounds', () {
      expect(EpisodeNavigation.nextIndex(currentIndex: 0, count: 3), 1);
      expect(EpisodeNavigation.nextIndex(currentIndex: 2, count: 3), isNull);
      expect(EpisodeNavigation.previousIndex(currentIndex: 1, count: 3), 0);
      expect(
        EpisodeNavigation.previousIndex(currentIndex: 0, count: 3),
        isNull,
      );
    });
  });
}
