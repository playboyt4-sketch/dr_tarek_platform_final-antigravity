import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dr_tarek_platform/features/authentication/presentation/screens/new_student_name_screen.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/screens/new_student_welcome_screen.dart';

/// Dedicated test for NewStudentWelcomeScreen (anchored layout):
/// illustration pinned below the status bar (+8 gap), button pinned to a
/// fixed bottom anchor via Spacer + minHeight, unified 128-base red
/// signature, 56px capsule navigating to NewStudentNameScreen.
///
/// Uses the real Gardenia Summer bytes so signature metrics are genuine.
Future<void> _loadGardenia() async {
  final bytes = File('assets/fonts/Gardenia Summer.ttf').readAsBytesSync();
  final loader = FontLoader('Gardenia Summer')
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}

Future<void> _pumpOnViewport(WidgetTester tester, Size vp) async {
  tester.view.physicalSize = vp;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(key: UniqueKey(), home: const NewStudentWelcomeScreen()),
  );
  await tester.pumpAndSettle();
}

double _expectedContentWidth(Size vp) =>
    (vp.width - 24.0 < 369.0) ? vp.width - 24.0 : 369.0;

double _expectedButtonWidth(Size vp) =>
    (vp.width - 48.0 < 345.0) ? vp.width - 48.0 : 345.0;

double _expectedIllustrationHeight(Size vp) => vp.height < 740.0
    ? 260.0
    : (vp.height * 0.45 < 385.0 ? vp.height * 0.45 : 385.0);

double _expectedLogoFont(Size vp) {
  final eff = vp.width < 440.0 ? vp.width : 440.0;
  return 128.0 * eff / 393.0;
}

Future<void> _scrollToEnd(WidgetTester tester) async {
  final state = tester.state<ScrollableState>(find.byType(Scrollable).first);
  state.position.jumpTo(state.position.maxScrollExtent);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(_loadGardenia);

  test('static brand constants', () {
    expect(NewStudentWelcomeScreen.backgroundColor, Colors.white);
    expect(NewStudentWelcomeScreen.primaryBlue, const Color(0xFF1D4ED8));
    expect(NewStudentWelcomeScreen.brandRed, const Color(0xFFDC2626));
    expect(NewStudentWelcomeScreen.designBaseWidth, 393.0);
    expect(NewStudentWelcomeScreen.logoBaseFontSize, 128.0);
  });

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
    testWidgets('${entry.key}: anchored composition', (tester) async {
      await _pumpOnViewport(tester, entry.value);
      expect(tester.takeException(), isNull);

      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        Colors.white,
      );

      // Illustration anchored below status bar (+8 gap), adaptive size.
      final clip = tester.widget<ClipRRect>(find.byType(ClipRRect).first);
      expect(clip.borderRadius, BorderRadius.circular(28));
      final illuSize = tester.getSize(find.byType(ClipRRect).first);
      expect(illuSize.width, closeTo(_expectedContentWidth(entry.value), 1.0));
      expect(
        illuSize.height,
        closeTo(_expectedIllustrationHeight(entry.value), 1.0),
      );
      expect(tester.getTopLeft(find.byType(ClipRRect).first).dy,
          closeTo(20.0 + 8.0, 1.5));
      expect(
        (tester.getCenter(find.byType(ClipRRect).first).dx -
                entry.value.width / 2)
            .abs(),
        lessThanOrEqualTo(2.0),
      );

      // Title typography.
      final title = tester
          .widget<Text>(find.text('Welcome to our community\nwith'))
          .style!;
      expect(title.fontSize, 28);
      expect(title.fontWeight, FontWeight.w700);
      expect(title.color, const Color(0xFF111827));

      // Unified red signature + Spacer-driven structure.
      final sigStyle =
          tester.widget<Text>(find.text('Tarek el araby')).style!;
      expect(sigStyle.fontFamily, 'Gardenia Summer');
      expect(sigStyle.fontSize, closeTo(_expectedLogoFont(entry.value), 0.5));
      expect(sigStyle.color, const Color(0xFFDC2626));
      expect(find.byType(Spacer), findsOneWidget);

      // Pinned capsule button: exact width, 56 height, bottom anchor.
      expect(find.text('Get Start'), findsOneWidget);
      final btnSize = tester.getSize(find.byType(ElevatedButton).first);
      expect(btnSize.width, closeTo(_expectedButtonWidth(entry.value), 1.0));
      expect(btnSize.height, 56);
      final btnStyle =
          tester.widget<ElevatedButton>(find.byType(ElevatedButton).first);
      expect(btnStyle.style!.backgroundColor!.resolve({}), const Color(0xFF1D4ED8));
      final btnLabel = tester.widget<Text>(find.text('Get Start')).style!;
      expect(btnLabel.fontSize, 20);
      expect(btnLabel.fontWeight, FontWeight.w700);

      await _scrollToEnd(tester);
      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.byType(ElevatedButton).first).bottom,
          closeTo(entry.value.height - 16.0, 2.0));
    });
  }

  testWidgets('compact illustration is 260, tall scales to 385 cap',
      (tester) async {
    await _pumpOnViewport(tester, const Size(375, 667));
    expect(tester.getSize(find.byType(ClipRRect).first).height, 260.0);
    await _pumpOnViewport(tester, const Size(393, 852));
    expect(tester.getSize(find.byType(ClipRRect).first).height,
        closeTo(852 * 0.45, 1.0));
    await _pumpOnViewport(tester, const Size(820, 1180));
    expect(tester.getSize(find.byType(ClipRRect).first).height, 385.0);
  });

  testWidgets('get start navigates to name screen', (tester) async {
    await _pumpOnViewport(tester, const Size(393, 852));
    await tester.scrollUntilVisible(find.text('Get Start'), 300);
    await tester.tap(find.text('Get Start'));
    await tester.pumpAndSettle();
    expect(find.byType(NewStudentNameScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
