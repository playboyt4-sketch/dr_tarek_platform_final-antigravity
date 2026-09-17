import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drtarek_dashboard/features/applications/presentation/providers/application_decision_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/providers/subject_details_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/widgets/add_lecture_overlay.dart';

Future<void> _pumpDialog(WidgetTester tester,
    {String gradeKey = 'grade_one'}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gradeSubjectsProvider(gradeKey)
            .overrideWith((ref) => Stream.value(const <SubjectOption>[])),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => ElevatedButton(
              onPressed: () => AddLectureOverlay.show(
                context,
                subjectId: '',
                gradeKey: gradeKey,
                tab: SubjectContentTab.lectures,
                initialOrder: 1,
                gradeColor: const Color(0xFFF59E0B),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  group('QuickUploadDialog production fixes', () {
    testWidgets('1. tapping the arrow icon opens the grade menu',
        (WidgetTester tester) async {
      // Unknown grade key -> nothing preselected, so menu items are unique.
      await _pumpDialog(tester, gradeKey: 'grade_unknown');
      expect(find.text('Select Grade'), findsOneWidget);
      // The arrow itself (not the label text) must open the menu: the
      // whole box, padding included, is one opaque GestureDetector.
      await tester.tap(
          find.byIcon(Icons.keyboard_arrow_down).first);
      await tester.pumpAndSettle();
      expect(find.text('الفرقة الأولى'), findsOneWidget);
      expect(find.text('الفرقة الرابعة'), findsOneWidget);
      // Menu popup: pure white, no tint, elevation 4, 360px wide.
      final Finder menuMat = find.byWidgetPredicate(
        (Widget w) =>
            w is Material && w.elevation == 4 && w.color == Colors.white,
      );
      expect(menuMat, findsOneWidget);
      final Material menu = tester.widget<Material>(menuMat);
      expect(menu.surfaceTintColor, Colors.transparent);
      expect(menu.shadowColor, const Color(0x20000000));
      final RoundedRectangleBorder menuShape =
          menu.shape! as RoundedRectangleBorder;
      expect(
        menuShape.side.color,
        const Color(0xFFE0E0E0),
      );
      final Finder menuBox = find.byWidgetPredicate(
        (Widget w) =>
            w is ConstrainedBox &&
            w.constraints.minWidth == 360 &&
            w.constraints.maxWidth == 360,
      );
      expect(menuBox, findsOneWidget);
      expect(tester.getSize(menuBox).width, 360);
    });

    testWidgets('2. grade menu opens below the field, not over the header',
        (WidgetTester tester) async {
      await _pumpDialog(tester, gradeKey: 'grade_unknown');
      await tester.tap(
          find.byIcon(Icons.keyboard_arrow_down).first);
      await tester.pumpAndSettle();
      final Offset fieldCenter =
          tester.getCenter(find.text('Select Grade'));
      final Offset menuTop =
          tester.getTopLeft(find.text('الفرقة الأولى'));
      // Downward-anchored menu: its top edge sits below the field center.
      expect(menuTop.dy, greaterThan(fieldCenter.dy));
      // Header stays clear of the menu.
      expect(find.text('Quick Upload'), findsOneWidget);
    });

    testWidgets('3. section options are clean English with a placeholder',
        (WidgetTester tester) async {
      await _pumpDialog(tester);
      expect(find.text('Select Section'), findsOneWidget);
      await tester.tap(find.text('Select Section'));
      await tester.pumpAndSettle();
      expect(find.text('Lecture'), findsOneWidget);
      expect(find.text('Revision'), findsOneWidget);
      expect(find.text('Final'), findsOneWidget);
      expect(find.text('Online'), findsOneWidget);
      expect(find.text('محاضرة (Lecture)'), findsNothing);
      expect(find.text('مراجعة (Revision)'), findsNothing);
      expect(find.text('نهائي (Final)'), findsNothing);
      expect(find.text('أونلاين (Online)'), findsNothing);
      // Chevron flips up while a menu is open.
      final Finder rotations = find.byType(AnimatedRotation);
      expect(rotations, findsWidgets);
      expect(
        tester
            .widgetList<AnimatedRotation>(rotations)
            .any((w) => w.turns == 0.5),
        isTrue,
      );
    });

    testWidgets('4+5. name and order start empty with gray hints',
        (WidgetTester tester) async {
      await _pumpDialog(tester);
      final TextField nameField =
          tester.widget<TextField>(find.byType(TextField).at(0));
      expect(nameField.controller?.text, '');
      expect(nameField.decoration?.hintText, 'أدخل اسم المحاضرة');
      expect(nameField.decoration?.hintStyle?.color,
          const Color(0xFFBDBDBD));
      final TextField orderField =
          tester.widget<TextField>(find.byType(TextField).at(1));
      expect(orderField.controller?.text, '');
      expect(orderField.decoration?.hintText, '01');
      expect(orderField.decoration?.hintStyle?.color,
          const Color(0xFFBDBDBD));
      final TextField minutesField =
          tester.widget<TextField>(find.byType(TextField).at(2));
      expect(minutesField.controller?.text, '');
      expect(minutesField.decoration?.hintText, '7');
      expect(minutesField.decoration?.hintStyle?.color,
          const Color(0xFFBDBDBD));
    });

    testWidgets('6. resources start empty with a clean empty state',
        (WidgetTester tester) async {
      await _pumpDialog(tester);
      expect(find.text('No resources added yet.'), findsOneWidget);
      expect(find.text('Video - Part 01'), findsNothing);
      expect(find.text('Video - Part 02'), findsNothing);
      expect(find.textContaining('PDF -'), findsNothing);
      expect(find.text('+ Add Resource'), findsOneWidget);
    });

    testWidgets('7. guest access row is centered',
        (WidgetTester tester) async {
      await _pumpDialog(tester);
      final Finder row = find.ancestor(
        of: find.text('Access for free Guest'),
        matching: find.byType(Row),
      );
      expect(row, findsOneWidget);
      expect(tester.widget<Row>(row).mainAxisAlignment,
          MainAxisAlignment.center);
    });

    testWidgets('publish date/time X buttons clear independently',
        (WidgetTester tester) async {
      await _pumpDialog(tester);
      final Finder clearIcons = find.byWidgetPredicate(
        (Widget w) =>
            w is Icon && w.icon == Icons.close && w.size == 14,
      );
      // Date: pick then clear via X.
      await tester.tap(find.text('Select Date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      expect(find.text('Sept 15, 2026'), findsOneWidget);
      expect(clearIcons, findsOneWidget);
      await tester.tap(clearIcons);
      await tester.pumpAndSettle();
      expect(find.text('Select Date'), findsOneWidget);
      // The picker must not have opened from the X tap.
      expect(find.text('Sep'), findsNothing);
      // Time: pick then clear via X.
      await tester.tap(find.text('Select Time'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      expect(find.text('09:00 AM'), findsOneWidget);
      expect(clearIcons, findsOneWidget);
      await tester.tap(clearIcons);
      await tester.pumpAndSettle();
      expect(find.text('Select Time'), findsOneWidget);
    });
  });
}
