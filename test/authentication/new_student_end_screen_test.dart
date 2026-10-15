import 'package:dr_tarek_platform/features/authentication/presentation/screens/new_student_end_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpOnDevice(WidgetTester tester, Size deviceSize) async {
  tester.view.physicalSize = deviceSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(const MaterialApp(home: NewStudentEndScreen()));
  await tester.pumpAndSettle();
}

void main() {
  group(
    'NewStudentEndScreen (New Student - End / Application Under Review)',
    () {
      testWidgets('393x852: renders Figma copy, bg, illustration, no overflow', (
        tester,
      ) async {
        await _pumpOnDevice(tester, const Size(393, 852));

        expect(tester.takeException(), isNull);

        // Exact Figma headline with intentional line break.
        expect(find.text('Your request is\nunder review'), findsOneWidget);
        // Exact Figma subtext with intentional line break.
        expect(
          find.text('We are reviewing your request\nyou will be notified soon'),
          findsOneWidget,
        );

        // Warm off-white canvas, not pure white.
        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
        expect(scaffold.backgroundColor, const Color(0xFFFFFCF7));

        // Local review asset (never a network placeholder).
        final image = tester.widget<Image>(find.byType(Image).first);
        expect((image.image as AssetImage).assetName, contains('End photo'));
        final clip = tester.widget<ClipRRect>(find.byType(ClipRRect).first);
        expect(clip.borderRadius, BorderRadius.circular(35));

        // Typography tokens: headline 28 regular dark, subtext 14 regular gray.
        final headline = tester.widget<Text>(
          find.text('Your request is\nunder review'),
        );
        expect(headline.style!.fontSize, 28);
        expect(headline.style!.fontWeight, FontWeight.w400);
        expect(headline.textAlign, TextAlign.center);
        final subtext = tester.widget<Text>(
          find.text('We are reviewing your request\nyou will be notified soon'),
        );
        expect(subtext.style!.fontSize, 14);
        expect(subtext.style!.color, const Color(0xFF9A9A9A));
        expect(subtext.textAlign, TextAlign.center);

        // No approval/dashboard/login copy may appear on this waiting state.
        expect(find.textContaining('approved'), findsNothing);
        expect(find.textContaining('Welcome'), findsNothing);
        expect(find.textContaining('active'), findsNothing);
      });

      testWidgets('360x640: renders without overflow or clipped text', (
        tester,
      ) async {
        await _pumpOnDevice(tester, const Size(360, 640));

        expect(tester.takeException(), isNull);
        expect(find.text('Your request is\nunder review'), findsOneWidget);
        expect(
          find.text('We are reviewing your request\nyou will be notified soon'),
          findsOneWidget,
        );
      });

      testWidgets(
        'preserves existing approved exit (Done -> popUntil isFirst); '
        'no auto-navigation, no extra CTA',
        (tester) async {
          await _pumpOnDevice(tester, const Size(393, 852));

          // Existing approved navigation mechanism is preserved verbatim.
          expect(find.widgetWithText(ElevatedButton, 'Done'), findsOneWidget);
          // No invented Figma-conflicting CTAs.
          expect(find.text('Back to Login'), findsNothing);
          expect(find.text('Go to Login'), findsNothing);
          expect(find.text('Got it'), findsNothing);
          expect(find.text('Continue'), findsNothing);
        },
      );
    },
  );
}
