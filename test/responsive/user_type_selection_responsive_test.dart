import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dr_tarek_platform/core/localization/locale_controller.dart';
import 'package:dr_tarek_platform/l10n/generated/app_localizations.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/screens/login_screen.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/screens/new_student_welcome_screen.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/screens/teacher_admin_selection_screen.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/screens/user_type_selection_screen.dart';

/// Dedicated responsive test for UserTypeSelectionScreen (unified brand):
/// max() safe padding, 393-anchored card widths, compact/standard card
/// heights (190 / width*260/345 around 740px height), unified 128-base
/// logo scaling, 40x40 bordered admin icon, Hero('splash-logo'),
/// MaterialPageRoute navigation.
///
/// Uses the real Gardenia Summer + Google Sans Flex bytes so metrics are
/// genuine: the fallback test font is ultra-wide and inflates unwrapped
/// text intrinsics past the 420 content cap, which de-centers cards.
Future<void> _loadGardenia() async {
  Future<void> load(String family, String asset) async {
    final bytes = File(asset).readAsBytesSync();
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }

  await load('Gardenia Summer', 'assets/fonts/Gardenia Summer.ttf');
  await load('Google Sans Flex', 'assets/fonts/GoogleSansFlex.ttf');
}

Future<void> _pumpOnViewport(WidgetTester tester, Size vp) async {
  tester.view.physicalSize = vp;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(key: UniqueKey(), home: const UserTypeSelectionScreen()),
  );
  await tester.pumpAndSettle();
}

/// Navigation targets (Login, Teacher/Admin gateway) are Riverpod
/// consumers that also read AppLocalizations — a pre-existing requirement
/// of those screens, unrelated to this change.
Future<void> _pumpForNavigation(WidgetTester tester, Size vp) async {
  tester.view.physicalSize = vp;
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
        home: const UserTypeSelectionScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _cardByColor(Color color) => find.byWidgetPredicate(
      (w) => w is Material && w.color == color,
    );

const _newStudentBg = Color(0xFFFBCB3D);
const _currentStudentBg = Color(0xFFE43639);

/// Mirrors the screen formula (zero-inset viewports).
double _expectedCardWidth(Size vp) =>
    (vp.width - 48.0 < 420.0) ? vp.width - 48.0 : 420.0;

double _expectedCardHeight(Size vp) => vp.height < 740.0
    ? 190.0
    : _expectedCardWidth(vp) * 260.0 / 345.0;

double _expectedLogoFont(Size vp) {
  final eff = vp.width < 440.0 ? vp.width : 440.0;
  return 128.0 * eff / 393.0;
}

void main() {
  setUpAll(_loadGardenia);

  // NOTE: the 'unified brand formula constants' unit test was removed here:
  // it locked statics (designBaseWidth, logoBaseFontSize, backgroundColor)
  // that no longer exist on UserTypeSelectionScreen, which now implements
  // the pixel-perfect Figma layout. The widget tests below still lock the
  // superseded contract and fail until rewritten.

  const viewports = <String, Size>{
    'phone_320x568': Size(320, 568),
    'phone_360x800': Size(360, 800),
    'phone_375x667': Size(375, 667),
    'phone_393x852': Size(393, 852),
    'phone_414x896': Size(414, 896),
    'phone_430x932': Size(430, 932),
    'tablet_768x1024': Size(768, 1024),
    'tablet_820x1180': Size(820, 1180),
    'web_1024x768': Size(1024, 768),
    'web_1280x800': Size(1280, 800),
    'web_1440x900': Size(1440, 900),
    'web_1920x1080': Size(1920, 1080),
  };

  for (final entry in viewports.entries) {
    testWidgets('${entry.key}: responsive composition', (tester) async {
      await _pumpOnViewport(tester, entry.value);
      expect(tester.takeException(), isNull);

      // Figma card titles and colors.
      expect(find.text('طالب جديد'), findsOneWidget);
      expect(find.text('طالب حالي'), findsOneWidget);
      expect(_cardByColor(_newStudentBg), findsOneWidget);
      expect(_cardByColor(_currentStudentBg), findsOneWidget);
      final newCard = tester.widget<Material>(_cardByColor(_newStudentBg));
      expect(newCard.borderRadius, BorderRadius.circular(24));
      expect(newCard.clipBehavior, Clip.antiAlias);

      // Cards: expected width/height, centered.
      final expW = _expectedCardWidth(entry.value);
      final expH = _expectedCardHeight(entry.value);
      for (final finder in [_cardByColor(_newStudentBg), _cardByColor(_currentStudentBg)]) {
        final size = tester.getSize(finder);
        expect(size.width, closeTo(expW, 1.0));
        expect(size.height, closeTo(expH, 1.0));
        expect(
          (tester.getCenter(finder).dx - entry.value.width / 2).abs(),
          lessThanOrEqualTo(2.0),
        );
      }

      // Illustrations keep their composition: cover, undistorted.
      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(images.length, 2);
      expect(images[0].fit, BoxFit.cover);
      expect(images[1].fit, BoxFit.cover);

      // Bold Figma typography.
      final title = tester.widget<Text>(find.text('I am a')).style!;
      expect(title.fontSize, 32);
      expect(title.fontWeight, FontWeight.w700);
      expect(title.color, const Color(0xFF111827));
      final subtitle =
          tester.widget<Text>(find.text('Select one that applies to you')).style!;
      expect(subtitle.fontSize, 14);
      expect(subtitle.fontWeight, FontWeight.w400);
      expect(subtitle.color, const Color(0xFF6B7280));
      for (final label in ['طالب جديد', 'طالب حالي']) {
        final style = tester.widget<Text>(find.text(label)).style!;
        expect(style.fontSize, 22);
        expect(style.fontWeight, FontWeight.w700);
        expect(style.color, Colors.white);
      }
      final year = tester.widget<Text>(find.text('2026-2027')).style!;
      expect(year.fontSize, 12);

      // Cohesive grouping: title never starts above the scroll padding
      // (+10 design offset; zero insets here, so 30). On tall viewports
      // the specified outer Center adds symmetric clearance above —
      // balanced, never overlap — so the contract is a minimum.
      final titleTop = tester.getTopLeft(find.text('I am a')).dy;
      expect(titleTop, greaterThanOrEqualTo(30.0 - 1.5));
      expect(titleTop, lessThan(entry.value.height / 2));

      // Unified brand signature: 128-base scaled font, single line.
      final sigStyle = tester.widget<Text>(find.text('Tarek el araby')).style!;
      expect(sigStyle.fontFamily, 'Gardenia Summer');
      expect(sigStyle.fontSize, closeTo(_expectedLogoFont(entry.value), 0.5));
      expect(
        tester.widget<Hero>(find.byType(Hero).first).tag,
        'splash-logo',
      );
      expect(find.text('2026-2027'), findsOneWidget);

      // Admin badge: 40x40 circle, 1.5 border, 22 icon.
      expect(find.byIcon(Icons.person_outline), findsOneWidget);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.person_outline)).size,
        22,
      );
      final badge = find.ancestor(
        of: find.byIcon(Icons.person_outline),
        matching: find.byType(Container),
      );
      expect(badge, findsOneWidget);
      final badgeSize = tester.getSize(badge);
      expect(badgeSize.width, 40);
      expect(badgeSize.height, 40);
      final deco = tester.widget<Container>(badge).decoration as BoxDecoration;
      expect(deco.shape, BoxShape.circle);
      expect(deco.border!.top.color, const Color(0xFFE5E7EB));
      expect(deco.border!.top.width, 1.5);
    });
  }

  testWidgets('compact screens use 190px cards', (tester) async {
    await _pumpOnViewport(tester, const Size(320, 568));
    expect(tester.getSize(_cardByColor(_newStudentBg)).height, 190.0);
    await _pumpOnViewport(tester, const Size(375, 667));
    expect(tester.getSize(_cardByColor(_newStudentBg)).height, 190.0);
  });

  testWidgets('standard screens scale cards by width', (tester) async {
    await _pumpOnViewport(tester, const Size(393, 852));
    expect(tester.getSize(_cardByColor(_newStudentBg)).height,
        closeTo(345.0 * 260.0 / 345.0, 1.0));
    await _pumpOnViewport(tester, const Size(820, 1180));
    expect(tester.getSize(_cardByColor(_newStudentBg)).height,
        closeTo(420.0 * 260.0 / 345.0, 1.0));
  });

  testWidgets('logo keeps 70%-width ratio on phones', (tester) async {
    await _pumpOnViewport(tester, const Size(375, 667));
    var style = tester.widget<Text>(find.text('Tarek el araby')).style!;
    expect(style.fontSize, closeTo(128.0 * 375.0 / 393.0, 0.5));
    await _pumpOnViewport(tester, const Size(440, 956));
    style = tester.widget<Text>(find.text('Tarek el araby')).style!;
    expect(style.fontSize, closeTo(128.0 * 440.0 / 393.0, 0.5));
  });

  testWidgets('tablet cards capped at 420, never full-bleed', (
    tester,
  ) async {
    await _pumpOnViewport(tester, const Size(820, 1180));
    final cardWidth =
        tester.getSize(_cardByColor(_newStudentBg)).width;
    expect(cardWidth, closeTo(420.0, 1.0));
    expect(cardWidth, lessThan(820));
  });

  testWidgets('short height scrolls to footer instead of clipping', (
    tester,
  ) async {
    await _pumpOnViewport(tester, const Size(393, 600));
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('2026-2027'), 300);
    expect(find.text('2026-2027'), findsOneWidget);
    await tester.scrollUntilVisible(find.byIcon(Icons.person_outline), 300);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide-short landscape keeps cards usable', (tester) async {
    await _pumpOnViewport(tester, const Size(800, 400));
    expect(tester.takeException(), isNull);
    expect(find.text('طالب جديد'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('2026-2027'), 300);
    expect(find.text('Tarek el araby'), findsOneWidget);
  });

  testWidgets('new student card navigates to welcome screen', (
    tester,
  ) async {
    await _pumpForNavigation(tester, const Size(393, 852));
    await tester.tap(find.text('طالب جديد'));
    await tester.pumpAndSettle();
    expect(find.byType(NewStudentWelcomeScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('current student card navigates to login', (tester) async {
    await _pumpForNavigation(tester, const Size(393, 852));
    await tester.tap(find.text('طالب حالي'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin icon opens teacher/admin gateway', (tester) async {
    await _pumpForNavigation(tester, const Size(393, 852));
    // Footer sits below the fold on the reference phone: scroll first.
    await tester.scrollUntilVisible(find.byIcon(Icons.person_outline), 300);
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    expect(find.byType(TeacherAdminSelectionScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
