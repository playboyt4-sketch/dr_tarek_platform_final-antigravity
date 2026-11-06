import 'package:dr_tarek_platform/core/theme/app_semantic_colors.dart';
import 'package:dr_tarek_platform/core/theme/app_theme.dart';
import 'package:dr_tarek_platform/core/theme/app_typography.dart';
import 'package:dr_tarek_platform/core/widgets/app_button.dart';
import 'package:dr_tarek_platform/core/widgets/glass_back_button.dart';
import 'package:dr_tarek_platform/core/widgets/password_strength_meter.dart';
import 'package:dr_tarek_platform/core/widgets/primary_button.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/widgets/brand_signature_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the shared-component colour contract from ADR-009: Light keeps its
/// approved values exactly, Dark resolves to the approved semantic roles.
Future<void> _pumpInTheme(
  WidgetTester tester,
  Widget child, {
  required ThemeData theme,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('PrimaryButton', () {
    testWidgets('solid keeps the approved Light fill and label colour',
        (tester) async {
      await _pumpInTheme(
        tester,
        PrimaryButton(label: 'Next', onPressed: () {}),
        theme: AppTheme.light,
      );

      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      final background = button.style!.backgroundColor!.resolve({});
      final foreground = button.style!.foregroundColor!.resolve({});
      expect(background, const Color(0xFF1D4ED8));
      expect(foreground, const Color(0xFFFFFFFF));
    });

    testWidgets('solid resolves to the approved Dark pair', (tester) async {
      await _pumpInTheme(
        tester,
        PrimaryButton(label: 'Next', onPressed: () {}),
        theme: AppTheme.dark,
      );

      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      final background = button.style!.backgroundColor!.resolve({});
      final foreground = button.style!.foregroundColor!.resolve({});
      expect(background, AppSemanticColors.dark.primary);
      expect(foreground, AppSemanticColors.dark.onPrimary);
      expect(_contrast(foreground!, background!), greaterThan(4.5));
    });

    testWidgets('glass keeps the Light 20%/30% white material', (tester) async {
      await _pumpInTheme(
        tester,
        PrimaryButton(
          label: 'Go',
          variant: ButtonVariant.glass,
          onPressed: () {},
        ),
        theme: AppTheme.light,
      );

      final box = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byType(PrimaryButton),
          matching: find.byType(DecoratedBox),
        ).first,
      );
      final decoration = box.decoration as BoxDecoration;
      expect(decoration.color, const Color(0x33FFFFFF));
      expect((decoration.border! as Border).top.color, const Color(0x4DFFFFFF));
    });

    testWidgets('glass resolves to the approved Dark material', (tester) async {
      await _pumpInTheme(
        tester,
        PrimaryButton(
          label: 'Go',
          variant: ButtonVariant.glass,
          onPressed: () {},
        ),
        theme: AppTheme.dark,
      );

      final box = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byType(PrimaryButton),
          matching: find.byType(DecoratedBox),
        ).first,
      );
      final decoration = box.decoration as BoxDecoration;
      expect(decoration.color, AppSemanticColors.dark.glassButtonFill);
      expect(
        (decoration.border! as Border).top.color,
        AppSemanticColors.dark.glassButtonBorder,
      );
    });
  });

  group('GlassBackButton', () {
    testWidgets('Light keeps the 25%/35% Figma circle', (tester) async {
      await _pumpInTheme(
        tester,
        const GlassBackButton(),
        theme: AppTheme.light,
      );

      final material = tester.widget<Material>(
        find.descendant(
          of: find.byType(GlassBackButton),
          matching: find.byType(Material),
        ).first,
      );
      expect(material.color, const Color.fromRGBO(255, 255, 255, 0.25));
      expect(
        (material.shape! as CircleBorder).side.color,
        const Color.fromRGBO(255, 255, 255, 0.35),
      );
    });

    testWidgets('Dark uses the semantic glass roles', (tester) async {
      await _pumpInTheme(
        tester,
        const GlassBackButton(),
        theme: AppTheme.dark,
      );

      final material = tester.widget<Material>(
        find.descendant(
          of: find.byType(GlassBackButton),
          matching: find.byType(Material),
        ).first,
      );
      expect(material.color, AppSemanticColors.dark.glassBackFill);
      expect(
        (material.shape! as CircleBorder).side.color,
        AppSemanticColors.dark.glassBackBorder,
      );
      expect(
        tester.widget<Icon>(find.byIcon(Icons.chevron_left)).color,
        AppSemanticColors.dark.glassText,
      );
    });
  });

  group('AppButton', () {
    testWidgets('filled keeps the second Light brand blue (D8)',
        (tester) async {
      await _pumpInTheme(
        tester,
        AppButton(label: 'Save', onPressed: () {}),
        theme: AppTheme.light,
      );

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(
        button.style!.backgroundColor!.resolve({}),
        const Color(0xFF1A73E8),
      );
      expect(
        button.style!.foregroundColor!.resolve({}),
        const Color(0xFFFFFFFF),
      );
    });

    testWidgets('filled resolves to the single approved Dark blue',
        (tester) async {
      await _pumpInTheme(
        tester,
        AppButton(label: 'Save', onPressed: () {}),
        theme: AppTheme.dark,
      );

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      final background = button.style!.backgroundColor!.resolve({});
      final foreground = button.style!.foregroundColor!.resolve({});
      expect(background, AppSemanticColors.dark.primary);
      expect(foreground, AppSemanticColors.dark.onPrimary);
      expect(_contrast(foreground!, background!), greaterThan(4.5));
    });
  });

  group('PasswordStrength', () {
    test('Light keeps the previous strength colours', () {
      const s = AppSemanticColors.light;
      expect(PasswordStrength.weak.resolveColor(s), const Color(0xFFE53935));
      expect(PasswordStrength.medium.resolveColor(s), const Color(0xFFFF9800));
      expect(PasswordStrength.strong.resolveColor(s), const Color(0xFF4CAF50));
      expect(
        PasswordStrength.veryStrong.resolveColor(s),
        const Color(0xFF00897B),
      );
    });

    test('Dark uses approved status tokens with AA text contrast', () {
      const s = AppSemanticColors.dark;
      for (final strength in [
        PasswordStrength.weak,
        PasswordStrength.medium,
        PasswordStrength.strong,
        PasswordStrength.veryStrong,
      ]) {
        final color = strength.resolveColor(s);
        expect(
          _contrast(color, s.canvas),
          greaterThan(4.5),
          reason: '${strength.name} must be readable on the dark canvas',
        );
      }
    });
  });

  group('BrandSignatureLogo', () {
    testWidgets('Light keeps black', (tester) async {
      await _pumpInTheme(
        tester,
        const BrandSignatureLogo(designPx: 64),
        theme: AppTheme.light,
      );

      final text = tester.widget<Text>(find.text('Tarek el araby'));
      expect(text.style!.color, Colors.black);
    });

    testWidgets('Dark uses the semantic text primary (D9)', (tester) async {
      await _pumpInTheme(
        tester,
        const BrandSignatureLogo(designPx: 64),
        theme: AppTheme.dark,
      );

      final text = tester.widget<Text>(find.text('Tarek el araby'));
      expect(text.style!.color, AppSemanticColors.dark.textPrimary);
    });

    testWidgets('an explicit colour always wins', (tester) async {
      await _pumpInTheme(
        tester,
        const BrandSignatureLogo(designPx: 64, color: Color(0xFF8C2323)),
        theme: AppTheme.dark,
      );

      final text = tester.widget<Text>(find.text('Tarek el araby'));
      expect(text.style!.color, const Color(0xFF8C2323));
    });
  });

  group('AppTypography defaults', () {
    testWidgets('uncoloured text follows the active theme', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (inner) {
              context = inner;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(
        AppTypography.titleLarge(context).color,
        AppSemanticColors.dark.textPrimary,
      );
      expect(
        AppTypography.captionSmall(context).color,
        AppSemanticColors.dark.textSecondary,
      );
    });
  });
}
