import 'package:dr_tarek_platform/core/widgets/glass_back_button.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/providers/registration_form_provider.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/screens/new_student_name_screen.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/screens/new_student_number_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Widget tests for the Full Name screen (08 Development Standards,
// Section 7: "Widget tests are required for any screen containing a form").

Future<ProviderContainer> pumpNameScreen(
  WidgetTester tester, {
  String? initialFullName,
}) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: NewStudentNameScreen(initialFullName: initialFullName),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('NewStudentNameScreen form rendering', () {
    testWidgets('renders headline, field, and Next on #FFFCF7', (tester) async {
      await pumpNameScreen(tester);

      expect(find.text("What's your name?"), findsOneWidget);
      expect(find.text('Full Name'), findsOneWidget);
      expect(find.text('Enter your full name'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, const Color(0xFFFFFCF7));
      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.byType(Form), findsOneWidget);
    });

    testWidgets('uses a native left-aligned floating label', (tester) async {
      await pumpNameScreen(tester);

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
      expect(inner.decoration?.labelText, 'Full Name');
      expect(inner.decoration?.hintText, 'Enter your full name');
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
      // Figma raw export: BOTH 'Full Name' and 'Enter your full name' are
      // fontSize 20 — reproduced as the shared bodyRegular size for both,
      // in Figma's #9A9A9A gray, LEFT-aligned (reference screenshots show
      // both flush-left, NOT centered).
      final labelSize = inner.decoration?.labelStyle?.fontSize;
      final hintSize = inner.decoration?.hintStyle?.fontSize;
      expect(labelSize, isNotNull);
      expect(hintSize, isNotNull);
      expect(labelSize, moreOrLessEquals(hintSize!));
      expect(inner.decoration?.labelStyle?.color, const Color(0xFF9A9A9A));
      expect(inner.decoration?.hintStyle?.color, const Color(0xFF9A9A9A));
    });

    testWidgets('floating label and hint never overlap', (tester) async {
      await pumpNameScreen(tester);

      // The floated label sits on the top border; the hint stays centered
      // in the input area — their vertical centers must remain distinct.
      expect(find.text('Full Name'), findsOneWidget);
      expect(find.text('Enter your full name'), findsOneWidget);
      final labelCenter = tester.getCenter(find.text('Full Name'));
      final hintCenter = tester.getCenter(find.text('Enter your full name'));
      expect(
        labelCenter.dy,
        lessThan(hintCenter.dy),
        reason: 'floating label must sit above the hint, not on top of it',
      );
    });

    testWidgets('label hugs the box left edge; box resolves to 69px', (
      tester,
    ) async {
      await pumpNameScreen(tester);

      // Left-aligned per Figma: measured inset is 22.0 (18px
      // contentPadding + 4px Material notch gap) — decisively not centered,
      // where the inset would exceed 100px on this surface.
      final boxLeft = tester.getTopLeft(find.byType(TextFormField)).dx;
      final labelLeft = tester.getTopLeft(find.text('Full Name')).dx;
      final inset = labelLeft - boxLeft;
      expect(inset, greaterThanOrEqualTo(0.0));
      expect(inset, lessThanOrEqualTo(24.0));
      // Figma's 69px bordered-container height, resolved intrinsically via
      // contentPadding (no fixed SizedBox, so validation-error states can
      // still grow the box instead of overflowing it).
      expect(
        tester.getSize(find.byType(TextFormField)).height,
        moreOrLessEquals(69.0, epsilon: 4.0),
      );
    });

    testWidgets('field geometry at 393px width (flush with illustration)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpNameScreen(tester);

      // Welcome-style Stack: Figma x-coords reproduced exactly —
      // illustration AND field render x=12..381, flush together.
      final fieldLeft = tester.getTopLeft(find.byType(TextFormField)).dx;
      final fieldRight = tester.getBottomRight(find.byType(TextFormField)).dx;
      expect(fieldLeft, moreOrLessEquals(12.0));
      expect(fieldRight, moreOrLessEquals(381.0));
      // Illustration box is keyed directly (the back button is a SIBLING
      // Positioned on the page Stack now, not a child of the art box —
      // same as the Welcome screen).
      final art = find.byKey(const Key('nameIllustrationStack'));
      expect(tester.getTopLeft(art).dx, moreOrLessEquals(12.0));
      expect(tester.getBottomRight(art).dx, moreOrLessEquals(381.0));
      expect(tester.getTopLeft(art).dx, moreOrLessEquals(fieldLeft));
      expect(tester.getBottomRight(art).dx, moreOrLessEquals(fieldRight));
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

      await pumpNameScreen(tester);

      // Figma node 38:43: back button (24,64), illustration (12,50) —
      // offset (12,14), same sibling-Positioned pattern as Welcome.
      final art = find.byKey(const Key('nameIllustrationStack'));
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
      await pumpNameScreen(tester);

      // Default test surface is 800x600: shortest side 600 -> tablet
      // bucket, textScale clamps raw 800/393=2.03 to 1.2, so the Welcome-
      // style rs(369) field resolves to 369*1.2=442.8 (no 600px cap —
      // the fixed-canvas Stack scales via context.rs like Welcome).
      expect(
        tester.getSize(find.byType(TextFormField)).width,
        moreOrLessEquals(369.0 * 1.2, epsilon: 1.0),
      );
    });
  });

  group('NewStudentNameScreen validation', () {
    testWidgets('empty submit shows an error and does not navigate', (
      tester,
    ) async {
      final container = await pumpNameScreen(tester);

      // Proportional gaps + desktop-capped illustration can push the CTA
      // below the fold on short (600px-tall) test surfaces — scroll first.
      await tester.ensureVisible(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'), warnIfMissed: false);
      await tester.pump();

      expect(find.text('Full name is required.'), findsOneWidget);
      expect(find.byType(NewStudentNumberScreen), findsNothing);
      // Nothing was written into the draft on a failed submit.
      expect(container.read(registrationFormProvider).fullName, isEmpty);
    });

    testWidgets('whitespace-only submit shows an error', (tester) async {
      await pumpNameScreen(tester);

      await tester.enterText(find.byType(TextFormField), '   ');
      await tester.ensureVisible(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'), warnIfMissed: false);
      await tester.pump();

      expect(find.text('Full name is required.'), findsOneWidget);
      expect(find.byType(NewStudentNumberScreen), findsNothing);
    });

    testWidgets('valid input writes the draft and navigates forward', (
      tester,
    ) async {
      final container = await pumpNameScreen(tester);

      await tester.enterText(find.byType(TextFormField), 'Ahmed Mohamed Ali');
      await tester.ensureVisible(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(NewStudentNumberScreen), findsOneWidget);
      expect(
        container.read(registrationFormProvider).fullName,
        'Ahmed Mohamed Ali',
      );
      final next = tester.widget<NewStudentNumberScreen>(
        find.byType(NewStudentNumberScreen),
      );
      expect(next.initialFullName, 'Ahmed Mohamed Ali');
    });
  });

  group('NewStudentNameScreen navigation chrome', () {
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
                        builder: (_) => const NewStudentNameScreen(),
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
      expect(find.byType(NewStudentNameScreen), findsOneWidget);

      await tester.tap(find.byType(GlassBackButton));
      await tester.pumpAndSettle();

      expect(find.byType(NewStudentNameScreen), findsNothing);
      expect(find.text('go'), findsOneWidget);
    });
  });

  // Rebuild verification at the 393x852 reference viewport (task points
  // 8a-8d): numeric layout guards that fail on the broken iterations
  // (clipped illustration, floating back button, cramped title->field
  // stack, mismatched label/hint sizes).
  group('NewStudentNameScreen rebuild geometry @393x852', () {
    Future<void> pumpAtReferenceViewport(WidgetTester tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await pumpNameScreen(tester);
    }

    testWidgets('8(a) illustration is non-zero and keeps 369:344', (
      tester,
    ) async {
      await pumpAtReferenceViewport(tester);

      final art = find.byKey(const Key('nameIllustrationStack'));
      expect(art, findsOneWidget);
      final size = tester.getSize(art);
      // NOT zero/clipped: must resolve to roughly the full 369 design
      // width with a proportional height (~344 at 393px viewport).
      expect(size.width, moreOrLessEquals(369.0, epsilon: 1.0));
      expect(size.height, greaterThan(100.0));
      final aspect = size.width / size.height;
      const expected = 369.0 / 344.0;
      expect(
        aspect,
        moreOrLessEquals(expected, epsilon: 0.05),
        reason: 'illustration must preserve the 369:344 aspect ratio, '
            'not force an independent height that clips the art',
      );
      // BoxFit.cover (clean crop) — never BoxFit.fill (stretch).
      final image = tester.widget<Image>(
        find.descendant(of: art, matching: find.byType(Image)),
      );
      expect(image.fit, BoxFit.cover);
    });

    testWidgets('8(b) back button at Figma offset (12,14)', (
      tester,
    ) async {
      await pumpAtReferenceViewport(tester);

      final art = find.byKey(const Key('nameIllustrationStack'));
      final buttonTopLeft = tester.getTopLeft(find.byType(GlassBackButton));
      final artTopLeft = tester.getTopLeft(art);
      expect(
        buttonTopLeft.dx - artTopLeft.dx,
        moreOrLessEquals(12.0, epsilon: 1.0),
      );
      expect(
        buttonTopLeft.dy - artTopLeft.dy,
        moreOrLessEquals(14.0, epsilon: 1.0),
      );
    });

    testWidgets('8(c) Figma y-coords: title 426, field 608 @393x852', (
      tester,
    ) async {
      await pumpAtReferenceViewport(tester);

      // Welcome-style contract: exact Figma tops, not a padded-Column gap.
      // (Figma title frame 393x67 @y426 -> bottom 493; field top 608 ->
      // 115 frame-to-frame. The rendered Text is shorter than its 67px
      // frame, so text-bottom->field-top measures ~110.)
      final titleTop = tester.getTopLeft(find.byKey(const Key('nameTitle'))).dy;
      final fieldTop =
          tester.getTopLeft(find.byKey(const Key('nameField'))).dy;
      expect(titleTop, moreOrLessEquals(426.0, epsilon: 3.0));
      expect(fieldTop, moreOrLessEquals(608.0, epsilon: 2.0));
      final gap =
          fieldTop - tester.getBottomRight(find.byKey(const Key('nameTitle'))).dy;
      expect(
        gap,
        greaterThanOrEqualTo(40.0),
        reason: 'field must sit well below the title, not cramped under it',
      );
      expect(gap, moreOrLessEquals(110.0, epsilon: 6.0));
    });

    testWidgets('scales with clamped rs/rsV @440x956 (Welcome-style)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(440, 956);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await pumpNameScreen(tester);

      // (a) Width scales past the old hard 369 cap:
      // rs(369) with widthScale 440/393 ~= 413.1.
      final fieldWidth = tester.getSize(find.byType(TextFormField)).width;
      expect(fieldWidth, moreOrLessEquals(440 * 369.0 / 393.0, epsilon: 1.5));
      expect(fieldWidth, greaterThan(400.0));

      // (b) Figma tops scale with rsV (heightScale 956/852): title ~478,
      // field ~682. Text-bottom gap lands ~124 (frame-to-frame 115 scaled).
      final titleTop = tester.getTopLeft(find.byKey(const Key('nameTitle'))).dy;
      final fieldTop =
          tester.getTopLeft(find.byKey(const Key('nameField'))).dy;
      expect(titleTop, moreOrLessEquals(426 * 956 / 852, epsilon: 4.0));
      expect(fieldTop, moreOrLessEquals(608 * 956 / 852, epsilon: 4.0));
      final gap =
          fieldTop - tester.getBottomRight(find.byKey(const Key('nameTitle'))).dy;
      expect(gap, moreOrLessEquals(956 * 115.0 / 852.0, epsilon: 7.0));
      expect(gap, greaterThan(100.0));
    });

    testWidgets('8(d) label and hint share size, both left-aligned', (
      tester,
    ) async {
      await pumpAtReferenceViewport(tester);

      final inner = tester.widget<TextField>(
        find.descendant(
          of: find.byType(TextFormField),
          matching: find.byType(TextField),
        ),
      );
      expect(inner.decoration?.labelStyle?.fontSize, isNotNull);
      expect(
        inner.decoration?.labelStyle?.fontSize,
        moreOrLessEquals(inner.decoration!.hintStyle!.fontSize!),
      );
      expect(
        inner.decoration?.floatingLabelAlignment,
        FloatingLabelAlignment.start,
      );
      expect(inner.textAlign, TextAlign.start);
    });
  });
}
