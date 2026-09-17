import 'package:flutter/material.dart';

/// Interactive menu button (`the menu`) from the approved dashboard frames.
///
/// Geometry (both states share the 80 x 80 hit-area):
/// - container 80 x 80, fully transparent, no shadow, no border;
/// - two black (#000000) lines, 1 px thick, 80 px long, fully rounded
///   (radius 9999), drawn directly on the page background;
/// - list state: parallel lines with a 10 px gap — line 1 at Y 34,
///   line 2 at Y 45 (1 px thickness accounts for the 11 px origins);
/// - X state: both lines cross at the center (40, 40), one at -45° and
///   the other at +45°.
///
/// The transition is a smooth Smart-Animate-style morph
/// ([Curves.easeOut], 300 ms) driven by [AnimatedContainer] (vertical
/// slide) + [AnimatedRotation] (quarter-turn eighths).
///
/// The [InkWell] feedback is fully transparent so only the two black
/// lines are ever visible — exactly like the Figma frame.
class TheMenuButton extends StatelessWidget {
  /// `false` → list icon, `true` → X (close) icon.
  final bool isOpen;

  final VoidCallback? onPressed;

  /// Alias for [onPressed] so the unified shell can use
  /// `TheMenuButton(isOpen: isMenuOpen, onTap: toggleMenu)`.
  /// Effective callback is `onTap ?? onPressed`.
  final VoidCallback? onTap;

  /// Accessibility label. Defaults adapt to [isOpen].
  final String? semanticsLabel;

  const TheMenuButton({
    super.key,
    required this.isOpen,
    this.onPressed,
    this.onTap,
    this.semanticsLabel,
  });

  /// Effective tap handler (`onTap` wins over legacy `onPressed`).
  VoidCallback? get _effectiveOnTap => onTap ?? onPressed;

  @override
  Widget build(BuildContext context) {
    const duration = Duration(milliseconds: 300);
    const curve = Curves.easeOut;

    // List state origins; X state collapses both to the vertical center
    // (40 - 0.5 = 39.5) before rotating around each line's own center.
    final double top1 = isOpen ? 39.5 : 34;
    final double top2 = isOpen ? 39.5 : 45;
    final double turns1 = isOpen ? -0.125 : 0;
    final double turns2 = isOpen ? 0.125 : 0;

    return Semantics(
      label: semanticsLabel ?? (isOpen ? 'Close menu' : 'Open menu'),
      button: true,
      enabled: _effectiveOnTap != null,
      child: SizedBox(
        width: 80,
        height: 80,
        child: Material(
          color: Colors.transparent,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          child: InkWell(
            onTap: _effectiveOnTap,
            borderRadius: BorderRadius.circular(16),
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            focusColor: Colors.transparent,
            child: Stack(
              children: <Widget>[
                AnimatedContainer(
                  duration: duration,
                  curve: curve,
                  margin: EdgeInsets.only(top: top1),
                  height: 1,
                  child: AnimatedRotation(
                    turns: turns1,
                    duration: duration,
                    curve: curve,
                    child: Container(
                      width: 80,
                      height: 1,
                      decoration: BoxDecoration(
                        color: const Color(0xFF000000),
                        borderRadius: BorderRadius.circular(9999),
                      ),
                    ),
                  ),
                ),
                AnimatedContainer(
                  duration: duration,
                  curve: curve,
                  margin: EdgeInsets.only(top: top2),
                  height: 1,
                  child: AnimatedRotation(
                    turns: turns2,
                    duration: duration,
                    curve: curve,
                    child: Container(
                      width: 80,
                      height: 1,
                      decoration: BoxDecoration(
                        color: const Color(0xFF000000),
                        borderRadius: BorderRadius.circular(9999),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Alias kept for readability at call sites.
typedef AnimatedMenuButton = TheMenuButton;
