import 'dart:ui';

import 'package:flutter/material.dart';

/// Liquid-glass login card matching the approved Figma Dev Mode frame
/// (`#login frame`, 1280 x 800 reference):
/// 480 x 452, radius 28, white @ 70% (Colors.white.withValues(alpha: 0.70)),
/// backdrop blur sigmaX/Y 20, 1.5 px inside stroke #E5E7EB, shadow
/// black 0x1E000000 (offset 0/12, blur 30).
///
/// [width]/[height] default to the Figma geometry. [height] may stay null
/// so validation messages can expand the card without clipping; the base
/// composition (exact inner gaps in the login screen) still sums to 452.
class LiquidGlassCard extends StatelessWidget {
  final double width;
  final double? height;
  final Widget child;

  const LiquidGlassCard({
    super.key,
    this.width = 480,
    this.height,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(28)),
            color: Colors.white.withValues(alpha: 0.70),
            border: const Border.fromBorderSide(
              BorderSide(
                color: Color(0xFFE5E7EB),
                width: 1.5,
                strokeAlign: BorderSide.strokeAlignInside,
              ),
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x1E000000),
                offset: Offset(0, 12),
                blurRadius: 30,
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
