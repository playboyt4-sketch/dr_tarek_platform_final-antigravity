import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drtarek_dashboard/app/shell/dashboard_full_menu.dart';
import 'package:drtarek_dashboard/core/theme/app_typography.dart';
import 'package:drtarek_dashboard/core/widgets/animated_menu_button.dart';

Future<({
  VoidCallback onClose,
  ValueChanged<String> onNavigate,
  List<String> closed,
  List<String> routes,
})> _pumpMenu(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final List<String> closed = <String>[];
  final List<String> routes = <String>[];

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DashboardFullMenu(
          onClose: () => closed.add('closed'),
          onNavigate: routes.add,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (
    onClose: () {},
    onNavigate: (_) {},
    closed: closed,
    routes: routes,
  );
}

Positioned _positionedOf(WidgetTester tester, String label) {
  final Finder text = find.text(label, skipOffstage: false);
  final Finder positioned = find.ancestor(
    of: text,
    matching: find.byType(Positioned),
  );
  return tester.widget<Positioned>(positioned.first);
}

void main() {
  group('full menu spec conformance (1280 x 800)', () {
    testWidgets('canvas is 1280x800 white and clipped', (tester) async {
      await _pumpMenu(tester);

      expect(
        find.byWidgetPredicate(
          (Widget w) =>
              w is SizedBox && w.width == 1280 && w.height == 800,
        ),
        findsOneWidget,
      );

      final Material material = tester.widget<Material>(
        find.descendant(
          of: find.byType(DashboardFullMenu),
          matching: find.byWidgetPredicate(
            (Widget w) =>
                w is Material && w.color == const Color(0xFFFFFFFF),
          ),
        ),
      );
      expect(material.color, const Color(0xFFFFFFFF));

      for (final SingleChildScrollView scroll
          in tester.widgetList<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      )) {
        expect(scroll.clipBehavior, Clip.antiAlias);
      }
      expect(
        tester
            .widget<ClipRect>(
              find.byWidgetPredicate(
                (Widget w) =>
                    w is ClipRect &&
                    w.child is SizedBox &&
                    (w.child! as SizedBox).width == 1280,
              ),
            )
            .clipBehavior,
        Clip.antiAlias,
      );
    });

    testWidgets('no inner menu button — shell owns the fixed (80, 24) button',
        (tester) async {
      await _pumpMenu(tester);

      // Pixel-shift regression guard: the overlay must not draw its own
      // button. The unified shell draws the single fixed TheMenuButton
      // at (80, 24, 80 x 80) in its top Stack layer.
      expect(
        find.descendant(
          of: find.byType(DashboardFullMenu),
          matching: find.byType(TheMenuButton),
        ),
        findsNothing,
      );
    });

    testWidgets('brand lockup at (370, 24), 540x80, 48px 400+100 black',
        (tester) async {
      await _pumpMenu(tester);

      final Text brand = tester.widget<Text>(
        find.byWidgetPredicate(
          (Widget w) =>
              w is Text &&
              w.textSpan is TextSpan &&
              (w.textSpan! as TextSpan).children?.length == 2,
        ),
      );
      final TextSpan span = brand.textSpan! as TextSpan;
      expect(span.children, hasLength(2));
      final TextSpan heavy = span.children![0] as TextSpan;
      final TextSpan light = span.children![1] as TextSpan;
      expect(heavy.text, 'Tarek el araby ');
      expect(heavy.style?.fontSize, 48);
      expect(heavy.style?.fontWeight, FontWeight.w400);
      expect(heavy.style?.color, const Color(0xFF000000));
      expect(light.text, 'Platform');
      expect(light.style?.fontSize, 48);
      expect(light.style?.fontWeight, FontWeight.w100);
      expect(light.style?.color, const Color(0xFF000000));
      expect(light.style?.letterSpacing, 0);

      expect(
        find.byWidgetPredicate(
          (Widget w) =>
              w is Positioned &&
              w.left == 370 &&
              w.top == 24 &&
              w.width == 540 &&
              w.height == 80,
        ),
        findsOneWidget,
      );
    });

    testWidgets('master column at X 370 with exact slots', (tester) async {
      await _pumpMenu(tester);

      expect(_positionedOf(tester, 'Home').left, 370);
      expect(_positionedOf(tester, 'Home').top, 164);
      expect(_positionedOf(tester, 'Home').width, 250);
      expect(_positionedOf(tester, 'Home').height, 40);

      expect(_positionedOf(tester, 'Grades').left, 370);
      expect(_positionedOf(tester, 'Grades').top, 228);

      expect(_positionedOf(tester, 'Management').left, 370);
      expect(_positionedOf(tester, 'Management').top, 402);

      final TextStyle homeStyle =
          tester.widget<Text>(find.text('Home')).style!;
      expect(homeStyle.fontSize, 32);
      expect(homeStyle.fontWeight, FontWeight.w400);
      expect(homeStyle.color, const Color(0xFF000000));
      expect(homeStyle.fontFamily, AppTypography.fontFamily);
    });

    testWidgets('sub column at X 660 with 12px gaps and 20/300 rows',
        (tester) async {
      await _pumpMenu(tester);

      // Frame 30 grades list at (660, 236).
      final Finder frame30 = find.ancestor(
        of: find.text('Grade One', skipOffstage: false),
        matching: find.byType(Positioned),
      );
      final Positioned pos30 = tester.widget<Positioned>(frame30.first);
      expect(pos30.left, 660);
      expect(pos30.top, 236);

      // Frame 31 management list at (660, 410).
      final Finder frame31 = find.ancestor(
        of: find.text('Subscription', skipOffstage: false),
        matching: find.byType(Positioned),
      );
      final Positioned pos31 = tester.widget<Positioned>(frame31.first);
      expect(pos31.left, 660);
      expect(pos31.top, 410);

      // 290 px inter-column gap.
      expect(pos30.left! - 370, 290);

      for (final String label in <String>[
        'Grade One',
        'Grade Two',
        'Grade Three',
        'Grade Four',
        'Subscription',
        'Admins',
        'Announcements',
        'Audit Logs',
        'Payments',
        'System Settings',
      ]) {
        final TextStyle style =
            tester.widget<Text>(find.text(label)).style!;
        expect(style.fontSize, 20, reason: label);
        expect(style.fontWeight, FontWeight.w300, reason: label);
        expect(style.color, const Color(0xFF000000), reason: label);
        expect(style.height, 24 / 20, reason: label);
      }
    });

    testWidgets('entries route (close is owned by the shell button)',
        (tester) async {
      final record = await _pumpMenu(tester);

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Grade Two'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Payments'));
      await tester.pumpAndSettle();
      expect(record.routes, <String>['home', 'gradeTwo', 'payments']);
    });

    testWidgets('hover shows click cursor and 70% opacity', (tester) async {
      await _pumpMenu(tester);

      final Finder regions = find.descendant(
        of: find.byType(DashboardFullMenu),
        matching: find.byWidgetPredicate(
          (Widget w) => w is MouseRegion && w.cursor == SystemMouseCursors.click,
        ),
      );
      // Home + 4 grades + 6 management entries.
      expect(regions, findsNWidgets(11));

      final Offset center = tester.getCenter(find.text('Home'));
      final TestGesture mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: center);
      await tester.pumpAndSettle();

      final Finder opacities = find.descendant(
        of: find.byType(DashboardFullMenu),
        matching: find.byWidgetPredicate(
          (Widget w) => w is AnimatedOpacity && w.opacity == 0.7,
        ),
      );
      expect(opacities, findsOneWidget);
      await mouse.removePointer();
    });
  });
}
