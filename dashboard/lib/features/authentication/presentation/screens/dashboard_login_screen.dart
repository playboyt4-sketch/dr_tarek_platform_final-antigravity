import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/glass_text_field.dart';
import '../../../../core/widgets/liquid_glass_card.dart';
import '../../../../core/widgets/primary_action_button.dart';
import '../../../../core/widgets/remember_me_checkbox.dart';
import '../providers/login_controller.dart';
import '../widgets/brand_title.dart';
import '../widgets/login_footer.dart';
import '../widgets/password_visibility_toggle.dart';

/// Approved Figma Dev Mode frame `dashboard login` (1280 x 800 reference).
///
/// Page: 1280 x 800, pure white #FFFFFF. Responsive layout centered
/// horizontally and vertically; a [SingleChildScrollView] prevents overflow
/// on small viewports.
/// Brand: max width 1120 above the card — "Tarek el araby" Regular 96 black
/// + " " Medium 96 + "Platform" Thin 96 #979797, centered, clamped 48–96.
/// Card (`#login frame`): 480 x 452 — radius 28, white 70%, blur 20/20,
/// 1.5 px inside stroke #E5E7EB, shadow black 0x1E000000 offset (0, 12)
/// blur 30.
///
/// Inner stack (relative to the card, horizontal padding 24 → 432 inner):
/// title Y24 (32 SemiBold #111827, centered) → gap 8 → subtitle Y80
/// (16 Regular #6B7280, centered) → gap 24 → phone Y128 432x68 → gap 16 →
/// password Y212 432x68 → gap 8 → remember Y288 (128x24, right) → gap 32 →
/// button Y344 345x56 → gap 16 → footer Y416 (16 px, centered).
///
/// Auth logic ([LoginController], Egyptian phone validation, password
/// length >= 6, loading state, staff-only gating in the controller +
/// router) is unchanged.
class DashboardLoginScreen extends ConsumerStatefulWidget {
  const DashboardLoginScreen({super.key});

  @override
  ConsumerState<DashboardLoginScreen> createState() =>
      _DashboardLoginScreenState();
}

class _DashboardLoginScreenState extends ConsumerState<DashboardLoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _passwordFocusNode = FocusNode();
  bool _passwordVisible = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  void _submit() {
    ref.read(loginControllerProvider.notifier).submit(
          phoneNumber: _phoneController.text,
          password: _passwordController.text,
        );
  }

  String? _messageFor(FailureCode code) {
    switch (code) {
      case FailureCode.wrongCredentials:
        return 'Incorrect phone number or password.';
      case FailureCode.approvalPending:
        return 'This account is waiting for approval.';
      case FailureCode.accountDisabled:
        return 'This account is disabled.';
      case FailureCode.permissionDenied:
        return 'You do not have access to this dashboard.';
      case FailureCode.tooManyRequests:
        return 'Too many attempts. Please try again later.';
      case FailureCode.validation:
        return null;
      case FailureCode.noInternet:
      case FailureCode.timeout:
      case FailureCode.appCheckFailed:
        return 'Connection problem. Check your network and try again.';
      case FailureCode.server:
      case FailureCode.unknown:
      case FailureCode.unauthorizedDevice:
      case FailureCode.notFound:
        return 'Could not sign in. Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final loginState = ref.watch(loginControllerProvider);
    final submitting = loginState is LoginSubmitting;
    final failure = loginState is LoginFailure ? loginState : null;
    final formMessage =
        failure == null ? null : _messageFor(failure.failure.code);

    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return SingleChildScrollView(
              physics: submitting
                  ? const NeverScrollableScrollPhysics()
                  : const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      // Brand 1120 max, centered, with top padding.
                      const Padding(
                        padding: EdgeInsets.only(top: 24),
                        child: Center(child: BrandTitle()),
                      ),
                      // Brand + 16 = card top (Y: 136 at reference).
                      const SizedBox(height: 16),
                      // Card 480 x 452, centered horizontally.
                      Center(
                        child: _LoginCard(
                          phoneController: _phoneController,
                          passwordController: _passwordController,
                          passwordFocusNode: _passwordFocusNode,
                          passwordVisible: _passwordVisible,
                          onTogglePasswordVisibility: () => setState(
                            () => _passwordVisible = !_passwordVisible,
                          ),
                          onSubmit: _submit,
                          submitting: submitting,
                          formMessage: formMessage,
                          phoneError: failure?.phoneError,
                          passwordError: failure?.passwordError,
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LoginCard extends StatefulWidget {
  final TextEditingController phoneController;
  final TextEditingController passwordController;
  final FocusNode passwordFocusNode;
  final bool passwordVisible;
  final VoidCallback onTogglePasswordVisibility;
  final VoidCallback onSubmit;
  final bool submitting;
  final String? formMessage;
  final String? phoneError;
  final String? passwordError;

  const _LoginCard({
    required this.phoneController,
    required this.passwordController,
    required this.passwordFocusNode,
    required this.passwordVisible,
    required this.onTogglePasswordVisibility,
    required this.onSubmit,
    required this.submitting,
    this.formMessage,
    this.phoneError,
    this.passwordError,
  });

  @override
  State<_LoginCard> createState() => _LoginCardState();
}

class _LoginCardState extends State<_LoginCard> {
  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.sizeOf(context).width;
    // Figma width is 480; shrink on narrow viewports so nothing clips.
    final double cardWidth =
        screenWidth < 560 ? (screenWidth - 48).clamp(0.0, 480.0) : 480;

    return LiquidGlassCard(
      width: cardWidth,
      child: Padding(
        // 24 sides → 432 inner; top 24 (title Y) / bottom 16 (footer pad).
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Y: 24 — title, 32 SemiBold #111827, centered.
              Text(
                'Login',
                style: AppTypography.loginHeading(),
                textAlign: TextAlign.center,
              ),
              // Title + gap 8 → subtitle Y: 80.
              const SizedBox(height: 8),
              // Y: 80 — subtitle, 16 Regular #6B7280, centered.
              Text(
                'Welcome back please login your account',
                style: AppTypography.loginSubtitle(),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              // Gap 24 → phone Y: 128.
              const SizedBox(height: 24),
              // Y: 128 — phone 432 x 68, hint 24 Thin black.
              GlassTextField(
                controller: widget.phoneController,
                placeholder: 'Phone Number',
                semanticsLabel: 'Phone Number',
                keyboardType: TextInputType.phone,
                autofillHints: const <String>[AutofillHints.telephoneNumber],
                textInputAction: TextInputAction.next,
                errorText: widget.phoneError,
                hintStyle: AppTypography.loginFieldPlaceholder(),
                textStyle: AppTypography.loginFieldValue(),
                suffixIcon: SvgPicture.asset(
                  'assets/images/Smartphone.svg',
                  width: 40,
                  height: 40,
                  semanticsLabel: 'Phone icon',
                ),
                enabled: !widget.submitting,
              ),
              // Gap 16 → password Y: 212.
              const SizedBox(height: 16),
              // Y: 212 — password 432 x 68 with Eye toggle 30x30.
              GlassTextField(
                controller: widget.passwordController,
                focusNode: widget.passwordFocusNode,
                placeholder: 'Password',
                semanticsLabel: 'Password',
                obscureText: !widget.passwordVisible,
                autofillHints: const <String>[AutofillHints.password],
                textInputAction: TextInputAction.done,
                errorText: widget.passwordError,
                hintStyle: AppTypography.loginFieldPlaceholder(),
                textStyle: AppTypography.loginFieldValue(),
                onSubmitted: (_) => widget.onSubmit(),
                suffixIcon: PasswordVisibilityToggle(
                  visible: widget.passwordVisible,
                  onToggle: widget.onTogglePasswordVisibility,
                ),
                enabled: !widget.submitting,
              ),
              // Gap 8 → remember Y: 288.
              const SizedBox(height: 8),
              // Y: 288 — remember row (128 x 24 Figma), right-aligned to
              // the form field boundaries.
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  height: 24,
                  child: Consumer(
                    builder: (BuildContext context, WidgetRef ref, _) {
                      final rememberMe = ref.watch(rememberMeProvider);
                      return RememberMeCheckbox(
                        value: rememberMe,
                        onChanged: (bool? value) => ref
                            .read(rememberMeProvider.notifier)
                            .set(value ?? false),
                      );
                    },
                  ),
                ),
              ),
              if (widget.formMessage != null) ...<Widget>[
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    widget.formMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 14,
                      height: 1.2,
                      color: Color(0xFFB3261E),
                    ),
                  ),
                ),
              ],
              // Gap 32 → button Y: 344.
              const SizedBox(height: 32),
              // Y: 344 — button 345 x 56, capsule 9999, #1D4ED8.
              Center(
                child: SizedBox(
                  width: 345,
                  height: 56,
                  child: PrimaryActionButton(
                    label: 'login',
                    semanticsLabel: 'Login',
                    onPressed: widget.onSubmit,
                    isLoading: widget.submitting,
                  ),
                ),
              ),
              // Gap 16 → footer Y: 416, centered at card bottom.
              const SizedBox(height: 16),
              const Center(child: LoginFooter()),
            ],
          ),
        ),
      ),
    );
  }
}
