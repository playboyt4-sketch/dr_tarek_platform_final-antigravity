import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_typography.dart';

/// Text field matching the approved Figma Dev Mode login inputs:
/// 432 x 68, radius 28, 1 px stroke #979797, white fill, horizontal
/// padding 24, hint Google Sans Flex Thin 100 24 px black.
///
/// [hintStyle]/[textStyle] allow callers outside the login frame to reuse
/// this field with different typography; the login screen passes the exact
/// Figma styles ([AppTypography.loginFieldPlaceholder] /
/// [AppTypography.loginFieldValue]).
///
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
  final TextStyle? hintStyle;
  final TextStyle? textStyle;
  final Color? borderColor;

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
    this.hintStyle,
    this.textStyle,
    this.borderColor,
  });

  @override
  State<GlassTextField> createState() => _GlassTextFieldState();
}

class _GlassTextFieldState extends State<GlassTextField> {
  final FocusNode _internalFocusNode = FocusNode();

  FocusNode get _effectiveFocusNode => widget.focusNode ?? _internalFocusNode;

  @override
  void initState() {
    super.initState();
    _effectiveFocusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(GlassTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_handleFocusChanged);
      _internalFocusNode.removeListener(_handleFocusChanged);
      _effectiveFocusNode.addListener(_handleFocusChanged);
    }
  }

  @override
  void dispose() {
    _effectiveFocusNode.removeListener(_handleFocusChanged);
    _internalFocusNode.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (mounted) setState(() {});
  }

  Color get _borderColor {
    if (widget.errorText != null) return const Color(0xFFB3261E);
    if (_effectiveFocusNode.hasFocus) return AppColors.headingInk;
    return widget.borderColor ?? AppColors.loginInputStroke;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticsLabel ?? widget.placeholder,
      textField: true,
      obscured: widget.obscureText,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // Reference geometry is 432 x 68; shrink proportionally when the
          // surrounding card is narrower (compact viewports) so nothing is
          // clipped and the Figma composition is preserved at reference.
          final double fieldWidth =
              constraints.maxWidth.isFinite ? constraints.maxWidth : 432;
          final double scale = (fieldWidth / 432).clamp(0.55, 1.0);
          final double fieldHeight = 68 * scale;
          final double horizontalPadding = 24 * scale;

          final TextStyle resolvedHint =
              widget.hintStyle ?? AppTypography.loginFieldPlaceholder();
          final TextStyle resolvedValue =
              widget.textStyle ?? AppTypography.loginFieldValue();
          final double baseHintSize = resolvedHint.fontSize ?? 24;
          final double baseValueSize = resolvedValue.fontSize ?? 24;

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: fieldWidth,
                height: fieldHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: _borderColor, width: 1),
                  color: Colors.white,
                ),
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: Row(
                  children: <Widget>[
                    if (widget.leadingIcon != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: _sizedIcon(widget.leadingIcon!),
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
                        style: resolvedValue.copyWith(
                          fontSize: baseValueSize * scale,
                        ),
                        cursorColor: AppColors.headingInk,
                        decoration: InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                          hintText: widget.placeholder,
                          hintStyle: resolvedHint.copyWith(
                            fontSize: baseHintSize * scale,
                          ),
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

  Widget _sizedIcon(Widget icon) {
    if (icon is Icon) {
      return Icon(
        icon.icon,
        size: 40,
        color: icon.color ?? AppColors.iconInk,
      );
    }
    return SizedBox(
      width: 40,
      height: 40,
      child: Center(child: icon),
    );
  }
}
