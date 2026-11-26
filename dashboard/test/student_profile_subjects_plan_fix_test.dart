import 'package:drtarek_dashboard/features/applications/presentation/providers/application_decision_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/providers/grade_students_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/providers/student_profile_subjects_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/screens/student_profile_overview_screen.dart';
import 'package:drtarek_dashboard/features/students/presentation/screens/student_profile_subjects_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Unified subscription plan parsing & display resolution', () {
    test('extractSubscriptionPlanId reads plan_id, plan, tier, and plan_key', () {
      expect(
        extractSubscriptionPlanId(<String, dynamic>{'plan_id': 'center_pro'}),
        'center_pro',
      );
      expect(
        extractSubscriptionPlanId(<String, dynamic>{'plan': 'pro'}),
        'pro',
      );
      expect(
        extractSubscriptionPlanId(<String, dynamic>{'tier': 'center_max'}),
        'center_max',
      );
      expect(
        extractSubscriptionPlanId(<String, dynamic>{'plan_key': 'center_free'}),
        'center_free',
      );
      expect(extractSubscriptionPlanId(<String, dynamic>{}), isEmpty);
    });

    test('resolvePlanDisplayLabel falls back to planDisplayForKey when plans map omits id', () {
      expect(
        resolvePlanDisplayLabel(
          planId: 'custom_id',
          planLabels: const <String, String>{'custom_id': 'MAX'},
        ),
        'MAX',
      );
      expect(
        resolvePlanDisplayLabel(
          planId: 'center_pro',
          planLabels: const <String, String>{},
        ),
        'PRO',
      );
      expect(
        resolvePlanDisplayLabel(
          planId: 'guest',
          planLabels: const <String, String>{},
        ),
        'FREE',
      );
    });

    test('buildNewStudentSubjects uses defaultPlan when no explicit plan choice exists', () {
      const scope = <SubjectOption>[
        SubjectOption(id: 'sub1', title: 'Math', gradeKey: 'grade_one'),
      ];
      final picked = buildNewStudentSubjects(
        scope: scope,
        toggles: const <String, bool>{'sub1': true},
        plans: const <String, String>{},
        alreadyRegistered: const <String>{},
        defaultPlan: 'pro',
      );
      expect(picked.single.plan, 'pro');
    });
  });

  group('Student Profile → Subjects tab plan editing & repair', () {
    testWidgets('shows Repair for broken row and edit icon on active plan row',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const student = GradeStudent(
        id: 'stu_1',
        name: 'Test Student',
        isCenter: true,
        isActive: true,
        lastSignIn: '1/1/2026',
      );

      const rows = <StudentSubjectRegistration>[
        StudentSubjectRegistration(
          subjectId: 's_broken',
          title: 'مادة تحتاج إصلاح',
          gradeKey: 'grade_one',
          planLabel: '',
          enabled: true,
        ),
        StudentSubjectRegistration(
          subjectId: 's_active',
          title: 'مادة بخطة نشطة',
          gradeKey: 'grade_one',
          planLabel: 'PRO',
          enabled: true,
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            studentProfileSubjectsProvider('stu_1').overrideWith(
              (ref) => Stream.value(rows),
            ),
            freePlanAvailabilityProvider.overrideWith((ref) async => true),
            for (final key in const <String>[
              'grade_one',
              'grade_two',
              'grade_three',
              'grade_four',
            ])
              gradeSubjectsProvider(key).overrideWith(
                (ref) => Stream.value(const <SubjectOption>[]),
              ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: StudentProfileOverviewScreen(
                student: student,
                gradeKey: 'grade_one',
                initialNav: 'Subjects',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('بدون خطة نشطة'), findsOneWidget);
      expect(find.text('Repair'), findsOneWidget);
      expect(find.text('PRO'), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);

      // Tapping active plan opens the edit plan dialog directly.
      await tester.tap(find.text('PRO'));
      await tester.pumpAndSettle();
      expect(find.text('تعديل الخطة'), findsOneWidget);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Tapping Repair opens the repair plan dialog.
      await tester.tap(find.text('Repair'));
      await tester.pumpAndSettle();
      expect(find.text('إصلاح الخطة'), findsOneWidget);
    });

    testWidgets('showRepairPlanDialog hides FREE when freePlanEnabled is false',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showRepairPlanDialog(
                  context,
                  accent: const Color(0xFF00C08B),
                  subjectTitle: 'Chemistry',
                  freePlanEnabled: false,
                  isEdit: true,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('FREE'), findsNothing);
      expect(find.text('PRO'), findsOneWidget);
      expect(find.text('MAX'), findsOneWidget);
    });
  });
}
