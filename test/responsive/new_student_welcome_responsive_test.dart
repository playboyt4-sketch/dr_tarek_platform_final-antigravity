import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dr_tarek_platform/core/widgets/primary_button.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/screens/new_student_name_screen.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/screens/new_student_welcome_screen.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/widgets/brand_signature_logo.dart';

/// Responsive contract for NewStudentWelcomeScreen (Figma node 35:18).
///
/// The screen is constraint-based: the SafeArea is the coordinate origin, the
/// hero is the flexible element, the CTA is pinned 8px above the safe-area
/// bottom edge, and the composition must never scroll on a supported portrait
/// viewport.
///
/// Real system insets are injected through `tester.view.padding` (the old test
/// left them at zero, which made `SafeArea` a no-op and hid the defect), and
/// real Google Sans Flex + Gardenia Summer bytes are loaded so typography
/// metrics are genuine.
const _rootKey = ValueKey<String>('welcome-root');
const _title = 'Welcome to our community\nwith';
const _ctaLabel = 'Get started';

Future<void> _loadFonts() async {
  Future<void> load(String family, String asset) async {
    final bytes = File(asset).readAsBytesSync();
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }

  await load('Gardenia Summer', 'assets/fonts/Gardenia Summer.ttf');
  await load('Google Sans Flex', 'assets/fonts/GoogleSansFlex.ttf');
}

Future<void> _pump(
  WidgetTester tester,
  Size viewport, {
  FakeViewPadding padding = FakeViewPadding.zero,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1.0;
  tester.view.padding = padding;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      home: const RepaintBoundary(
        key: _rootKey,
        child: NewStudentWelcomeScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

double _maxScrollExtent(WidgetTester tester) {
  final state = tester.state<ScrollableState>(find.byType(Scrollable).first);
  return state.position.maxScrollExtent;
}

Rect _heroRect(WidgetTester tester) =>
    tester.getRect(find.byType(ClipRRect).first);

class _Viewport {
  const _Viewport(this.size, this.padding);

  final Size size;
  final FakeViewPadding padding;

  double get safeBottom => size.height - padding.bottom;
}

final Map<String, _Viewport> _viewports = <String, _Viewport>{
  '393x852 (iPhone 14/15)': const _Viewport(
    Size(393, 852),
    FakeViewPadding(top: 59, bottom: 34),
  ),
  '430x932 (iPhone Pro Max)': const _Viewport(
    Size(430, 932),
    FakeViewPadding(top: 59, bottom: 34),
  ),
  '412x915 (Android)': const _Viewport(
    Size(412, 915),
    FakeViewPadding(top: 24, bottom: 24),
  ),
  '375x667 (iPhone SE)': const _Viewport(
    Size(375, 667),
    FakeViewPadding(top: 20),
  ),
  '360x640 (small Android)': const _Viewport(
    Size(360, 640),
    FakeViewPadding(top: 24, bottom: 48),
  ),
  '320x568 (compact)': const _Viewport(
    Size(320, 568),
    FakeViewPadding(top: 20),
  ),
  '820x1180 (tablet)': const _Viewport(
    Size(820, 1180),
    FakeViewPadding(top: 24, bottom: 20),
  ),
  '852x393 (landscape)': const _Viewport(
    Size(852, 393),
    FakeViewPadding.zero,
  ),
};

void main() {
  setUpAll(_loadFonts);

  group('portrait + tablet + landscape', () {
    for (final entry in _viewports.entries) {
      testWidgets('${entry.key}: fits with zero scroll', (tester) async {
        final vp = entry.value;
        await _pump(tester, vp.size, padding: vp.padding);

        expect(tester.takeException(), isNull,
            reason: 'no RenderFlex overflow / paint exception');
        expect(_maxScrollExtent(tester), 0.0,
            reason: 'normal screens must not scroll');

        // --- CTA: bottom-anchored, fully visible, canonical size. ---
        final cta = tester.getRect(find.byType(PrimaryButton));
        expect(cta.height, 56.0);
        expect(cta.bottom, closeTo(vp.safeBottom - 8.0, 0.51));
        expect(cta.top, greaterThanOrEqualTo(vp.padding.top - 0.01));
        expect(cta.left, greaterThanOrEqualTo(-0.01));
        expect(cta.right, lessThanOrEqualTo(vp.size.width + 0.01));
        expect(find.text(_ctaLabel), findsOneWidget);

        // --- Hero: starts at the safe-area top, keeps 369:395, no clip. ---
        final hero = _heroRect(tester);
        expect(hero.top, closeTo(vp.padding.top, 0.51));
        expect(hero.left, greaterThanOrEqualTo(-0.01));
        expect(hero.right, lessThanOrEqualTo(vp.size.width + 0.01));
        expect(hero.width / hero.height, closeTo(369 / 395, 0.006));

        // --- Title: two hard lines, inside the viewport. ---
        final title = tester.getRect(find.text(_title));
        expect(title.left, greaterThanOrEqualTo(-0.01));
        expect(title.right, lessThanOrEqualTo(vp.size.width + 0.01));
        expect(title.top, greaterThanOrEqualTo(vp.padding.top - 0.01));
        expect(title.bottom, lessThanOrEqualTo(vp.safeBottom + 0.01));

        // --- Signature: centered, inside the safe area, never clipped. ---
        final signature = tester.getRect(find.byType(BrandSignatureLogo));
        expect(signature.center.dx, closeTo(vp.size.width / 2, 1.0));
        expect(signature.left, greaterThanOrEqualTo(-0.01));
        expect(signature.right, lessThanOrEqualTo(vp.size.width + 0.01));
        expect(signature.top, greaterThanOrEqualTo(vp.padding.top - 0.01));
        expect(signature.bottom, lessThanOrEqualTo(vp.safeBottom + 0.01));

        // --- Back button lives inside the hero bounds. ---
        final back = tester.getRect(find.byType(SvgPicture));
        expect(back.left, greaterThanOrEqualTo(hero.left - 0.01));
        expect(back.right, lessThanOrEqualTo(hero.right + 0.01));
        expect(back.top, greaterThanOrEqualTo(hero.top - 0.01));
        expect(back.bottom, lessThanOrEqualTo(hero.bottom + 0.01));
      });
    }
  });

  testWidgets('reference frame reproduces the Figma composition',
      (tester) async {
    const vp = Size(393, 852);
    const padding = FakeViewPadding(top: 59, bottom: 34);
    await _pump(tester, vp, padding: padding);

    // Figma content band starts at the safe-area top (frame y=50 already
    // includes the status bar, so nothing is added inside SafeArea).
    final hero = _heroRect(tester);
    expect(hero.top, closeTo(59, 0.51));
    expect(hero.width, closeTo(369, 0.51));
    expect(hero.height, closeTo(395, 0.51));

    // Two 36px lines => 72px block.
    final title = tester.getRect(find.text(_title));
    expect(title.height, closeTo(72, 0.51));

    // 95px signature slot, artwork rendering at its natural 128px line box.
    final signature = tester.getRect(find.byType(BrandSignatureLogo));
    expect(signature.height, closeTo(128, 0.51));

    // CTA: 345x56, pill handled by PrimaryButton, bottom at safe edge - 8.
    final cta = tester.getRect(find.byType(PrimaryButton));
    expect(cta.width, closeTo(345, 0.51));
    expect(cta.height, closeTo(56, 0.51));
    expect(cta.bottom, closeTo(852 - 34 - 8, 0.51));
  });

  testWidgets('signature ink matches the 92px Figma artwork', (tester) async {
    const vp = Size(393, 852);
    const padding = FakeViewPadding(top: 59, bottom: 34);
    await _pump(tester, vp, padding: padding);

    final signatureBox = tester.getRect(find.byType(BrandSignatureLogo));
    final signatureSlot = tester.getRect(find.byType(OverflowBox));
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_rootKey),
    );

    final ui.Image? image =
        await tester.runAsync(() => boundary.toImage(pixelRatio: 1.0));
    expect(image, isNotNull, reason: 'screen must rasterise');
    final ByteData? bytes = await tester.runAsync<ByteData?>(
      () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    expect(bytes, isNotNull, reason: 'pixels must be readable');
    image!.dispose();

    final data = bytes!.buffer.asUint8List();
    final width = vp.width.toInt();
    final height = vp.height.toInt();
    final yStart = math.max(0, signatureBox.top.floor() - 12);
    final yEnd = math.min(height, signatureBox.bottom.ceil() + 12);

    var minX = width, maxX = -1, minY = height, maxY = -1, count = 0;
    for (var y = yStart; y < yEnd; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        final r = data[i];
        final g = data[i + 1];
        final b = data[i + 2];
        if (r > 150 && g < 110 && b < 110) {
          count++;
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }

    expect(count, greaterThan(1000), reason: 'signature ink must be painted');
    final inkHeight = maxY - minY + 1;
    final inkWidth = maxX - minX + 1;
    final inkCenterY = (minY + maxY) / 2;

    debugPrint(
      'signature ink: ${inkWidth}x$inkHeight at '
      '($minX,$minY)-($maxX,$maxY), centerY=$inkCenterY '
      '(slot center ${signatureSlot.center.dy})',
    );

    // Figma: ink 92 tall, 269 wide, centered at x=196.5 and inside the slot.
    expect(inkHeight, inInclusiveRange(88, 96),
        reason: 'shared widget must not be downscaled by the 95px slot');
    expect(inkWidth, greaterThan(230));
    expect((minX + maxX) / 2, closeTo(vp.width / 2, 2.0));
    expect(inkCenterY, closeTo(signatureSlot.center.dy, 4.0));
  });

  testWidgets('accessibility text scale 1.3 still fits without scrolling',
      (tester) async {
    const vp = Size(393, 852);
    const padding = FakeViewPadding(top: 59, bottom: 34);
    await _pump(tester, vp, padding: padding, textScale: 1.3);

    expect(tester.takeException(), isNull);
    expect(_maxScrollExtent(tester), 0.0);

    final cta = tester.getRect(find.byType(PrimaryButton));
    expect(cta.bottom, closeTo(852 - 34 - 8, 0.51));
    expect(cta.left, greaterThanOrEqualTo(0));
    expect(cta.right, lessThanOrEqualTo(393));

    final title = tester.getRect(find.text(_title));
    expect(title.height, greaterThan(72),
        reason: 'title must actually scale with the text scaler');
    expect(title.bottom, lessThanOrEqualTo(852 - 34 + 0.01));

    final signature = tester.getRect(find.byType(BrandSignatureLogo));
    expect(signature.bottom, lessThanOrEqualTo(852 - 34 + 0.01));
  });

  testWidgets('get started navigates, back button pops', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const NewStudentWelcomeScreen(),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(NewStudentWelcomeScreen), findsOneWidget);

    await tester.tap(find.text(_ctaLabel));
    await tester.pumpAndSettle();
    expect(find.byType(NewStudentNameScreen), findsOneWidget);

    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    expect(find.byType(NewStudentWelcomeScreen), findsOneWidget);

    await tester.tap(find.byType(SvgPicture));
    await tester.pumpAndSettle();
    expect(find.byType(NewStudentWelcomeScreen), findsNothing);
  });
}
