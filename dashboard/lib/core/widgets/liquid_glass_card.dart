import 'package:flutter/material.dart';

/// Reproduction of the Figma `Liquid Glass - Notification - Light` surface
/// used by the dashboard login card, verified against the live frame
/// (452:397): corner radius 20, opaque white fill, a soft ambient drop
/// shadow (black @25%, offset 0/8, blur 48) and three hairline #DBDBDB
/// shadows tracing the card edge (spread 0.5 / -0.75 at x offsets).
///
/// The Figma `GLASS` backdrop effect and its two inset #282828 hairlines
/// sit behind an opaque white fill, so they are imperceptible and are
/// intentionally omitted here.
class LiquidGlassCard extends StatelessWidget {
  final double width;
  final double? height;
  final Widget child;

  const LiquidGlassCard({
    super.key,
    required this.width,
    this.height,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(20)),
        color: Colors.white,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(0x40000000),
            offset: Offset(0, 8),
            blurRadius: 48,
          ),
          BoxShadow(
            color: Color(0xFFDBDBDB),
            offset: Offset.zero,
            spreadRadius: 0.5,
          ),
          BoxShadow(
            color: Color(0xFFDBDBDB),
            offset: Offset(-1.25, 0),
            spreadRadius: -0.75,
          ),
          BoxShadow(
            color: Color(0xFFDBDBDB),
            offset: Offset(1.25, 0),
            spreadRadius: -0.75,
          ),
        ],
      ),
      child: child,
    );
  }
}
