import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dr_tarek_platform/core/localization/locale_controller.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/screens/login_screen.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/screens/new_student_welcome_screen.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/screens/user_type_selection_screen.dart';
import 'package:dr_tarek_platform/l10n/generated/app_localizations.dart';

/// Device matrix:
///  * small Android phone  — 360x640
///  * reference iPhone     — 393x852 (Figma canvas)
///  * large iPhone         — 430x932
///  * iPad portrait        — 820x1180 (tablet breakpoint)
const _devices = <String, Size>{
  'small_phone_360x640': Size(360, 640),
  'reference_phone_393x852': Size(393, 852),
  'large_phone_430x932': Size(430, 932),
  'tablet_820x1180': Size(820, 1180),
};

Future<void> _pumpOnDevice(
  WidgetTester tester,
  Size deviceSize,
  Widget screen,
) async {
  tester.view.physicalSize = deviceSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        initialLocaleProvider.overrideWithValue(const Locale('ar')),
      ],
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('UserTypeSelectionScreen adapts to every device class', () {
    for (final entry in _devices.entries) {
      testWidgets('${entry.key}: renders without overflow', (tester) async {
        await _pumpOnDevice(tester, entry.value, const UserTypeSelectionScreen());

        expect(tester.takeException(), isNull);
        expect(find.text('طالب جديد'), findsOneWidget);
        expect(find.text('طالب حالي'), findsOneWidget);

        // Cards must fit inside the viewport width.
        final card = tester.getSize(find.text('طالب جديد').first);
        expect(card.width, lessThanOrEqualTo(entry.value.width));
      });
    }

    testWidgets('cards scale with the device width', (tester) async {
      await _pumpOnDevice(
        tester,
        _devices['small_phone_360x640']!,
        const UserTypeSelectionScreen(),
      );
      final smallCardWidth =
          tester.getSize(find.byType(InkWell).first).width;

      await _pumpOnDevice(
        tester,
        _devices['reference_phone_393x852']!,
        const UserTypeSelectionScreen(),
      );
      final referenceCardWidth =
          tester.getSize(find.byType(InkWell).first).width;

      expect(smallCardWidth, lessThan(referenceCardWidth));
    });

    testWidgets('tablet constrains cards instead of stretching them', (
      tester,
    ) async {
      const tablet = Size(820, 1180);
      await _pumpOnDevice(tester, tablet, const UserTypeSelectionScreen());

      final cardWidth = tester.getSize(find.byType(InkWell).first).width;
      // Scaled design card (345 x ~1.15 cap) stays well below full width.
      expect(cardWidth, lessThan(tablet.width));
      expect(cardWidth, greaterThan(300));
    });
  });

  group('NewStudentWelcomeScreen adapts to every device class', () {
    for (final entry in _devices.entries) {
      testWidgets('${entry.key}: renders without overflow', (tester) async {
        await _pumpOnDevice(
          tester,
          entry.value,
          const NewStudentWelcomeScreen(),
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Get started'), findsOneWidget);
      });
    }
  });

  group('LoginScreen adapts to every device class', () {
    for (final entry in _devices.entries) {
      testWidgets('${entry.key}: renders form without overflow', (
        tester,
      ) async {
        await _pumpOnDevice(tester, entry.value, const LoginScreen());

        expect(tester.takeException(), isNull);
        expect(find.text('Login'), findsAtLeastNWidgets(1));
        expect(find.byType(TextFormField), findsNWidgets(2));
      });
    }

    testWidgets('login button height scales between phone and tablet', (
      tester,
    ) async {
      await _pumpOnDevice(
        tester,
        _devices['reference_phone_393x852']!,
        const LoginScreen(),
      );
      final phoneButtonHeight =
          tester.getSize(find.widgetWithText(FilledButton, 'Login')).height;

      await _pumpOnDevice(
        tester,
        _devices['tablet_820x1180']!,
        const LoginScreen(),
      );
      final tabletButtonHeight =
          tester.getSize(find.widgetWithText(FilledButton, 'Login')).height;

      expect(phoneButtonHeight, closeTo(64, 1.5));
      expect(tabletButtonHeight, closeTo(64 * 1.15, 2.5));
    });
  });
}
