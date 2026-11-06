import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_semantic_colors.dart';

/// Canonical floating glass back button (`❖ button/back`).
///
/// Figma spec ("New Student - name", Header Section): 44x44 circle,
/// `radius/full`, Liquid Glass fill White 25% + 1px White 35% stroke,
/// `BackdropFilter` blur 20px, white chevron-left icon (20px), `onTap` pops
/// the route with a rightward 300ms EaseOut transition (standard
/// [Navigator.pop] behavior).
///
/// CONFLICT NOTE (existing code vs Figma): the previous feature-local copy
/// (`features/authentication/presentation/widgets/glass_back_button.dart`)
/// used blur ~10px and `Icons.arrow_back_ios_new_rounded`. This canonical
/// widget follows the Figma values (blur 20px, `Icons.chevron_left`,
/// 20px); the feature-local file is now a deprecated adapter over this one
/// so there is exactly one glass-back-button implementation (Master
/// Architecture, Section 9: "No duplicated code").
///
/// Liquid-glass rules followed: soft/thin 1px border, subtle low-opacity
/// fill, background blur only — no heavy shadow, no opaque background.
///
/// Reused by every New Student registration step (Name, Phone Number,
/// Photo, Grade, Password) and the Login screen.
class GlassBackButton extends StatelessWidget {
  /// Tap handler. When null, defaults to popping the current route
  /// (`Navigator.maybePop`), which matches the Figma `OnTap -> pop` action.
  final VoidCallback? onTap;

  /// Button diameter in logical pixels. Figma default is 44.
  final double size;

  const GlassBackButton({super.key, this.onTap, this.size = 44});

  void _handleTap(BuildContext context) {
    final handler = onTap;
    if (handler != null) {
      handler();
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final semantic = AppSemanticColors.of(context);
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Material(
          // Light keeps the approved Figma 25% fill / 35% stroke; Dark uses
          // the approved glass roles (14%/20%) with the semantic glass text.
          color: semantic.glassBackFill,
          shape: CircleBorder(
            side: BorderSide(
              color: semantic.glassBackBorder,
              width: 1.0,
            ),
          ),
          child: InkWell(
            onTap: () => _handleTap(context),
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: size,
              height: size,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 2.0),
                  child: Icon(
                    Icons.chevron_left,
                    color: semantic.glassText,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
