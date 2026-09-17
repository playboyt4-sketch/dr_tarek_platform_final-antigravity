import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Password visibility toggle (Eye / Eye off) per the approved Figma
/// Dev Mode spec: `assets/images/Eye.svg` and `assets/images/Eye off.svg`
/// rendered at 30 x 30 inside a 40 x 40 hit-area. Presentation state
/// lives in the parent.
class PasswordVisibilityToggle extends StatelessWidget {
  final bool visible;
  final VoidCallback onToggle;

  const PasswordVisibilityToggle({
    super.key,
    required this.visible,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton(
        onPressed: onToggle,
        icon: SvgPicture.asset(
          visible ? 'assets/images/Eye off.svg' : 'assets/images/Eye.svg',
          width: 30,
          height: 30,
          semanticsLabel: visible ? 'Hide password' : 'Show password',
        ),
        iconSize: 30,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        tooltip: visible ? 'Hide password' : 'Show password',
      ),
    );
  }
}
