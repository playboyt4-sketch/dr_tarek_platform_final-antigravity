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
})> _pumpMenu(
  WidgetTester tester, {
  Size size = const Size(1280, 800),
}) async {
  tester.view.physicalSize = size;
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

void main() {
  group('full menu responsive conformance', () {
    testWidgets('fills available viewport with white background and no fixed box',
        (tester) async {
      await _pumpMenu(tester, size: const Size(1440, 900));

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

      // Expands to full width on desktop without FittedBox scaling.
      expect(
        find.descendant(
          of: find.byType(DashboardFullMenu),
          matching: find.byType(SizedBox),
        ),
        findsWidgets,
      );
      final Size menuSize = tester.getSize(find.byType(DashboardFullMenu));
      expect(menuSize, const Size(1440, 900));
    });

    testWidgets('no inner menu button — shell owns the fixed button',
        (tester) async {
      await _pumpMenu(tester);

      expect(
        find.descendant(
          of: find.byType(DashboardFullMenu),
          matching: find.byType(TheMenuButton),
        ),
        findsNothing,
      );
    });

    testWidgets('brand lockup renders on desktop with 400+100 black',
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
      expect(heavy.style?.fontWeight, FontWeight.w400);
      expect(heavy.style?.color, const Color(0xFF000000));
      expect(light.text, 'Platform');
      expect(light.style?.fontWeight, FontWeight.w100);
      expect(light.style?.color, const Color(0xFF000000));
    });

    testWidgets('master and sub entries render with expected typography',
        (tester) async {
      await _pumpMenu(tester);

      final TextStyle homeStyle =
          tester.widget<Text>(find.text('Home')).style!;
      expect(homeStyle.fontSize, 32);
      expect(homeStyle.fontWeight, FontWeight.w400);
      expect(homeStyle.color, const Color(0xFF000000));
      expect(homeStyle.fontFamily, AppTypography.fontFamily);

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
        'Archive',
      ]) {
        final TextStyle style =
            tester.widget<Text>(find.text(label)).style!;
        expect(style.fontSize, 20, reason: label);
        expect(style.fontWeight, FontWeight.w300, reason: label);
        expect(style.color, const Color(0xFF000000), reason: label);
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
      expect(regions, findsNWidgets(13));

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
