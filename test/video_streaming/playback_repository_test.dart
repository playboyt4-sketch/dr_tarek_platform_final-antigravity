import 'package:dr_tarek_platform/features/video_streaming/data/repositories/playback_repository.dart';
import 'package:dr_tarek_platform/features/video_streaming/domain/entities/playback_entities.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('restores Episode 1 from 03:24 after leaving and reopening', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = PlaybackRepositoryImpl(
      userId: 'student-1',
      localStore: preferences,
    );
    final savedAt = DateTime(2026, 8, 15, 10, 0);
    final record = PlaybackProgressRecord(
      userId: 'student-1',
      lectureId: 'episode-1',
      subjectId: 'subject-1',
      sectionId: 'season-1',
      lectureTitle: 'Episode 1',
      position: const Duration(minutes: 3, seconds: 24),
      duration: const Duration(minutes: 20),
      progressPercent: .17,
      completed: false,
      updatedAt: savedAt,
    );

    await repository.save(record, syncCloud: false);
    final restored = await repository.read('episode-1');

    expect(restored, isNotNull);
    expect(restored!.position, const Duration(minutes: 3, seconds: 24));
    expect(restored.subjectId, 'subject-1');
    expect(ProgressMath.resumeAction(restored), ResumeAction.continueWatching);

    final continueWatching = await repository.getContinueWatching();
    expect(
      continueWatching.map((item) => item.lectureId),
      contains('episode-1'),
    );
  });
}
