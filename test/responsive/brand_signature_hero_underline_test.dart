import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dr_tarek_platform/features/authentication/presentation/screens/user_type_selection_screen.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/widgets/brand_signature_logo.dart';

/// Regression test for the yellow bar seen under the brand signature during
/// the Splash → User Type Selection Hero flight.
///
/// A Hero shuttle is re-parented into the app Overlay. There it no longer
/// sits under a Material/DefaultTextStyle, so a Text with no explicit
/// decoration merges with MaterialApp's fallback text style, which carries
/// a yellow double underline (`_errorTextStyle` in material/app.dart).
///
/// The brand signature token must explicitly opt out of decoration so the
/// flying logo stays clean at every frame. The logo itself must still travel
/// from the splash centre to the footer.
Future<void> _loadFonts() async {
  Future<void> load(String family, String asset) async {
    final loader = FontLoader(family)
      ..addFont(rootBundle.load(asset));
    await loader.load();
  }

  await load('Gardenia Summer', 'assets/fonts/Gardenia Summer.ttf');
  await load('Google Sans Flex', 'assets/fonts/GoogleSansFlex.ttf');
}

class _HeroFlightHarness extends StatefulWidget {
  const _HeroFlightHarness();

  @override
  State<_HeroFlightHarness> createState() => _HeroFlightHarnessState();
}

class _HeroFlightHarnessState extends State<_HeroFlightHarness> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Mirrors AppRouter's User Type Selection page: 800ms easeOut fade,
      // with the logo Hero flying from the splash centre to the footer.
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 800),
          pageBuilder: (_, _, _) => const UserTypeSelectionScreen(),
          transitionsBuilder: (_, animation, _, child) => FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFFFFCF7),
      body: Center(
        child: Hero(
          tag: 'brand_logo_signature',
          child: BrandSignatureLogo(designPx: 128),
        ),
      ),
    );
  }
}

Finder _signatureTexts() => find.byWidgetPredicate(
      (widget) =>
          widget is RichText &&
          widget.text.toPlainText() == 'Tarek el araby',
    );

void main() {
  setUpAll(_loadFonts);

  testWidgets(
      'signature has no inherited underline during the Hero flight and still moves',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: _HeroFlightHarness()));
    // First frame shows the centred splash logo and schedules the push.
    await tester.pump();
    final initial = tester.getRect(_signatureTexts().first);

    // Mid-flight: the shuttle is inside the Overlay.
    await tester.pump(const Duration(milliseconds: 200));
    final midRects = <Rect>[
      for (var i = 0; i < _signatureTexts().evaluate().length; i++)
        tester.getRect(_signatureTexts().at(i)),
    ];
    final midStyles = <TextStyle?>[
      for (final element in _signatureTexts().evaluate())
        (element.widget as RichText).text.style,
    ];

    expect(midStyles, isNotEmpty);
    for (final style in midStyles) {
      expect(
        style?.decoration,
        isNot(TextDecoration.underline),
        reason: 'Hero shuttle inherited a text underline',
      );
    }

    // The logo is still animating downward (not frozen at either endpoint).
    final midTop = midRects.map((r) => r.top).reduce((a, b) => a > b ? a : b);
    expect(midTop, greaterThan(initial.top));

    // End of the flight: the logo lands at the User Type Selection footer.
    await tester.pump(const Duration(milliseconds: 600));
    final finalRects = <Rect>[
      for (var i = 0; i < _signatureTexts().evaluate().length; i++)
        tester.getRect(_signatureTexts().at(i)),
    ];
    final finalTop =
        finalRects.map((r) => r.top).reduce((a, b) => a > b ? a : b);
    expect(finalTop, greaterThan(midTop));
    expect(tester.takeException(), isNull);
  });
}
