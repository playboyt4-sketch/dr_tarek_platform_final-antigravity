import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dr_tarek_platform/features/admin/domain/admin_grades.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/screens/new_student_grade_screen.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/screens/new_student_password_screen.dart';

Future<void> _pumpGradeScreen(
  WidgetTester tester, {
  Size? deviceSize,
  String? initialFullName,
  String? initialPhoneNumber,
  String? initialPhotoPath,
  String? initialGrade,
}) async {
  if (deviceSize != null) {
    tester.view.physicalSize = deviceSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }
  await tester.pumpWidget(
    MaterialApp(
      home: NewStudentGradeScreen(
        initialFullName: initialFullName,
        initialPhoneNumber: initialPhoneNumber,
        initialPhotoPath: initialPhotoPath,
        initialGrade: initialGrade,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder, warnIfMissed: false);
  await tester.pumpAndSettle();
}

void main() {
  group('NewStudentGradeScreen visuals (393x852 Figma)', () {
    testWidgets('renders on #FFFCF7 with headline and 4 grades, no Next', (
      tester,
    ) async {
      await _pumpGradeScreen(tester);

      expect(find.text('Which year are you in?'), findsOneWidget);
      expect(find.text('Grade one'), findsOneWidget);
      expect(find.text('Grade two'), findsOneWidget);
      expect(find.text('Grade three'), findsOneWidget);
      expect(find.text('Grade four'), findsOneWidget);
      // Teacher request: no bottom CTA — tapping a capsule navigates.
      expect(find.text('Next'), findsNothing);

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, const Color(0xFFFFFCF7));
    });

    testWidgets('stays put until a grade is tapped (no auto-navigation)', (
      tester,
    ) async {
      await _pumpGradeScreen(tester);

      // Nothing tapped: no navigation, no validation error.
      expect(find.byType(NewStudentPasswordScreen), findsNothing);
      expect(find.text('Please select your grade'), findsNothing);
      expect(find.byType(NewStudentGradeScreen), findsOneWidget);
    });

    testWidgets('restores existing selected grade from registration state', (
      tester,
    ) async {
      await _pumpGradeScreen(tester, initialGrade: 'grade_three');

      // Tapping the restored grade navigates straight to Password.
      await _tapVisible(tester, find.text('Grade three'));

      expect(find.byType(NewStudentPasswordScreen), findsOneWidget);
      final password = tester.widget<NewStudentPasswordScreen>(
        find.byType(NewStudentPasswordScreen),
      );
      expect(password.initialGrade, 'grade_three');
    });
  });

  group('NewStudentGradeScreen selection', () {
    testWidgets('tapping a grade selects it and navigates immediately', (
      tester,
    ) async {
      await _pumpGradeScreen(tester);

      // First tap navigates at once — no separate Next step.
      await _tapVisible(tester, find.text('Grade two'));
      expect(find.byType(NewStudentPasswordScreen), findsOneWidget);
      final password = tester.widget<NewStudentPasswordScreen>(
        find.byType(NewStudentPasswordScreen),
      );
      expect(password.initialGrade, 'grade_two');
    });

    testWidgets('display label maps to correct persisted value', (
      tester,
    ) async {
      const expected = {
        'Grade one': 'grade_one',
        'Grade two': 'grade_two',
        'Grade three': 'grade_three',
        'Grade four': 'grade_four',
      };
      await _pumpGradeScreen(tester);
      for (final entry in expected.entries) {
        await _tapVisible(tester, find.text(entry.key));

        expect(find.byType(NewStudentPasswordScreen), findsOneWidget);
        final password = tester.widget<NewStudentPasswordScreen>(
          find.byType(NewStudentPasswordScreen),
        );
        expect(password.initialGrade, entry.value);

        // Return to Grade for the next mapping (also proves the selected
        // grade survives Password -> Grade back navigation).
        await _tapVisible(
          tester,
          find.byIcon(Icons.arrow_back_ios_new_rounded),
        );
        expect(find.byType(NewStudentGradeScreen), findsOneWidget);
      }
    });

    testWidgets('valid grade set matches domain config (no hardcoded rule)', (
      tester,
    ) async {
      expect(kCanonicalGradeKeys, hasLength(4));
      await _pumpGradeScreen(tester);
      for (final key in kCanonicalGradeKeys) {
        expect([
          'grade_one',
          'grade_two',
          'grade_three',
          'grade_four',
        ], contains(key));
      }
    });
  });

  group('NewStudentGradeScreen navigation', () {
    testWidgets('tapping a grade navigates to Password with state', (
      tester,
    ) async {
      await _pumpGradeScreen(
        tester,
        initialFullName: 'Ahmed Mohamed Ali',
        initialPhoneNumber: '01001234567',
      );

      await _tapVisible(tester, find.text('Grade two'));

      expect(find.byType(NewStudentPasswordScreen), findsOneWidget);
      final password = tester.widget<NewStudentPasswordScreen>(
        find.byType(NewStudentPasswordScreen),
      );
      expect(password.initialFullName, 'Ahmed Mohamed Ali');
      expect(password.initialPhoneNumber, '01001234567');
      expect(password.initialGrade, 'grade_two');
    });

    testWidgets('back returns to previous step via pop', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const NewStudentGradeScreen(),
                    ),
                  ),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.byType(NewStudentGradeScreen), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(NewStudentGradeScreen), findsNothing);
      expect(find.text('go'), findsOneWidget);
    });
  });

  group('NewStudentGradeScreen responsive', () {
    testWidgets('393x852 renders without overflow', (tester) async {
      await _pumpGradeScreen(tester, deviceSize: const Size(393, 852));

      expect(tester.takeException(), isNull);
      expect(find.text('Which year are you in?'), findsOneWidget);
      expect(find.text('Grade one'), findsOneWidget);
    });

    testWidgets('360x640 renders without overflow', (tester) async {
      await _pumpGradeScreen(tester, deviceSize: const Size(360, 640));

      expect(tester.takeException(), isNull);
      expect(find.text('Which year are you in?'), findsOneWidget);
      expect(find.text('Grade four'), findsOneWidget);
    });
  });
}
