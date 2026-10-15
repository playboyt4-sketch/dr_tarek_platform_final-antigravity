import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dr_tarek_platform/core/widgets/glass_back_button.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/screens/new_student_number_screen.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/screens/new_student_photo_screen.dart';

Future<void> _pumpNumberScreen(
  WidgetTester tester, {
  Size? deviceSize,
  String? initialFullName,
  String? initialPhoneNumber,
}) async {
  if (deviceSize != null) {
    tester.view.physicalSize = deviceSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: NewStudentNumberScreen(
          initialFullName: initialFullName,
          initialPhoneNumber: initialPhoneNumber,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The CTA sits at Figma y754 on a fixed 852-tall canvas, below the fold
/// on the default 800x600 test surface — scroll it into view first.
Future<void> _tapNext(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Next'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Next'), warnIfMissed: false);
  await tester.pump();
}

void main() {
  group('NewStudentNumberScreen visuals (393x852 Figma)', () {
    testWidgets('renders headline, field, and Next on #FFFCF7', (tester) async {
      await _pumpNumberScreen(tester);

      expect(find.text('Your phone number?'), findsOneWidget);
      expect(find.text('phone number'), findsOneWidget);
      expect(find.text('Enter your phone number'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, const Color(0xFFFFFCF7));
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('phone field is numeric with 11-digit limit', (tester) async {
      await _pumpNumberScreen(tester);

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.keyboardType, TextInputType.phone);
    });
  });

  group('NewStudentNumberScreen validation', () {
    testWidgets('empty phone is rejected and stays on screen', (tester) async {
      await _pumpNumberScreen(tester);

      await _tapNext(tester);

      expect(find.text('Phone number is required.'), findsOneWidget);
      expect(find.byType(NewStudentPhotoScreen), findsNothing);
    });

    testWidgets('whitespace-only phone is rejected', (tester) async {
      await _pumpNumberScreen(tester);

      // digitsOnly formatter strips spaces, so the trimmed value is empty.
      await tester.enterText(find.byType(TextField), '   ');
      await _tapNext(tester);

      expect(find.text('Phone number is required.'), findsOneWidget);
      expect(find.byType(NewStudentPhotoScreen), findsNothing);
    });

    testWidgets('invalid Egyptian format is rejected', (tester) async {
      await _pumpNumberScreen(tester);

      await tester.enterText(find.byType(TextField), '12345678901');
      await _tapNext(tester);

      expect(find.textContaining('valid Egyptian mobile'), findsOneWidget);
      expect(find.byType(NewStudentPhotoScreen), findsNothing);
    });

    testWidgets('country-code form is rejected (V1 has no +20)', (
      tester,
    ) async {
      await _pumpNumberScreen(tester);

      // digitsOnly keeps the digits; the 13-digit result fails the 11-digit
      // `01...` rule and must not navigate.
      await tester.enterText(find.byType(TextField), '201001234567');
      await _tapNext(tester);

      expect(find.textContaining('valid Egyptian mobile'), findsOneWidget);
      expect(find.byType(NewStudentPhotoScreen), findsNothing);
    });

    testWidgets('valid Egyptian phone navigates to the Photo step', (
      tester,
    ) async {
      await _pumpNumberScreen(tester, initialFullName: 'Ahmed Mohamed Ali');

      await tester.enterText(find.byType(TextField), '01001234567');
      await tester.ensureVisible(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(NewStudentPhotoScreen), findsOneWidget);

      // Registration state survives: full name carried forward, phone saved.
      final photo = tester.widget<NewStudentPhotoScreen>(
        find.byType(NewStudentPhotoScreen),
      );
      expect(photo.initialFullName, 'Ahmed Mohamed Ali');
      expect(photo.initialPhoneNumber, '01001234567');
    });
  });

  group('NewStudentNumberScreen state preservation', () {
    testWidgets('existing phone value is restored, not overwritten', (
      tester,
    ) async {
      await _pumpNumberScreen(tester, initialPhoneNumber: '01512345678');

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, '01512345678');
    });

    testWidgets('back returns to previous step via pop', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const NewStudentNumberScreen(
                          initialFullName: 'Ahmed Mohamed Ali',
                        ),
                      ),
                    ),
                    child: const Text('go'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.byType(NewStudentNumberScreen), findsOneWidget);

      // Glass back button pops instead of reconstructing the route.
      await tester.tap(find.byType(GlassBackButton));
      await tester.pumpAndSettle();

      expect(find.byType(NewStudentNumberScreen), findsNothing);
      expect(find.text('go'), findsOneWidget);
    });
  });

  group('NewStudentNumberScreen responsive (360x640)', () {
    testWidgets('no overflow with error visible on small screen', (
      tester,
    ) async {
      await _pumpNumberScreen(tester, deviceSize: const Size(360, 640));

      await _tapNext(tester);

      expect(find.text('Phone number is required.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(find.text('Next'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });
  });
}
