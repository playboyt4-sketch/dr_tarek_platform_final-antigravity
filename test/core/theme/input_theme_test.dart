import 'package:dr_tarek_platform/app/app.dart';
import 'package:dr_tarek_platform/core/localization/locale_controller.dart';
import 'package:dr_tarek_platform/core/theme/app_colors.dart';
import 'package:dr_tarek_platform/core/theme/app_semantic_colors.dart';
import 'package:dr_tarek_platform/core/theme/app_theme.dart';
import 'package:dr_tarek_platform/core/theme/theme_controller.dart';
import 'package:dr_tarek_platform/features/authentication/domain/entities/session_state.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/providers/session_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the global editable-input appearance in BOTH appearances.
///
/// Product requirement (preserved): every editable text field is white in
/// Light Mode, independent of the OS brightness.
///
/// ADR-009 requirement: when the app renders Dark Mode, the same fields must
/// stay readable — a dark fill with a light label and a distinguishable
/// border. The previous, removed Dark Mode violated exactly this.
///
/// All Light-mode assertions below are unchanged from the original guard.
class _FakeSessionController extends SessionController {
  @override
  Future<SessionState> build() async => const SessionUnauthenticated();
}

double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

BorderSide _sideOf(InputBorder? border) {
  expect(border, isA<OutlineInputBorder>());
  return (border! as OutlineInputBorder).borderSide;
}

void main() {
  group('AppTheme.light input decoration', () {
    final theme = AppTheme.light;
    final inputs = theme.inputDecorationTheme;

    test('editable fields are filled white', () {
      expect(inputs.filled, isTrue);
      expect(inputs.fillColor, AppColors.canvas);
      expect(inputs.fillColor, const Color(0xFFFFFFFF));
    });

    test('field text is dark enough to read on white', () {
      final textColor = theme.textTheme.bodyLarge?.color;
      expect(textColor, isNotNull);
      expect(textColor, AppColors.textPrimary);
      expect(_contrastRatio(textColor!, AppColors.canvas), greaterThan(4.5));
    });

    test('normal, focused, error and disabled states are distinct', () {
      final enabled = _sideOf(inputs.enabledBorder);
      final focused = _sideOf(inputs.focusedBorder);
      final error = _sideOf(inputs.errorBorder);
      final focusedError = _sideOf(inputs.focusedErrorBorder);
      final disabled = _sideOf(inputs.disabledBorder);

      // Documented Figma input border.
      expect(enabled.color, AppColors.inputBorder);
      expect(enabled.color, const Color(0xFFD0D0D0));
      // Focus uses the product blue and a heavier stroke.
      expect(focused.color, AppColors.buttonSolid);
      expect(focused.width, greaterThan(enabled.width));
      // Error uses the semantic error red.
      expect(error.color, AppColors.error);
      expect(focusedError.color, AppColors.error);
      expect(focusedError.width, greaterThan(error.width));
      // Disabled is present but muted.
      expect(disabled.color, AppColors.divider);

      expect(
        {enabled.color, focused.color, error.color, disabled.color}.length,
        4,
      );
    });

    test('field shape keeps the design-system radius', () {
      final border = inputs.enabledBorder! as OutlineInputBorder;
      expect(border.borderRadius, BorderRadius.circular(16));
    });

    test('brightness and semantic extension are the approved light values', () {
      expect(theme.brightness, Brightness.light);
      final semantic = theme.extension<AppSemanticColors>();
      expect(semantic, isNotNull);
      expect(semantic!.isDark, isFalse);
      expect(semantic.canvas, const Color(0xFFFFFFFF));
      expect(semantic.textPrimary, const Color(0xFF111827));
      // Light must keep both approved brand blues (Owner decision D8).
      expect(semantic.primary, const Color(0xFF1D4ED8));
      expect(semantic.primaryLegacy, const Color(0xFF1A73E8));
    });
  });

  group('AppTheme.dark input decoration', () {
    final theme = AppTheme.dark;
    final inputs = theme.inputDecorationTheme;

    test('reports a true dark brightness', () {
      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.brightness, Brightness.dark);
    });

    test('editable fields use the approved dark fill', () {
      expect(inputs.filled, isTrue);
      expect(inputs.fillColor, const Color(0xFF15181F));
    });

    test('field text is readable on the dark fill', () {
      final textColor = theme.textTheme.bodyLarge?.color;
      expect(textColor, isNotNull);
      expect(textColor, const Color(0xFFF2F4F7));
      expect(
        _contrastRatio(textColor!, inputs.fillColor!),
        greaterThan(4.5),
        reason: 'dark field text must pass WCAG AA on the dark fill',
      );
    });

    test('normal, focused, error and disabled states are distinct', () {
      final enabled = _sideOf(inputs.enabledBorder);
      final focused = _sideOf(inputs.focusedBorder);
      final error = _sideOf(inputs.errorBorder);
      final focusedError = _sideOf(inputs.focusedErrorBorder);
      final disabled = _sideOf(inputs.disabledBorder);

      expect(enabled.color, const Color(0xFF636C80));
      expect(focused.color, const Color(0xFF7FA9FF));
      expect(focused.width, greaterThan(enabled.width));
      expect(error.color, const Color(0xFFFFB4AB));
      expect(focusedError.color, const Color(0xFFFFB4AB));
      expect(disabled.color, const Color(0xFF2A2F3A));

      expect(
        {enabled.color, focused.color, error.color, disabled.color}.length,
        4,
      );
    });

    test('the enabled border is visible against the field fill', () {
      // WCAG 1.4.11 non-text contrast: 3:1 for control boundaries. The Light
      // #D0D0D0-on-white border fails this at 1.54:1 (pre-existing, preserved);
      // the Dark border was chosen to pass.
      expect(
        _contrastRatio(
          _sideOf(inputs.enabledBorder).color,
          inputs.fillColor!,
        ),
        greaterThanOrEqualTo(3.0),
      );
    });

    test('field shape keeps the design-system radius', () {
      final border = inputs.enabledBorder! as OutlineInputBorder;
      expect(
        border.borderRadius,
        BorderRadius.circular(AppShapes.radiusMd),
      );
    });
  });

  group('AppSemanticColors', () {
    test('light maps 1:1 to the approved constants', () {
      const s = AppSemanticColors.light;
      expect(s.canvas, AppColors.canvas);
      expect(s.textPrimary, AppColors.textPrimary);
      expect(s.textSecondary, AppColors.textSecondary);
      expect(s.inputBorder, AppColors.inputBorder);
      expect(s.divider, AppColors.divider);
      expect(s.primary, AppColors.buttonSolid);
      expect(s.error, AppColors.error);
      expect(s.success, AppColors.success);
      expect(s.warning, AppColors.warning);
      expect(s.info, AppColors.info);
      expect(s.canvasWarm, const Color(0xFFFFFCF7));
    });

    test('dark matches the approved token table', () {
      const s = AppSemanticColors.dark;
      expect(s.canvas, const Color(0xFF0B0D12));
      expect(s.surface, const Color(0xFF15181F));
      expect(s.textPrimary, const Color(0xFFF2F4F7));
      expect(s.textSecondary, const Color(0xFFA7AEBC));
      expect(s.primary, const Color(0xFF7FA9FF));
      expect(s.onPrimary, const Color(0xFF08142B));
      expect(s.inputFill, const Color(0xFF15181F));
      expect(s.inputBorder, const Color(0xFF636C80));
      expect(s.isDark, isTrue);
    });

    test('every measured dark text pairing passes WCAG AA', () {
      const s = AppSemanticColors.dark;
      expect(_contrastRatio(s.textPrimary, s.canvas), greaterThan(4.5));
      expect(_contrastRatio(s.textPrimary, s.surface), greaterThan(4.5));
      expect(
        _contrastRatio(s.textPrimary, s.surfaceContainer),
        greaterThan(4.5),
      );
      expect(_contrastRatio(s.textSecondary, s.canvas), greaterThan(4.5));
      expect(_contrastRatio(s.primary, s.canvas), greaterThan(4.5));
      expect(_contrastRatio(s.onPrimary, s.primary), greaterThan(4.5));
      expect(_contrastRatio(s.error, s.canvas), greaterThan(4.5));
      expect(_contrastRatio(s.success, s.surface), greaterThan(4.5));
      expect(_contrastRatio(s.warning, s.surface), greaterThan(4.5));
      expect(_contrastRatio(s.info, s.surface), greaterThan(4.5));
      expect(
        _contrastRatio(s.snackbarText, s.snackbarBackground),
        greaterThan(4.5),
      );
    });

    test('grade accents stay readable on the neutral dark canvas', () {
      const s = AppSemanticColors.dark;
      for (final accent in [
        s.gradeAccent1,
        s.gradeAccent2,
        s.gradeAccent3,
        s.gradeAccent4,
      ]) {
        expect(_contrastRatio(accent, s.canvas), greaterThan(4.5));
      }
    });

    test('lerp interpolates role by role', () {
      final quarter = AppSemanticColors.light.lerp(AppSemanticColors.dark, 0.25);
      expect(quarter.canvas, isNot(AppSemanticColors.light.canvas));
      expect(quarter.canvas, isNot(AppSemanticColors.dark.canvas));
      expect(quarter.isDark, isFalse);

      final threeQuarters =
          AppSemanticColors.light.lerp(AppSemanticColors.dark, 0.75);
      expect(threeQuarters.isDark, isTrue);
    });
  });

  group('OS appearance wiring', () {
    Future<MaterialApp> pumpApp(
      WidgetTester tester, {
      required ThemeMode mode,
      required Brightness osBrightness,
    }) async {
      tester.platformDispatcher.platformBrightnessTestValue = osBrightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialLocaleProvider.overrideWithValue(const Locale('ar')),
            initialThemeModeProvider.overrideWithValue(mode),
            sessionProvider.overrideWith(_FakeSessionController.new),
          ],
          child: const DrTarekPlatformApp(),
        ),
      );
      await tester.pump();
      // Splash holds a 5.8s navigation timer; consume it so no timers
      // outlive the test, then let the hand-off transition paint.
      await tester.pump(const Duration(milliseconds: 5800));
      await tester.pump(const Duration(milliseconds: 500));

      return tester.widget<MaterialApp>(find.byType(MaterialApp));
    }

    testWidgets('system mode follows a dark OS into the dark theme',
        (tester) async {
      final app = await pumpApp(
        tester,
        mode: ThemeMode.system,
        osBrightness: Brightness.dark,
      );

      expect(app.themeMode, ThemeMode.system);
      expect(app.darkTheme, isNotNull);

      final resolved = Theme.of(tester.element(find.byType(Scaffold).first));
      expect(resolved.brightness, Brightness.dark);
      expect(
        resolved.inputDecorationTheme.fillColor,
        AppSemanticColors.dark.inputFill,
      );
      expect(
        resolved.textTheme.bodyLarge?.color,
        AppSemanticColors.dark.textPrimary,
      );
    });

    testWidgets('system mode follows a light OS into the light theme',
        (tester) async {
      await pumpApp(
        tester,
        mode: ThemeMode.system,
        osBrightness: Brightness.light,
      );

      final resolved = Theme.of(tester.element(find.byType(Scaffold).first));
      expect(resolved.brightness, Brightness.light);
      expect(
        resolved.inputDecorationTheme.fillColor,
        AppColors.canvas,
      );
    });

    testWidgets('an explicit light choice overrides a dark OS', (tester) async {
      await pumpApp(
        tester,
        mode: ThemeMode.light,
        osBrightness: Brightness.dark,
      );

      final resolved = Theme.of(tester.element(find.byType(Scaffold).first));
      expect(resolved.brightness, Brightness.light);
      expect(resolved.inputDecorationTheme.fillColor, AppColors.canvas);
    });

    testWidgets('an explicit dark choice overrides a light OS', (tester) async {
      await pumpApp(
        tester,
        mode: ThemeMode.dark,
        osBrightness: Brightness.light,
      );

      final resolved = Theme.of(tester.element(find.byType(Scaffold).first));
      expect(resolved.brightness, Brightness.dark);
      expect(
        resolved.inputDecorationTheme.fillColor,
        AppSemanticColors.dark.inputFill,
      );
    });
  });
}
