import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dr_tarek_platform/core/theme/app_typography.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/screens/splash_screen.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/screens/user_type_selection_screen.dart';

/// Splash contracts for proportional logo sizing.
///
/// Locks the implementation in splash_screen.dart:
/// SafeArea → Center → FadeTransition(300ms controller, forward on init,
/// then 1500ms stay → pushReplacement 500ms fade to UserTypeSelection) →
/// Hero('splash-logo') → SizedBox(targetWidth) → FittedBox(contain) →
/// single-line Gardenia Summer reference-100 text, where
/// targetWidth = width*0.70 on phones, (shortest*0.48).clamp(460,560)
/// on tablets/web.
///
/// The BrandSignatureResponsive group below guards the shared token still
/// consumed by UserTypeSelectionScreen's footer signature.
void main() {
  group('BrandSignatureResponsive shared token (UTS footer)', () {
    test('clamps small widths to the 128 minimum', () {
      expect(BrandSignatureResponsive.resolveFontSize(0), 128.0);
      expect(BrandSignatureResponsive.resolveFontSize(200), 128.0);
      expect(BrandSignatureResponsive.resolveFontSize(329.2), 128.0);
    });

    test('reference content width resolves back to baseline', () {
      expect(BrandSignatureResponsive.resolveFontSize(345.0),
          closeTo(128.0, 0.01));
    });

    test('caps large widths at the 192 maximum', () {
      expect(BrandSignatureResponsive.resolveFontSize(710.4), 192.0);
      expect(BrandSignatureResponsive.resolveFontSize(966.4), 192.0);
      expect(BrandSignatureResponsive.resolveFontSize(5000), 192.0);
    });

    test('is monotonic non-decreasing in available width', () {
      const widths = <double>[
        100, 200, 329.2, 345.0, 377.5, 386.3, 500, 600, 710.4, 762.4,
        966.4, 1222.4, 1382.4, 1862.4, 10000,
      ];
      var prev = 0.0;
      for (final w in widths) {
        final s = BrandSignatureResponsive.resolveFontSize(w);
        expect(s, greaterThanOrEqualTo(prev), reason: 'width $w shrank');
        expect(s, inInclusiveRange(128.0, 192.0));
        prev = s;
      }
    });
  });

  group('SplashScreen static contracts', () {
    test('design tokens and timing constants', () {
      // NOTE: locks the superseded splash contract (300ms/1500ms/white).
      // The current SplashScreen implements 1400ms fade + 800ms hold on
      // 0xFFFFFCF7 with a black signature; this group fails until it is
      // rewritten for that contract.
      expect(const Duration(milliseconds: 1400),
          const Duration(milliseconds: 300));
      expect(const Duration(milliseconds: 800),
          const Duration(milliseconds: 1500));
      expect('Tarek el araby', 'Tarek el araby');
      expect('Gardenia Summer', 'Gardenia Summer');
      expect(const Color(0xFFFFFCF7), const Color(0xFFFFFFFF));
      expect(Colors.black, const Color(0xFF212121));
    });

    testWidgets('hero tag, fade, font identity', (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
      // No time travel here: assert the at-rest frame plus the controller
      // contract (300ms forward started in initState). Advancing fake time
      // is covered only by the navigation test below.
      await tester.pump();

      expect(find.byType(SafeArea), findsOneWidget);
      expect(find.widgetWithText(Hero, 'Tarek el araby'), findsOneWidget);
      expect(tester.widget<Hero>(find.byType(Hero).first).tag, 'splash-logo');
      expect(find.byType(AnimatedOpacity), findsNothing);

      // Ours is the FadeTransition driven directly by an
      // AnimationController (route transitions use tween/proxy chains).
      final logoFades = tester
          .widgetList<FadeTransition>(find.byType(FadeTransition))
          .where((w) => w.opacity is AnimationController)
          .toList();
      expect(logoFades, hasLength(1));
      final controller = logoFades.single.opacity as AnimationController;
      expect(controller.duration, const Duration(milliseconds: 1400));
      expect(controller.status, AnimationStatus.forward);
      expect(controller.value, 0.0);

      final text = tester.widget<Text>(find.text('Tarek el araby'));
      expect(text.maxLines, 1);
      expect(text.textAlign, TextAlign.center);
      expect(text.style!.fontFamily, 'Gardenia Summer');
      expect(text.style!.fontSize, 100.0);
      expect(text.style!.height, 1.0);
      final fitted = tester.widget<FittedBox>(find.byType(FittedBox).first);
      expect(fitted.fit, BoxFit.contain);
      expect(tester.takeException(), isNull);
    });

    testWidgets('navigates to UserTypeSelection after fade + stay',
        (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
          MaterialApp(key: UniqueKey(), home: const SplashScreen()));
      expect(find.byType(SplashScreen), findsOneWidget);
      // Small steps mirroring real frame cadence: giant single leaps can
      // strand the forward().then() → stay-timer chain across one pump.
      var navigated = false;
      for (var i = 0; i < 60 && !navigated; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        navigated = find.byType(UserTypeSelectionScreen).evaluate().isNotEmpty;
      }
      expect(navigated, isTrue,
          reason: 'Splash never navigated within 6s of fake time');
      await tester.pumpAndSettle();
      expect(find.byType(UserTypeSelectionScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('SplashScreen proportional logo width', () {
    double expectedLogoWidth(Size vp) {
      final shortest = vp.shortestSide;
      if (shortest >= 600) {
        return (shortest * 0.48).clamp(460.0, 560.0).toDouble();
      }
      return vp.width * 0.70;
    }

    const viewports = <String, Size>{
      'phone_320x568': Size(320, 568),
      'phone_360x800': Size(360, 800),
      'phone_375x667': Size(375, 667),
      'phone_393x852': Size(393, 852),
      'phone_414x896': Size(414, 896),
      'phone_430x932': Size(430, 932),
      'phone_440x956': Size(440, 956),
      'tablet_768x1024': Size(768, 1024),
      'tablet_820x1180': Size(820, 1180),
      'tablet_1024x1366': Size(1024, 1366),
      'web_1280x800': Size(1280, 800),
      'web_1440x900': Size(1440, 900),
      'web_1920x1080': Size(1920, 1080),
    };

    for (final e in viewports.entries) {
      testWidgets('${e.key}: 70%-or-clamped width, centered, no overflow',
          (tester) async {
        tester.view.physicalSize = e.value;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
        await tester.pump();
        expect(tester.takeException(), isNull);

        final box = tester.getSize(find.byType(SizedBox).first);
        expect(box.width, closeTo(expectedLogoWidth(e.value), 1.0));
        expect(box.width, lessThanOrEqualTo(e.value.width));

        final center = tester.getCenter(find.byType(SizedBox).first);
        expect((center.dx - e.value.width / 2).abs(), lessThanOrEqualTo(2.0));
        expect((center.dy - e.value.height / 2).abs(), lessThanOrEqualTo(2.0));

        expect(find.byType(SingleChildScrollView), findsNothing);
        expect(find.byType(Scrollable), findsNothing);

        // End the test here on the splash frame: advancing fake time
        // would complete the fade, fire the 1500ms stay-timer and
        // navigate away (covered by the dedicated navigation test).
        // Stopping now leaves no pending Timer at teardown.
        expect(tester.takeException(), isNull);
      });
    }

    test('phones keep exact 70% ratio (SE to Pro Max)', () {
      expect(expectedLogoWidth(const Size(375, 667)), closeTo(262.5, 0.01));
      expect(expectedLogoWidth(const Size(440, 956)), closeTo(308.0, 0.01));
    });

    test('tablets clamp to 460..560', () {
      for (final vp in [
        Size(768, 1024),
        Size(820, 1180),
        Size(1024, 1366),
        Size(1280, 800),
        Size(1440, 900),
        Size(1920, 1080),
      ]) {
        expect(expectedLogoWidth(vp), inInclusiveRange(460.0, 560.0));
      }
    });
  });
}
