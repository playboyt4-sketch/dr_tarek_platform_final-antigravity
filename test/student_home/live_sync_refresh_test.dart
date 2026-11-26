import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dr_tarek_platform/features/authentication/domain/entities/auth_user.dart';
import 'package:dr_tarek_platform/features/student_dashboard/domain/entities/dashboard_subject.dart';
import 'package:dr_tarek_platform/features/student_dashboard/presentation/providers/dashboard_providers.dart';
import 'package:dr_tarek_platform/features/student_home/presentation/screens/student_home_screen.dart';
import 'package:dr_tarek_platform/features/subject_navigation/domain/entities/subject_learning_entities.dart';
import 'package:dr_tarek_platform/features/subject_navigation/presentation/providers/subject_navigation_providers.dart';
import 'package:dr_tarek_platform/features/subject_navigation/presentation/screens/subject_navigation_screen.dart';
import 'package:dr_tarek_platform/l10n/generated/app_localizations.dart';

void main() {
  testWidgets(
    'StudentHomeScreen updates cover poster key and title live from stream, supports RefreshIndicator and app resume',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final controller = StreamController<List<DashboardSubject>>.broadcast();
      addTearDown(controller.close);
      var subscriptionCount = 0;

      const user = AuthUser(
        id: 'stu-1',
        fullName: 'Tarek Student',
        phoneNumber: '01000000000',
        role: 'student',
        studentType: 'guest',
        grade: 'grade_one',
        approvalStatus: 'approved',
        accountStatus: 'active',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dashboardSubjectsProvider.overrideWith((ref) {
              subscriptionCount++;
              return controller.stream;
            }),
          ],
          child: MaterialApp(
            locale: const Locale('ar'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: StudentHomeScreen(user: user),
          ),
        ),
      );

      controller.add([
        DashboardSubject(
          id: 'sub-1',
          title: 'الفيزياء',
          thumbnailUrl: 'https://example.com/poster_v1.png',
          displayOrder: 1,
          updatedAt: DateTime.utc(2026, 11, 26, 10, 0),
        ),
      ]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('الفيزياء'), findsOneWidget);
      expect(
        find.byKey(
          ValueKey(
            'sub-1|https://example.com/poster_v1.png|${DateTime.utc(2026, 11, 26, 10, 0).millisecondsSinceEpoch}',
          ),
        ),
        findsOneWidget,
      );

      // Live Firestore update changes subject name & poster URL without restarting.
      controller.add([
        DashboardSubject(
          id: 'sub-1',
          title: 'الفيزياء الحديثة',
          thumbnailUrl: 'https://example.com/poster_v2.png',
          displayOrder: 1,
          updatedAt: DateTime.utc(2026, 11, 26, 11, 0),
        ),
      ]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('الفيزياء الحديثة'), findsOneWidget);
      expect(
        find.byKey(
          ValueKey(
            'sub-1|https://example.com/poster_v2.png|${DateTime.utc(2026, 11, 26, 11, 0).millisecondsSinceEpoch}',
          ),
        ),
        findsOneWidget,
      );

      // Pull-to-refresh widget is present on Home.
      expect(find.byType(RefreshIndicator), findsOneWidget);

      // App resume triggers provider refresh/re-subscription.
      final beforeResumeCount = subscriptionCount;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      controller.add([
        const DashboardSubject(
          id: 'sub-1',
          title: 'الفيزياء الحديثة',
          thumbnailUrl: 'https://example.com/poster_v2.png',
          displayOrder: 1,
        ),
      ]);
      await tester.pump();
      expect(subscriptionCount, greaterThan(beforeResumeCount));
    },
  );

  testWidgets(
    'SubjectNavigationScreen updates lectures live from StreamProvider and renders RefreshIndicator',
    (tester) async {
      final sectionsController =
          StreamController<List<LearningSection>>.broadcast();
      final lecturesController =
          StreamController<List<LectureSummary>>.broadcast();
      addTearDown(() async {
        await sectionsController.close();
        await lecturesController.close();
      });

      const subject = DashboardSubject(
        id: 'sub-1',
        title: 'الكيمياء',
        gradeKey: 'grade_one',
        displayOrder: 1,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dashboardSubjectsProvider.overrideWith(
              (ref) => Stream.value(const [subject]),
            ),
            subjectSectionsProvider('sub-1')
                .overrideWith((ref) => sectionsController.stream),
            sectionLecturesProvider('sec-1')
                .overrideWith((ref) => lecturesController.stream),
            sectionDisplayMediaProvider('sec-1').overrideWith(
              (ref) async => const <String, LectureDisplayMedia>{},
            ),
          ],
          child: const MaterialApp(
            home: SubjectNavigationScreen(subject: subject),
          ),
        ),
      );

      await tester.pump();
      sectionsController.add(const [
        LearningSection(
          id: 'sec-1',
          title: 'الشرح',
          sectionKey: 'explanation',
          isSystemSection: true,
          displayOrder: 0,
          isVisible: true,
          isLocked: false,
        ),
      ]);
      await tester.pump();
      await tester.pump();

      lecturesController.add(const [
        LectureSummary(
          id: 'lec-1',
          title: 'المحاضرة الأولى',
          status: 'not_started',
          displayOrder: 0,
          isLocked: false,
          subjectId: 'sub-1',
          sectionId: 'sec-1',
          thumbnailUrl: 'https://example.com/lec1.png',
        ),
      ]);
      await tester.pump();
      await tester.pump();

      expect(find.text('المحاضرة الأولى'), findsOneWidget);
      expect(find.byType(RefreshIndicator), findsOneWidget);

      // Admin publishes a second lecture -> appears live without closing screen.
      lecturesController.add(const [
        LectureSummary(
          id: 'lec-1',
          title: 'المحاضرة الأولى',
          status: 'not_started',
          displayOrder: 0,
          isLocked: false,
          subjectId: 'sub-1',
          sectionId: 'sec-1',
          thumbnailUrl: 'https://example.com/lec1.png',
        ),
        LectureSummary(
          id: 'lec-2',
          title: 'المحاضرة الثانية',
          status: 'not_started',
          displayOrder: 1,
          isLocked: false,
          subjectId: 'sub-1',
          sectionId: 'sec-1',
          thumbnailUrl: 'https://example.com/lec2.png',
        ),
      ]);
      await tester.pump();
      await tester.pump();

      expect(find.text('المحاضرة الثانية'), findsOneWidget);
    },
  );
}
