import 'package:dr_tarek_platform/core/widgets/glass_back_button.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/providers/registration_form_provider.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/screens/new_student_number_screen.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/screens/new_student_photo_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Widget tests for the Phone Number screen (08 Development Standards,
// Section 7: "Widget tests are required for any screen containing a form").

Future<ProviderContainer> pumpNumberScreen(
  WidgetTester tester, {
  String? initialFullName,
  String? initialPhoneNumber,
}) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: NewStudentNumberScreen(
          initialFullName: initialFullName,
          initialPhoneNumber: initialPhoneNumber,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('NewStudentNumberScreen form rendering', () {
    testWidgets('renders headline, field, glass back, and Next', (
      tester,
    ) async {
      await pumpNumberScreen(tester);

      expect(find.text('Your phone number?'), findsOneWidget);
      expect(find.text('phone number'), findsOneWidget);
      expect(find.text('Enter your phone number'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, const Color(0xFFFFFCF7));
      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.byType(Form), findsOneWidget);
      expect(find.byType(GlassBackButton), findsOneWidget);
    });

    testWidgets('uses a native left-aligned floating label', (tester) async {
      await pumpNumberScreen(tester);

      // Figma: the label straddles the top border (notch drawn by the
      // OutlineInputBorder itself — no manual background patch) and sits
      // flush-left, as does the hint. (TextFormField forwards its
      // InputDecoration to the inner TextField, which is where the getter
      // lives.)
      final inner = tester.widget<TextField>(
        find.descendant(
          of: find.byType(TextFormField),
          matching: find.byType(TextField),
        ),
      );
      expect(inner.decoration?.labelText, 'phone number');
      expect(inner.decoration?.hintText, 'Enter your phone number');
      expect(
        inner.decoration?.floatingLabelBehavior,
        FloatingLabelBehavior.always,
      );
      expect(
        inner.decoration?.floatingLabelAlignment,
        FloatingLabelAlignment.start,
      );
      // textAlign is forwarded to the inner TextField (same pattern as
      // the decoration getter above).
      expect(inner.textAlign, TextAlign.start);
      // Figma: the captionSmall label is genuinely smaller than the
      // bodyRegular hint; both share #9A9A9A.
      final labelSize = inner.decoration?.labelStyle?.fontSize;
      final hintSize = inner.decoration?.hintStyle?.fontSize;
      expect(labelSize, isNotNull);
      expect(hintSize, isNotNull);
      expect(labelSize!, lessThan(hintSize!));
      expect(inner.decoration?.labelStyle?.color, const Color(0xFF9A9A9A));
      expect(inner.decoration?.hintStyle?.color, const Color(0xFF9A9A9A));
    });

    testWidgets('label hugs the box left edge; box resolves to 69px', (
      tester,
    ) async {
      await pumpNumberScreen(tester);

      // Left-aligned per Figma: measured inset is 22.0 (18px
      // contentPadding + 4px Material notch gap) — decisively not centered,
      // where the inset would exceed 100px on this surface.
      final boxLeft = tester.getTopLeft(find.byType(TextFormField)).dx;
      final labelLeft = tester.getTopLeft(find.text('phone number')).dx;
      final inset = labelLeft - boxLeft;
      expect(inset, greaterThanOrEqualTo(0.0));
      expect(inset, lessThanOrEqualTo(24.0));
      // Figma's 69px bordered-container height, resolved intrinsically via
      // contentPadding (no fixed SizedBox, so validation-error states can
      // still grow the box instead of overflowing it).
      expect(
        tester.getSize(find.byType(TextFormField)).height,
        moreOrLessEquals(69.0),
      );
    });

    testWidgets('floating label and hint never overlap', (tester) async {
      await pumpNumberScreen(tester);

      // The floated label sits on the top border; the hint stays centered
      // in the input area — their vertical centers must remain distinct.
      expect(find.text('phone number'), findsOneWidget);
      expect(find.text('Enter your phone number'), findsOneWidget);
      final labelCenter = tester.getCenter(find.text('phone number'));
      final hintCenter = tester.getCenter(find.text('Enter your phone number'));
      expect(
        labelCenter.dy,
        lessThan(hintCenter.dy),
        reason: 'floating label must sit above the hint, not on top of it',
      );
    });

    testWidgets('field sits at x=24..369 at 393px width (inset field)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpNumberScreen(tester);

      // Welcome-style Stack: Figma x-coords reproduced exactly —
      // field container at left:24, width:345 (x=24..369), inset 12px
      // more than the illustration on each side (NOT flush like the
      // Name screen's field — genuine per-frame difference).
      final fieldLeft = tester.getTopLeft(find.byType(TextFormField)).dx;
      final fieldRight = tester.getBottomRight(find.byType(TextFormField)).dx;
      expect(fieldLeft, moreOrLessEquals(24.0));
      expect(fieldRight, moreOrLessEquals(369.0));
      // Illustration box is keyed directly (the back button is a SIBLING
      // Positioned on the page Stack now, not a child of the art box —
      // same as the Welcome screen).
      final art = find.byKey(const Key('numberIllustrationStack'));
      expect(art, findsOneWidget);
      final artLeft = tester.getTopLeft(art).dx;
      final artRight = tester.getBottomRight(art).dx;
      expect(artLeft, moreOrLessEquals(12.0));
      expect(artRight, moreOrLessEquals(381.0));
      expect(fieldLeft - artLeft, moreOrLessEquals(12.0));
      expect(artRight - fieldRight, moreOrLessEquals(12.0));
      // Figma y-coords: illustration top 50, field top 608.
      expect(tester.getTopLeft(art).dy, moreOrLessEquals(50.0, epsilon: 1.0));
      expect(
        tester.getTopLeft(find.byType(TextFormField)).dy,
        moreOrLessEquals(608.0, epsilon: 2.0),
      );
    });

    testWidgets('back button sits at Figma (24,64) over the illustration', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpNumberScreen(tester);

      // Figma "New Student - number": back button (24,64), illustration
      // (12,50) — offset (12,14), same sibling-Positioned pattern as
      // Welcome/Name (NOT nested 16,16 inside the art box).
      final art = find.byKey(const Key('numberIllustrationStack'));
      final buttonTopLeft = tester.getTopLeft(find.byType(GlassBackButton));
      final artTopLeft = tester.getTopLeft(art);
      expect(buttonTopLeft.dx - artTopLeft.dx, moreOrLessEquals(12.0));
      expect(buttonTopLeft.dy - artTopLeft.dy, moreOrLessEquals(14.0));
      // Absolute page coords too.
      expect(buttonTopLeft.dx, moreOrLessEquals(24.0));
      expect(buttonTopLeft.dy, moreOrLessEquals(64.0, epsilon: 1.0));
    });

    testWidgets('field scales with the clamped responsive scale', (
      tester,
    ) async {
      await pumpNumberScreen(tester);

      // Default test surface is 800x600: shortest side 600 -> tablet
      // bucket, textScale clamps raw 800/393=2.03 to 1.2, so the Welcome-
      // style rs(345) field resolves to 345*1.2=414.0 (no 600px cap —
      // the fixed-canvas Stack scales via context.rs like Welcome).
      expect(
        tester.getSize(find.byType(TextFormField)).width,
        moreOrLessEquals(345.0 * 1.2, epsilon: 1.0),
      );
    });

    testWidgets('scales with clamped rs/rsV @440x956 (Welcome-style)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(440, 956);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await pumpNumberScreen(tester);

      // (a) Width scales via rs: rs(345) with widthScale 440/393 ~= 386.3.
      final fieldWidth = tester.getSize(find.byType(TextFormField)).width;
      expect(fieldWidth, moreOrLessEquals(440 * 345.0 / 393.0, epsilon: 1.5));
      expect(fieldWidth, greaterThan(370.0));
      // Illustration scales the same way: rs(369) ~= 413.1.
      final art = find.byKey(const Key('numberIllustrationStack'));
      expect(
        tester.getSize(art).width,
        moreOrLessEquals(440 * 369.0 / 393.0, epsilon: 1.5),
      );

      // (b) Figma tops scale with rsV (heightScale 956/852): title ~490,
      // field ~682.
      final titleTop = tester.getTopLeft(find.byKey(const Key('numberTitle'))).dy;
      final fieldTop =
          tester.getTopLeft(find.byKey(const Key('numberField'))).dy;
      expect(titleTop, moreOrLessEquals(437 * 956 / 852, epsilon: 4.0));
      expect(fieldTop, moreOrLessEquals(608 * 956 / 852, epsilon: 4.0));
      final gap =
          fieldTop - tester.getBottomRight(find.byKey(const Key('numberTitle'))).dy;
      expect(gap, greaterThan(80.0));
    });

    testWidgets('Figma y-coords: title 437, field 608 @393x852', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await pumpNumberScreen(tester);

      // Welcome-style contract: exact Figma tops, not a padded-Column gap.
      final titleTop = tester.getTopLeft(find.byKey(const Key('numberTitle'))).dy;
      final fieldTop =
          tester.getTopLeft(find.byKey(const Key('numberField'))).dy;
      expect(titleTop, moreOrLessEquals(437.0, epsilon: 3.0));
      expect(fieldTop, moreOrLessEquals(608.0, epsilon: 2.0));
      final gap =
          fieldTop - tester.getBottomRight(find.byKey(const Key('numberTitle'))).dy;
      expect(
        gap,
        greaterThanOrEqualTo(40.0),
        reason: 'field must sit well below the title, not cramped under it',
      );
    });

    testWidgets('phone field uses the phone keyboard', (tester) async {
      await pumpNumberScreen(tester);

      // TextFormField builds an inner TextField; the keyboard type lives
      // on that inner widget.
      final inner = find.descendant(
        of: find.byType(TextFormField),
        matching: find.byType(TextField),
      );
      expect(inner, findsOneWidget);
      expect(tester.widget<TextField>(inner).keyboardType, TextInputType.phone);
    });

    testWidgets('seeds the field from a previously entered value', (
      tester,
    ) async {
      await pumpNumberScreen(tester, initialPhoneNumber: '01001234567');

      final field = tester.widget<TextFormField>(find.byType(TextFormField));
      expect(field.controller!.text, '01001234567');
    });
  });

  group('NewStudentNumberScreen validation', () {
    testWidgets('empty submit shows an error and does not navigate', (
      tester,
    ) async {
      final container = await pumpNumberScreen(tester);

      // Fixed 393x852 canvas: the CTA at y754 sits below the fold on
      // short (600px-tall) test surfaces — scroll first (same as Name).
      await tester.ensureVisible(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'), warnIfMissed: false);
      await tester.pump();

      expect(find.text('Phone number is required.'), findsOneWidget);
      expect(find.byType(NewStudentPhotoScreen), findsNothing);
      // Nothing was written into the draft on a failed submit.
      expect(container.read(registrationFormProvider).phoneNumber, isEmpty);
    });

    testWidgets('non-Egyptian input shows an error and blocks navigation', (
      tester,
    ) async {
      final container = await pumpNumberScreen(tester);

      await tester.enterText(find.byType(TextFormField), '12345');
      await tester.ensureVisible(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'), warnIfMissed: false);
      await tester.pump();

      expect(
        find.text('Enter a valid Egyptian mobile number (e.g. 01001234567).'),
        findsOneWidget,
      );
      expect(find.byType(NewStudentPhotoScreen), findsNothing);
      expect(container.read(registrationFormProvider).phoneNumber, isEmpty);
    });

    testWidgets('wrong-prefix input shows an error and blocks navigation', (
      tester,
    ) async {
      await pumpNumberScreen(tester);

      // 11 digits but not an Egyptian mobile prefix (010/011/012/015).
      await tester.enterText(find.byType(TextFormField), '01901234567');
      await tester.ensureVisible(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'), warnIfMissed: false);
      await tester.pump();

      expect(
        find.text('Enter a valid Egyptian mobile number (e.g. 01001234567).'),
        findsOneWidget,
      );
      expect(find.byType(NewStudentPhotoScreen), findsNothing);
    });

    testWidgets('valid input writes the draft and navigates forward', (
      tester,
    ) async {
      final container = await pumpNumberScreen(
        tester,
        initialFullName: 'Ahmed Mohamed Ali',
      );

      await tester.enterText(find.byType(TextFormField), '01001234567');
      await tester.ensureVisible(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(NewStudentPhotoScreen), findsOneWidget);
      expect(
        container.read(registrationFormProvider).phoneNumber,
        '01001234567',
      );
      final next = tester.widget<NewStudentPhotoScreen>(
        find.byType(NewStudentPhotoScreen),
      );
      expect(next.initialPhoneNumber, '01001234567');
      expect(next.initialFullName, 'Ahmed Mohamed Ali');
    });
  });

  group('NewStudentNumberScreen has no wizard chrome (regression guard)', () {
    testWidgets('no step counter, progress bar, or Previous button', (
      tester,
    ) async {
      await pumpNumberScreen(tester);

      // The wrong wizard pattern (StudentRegistrationWizard) must never
      // reappear on this Figma-approved screen.
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.text('السابق'), findsNothing);
      expect(find.text('ما هو رقم هاتفك؟'), findsNothing);
      expect(find.textContaining('خطوة'), findsNothing);
      expect(find.textContaining('من 5'), findsNothing);
    });

    testWidgets('glass back button pops instead of rebuilding', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const NewStudentNumberScreen(),
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

      await tester.tap(find.byType(GlassBackButton));
      await tester.pumpAndSettle();

      expect(find.byType(NewStudentNumberScreen), findsNothing);
      expect(find.text('go'), findsOneWidget);
    });
  });
}
