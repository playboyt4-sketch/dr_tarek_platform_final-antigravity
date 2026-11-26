import 'package:dr_tarek_platform/features/lecture/presentation/screens/pdf_viewer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'ResizableFloatingPdfWindow resizes via corner handle and drags via top handle within SafeArea',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(450, 750);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 700,
            child: ResizableFloatingPdfWindow(
              areaWidth: 400,
              areaHeight: 700,
              initialWidth: 180,
              initialHeight: 260,
              child: ColoredBox(color: Colors.blue),
            ),
          ),
        ),
      ),
    );

    final Finder windowFinder = find.byKey(const Key('floating-pdf-window'));
    final Size initialSize = tester.getSize(windowFinder);
    expect(initialSize, const Size(180, 260));

    // Drag the top drag bar right and up to move without changing size.
    final Offset beforeMoveTopLeft = tester.getTopLeft(windowFinder);
    await tester.drag(
      find.byKey(const Key('floating-pdf-drag-handle')),
      const Offset(40, -100),
    );
    await tester.pump();
    final Offset afterMoveTopLeft = tester.getTopLeft(windowFinder);
    expect(afterMoveTopLeft.dx, closeTo(beforeMoveTopLeft.dx + 40, 1.0));
    expect(afterMoveTopLeft.dy, closeTo(beforeMoveTopLeft.dy - 100, 1.0));
    expect(tester.getSize(windowFinder), initialSize);

    // Drag the resize handle to grow width and height.
    await tester.drag(
      find.byKey(const Key('floating-pdf-resize-handle')),
      const Offset(80, 60),
    );
    await tester.pump();
    final Size grownSize = tester.getSize(windowFinder);
    expect(grownSize.width, greaterThan(initialSize.width));
    expect(grownSize.height, greaterThan(initialSize.height));

    // Dragging far negative clamps cleanly to safe minimum dimensions.
    await tester.drag(
      find.byKey(const Key('floating-pdf-resize-handle')),
      const Offset(-500, -500),
    );
    await tester.pump();
    final Size minClamped = tester.getSize(windowFinder);
    expect(minClamped.width, greaterThanOrEqualTo(140));
    expect(minClamped.height, greaterThanOrEqualTo(180));

    // Dragging far positive clamps within area bounds.
    await tester.drag(
      find.byKey(const Key('floating-pdf-resize-handle')),
      const Offset(1000, 1000),
    );
    await tester.pump();
    final Rect finalRect = tester.getRect(windowFinder);
    expect(finalRect.right, lessThanOrEqualTo(400 - 8 + 0.1));
    expect(finalRect.bottom, lessThanOrEqualTo(700 - 8 + 0.1));
  });

  testWidgets(
      'PdfViewerMainMenuSheet wraps items in SafeArea + SingleChildScrollView without bottom clipping on short iPhone viewports',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(375, 420);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(375, 420),
            padding: EdgeInsets.only(bottom: 34),
          ),
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: Material(
                color: Colors.white,
                child: PdfViewerMainMenuSheet(
                  isOfflineEnabled: false,
                  onSearchTap: () {},
                  onNotesTap: () {},
                  onOfflineChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(PdfViewerMainMenuSheet),
        matching: find.byWidgetPredicate(
          (Widget w) => w is SafeArea && !w.top && w.bottom,
        ),
      ),
      findsOneWidget,
    );
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.text('البحث والفهرس'), findsOneWidget);
    expect(find.text('الملاحظات الشخصية'), findsOneWidget);
    expect(find.text('Offline mode'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
