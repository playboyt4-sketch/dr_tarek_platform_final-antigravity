import 'package:flutter/material.dart';

import '../../../../core/widgets/glass_back_button.dart' as core;

/// Deprecated feature-local alias.
///
/// The canonical implementation now lives in
/// `core/widgets/glass_back_button.dart` (single source of truth per Master
/// Architecture, Section 9: "No duplicated code"). This adapter keeps the
/// old `onPressed` call sites (e.g. the Login screen) compiling while new
/// code — including every New Student registration step — uses
/// [core.GlassBackButton] with `onTap` directly. Canonical values follow
/// Figma `❖ button/back` (blur 20px, white chevron 20px); this adapter only
/// forwards, it holds no markup of its own.
@Deprecated(
  'Use GlassBackButton from core/widgets/glass_back_button.dart instead.',
)
class GlassBackButton extends StatelessWidget {
  final VoidCallback onPressed;
  final double size;

  const GlassBackButton({super.key, required this.onPressed, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return core.GlassBackButton(onTap: onPressed, size: size);
  }
}
