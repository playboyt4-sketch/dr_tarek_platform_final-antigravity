import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_semantic_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/primary_button.dart';
import '../widgets/brand_signature_logo.dart';
import 'new_student_name_screen.dart';

// ---------------------------------------------------------------------------
// Figma node 35:18 "New Student - Welcome", reference frame 393x852.
//
// IMPORTANT: the frame's hero Y = 50 *includes* the 50px status-bar band
// (the exported frame's chrome reserve). The live composition must therefore
// start at the top of the SafeArea with offset 0 — never +50 again.
//
// Verified against the exported frame by pixel measurement:
//   hero            y  50..444  (x 12..380, 369x395)
//   title ink       y 475..532  (two 36px lines)
//   signature ink   y 572..663  (92px tall, 269 wide, centered)
//   CTA             y 754..809  (x 24..368, 345x56, pill, #1D4ED8)
// ---------------------------------------------------------------------------
abstract final class _WelcomeDesign {
  static const canvasWidth = 393.0;

  // Hero: 369x395 at (12, 50) in the frame, radius 35.
  static const heroWidth = 369.0;
  static const heroHeight = 395.0;
  static const heroMargin = 12.0;
  static const heroCornerRadius = 35.0;
  static const heroAsset = 'assets/images/New Student - Welcome photo.png';

  // Exact Figma crop alignment (cropTransform-derived, not a generic cover).
  static const heroAlignX = -0.0034;
  static const heroAlignY = -0.8009;

  // Floating back button: 44x44 at frame (24, 54) -> (12, 4) inside the hero.
  static const backButtonOffsetX = 12.0;
  static const backButtonOffsetY = 4.0;
  static const backButtonSize = 44.0;
  static const backAsset = 'assets/images/back.svg';

  // Headline: title/large (28/36). The break is hard, as in the frame and in
  // the design reference code — line 1 "Welcome to our community", line 2
  // "with" — so font metrics can never collapse it into a single line.
  static const title = 'Welcome to our community\nwith';
  static const gapHeroTitle = 24.0;
  static const gapTitleSignature = 30.0;

  // Signature: logo/signature component, 95px slot holding 128px artwork
  // (the exported ink is 92px tall, i.e. it fills the slot).
  static const signatureSlot = 95.0;
  static const signatureSize = 128.0;
  static const signatureRed = Color(0xFFDC2626);

  // The Gardenia line box is asymmetric around its ink: at 128px the ink
  // centre sits 7.5px below the line-box centre (measured from the real font
  // by rasterising the screen). Figma centres the *ink* in the 95px slot, so
  // the artwork is lifted by the same amount. Scales with the font size.
  static const signatureInkOffset = 7.5;

  // CTA: button/primary Solid, 345x56, radius/full (28 at this height),
  // #1D4ED8. Radius and fill come from the canonical PrimaryButton.
  static const ctaWidth = 345.0;
  static const ctaHeight = 56.0;
  static const ctaGutter = 24.0;
  static const ctaLabel = 'Get started';

  // Distance from the safe-area bottom edge to the CTA.
  // Frame bottom 852 - CTA bottom 810 = 42; minus the 34px design bottom
  // inset = 8px that must remain inside the live safe area.
  static const bottomOffset = 8.0;

  // Compact fallback for short viewports: tighten non-essential gaps before
  // the illustration is allowed to shrink.
  static const compactGap = 12.0;
  static const compactTrigger = 0.7;
  static const minHeroHeight = 56.0;
}

// ---------------------------------------------------------------------------
class NewStudentWelcomeScreen extends StatelessWidget {
  const NewStudentWelcomeScreen({super.key});

  void _onGetStartedPressed(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const NewStudentNameScreen(),
      ),
    );
  }

  void _onBackPressed(BuildContext context) {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // Horizontal design scale (identical to Figma at the 393 reference).
    final scale = context.textScale;
    final semantic = AppSemanticColors.of(context);
    final titleStyle =
        AppTypography.titleLarge(context, color: semantic.textPrimary);

    return Scaffold(
      backgroundColor: semantic.canvas,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableHeight = constraints.maxHeight;
            final viewportWidth = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : _WelcomeDesign.canvasWidth * scale;

            // Bounded band: full width on phones, centered on large screens.
            final contentWidth = math.min(
              viewportWidth,
              _WelcomeDesign.canvasWidth * scale,
            );
            final titleHeight =
                _measureTitleHeight(context, titleStyle, contentWidth);

            final layout = _WelcomeLayout.resolve(
              availableHeight: availableHeight,
              contentWidth: contentWidth,
              titleHeight: titleHeight,
              scale: scale,
            );

            return SingleChildScrollView(
              // The child is constrained to exactly the available height, so
              // this never scrolls: it only guarantees that a regression which
              // makes the content taller surfaces as maxScrollExtent > 0
              // instead of silently clipping.
              physics: const ClampingScrollPhysics(),
              child: SizedBox(
                height: availableHeight,
                child: Center(
                  child: SizedBox(
                    width: contentWidth,
                    child: Directionality(
                      // Force LTR - this is an English-only screen.
                      textDirection: TextDirection.ltr,
                      child: _WelcomeBody(
                        layout: layout,
                        titleStyle: titleStyle,
                        scale: scale,
                        onBack: () => _onBackPressed(context),
                        onGetStarted: () => _onGetStartedPressed(context),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Measures the wrapped headline with the real style and accessibility
  /// text scaler so the column can reserve its exact height.
  static double _measureTitleHeight(
    BuildContext context,
    TextStyle style,
    double width,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: _WelcomeDesign.title, style: style),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    )..layout(maxWidth: width);
    final height = painter.height;
    painter.dispose();
    return height;
  }
}

// ---------------------------------------------------------------------------
/// Resolved geometry for one viewport. All vertical values are logical px
/// inside the SafeArea.
class _WelcomeLayout {
  const _WelcomeLayout({
    required this.heroWidth,
    required this.heroHeight,
    required this.gapHeroTitle,
    required this.gapTitleSignature,
    required this.signatureSlot,
    required this.ctaWidth,
  });

  final double heroWidth;
  final double heroHeight;
  final double gapHeroTitle;
  final double gapTitleSignature;
  final double signatureSlot;
  final double ctaWidth;

  static _WelcomeLayout resolve({
    required double availableHeight,
    required double contentWidth,
    required double titleHeight,
    required double scale,
  }) {
    final signatureSlot = _WelcomeDesign.signatureSlot * scale;
    final designHeroHeight = _WelcomeDesign.heroHeight * scale;
    final maxHeroWidth = math.max(
      0.0,
      contentWidth - 2 * _WelcomeDesign.heroMargin * scale,
    );

    double gapHeroTitle = _WelcomeDesign.gapHeroTitle * scale;
    double gapTitleSignature = _WelcomeDesign.gapTitleSignature * scale;

    double heroSpace() =>
        availableHeight -
        _WelcomeDesign.bottomOffset -
        _WelcomeDesign.ctaHeight -
        gapHeroTitle -
        titleHeight -
        gapTitleSignature -
        signatureSlot;

    // Short viewport: remove non-essential vertical gaps first.
    if (heroSpace() < designHeroHeight * _WelcomeDesign.compactTrigger) {
      gapHeroTitle = _WelcomeDesign.compactGap * scale;
      gapTitleSignature = _WelcomeDesign.compactGap * scale;
    }

    final heroSpaceNow = heroSpace();
    final heroAspect = _WelcomeDesign.heroWidth / _WelcomeDesign.heroHeight;

    // Illustration is the flexible element: it keeps its aspect ratio and
    // gives up height before anything else can be clipped.
    final heroWidth = math.max(
      0.0,
      math.min(maxHeroWidth, heroSpaceNow * heroAspect),
    );
    final heroHeight = heroWidth / heroAspect;

    if (heroHeight < _WelcomeDesign.minHeroHeight) {
      final required = _WelcomeDesign.bottomOffset +
          _WelcomeDesign.ctaHeight +
          gapHeroTitle +
          titleHeight +
          gapTitleSignature +
          signatureSlot +
          _WelcomeDesign.minHeroHeight;
      throw FlutterError.fromParts([
        ErrorSummary(
          'NewStudentWelcomeScreen cannot fit the available viewport.',
        ),
        ErrorDescription(
          'Available height ${availableHeight.toStringAsFixed(1)} logical px '
          'leaves ${heroSpaceNow.toStringAsFixed(1)} logical px for the hero, '
          'below the ${_WelcomeDesign.minHeroHeight.toStringAsFixed(0)} px '
          'minimum. Title height is ${titleHeight.toStringAsFixed(1)} px at '
          'this width/text scale.',
        ),
        ErrorHint(
          'The Welcome composition needs at least '
          '${required.toStringAsFixed(1)} logical px of height at this text '
          'scale. Provide a taller viewport or reduce the text scale — '
          'content is never clipped or scrolled to hide this.',
        ),
      ]);
    }

    final ctaWidth = math.min(
      _WelcomeDesign.ctaWidth * scale,
      math.max(0.0, contentWidth - 2 * _WelcomeDesign.ctaGutter * scale),
    );

    return _WelcomeLayout(
      heroWidth: heroWidth,
      heroHeight: heroHeight,
      gapHeroTitle: gapHeroTitle,
      gapTitleSignature: gapTitleSignature,
      signatureSlot: signatureSlot,
      ctaWidth: ctaWidth,
    );
  }
}

// ---------------------------------------------------------------------------
class _WelcomeBody extends StatelessWidget {
  const _WelcomeBody({
    required this.layout,
    required this.titleStyle,
    required this.scale,
    required this.onBack,
    required this.onGetStarted,
  });

  final _WelcomeLayout layout;
  final TextStyle titleStyle;
  final double scale;
  final VoidCallback onBack;
  final VoidCallback onGetStarted;

  @override
  Widget build(BuildContext context) {
    final semantic = AppSemanticColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Hero photo + floating back button. The photo keeps the Figma
        // 369:395 aspect at every size.
        SizedBox(
          height: layout.heroHeight,
          child: Center(
            child: SizedBox(
              width: layout.heroWidth,
              height: layout.heroHeight,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        context.rs(_WelcomeDesign.heroCornerRadius),
                      ),
                      child: Image.asset(
                        _WelcomeDesign.heroAsset,
                        fit: BoxFit.cover,
                        alignment: const Alignment(
                          _WelcomeDesign.heroAlignX,
                          _WelcomeDesign.heroAlignY,
                        ),
                        errorBuilder: (context, error, stackTrace) =>
                            Container(
                          color: semantic.surface,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            size: context.rs(48),
                            color: semantic.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: _WelcomeDesign.backButtonOffsetX * scale,
                    top: _WelcomeDesign.backButtonOffsetY * scale,
                    child: GestureDetector(
                      onTap: onBack,
                      behavior: HitTestBehavior.opaque,
                      child: SvgPicture.asset(
                        _WelcomeDesign.backAsset,
                        width: context.rs(_WelcomeDesign.backButtonSize),
                        height: context.rs(_WelcomeDesign.backButtonSize),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        SizedBox(height: layout.gapHeroTitle),

        SizedBox(
          width: double.infinity,
          child: Text(
            _WelcomeDesign.title,
            textAlign: TextAlign.center,
            style: titleStyle,
          ),
        ),

        SizedBox(height: layout.gapTitleSignature),

        // Signature slot stays 95 design-px tall. The shared widget is not
        // modified: it is given its natural 128px line box and centered, so
        // the ink (92px in Figma) is not downscaled by the 95px slot.
        SizedBox(
          height: layout.signatureSlot,
          child: OverflowBox(
            minHeight: 0,
            maxHeight: _WelcomeDesign.signatureSize * scale,
            alignment: Alignment.center,
            child: Transform.translate(
              offset: Offset(
                0,
                -_WelcomeDesign.signatureInkOffset * scale,
              ),
              child: const BrandSignatureLogo(
                designPx: _WelcomeDesign.signatureSize,
                color: _WelcomeDesign.signatureRed,
              ),
            ),
          ),
        ),

        // Flexible spacing absorbs every extra pixel of viewport height.
        const Spacer(),

        Center(
          child: SizedBox(
            width: layout.ctaWidth,
            height: _WelcomeDesign.ctaHeight,
            child: PrimaryButton(
              label: _WelcomeDesign.ctaLabel,
              onPressed: onGetStarted,
            ),
          ),
        ),

        const SizedBox(height: _WelcomeDesign.bottomOffset),
      ],
    );
  }
}
