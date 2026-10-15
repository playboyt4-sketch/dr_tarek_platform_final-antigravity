import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dr_tarek_platform/features/authentication/presentation/screens/new_student_grade_screen.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/screens/new_student_photo_screen.dart';

Future<void> _pumpPhotoScreen(
  WidgetTester tester, {
  Size? deviceSize,
  String? initialFullName,
  String? initialPhoneNumber,
  String? initialPhotoPath,
}) async {
  if (deviceSize != null) {
    tester.view.physicalSize = deviceSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }
  await tester.pumpWidget(
    MaterialApp(
      home: NewStudentPhotoScreen(
        initialFullName: initialFullName,
        initialPhoneNumber: initialPhoneNumber,
        initialPhotoPath: initialPhotoPath,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('NewStudentPhotoScreen visuals (393x852 Figma)', () {
    testWidgets('renders on #FFFCF7 with headline, + target, and Next', (
      tester,
    ) async {
      await _pumpPhotoScreen(tester);

      expect(find.text('Add a photo'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, const Color(0xFFFFFCF7));
    });

    testWidgets('empty placeholder uses 159 circle target', (tester) async {
      // Fixed-canvas Stack (Welcome-style): rs(159) resolves to exactly
      // 159 at the 393x852 Figma reference viewport.
      await _pumpPhotoScreen(
        tester,
        deviceSize: const Size(393, 852),
      );

      final target = tester.getSize(
        find
            .ancestor(
              of: find.byIcon(Icons.add_rounded),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      expect(target.width, 159);
      expect(target.height, 159);
    });
  });

  group('NewStudentPhotoScreen photo-source overlay', () {
    testWidgets('+ opens sheet with both source rows', (tester) async {
      await _pumpPhotoScreen(tester);

      // Fixed 393x852 canvas can place the target below the fold on
      // short (600px-tall) test surfaces — scroll first (same pattern
      // as the Name screen tests).
      await tester.ensureVisible(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Take a photo'), findsOneWidget);
      expect(find.text('Choose from gallery'), findsOneWidget);
      expect(find.byType(PhotoPickerActionSheet), findsOneWidget);
    });
  });

  group('NewStudentPhotoScreen navigation (photo optional)', () {
    testWidgets('Next works with NO photo and preserves state to Grade', (
      tester,
    ) async {
      await _pumpPhotoScreen(
        tester,
        initialFullName: 'Ahmed Mohamed Ali',
        initialPhoneNumber: '01001234567',
      );

      // No "Please select a photo" gate may exist.
      expect(find.textContaining('select a photo'), findsNothing);

      // Fixed 393x852 canvas puts the CTA at y754 — below the fold on
      // short (600px-tall) test surfaces, so scroll first.
      await tester.ensureVisible(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.byType(NewStudentGradeScreen), findsOneWidget);
      final grade = tester.widget<NewStudentGradeScreen>(
        find.byType(NewStudentGradeScreen),
      );
      expect(grade.initialFullName, 'Ahmed Mohamed Ali');
      expect(grade.initialPhoneNumber, '01001234567');
      expect(grade.initialPhotoPath, isNull);
    });

    testWidgets('back returns to previous step via pop', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const NewStudentPhotoScreen(
                        initialPhoneNumber: '01001234567',
                      ),
                    ),
                  ),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.byType(NewStudentPhotoScreen), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(NewStudentPhotoScreen), findsNothing);
      expect(find.text('go'), findsOneWidget);
    });
  });

  group('NewStudentPhotoScreen responsive', () {
    testWidgets('393x852 renders without overflow', (tester) async {
      await _pumpPhotoScreen(tester, deviceSize: const Size(393, 852));

      expect(tester.takeException(), isNull);
      expect(find.text('Add a photo'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
    });

    testWidgets('360x640 renders without overflow', (tester) async {
      await _pumpPhotoScreen(tester, deviceSize: const Size(360, 640));

      expect(tester.takeException(), isNull);
      expect(find.text('Add a photo'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
    });

    testWidgets('overlay fits within 360x640 viewport', (tester) async {
      await _pumpPhotoScreen(tester, deviceSize: const Size(360, 640));

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Take a photo'), findsOneWidget);
      expect(find.text('Choose from gallery'), findsOneWidget);
    });
  });
}
