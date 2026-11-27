import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dr_tarek_platform/features/authentication/domain/entities/auth_user.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/providers/auth_provider.dart';
import 'package:dr_tarek_platform/features/membership/presentation/widgets/center_phone_actions.dart';
import 'package:dr_tarek_platform/features/subject_navigation/data/datasources/subject_navigation_remote_data_source.dart';
import 'package:dr_tarek_platform/features/subject_navigation/domain/entities/subject_learning_entities.dart';
import 'package:dr_tarek_platform/features/subject_navigation/presentation/widgets/lecture_download_button.dart';
import 'package:dr_tarek_platform/features/video_streaming/data/services/video_download_service.dart';
import 'package:dr_tarek_platform/features/video_streaming/domain/entities/playback_entities.dart';

class _FreeUpgradeDownloadController extends VideoDownloadController {
  @override
  Map<String, LectureDownloadState> build() => const <String, LectureDownloadState>{};

  @override
  Future<void> syncLectureStatus({
    required String subjectId,
    required String lectureId,
  }) async {}

  @override
  Future<VideoDownloadActionOutcome> downloadLecture({
    required String userId,
    required String subjectId,
    required LectureSummary lecture,
    VideoQuality preferredQuality = VideoQuality.q720,
  }) async {
    return const VideoDownloadActionOutcome(
      success: false,
      requiresUpgrade: true,
      currentPlanLabel: 'FREE',
      message: 'تحميل الفيديوهات أوفلاين متاح في باقتي Pro و Max فقط.',
    );
  }
}

class _ProgressDownloadController extends VideoDownloadController {
  final Map<String, LectureDownloadState> _initial;
  _ProgressDownloadController(this._initial);

  @override
  Map<String, LectureDownloadState> build() => _initial;

  @override
  Future<void> syncLectureStatus({
    required String subjectId,
    required String lectureId,
  }) async {}
}

class _FakeAuthNotifier extends AuthController {
  final AuthUser? user;
  _FakeAuthNotifier(this.user);

  @override
  Future<AuthUser?> build() async => user;
}

const _student = AuthUser(
  id: 'student-1',
  fullName: 'Student',
  phoneNumber: '01012345678',
  role: 'student',
  approvalStatus: 'approved',
  accountStatus: 'active',
);

const _lecture = LectureSummary(
  id: 'lec-1',
  title: 'المحاضرة الأولى',
  status: 'published',
  displayOrder: 1,
  isLocked: false,
);

void main() {
  group('LectureDownloadButton Free upgrade & determinate progress', () {
    testWidgets(
      'opens upgrade bottom sheet with CenterPhoneActions when Free user taps download without spinning',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authProvider.overrideWith(() => _FakeAuthNotifier(_student)),
              videoDownloadControllerProvider.overrideWith(
                _FreeUpgradeDownloadController.new,
              ),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: Center(
                  child: LectureDownloadButton(
                    lecture: _lecture,
                    subjectId: 'sub-1',
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.file_download_outlined));
        await tester.pumpAndSettle();

        expect(find.text('تحميل المحاضرات متاح لـ Pro و Max'), findsOneWidget);
        expect(find.byType(CenterPhoneActions), findsOneWidget);
        expect(find.byKey(const ValueKey('center_phone_copy_btn')), findsOneWidget);
        expect(find.byKey(const ValueKey('center_phone_call_btn')), findsOneWidget);
        expect(find.byKey(const ValueKey('center_phone_whatsapp_btn')), findsOneWidget);
      },
    );

    testWidgets(
      'renders determinate CircularProgressIndicator and percentage text inside button',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authProvider.overrideWith(() => _FakeAuthNotifier(_student)),
              videoDownloadControllerProvider.overrideWith(
                () => _ProgressDownloadController({
                  'lec-1': const LectureDownloadState(
                    isDownloading: true,
                    progress: 0.45,
                    subjectId: 'sub-1',
                    isVideo: true,
                  ),
                }),
              ),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: Center(
                  child: LectureDownloadButton(
                    lecture: _lecture,
                    subjectId: 'sub-1',
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final indicator = tester.widget<CircularProgressIndicator>(
          find.byType(CircularProgressIndicator),
        );
        expect(indicator.value, closeTo(0.45, 0.001));
        expect(find.text('45%'), findsOneWidget);
      },
    );

    testWidgets(
      'renders preparing spinner before bytes start streaming so tap never appears dead',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authProvider.overrideWith(() => _FakeAuthNotifier(_student)),
              videoDownloadControllerProvider.overrideWith(
                () => _ProgressDownloadController({
                  'lec-1': const LectureDownloadState(
                    isDownloading: true,
                    isPreparing: true,
                    progress: 0.0,
                    subjectId: 'sub-1',
                    isVideo: true,
                  ),
                }),
              ),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: Center(
                  child: LectureDownloadButton(
                    lecture: _lecture,
                    subjectId: 'sub-1',
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final indicator = tester.widget<CircularProgressIndicator>(
          find.byType(CircularProgressIndicator),
        );
        expect(indicator.value, isNull);
      },
    );
  });

  group('parseFlexibleLectureDuration', () {
    test('parses numeric, nested first_video/video, and string durations cleanly', () {
      expect(
        parseFlexibleLectureDuration({'duration_seconds': 3163}),
        const Duration(seconds: 3163),
      );
      expect(
        parseFlexibleLectureDuration({'durationSeconds': 125}),
        const Duration(seconds: 125),
      );
      expect(
        parseFlexibleLectureDuration({'video_duration': '52:43'}),
        const Duration(minutes: 52, seconds: 43),
      );
      expect(
        parseFlexibleLectureDuration({
          'first_video': {'duration_seconds': '01:15:20'},
        }),
        const Duration(hours: 1, minutes: 15, seconds: 20),
      );
      expect(
        parseFlexibleLectureDuration({'duration_minutes': 45}),
        const Duration(minutes: 45),
      );
      expect(parseFlexibleLectureDuration({'duration_seconds': 0}), isNull);
      expect(parseFlexibleLectureDuration({'duration': '00:00'}), isNull);
      expect(parseFlexibleLectureDuration({}), isNull);
    });
  });
}
