import 'package:dr_tarek_platform/core/theme/app_semantic_colors.dart';
import 'package:dr_tarek_platform/core/theme/app_theme.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/screens/new_student_end_screen.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/screens/new_student_grade_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the Phase 4 screen migration: each migrated screen must keep the
/// approved Light values exactly and resolve to the approved Dark roles.
Future<void> _pumpScreen(
  WidgetTester tester,
  Widget screen, {
  required ThemeData theme,
}) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(theme: theme, home: screen));
  await tester.pumpAndSettle();
}

double _contrast(Color foreground, Color background) {
  final lf = foreground.computeLuminance();
  final lb = background.computeLuminance();
  final hi = lf > lb ? lf : lb;
  final lo = lf > lb ? lb : lf;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  const light = AppSemanticColors.light;
  const dark = AppSemanticColors.dark;

  group('NewStudentEndScreen theme contract', () {
    testWidgets('Light is byte-identical to the approved values', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        const NewStudentEndScreen(),
        theme: AppTheme.light,
      );

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, const Color(0xFFFFFCF7));

      final title = tester.widget<Text>(
        find.text('Your request is\nunder review'),
      );
      expect(title.style!.color, const Color(0xFF111827));

      final subtitle = tester.widget<Text>(
        find.text('We are reviewing your request\nyou will be notified soon'),
      );
      expect(subtitle.style!.color, const Color(0xFF9A9A9A));
    });

    testWidgets('Dark uses the approved semantic canvas and text', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        const NewStudentEndScreen(),
        theme: AppTheme.dark,
      );

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, dark.canvasWarm);

      final title = tester.widget<Text>(
        find.text('Your request is\nunder review'),
      );
      expect(title.style!.color, dark.textPrimary);

      final subtitle = tester.widget<Text>(
        find.text('We are reviewing your request\nyou will be notified soon'),
      );
      expect(subtitle.style!.color, dark.inputHint);

      expect(_contrast(title.style!.color!, dark.canvas), greaterThan(4.5));
      expect(_contrast(subtitle.style!.color!, dark.canvas), greaterThan(3.0));
    });
  });

  group('NewStudentGradeScreen theme contract', () {
    testWidgets('Light keeps the warm canvas and white capsule labels', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        const NewStudentGradeScreen(initialGrade: 'grade_one'),
        theme: AppTheme.light,
      );

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, const Color(0xFFFFFCF7));

      final title = tester.widget<Text>(find.text('Which year are you in?'));
      expect(title.style!.color, const Color(0xFF111827));

      final label = tester.widget<Text>(find.text('Grade one'));
      expect(label.style!.color, Colors.white);

      final capsules = tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .toList();
      expect(capsules.length, 4);
      expect(
        (capsules.first.decoration! as BoxDecoration).color,
        const Color(0xFFF59E0B),
      );
    });

    testWidgets('Dark follows Option B (neutral fill + grade accent)', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        const NewStudentGradeScreen(initialGrade: 'grade_one'),
        theme: AppTheme.dark,
      );

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, dark.canvasWarm);

      final title = tester.widget<Text>(find.text('Which year are you in?'));
      expect(title.style!.color, dark.textPrimary);

      final label = tester.widget<Text>(find.text('Grade one'));
      expect(label.style!.color, dark.gradeText1);

      final capsules = tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .toList();
      expect(capsules.length, 4);
      for (final capsule in capsules) {
        final decoration = capsule.decoration! as BoxDecoration;
        expect(decoration.color, dark.surfaceContainer);
        expect((decoration.border! as Border).top.color.a, greaterThan(0));
      }
      expect(
        ((capsules.first.decoration! as BoxDecoration).border! as Border)
            .top
            .color,
        dark.gradeAccent1,
      );

      expect(
        _contrast(dark.gradeText1, dark.surfaceContainer),
        greaterThan(4.5),
      );
    });
  });

  group('approved semantic contrast', () {
    test('Dark text/token pairs meet WCAG AA where text is on canvas', () {
      expect(_contrast(dark.textPrimary, dark.canvas), greaterThan(7.0));
      expect(_contrast(dark.textSecondary, dark.canvas), greaterThan(4.5));
      expect(_contrast(dark.primary, dark.canvas), greaterThan(4.5));
      expect(_contrast(dark.onPrimary, dark.primary), greaterThan(4.5));
    });

    test('Light tokens are unchanged', () {
      expect(light.canvas, const Color(0xFFFFFFFF));
      expect(light.canvasWarm, const Color(0xFFFFFCF7));
      expect(light.textPrimary, const Color(0xFF111827));
      expect(light.textSecondary, const Color(0xFF6B7280));
    });
  });
}
