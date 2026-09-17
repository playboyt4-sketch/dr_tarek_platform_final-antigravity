import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dr_tarek_platform/features/authentication/presentation/screens/user_type_selection_screen.dart';

/// Safe Area regression test for UserTypeSelectionScreen (unified brand).
///
/// Locks the contract (real Gardenia + Google Sans Flex bytes so metrics
/// are genuine — the fallback test font is ultra-wide and would inflate
/// unwrapped text intrinsics past the content cap):
///
/// ```text
/// top content position    = max(padding.top, 20) + 10
/// bottom content position = viewportH - max(padding.bottom, 16)
/// ```
///
/// Horizontal gutters stay 24px; card column width stays min(w-48, 420).
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

Future<void> _pump(
  WidgetTester tester,
  Size vp, {
  FakeViewPadding padding = FakeViewPadding.zero,
  FakeViewPadding insets = FakeViewPadding.zero,
}) async {
  tester.view.physicalSize = vp;
  tester.view.devicePixelRatio = 1.0;
  tester.view.padding = padding;
  tester.view.viewInsets = insets;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(key: UniqueKey(), home: const UserTypeSelectionScreen()),
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollToEnd(WidgetTester tester) async {
  final scrollable = find.byType(Scrollable).first;
  final state = tester.state<ScrollableState>(scrollable);
  state.position.jumpTo(state.position.maxScrollExtent);
  await tester.pumpAndSettle();
}

Finder _adminBadge() => find.byWidgetPredicate(
      (w) =>
          w is Container &&
          (w.decoration as BoxDecoration?)?.shape == BoxShape.circle,
    );

/// Bottom contract depends on fit: overflowing content pins the badge
/// exactly on the safe line after scrolling to the end; shorter content
/// groups at the top (no spaceBetween), so the badge rests above the line.
/// Both are correct — clipping (past the line) is the failure.
void _expectNoBottomClipping(
  WidgetTester tester,
  Size vp,
  FakeViewPadding pad,
) {
  final safeLine = vp.height - (pad.bottom > 16.0 ? pad.bottom : 16.0);
  final badgeBottom = tester.getRect(_adminBadge()).bottom;
  final scrollable = find.byType(Scrollable).first;
  final maxExtent =
      tester.state<ScrollableState>(scrollable).position.maxScrollExtent;
  if (maxExtent > 0) {
    expect(badgeBottom, closeTo(safeLine, 2.0));
  } else {
    expect(badgeBottom, lessThanOrEqualTo(safeLine + 1.5));
  }
}

void main() {
  setUpAll(_loadGardenia);

  group('safe area insets are respected, design gaps preserved', () {
    const cases = <String, (Size, FakeViewPadding)>{
      'iphone_16_pro_max_440x956':
          (Size(440, 956), FakeViewPadding(top: 59, bottom: 34)),
      'iphone_se_375x667':
          (Size(375, 667), FakeViewPadding(top: 20, bottom: 0)),
      'ipad_portrait_820x1180':
          (Size(820, 1180), FakeViewPadding(top: 24, bottom: 20)),
      'ipad_portrait_1024x1366':
          (Size(1024, 1366), FakeViewPadding(top: 24, bottom: 20)),
      'ipad_landscape_1366x1024': (
        Size(1366, 1024),
        FakeViewPadding(left: 47, top: 0, right: 47, bottom: 21),
      ),
      'web_1920x1080': (Size(1920, 1080), FakeViewPadding.zero),
    };

    for (final entry in cases.entries) {
      testWidgets('${entry.key}: no top overlap, no bottom clipping',
          (tester) async {
        final vp = entry.value.$1;
        final pad = entry.value.$2;
        await _pump(tester, vp, padding: pad);
        expect(tester.takeException(), isNull);

        // TOP: header never starts above max(inset, 20) + the 10px gap.
        // Exact when content overflows; the specified outer Center adds
        // symmetric clearance when content is shorter (balanced, never
        // overlap) — so the contract is a minimum, not equality.
        final expectedTop = (pad.top > 20.0 ? pad.top : 20.0) + 10.0;
        final titleTop = tester.getTopLeft(find.text('I am a')).dy;
        expect(titleTop, greaterThanOrEqualTo(expectedTop - 1.5));
        expect(titleTop, lessThan(vp.height / 2));

        // BOTTOM: 40px admin badge never crosses the max(inset, 16) line.
        await _scrollToEnd(tester);
        expect(tester.takeException(), isNull);
        expect(_adminBadge(), findsOneWidget);
        _expectNoBottomClipping(tester, vp, pad);

        // Responsive behavior unchanged by insets.
        expect(
          tester.widget<Hero>(find.byType(Hero).first).tag,
          'splash-logo',
        );
        expect(find.text('Tarek el araby'), findsOneWidget);
      });
    }
  });

  testWidgets('keyboard insets cause no ViewInsets assertions', (
    tester,
  ) async {
    await _pump(tester, const Size(393, 852),
        insets: const FakeViewPadding(bottom: 300));
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('2026-2027'), 400);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('browser resize and padding changes are safe', (tester) async {
    await _pump(tester, const Size(1280, 800));
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 20);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('طالب جديد'), findsOneWidget);
  });
}
