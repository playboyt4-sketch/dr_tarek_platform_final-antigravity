import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/glass_text_field.dart';
import '../../../../core/widgets/liquid_glass_card.dart';
import '../../../../core/widgets/primary_action_button.dart';
import '../../../../core/widgets/remember_me_checkbox.dart';
import '../providers/login_controller.dart';
import '../widgets/brand_title.dart';
import '../widgets/login_footer.dart';
import '../widgets/password_visibility_toggle.dart';

/// Figma `education - os ui`, Page 2, frame `dashboard login` (452:397).
///
/// Composition at the 1440 x 1024 reference viewport: brand title top,
/// liquid-glass login card centered with the footer attribution inside the
/// card near its bottom edge. The layout adapts responsively (scrolls when
/// the viewport is too short) without distorting typography or shrinking
/// the card arbitrarily.
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
    final formMessage = failure == null ? null : _messageFor(failure.failure.code);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return SingleChildScrollView(
              physics: submitting
                  ? const NeverScrollableScrollPhysics()
                  : const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    context.isCompact ? 24 : 48,
                    40,
                    context.isCompact ? 24 : 48,
                    32,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      const BrandTitle(),
                      SizedBox(height: context.rs(48)),
                      _LoginCard(
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
    final cardWidth = context.isCompact
        ? MediaQuery.sizeOf(context).width - 48
        : 620.0;
    final horizontalPadding = context.isCompact ? 24.0 : 70.0;

    return LiquidGlassCard(
      width: cardWidth,
      child: Padding(
        padding: EdgeInsets.fromLTRB(horizontalPadding, 76, horizontalPadding, 15),
        child: AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text('Login', style: AppTypography.loginHeading()),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Welcome back please login your account',
                style: AppTypography.loginSubtitle(),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              GlassTextField(
                controller: widget.phoneController,
                placeholder: 'Phone Number',
                semanticsLabel: 'Phone Number',
                keyboardType: TextInputType.phone,
                autofillHints: const <String>[AutofillHints.telephoneNumber],
                textInputAction: TextInputAction.next,
                errorText: widget.phoneError,
                suffixIcon: const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(
                    Icons.smartphone_outlined,
                    size: 49,
                    color: AppColors.iconInk,
                  ),
                ),
                enabled: !widget.submitting,
              ),
              const SizedBox(height: 20),
              GlassTextField(
                controller: widget.passwordController,
                focusNode: widget.passwordFocusNode,
                placeholder: 'Password',
                semanticsLabel: 'Password',
                obscureText: !widget.passwordVisible,
                autofillHints: const <String>[AutofillHints.password],
                textInputAction: TextInputAction.done,
                errorText: widget.passwordError,
                onSubmitted: (_) => widget.onSubmit(),
                suffixIcon: PasswordVisibilityToggle(
                  visible: widget.passwordVisible,
                  onToggle: widget.onTogglePasswordVisibility,
                ),
                enabled: !widget.submitting,
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: Consumer(
                  builder: (BuildContext context, WidgetRef ref, _) {
                    final rememberMe = ref.watch(rememberMeProvider);
                    return RememberMeCheckbox(
                      value: rememberMe,
                      onChanged: (bool? value) =>
                          ref.read(rememberMeProvider.notifier).set(value ?? false),
                    );
                  },
                ),
              ),
              const SizedBox(height: 36),
              if (widget.formMessage != null) ...<Widget>[
                Semantics(
                  liveRegion: true,
                  child: Text(
                    widget.formMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 16,
                      height: 1.2,
                      color: Color(0xFFB3261E),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              PrimaryActionButton(
                label: 'Login',
                onPressed: widget.onSubmit,
                isLoading: widget.submitting,
              ),
              const SizedBox(height: 32),
              const LoginFooter(),
            ],
          ),
        ),
      ),
    );
  }
}
