import 'package:dr_tarek_platform/features/lecture_viewer/presentation/screens/lecture_viewer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Advances fake time past the SnackBar entrance (250ms), lets
  /// ScaffoldMessengerState.build create the auto-dismiss timer, fires it
  /// (2s), then settles the exit animation. Needed because the timer is
  /// only created in a post-entrance build, so a single pump() never fires
  /// it (on a real device frames run continuously, so this is test-only).
  Future<void> dismissSnackBar(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  }

  testWidgets('LectureViewer cycles through 3 view modes via FAB',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: LectureViewerScreen()),
    );
    await tester.pumpAndSettle();

    // RTL + Arabic header visible.
    expect(find.text('المحاسبة المالية - محاضرة 01'), findsOneWidget);
    expect(find.text('صفحة 18 من 42'), findsOneWidget);

    // Mode 0 -> 1 : split screen.
    await tester.tap(find.byType(FloatingActionButton),
        warnIfMissed: false);
    await tester.pump();
    expect(find.text('وضع الشاشة المنقسمة'), findsOneWidget);
    await dismissSnackBar(tester);

    // Mode 1 -> 2 : floating PDF.
    await tester.tap(find.byType(FloatingActionButton),
        warnIfMissed: false);
    await tester.pump();
    expect(find.text('وضع الـ PDF العائم'), findsOneWidget);
    await dismissSnackBar(tester);

    // Mode 2 -> 0 : full PDF.
    await tester.tap(find.byType(FloatingActionButton),
        warnIfMissed: false);
    await tester.pump();
    expect(find.text('وضع القراءة الكامل'), findsOneWidget);
  });

  testWidgets('Main menu opens notes sheet with both tabs', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: LectureViewerScreen()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();
    expect(find.text('البحث والفهرس'), findsOneWidget);
    expect(find.text('الملاحظات والأسئلة'), findsOneWidget);

    await tester.tap(find.text('الملاحظات والأسئلة'));
    await tester.pumpAndSettle();
    expect(find.text('ملاحظة للمذاكرة'), findsOneWidget);
    expect(find.text('اسأل د. طارق'), findsOneWidget);
    expect(find.text('حفظ الملاحظة'), findsOneWidget);

    // Switch to teacher tab -> button + hint change.
    await tester.tap(find.text('اسأل د. طارق'));
    await tester.pumpAndSettle();
    expect(find.text('إرسال السؤال للدكتور'), findsOneWidget);
  });
}
