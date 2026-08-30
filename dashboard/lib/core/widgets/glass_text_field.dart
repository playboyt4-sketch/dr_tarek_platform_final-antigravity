import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_typography.dart';

/// Text field matching the Figma dashboard login input geometry:
/// 480 x 80, corner radius 28, stroke #000000 @ 20% opacity (1.5 px,
/// inside), fill #D9D9D9 @ 0% (transparent).
///
/// The [suffixIcon] slot carries the Figma icon instance (e.g. the
/// `Smartphone` icon sits on the trailing side of the phone field in the
/// live frame). Placeholder typography is Google Sans Flex Thin 24.
/// Validation messages render below the field so the Figma geometry of the
/// input itself never changes.
class GlassTextField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String placeholder;
  final Widget? leadingIcon;
  final bool obscureText;
  final Widget? suffixIcon;
  final String? errorText;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? semanticsLabel;
  final bool autofocus;
  final bool enabled;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;

  const GlassTextField({
    super.key,
    required this.controller,
    this.focusNode,
    required this.placeholder,
    this.leadingIcon,
    this.obscureText = false,
    this.suffixIcon,
    this.errorText,
    this.onSubmitted,
    this.keyboardType,
    this.inputFormatters,
    this.semanticsLabel,
    this.autofocus = false,
    this.enabled = true,
    this.autofillHints,
    this.textInputAction,
  });

  @override
  State<GlassTextField> createState() => _GlassTextFieldState();
}

class _GlassTextFieldState extends State<GlassTextField> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (mounted) setState(() {});
  }

  Color get _borderColor {
    if (widget.errorText != null) return const Color(0xFFB3261E);
    if (_focusNode.hasFocus) return AppColors.ink;
    return AppColors.inputStroke;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticsLabel ?? widget.placeholder,
      textField: true,
      obscured: widget.obscureText,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // Reference geometry is 480 x 80; shrink proportionally when the
          // surrounding card is narrower (compact viewports) so nothing is
          // clipped and the Figma composition is preserved at reference.
          final double fieldWidth =
              constraints.maxWidth.isFinite ? constraints.maxWidth : 480;
          final double scale =
              (fieldWidth / 480).clamp(0.55, 1.0);
          final double fieldHeight = 80 * scale;
          final double fontSize = 24 * scale;
          // The Figma field icon instance (e.g. the `Smartphone`) is a
          // 49 px glyph; accessory controls (eye toggle) stay 24 px.
          final bool hasGlyphIcon =
              widget.leadingIcon is Icon || widget.suffixIcon is Icon;
          final double iconSize = hasGlyphIcon ? 49 * scale : 24 * scale;
          final double horizontalPadding = 24 * scale;

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: fieldWidth,
                height: fieldHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: _borderColor, width: 1.5),
                  color: const Color(0x00D9D9D9),
                ),
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: Row(
                  children: <Widget>[
                    if (widget.leadingIcon != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: _sizedIcon(widget.leadingIcon!, iconSize),
                      ),
                    Expanded(
                      child: TextField(
                        controller: widget.controller,
                        focusNode: widget.focusNode,
                        autofocus: widget.autofocus,
                        enabled: widget.enabled,
                        obscureText: widget.obscureText,
                        onSubmitted: widget.onSubmitted,
                        keyboardType: widget.keyboardType,
                        inputFormatters: widget.inputFormatters,
                        autofillHints: widget.autofillHints,
                        textInputAction: widget.textInputAction,
                        style: AppTypography.fieldValue(fontSize: fontSize),
                        cursorColor: AppColors.ink,
                        decoration: InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                          hintText: widget.placeholder,
                          hintStyle:
                              AppTypography.fieldPlaceholder(fontSize: fontSize),
                        ),
                      ),
                    ),
                    if (widget.suffixIcon != null) widget.suffixIcon!,
                  ],
                ),
              ),
              if (widget.errorText != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 16),
                  child: Text(
                    widget.errorText!,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.2,
                      color: Color(0xFFB3261E),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _sizedIcon(Widget icon, double size) {
    if (icon is Icon) {
      return Icon(
        icon.icon,
        size: size,
        color: icon.color,
      );
    }
    return icon;
  }
}
