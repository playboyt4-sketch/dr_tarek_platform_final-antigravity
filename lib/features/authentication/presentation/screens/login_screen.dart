import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failure_messages.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_semantic_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/validators/egyptian_phone.dart';
import '../../../../core/widgets/glass_back_button.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../profile/data/repositories/profile_repository_impl.dart';
import '../../../profile/data/services/pending_profile_photo_store.dart';
import '../../domain/entities/auth_user.dart';
import '../../data/remember_me_prefs.dart';
import '../../domain/entities/session_state.dart';
import '../providers/auth_provider.dart';
import '../providers/session_provider.dart';
import '../widgets/forced_password_change_screen.dart';
import '../widgets/forgot_password_sheet.dart';
import 'auth_gate.dart';

// ---------------------------------------------------------------------------
// Design constants for "current Student - sign in" (Figma node 52-143).
// Raw design-pixel values from Figma dev mode, consumed exclusively via
// context.rs() / context.rsV() / context.rsFont() (through AppTypography) —
// identical to Figma at the 393x852 reference, proportionally preserved
// elsewhere. Pattern mirrors NewStudentNameScreen / NewStudentWelcomeScreen:
// Scaffold + SafeArea + SingleChildScrollView +
// ConstrainedBox(minHeight: viewportHeight) + SizedBox(393x852) + Stack of
// exact Positioned coordinates.
//
// Frame map (dev mode paste):
//   hero      12,50   369x320 r35 (IMAGE fill)
//   back      24,64   44x44 glass (white 25% + white 35% stroke)
//   title     0,401   393x43  "Welcome back" 28/36 centered black
//   phone     23,486  347x69  border #D0D0D0 r12, hint Inter 20 #9A9A9A
//             phone icon 42,510 20x20 / hint 102,507 157x29
//   password  23,569  347x69  same border, lock 42,589 20x20,
//             eye 324,589 24x24, hint 102,589
//   forget    206,655 186x24  14 w100 black centered (right-aligned)
//   button    24,754  w345 Style3 solid #1D4ED8 r9999 pad 24x14
//             label "Login" 20/26 white centered
// The stray 168x46 "Login" text layer at y732 in the export is superseded
// by the Style3 "Next" button — not reproduced.
// The simulated OS status bar ("9:41" / battery, 0-50 chrome) is NOT
// reproduced — the OS draws the real status bar and SafeArea insets for it.
// ---------------------------------------------------------------------------
abstract final class _LoginDesign {
  static const canvasWidth = 393.0;
  static const canvasHeight = 852.0;

  static const heroX = 12.0;
  static const heroY = 50.0;
  static const heroWidth = 369.0;
  static const heroHeight = 320.0;
  static const heroRadius = 35.0;
  // Figma export for this frame (puzzle art + waving boy), renamed to
  // snake_case — the shipped file had spaces + trailing space which breaks
  // web asset URLs.
  static const heroAsset = 'assets/images/current_student_sign_in.png';

  static const backX = 24.0;
  static const backY = 64.0;
  static const backSize = 44.0;

  static const titleY = 401.0;

  static const fieldX = 23.0;
  static const phoneY = 486.0;
  static const passwordY = 569.0;
  static const fieldWidth = 347.0;

  static const forgetY = 655.0;
  static const optionsRowHeight = 32.0;

  static const buttonX = 24.0;
  static const buttonY = 754.0;
  static const buttonWidth = 345.0;
}

/// Current Student - Sign In (Figma node 52-143, 393x852, `#FFFCF7`).
///
/// Pixel composition follows [_LoginDesign] exactly; authentication behavior
/// is unchanged: the existing Custom Token login flow, session/AuthGate
/// continuation, device-binding enforcement, throttling, account-state
/// handling, and error mapping are all reused from the existing providers —
/// this widget performs no Firebase, Firestore, Functions, device, or
/// session work itself.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;

  /// "Remember me" choice. Defaults to true (current behavior: the session
  /// survives app restarts); restored from persistence on init.
  bool _rememberMe = true;

  @override
  void initState() {
    super.initState();
    loadRememberMeChoice().then((rememberMe) {
      if (!mounted || rememberMe == _rememberMe) return;
      setState(() => _rememberMe = rememberMe);
    });
  }

  /// Terminal non-error session message (pending/rejected/disabled/…).
  /// Shown inline in the error slot; such sessions stay on this screen
  /// instead of navigating anywhere.
  String? _terminalMessage;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _setRememberMe(bool value) {
    if (value == _rememberMe) return;
    setState(() => _rememberMe = value);
    saveRememberMeChoice(value);
  }

  String _homeRouteForRole(String role) {
    return authGateDestinationForRole(role) == AuthGateDestination.admin
        ? AppRoutes.adminHome
        : AppRoutes.studentHome;
  }

  /// Uploads a photo stashed at registration time (the client is signed out
  /// then, so the upload can only happen on the first authenticated login).
  /// Best-effort: failures keep the stash for the next login and never
  /// block navigation. On success the auth/session state is refreshed so
  /// every avatar picks up the new URL immediately.
  Future<void> _flushPendingPhoto(AuthUser user) async {
    final pending = await PendingProfilePhotoStore.load(user.phoneNumber);
    if (pending == null || !mounted) return;
    try {
      final bytes = await pending.readAsBytes();
      // Storage cap is 5MB; oversized picks stay stashed (the profile
      // screen lets the student retry with a smaller photo).
      if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) return;
      final repo = ProfileRepositoryImpl();
      final url = await repo.uploadProfilePhoto(
        userId: user.id,
        bytes: bytes,
        fileName: 'profile.jpg',
      );
      await repo.updateProfilePhotoUrl(userId: user.id, url: url);
      await PendingProfilePhotoStore.clear(user.phoneNumber);
      // Refresh the cached profile (and the session derived from it) so
      // avatars everywhere — home header, dashboard — show the photo now.
      ref.invalidate(authProvider);
    } catch (_) {
      // Keep the stash for the next login.
    }
  }

  String _messageFor(SessionState session) {
    final l10n = AppLocalizations.of(context);
    return switch (session) {
      SessionPendingApproval() => l10n.pendingApprovalMessage,
      SessionRejected() => l10n.rejectedMessage,
      SessionDisabled() => l10n.disabledMessage,
      SessionUnauthorizedDevice() =>
        l10n.unauthorizedDeviceMessage,
      SessionRoleBlocked(:final role) =>
        l10n.roleUnavailableMessage(role),
      _ => l10n.sessionErrorTitle,
    };
  }

  Future<void> _login() async {
    setState(() => _terminalMessage = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // Persist the choice first so a cold start during this very session
    // already honors it, then apply it to the Firebase session (web-native
    // persistence; mobile is enforced at cold start). Both best-effort:
    // login must never fail because of them.
    await saveRememberMeChoice(_rememberMe);
    await ref
        .read(authProvider.notifier)
        .applyRememberMePersistence(_rememberMe);

    await ref.read(authProvider.notifier).login(
          phoneNumber: _phoneController.text.trim(),
          password: _passwordController.text,
        );

    if (!mounted) return;
    final authState = ref.read(authProvider);
    if (authState.hasError || authState.value == null) return;

    ref.invalidate(sessionProvider);
    final session = await ref.read(sessionProvider.future);
    if (!mounted) return;

    // Authenticated → role home. The GoRouter session redirect guards the
    // same invariant for deep links / restored URLs.
    if (session is SessionAuthenticated) {
      await _flushPendingPhoto(session.user);
      if (!mounted) return;
      context.goNamed(_homeRouteForRole(session.user.role));
      return;
    }
    // Error sessions surface inline via the watched providers below.
    if (session is SessionError) return;
    // Forced password change → mandatory dialog (same flow as AuthGate);
    // on success the session re-resolves and an authenticated session
    // routes home.
    if (session is SessionForcePasswordChange) {
      final changed = await showForcedPasswordChangeDialog(
        context,
        studentName: session.user.fullName,
      );
      if (!mounted) return;
      if (changed == true) {
        ref.invalidate(sessionProvider);
        final retry = await ref.read(sessionProvider.future);
        if (!mounted) return;
        if (retry is SessionAuthenticated) {
          context.goNamed(_homeRouteForRole(retry.user.role));
          return;
        }
        if (retry is! SessionError) {
          setState(() => _terminalMessage = _messageFor(retry));
        }
      }
      return;
    }
    // Any other terminal session (pending/rejected/disabled/unauthorized
    // device/role-blocked) stays here with an inline message — never pops
    // back to user-type selection on a successful sign-in.
    setState(() => _terminalMessage = _messageFor(session));
  }

  InputDecoration _fieldDecoration(
    BuildContext context, {
    required String hint,
    required Widget prefixIcon,
    Widget? suffixIcon,
  }) {
    final semantic = AppSemanticColors.of(context);
    OutlineInputBorder border(Color color, [double width = 1]) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return InputDecoration(
      hintText: hint,
      // Figma: Inter 20 #9A9A9A. Rendered via the design-system 20px
      // regular token (titleMedium) so size/weight match Figma exactly
      // while staying on the shared typography scale.
      hintStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w400,
        color: semantic.inputHint,
      ),
      // Vertical padding resolves the bordered box to Figma's ~69px
      // field height; horizontal padding leaves room for the 20px
      // leading icon + 24px eye toggle.
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 23,
      ),
      prefixIcon: Padding(
        padding: const EdgeInsets.only(left: 19, right: 12),
        child: prefixIcon,
      ),
      prefixIconConstraints: const BoxConstraints(
        minWidth: 51,
        minHeight: 20,
      ),
      suffixIcon: suffixIcon,
      suffixIconConstraints: const BoxConstraints(
        minWidth: 48,
        minHeight: 24,
      ),
      enabledBorder: border(semantic.inputBorder),
      focusedBorder: border(semantic.inputBorderFocused, 1.5),
      errorBorder: border(semantic.error),
      focusedErrorBorder: border(semantic.error, 1.5),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final authState = ref.watch(authProvider);
    final sessionState = ref.watch(sessionProvider);
    final isLoading = authState.isLoading || sessionState.isLoading;
    final authError = authState.hasError
        ? friendlyErrorMessage(context, authState.error)
        : sessionState.hasError
            ? friendlyErrorMessage(context, sessionState.error)
            : _terminalMessage;

    final viewportHeight = MediaQuery.of(context).size.height -
        MediaQuery.of(context).padding.vertical;
    final semantic = AppSemanticColors.of(context);

    return Scaffold(
      backgroundColor: semantic.canvasWarm,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: viewportHeight),
            child: Directionality(
              // Force LTR — English-only screen, mirrors sibling steps.
              textDirection: TextDirection.ltr,
              child: SizedBox(
                width: context.rs(_LoginDesign.canvasWidth),
                height: context.rsV(_LoginDesign.canvasHeight),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // --- 1. Illustration panel (Figma 12,50 369x320 r35).
                    // BoxFit.cover crops cleanly — never BoxFit.fill.
                    Positioned(
                      left: context.rs(_LoginDesign.heroX),
                      top: context.rsV(_LoginDesign.heroY),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          context.rs(_LoginDesign.heroRadius),
                        ),
                        child: SizedBox(
                          width: context.rs(_LoginDesign.heroWidth),
                          height: context.rsV(_LoginDesign.heroHeight),
                          child: Image.asset(
                            _LoginDesign.heroAsset,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                              color: semantic.surface,
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                size: 64,
                                color: semantic.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // --- 2. Back button (Figma 24,64 44x44 over illustration).
                    Positioned(
                      left: context.rs(_LoginDesign.backX),
                      top: context.rsV(_LoginDesign.backY),
                      child: SizedBox(
                        width: context.rs(_LoginDesign.backSize),
                        height: context.rs(_LoginDesign.backSize),
                        child: GlassBackButton(
                          onTap: () => Navigator.of(context).maybePop(),
                        ),
                      ),
                    ),

                    // --- 3. Headline (Figma y401, 393 wide, centered).
                    Positioned(
                      top: context.rsV(_LoginDesign.titleY),
                      left: 0,
                      right: 0,
                      child: Text(
                        'Welcome back',
                        textAlign: TextAlign.center,
                        style: AppTypography.titleLarge(
                          context,
                          color: semantic.textPrimary,
                        ),
                      ),
                    ),

                    // --- 4+5. Phone + password fields inside one Form so a
                    // single validate() call covers both (Figma 23,486 and
                    // 23,569, both 347 wide).
                    Positioned.fill(
                      child: Form(
                        key: _formKey,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // Phone (Figma 23,486 w347).
                            // V1 convention: Egyptian mobile without country
                            // code; no `+20` transformation.
                            Positioned(
                              left: context.rs(_LoginDesign.fieldX),
                              top: context.rsV(_LoginDesign.phoneY),
                              child: SizedBox(
                                width: context.rs(_LoginDesign.fieldWidth),
                                child: TextFormField(
                                  controller: _phoneController,
                                  keyboardType: TextInputType.phone,
                                  textDirection: TextDirection.ltr,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [
                                    AutofillHints.telephoneNumber
                                  ],
                                  validator: (value) {
                                    final normalized =
                                        normalizeEgyptianPhone(value ?? '');
                                    if (normalized.isEmpty) {
                                      return l10n.errorValidation;
                                    }
                                    if (!isValidEgyptianPhone(normalized)) {
                                      return 'يرجى إدخال رقم هاتف مصري صحيح';
                                    }
                                    return null;
                                  },
                                  style: AppTypography.titleMedium(
                                    context,
                                    color: semantic.textPrimary,
                                  ),
                                  decoration: _fieldDecoration(
                                    context,
                                    hint: 'phone number',
                                    prefixIcon: SvgPicture.asset(
                                      'assets/images/Smartphone.svg',
                                      width: 20,
                                      height: 20,
                                      colorFilter: ColorFilter.mode(
                                        semantic.inputHint,
                                        BlendMode.srcIn,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // Password (Figma 23,569 w347, masked default,
                            // eye toggle at the Figma 324,589 slot).
                            Positioned(
                              left: context.rs(_LoginDesign.fieldX),
                              top: context.rsV(_LoginDesign.passwordY),
                              child: SizedBox(
                                width: context.rs(_LoginDesign.fieldWidth),
                                child: TextFormField(
                                  controller: _passwordController,
                                  obscureText: _obscurePassword,
                                  textInputAction: TextInputAction.done,
                                  onFieldSubmitted: (_) =>
                                      isLoading ? null : _login(),
                                  validator: (value) =>
                                      (value == null || value.isEmpty)
                                          ? l10n.errorValidation
                                          : null,
                                  style: AppTypography.titleMedium(
                                    context,
                                    color: semantic.textPrimary,
                                  ),
                                  decoration: _fieldDecoration(
                                    context,
                                    hint: 'Password',
                                    prefixIcon: Icon(
                                      Icons.lock_outline,
                                      size: 20,
                                      color: semantic.inputHint,
                                    ),
                                    suffixIcon: IconButton(
                                      key: const Key(
                                        'passwordVisibilityToggle',
                                      ),
                                      onPressed: () => setState(
                                        () => _obscurePassword =
                                            !_obscurePassword,
                                      ),
                                      icon: SvgPicture.asset(
                                        _obscurePassword
                                            ? 'assets/images/Eye.svg'
                                            : 'assets/images/Eye off.svg',
                                        width: 24,
                                        height: 24,
                                        colorFilter: ColorFilter.mode(
                                          semantic.inputHint,
                                          BlendMode.srcIn,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // Remember me + Forget password on one row. The
                            // right-aligned link (Figma 206,655 186x24,
                            // 14 w100 black centered) opens the existing
                            // V1 forgot-password bottom sheet; the
                            // left-aligned checkbox toggles session
                            // persistence (checked = stay signed in across
                            // restarts, the long-standing default).
                            Positioned(
                              top: context.rsV(_LoginDesign.forgetY),
                              left: context.rs(24),
                              right: context.rs(24),
                              child: SizedBox(
                                height: context.rsV(
                                  _LoginDesign.optionsRowHeight,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: GestureDetector(
                                          onTap: () => _setRememberMe(
                                            !_rememberMe,
                                          ),
                                          behavior: HitTestBehavior.opaque,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              SizedBox(
                                                width: 24,
                                                height: 24,
                                                child: Checkbox(
                                                  value: _rememberMe,
                                                  onChanged: (value) =>
                                                      _setRememberMe(
                                                    value ?? false,
                                                  ),
                                                  activeColor: semantic.primary,
                                                  materialTapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Flexible(
                                                child: Text(
                                                  'Remember me',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style:
                                                      AppTypography.bodyThin(
                                                    context,
                                                    color: semantic.isDark ? semantic.textPrimary : Colors.black,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Align(
                                        alignment: Alignment.centerRight,
                                        child: GestureDetector(
                                          onTap: () =>
                                              showForgotPasswordSheet(
                                            context: context,
                                            phoneNumber:
                                                _phoneController.text,
                                          ),
                                          behavior: HitTestBehavior.opaque,
                                          child: Padding(
                                            padding: EdgeInsets.symmetric(
                                              vertical: context.rsV(4),
                                            ),
                                            child: Text(
                                              'Forget password?',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.right,
                                              style: AppTypography.bodyThin(
                                                context,
                                                color: semantic.isDark ? semantic.textPrimary : Colors.black,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // Auth error (no Figma slot — sits in the gap
                            // between the forget link and the CTA so the
                            // fixed composition never overflows).
                            if (authError != null)
                              Positioned(
                                top: context.rsV(688),
                                left: context.rs(24),
                                right: context.rs(24),
                                child: Text(
                                  authError,
                                  textAlign: TextAlign.center,
                                  style: AppTypography.bodyRegular(
                                    context,
                                    color: semantic.error,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    // --- 6. Primary CTA (Figma 24,754 w345, Style3 solid).
                    // Label is "Login" per product copy (Figma export says
                    // "Next"); behavior is the existing login flow. Loading
                    // disables the button and shows a spinner in the same
                    // 56px pill geometry.
                    Positioned(
                      left: context.rs(_LoginDesign.buttonX),
                      top: context.rsV(_LoginDesign.buttonY),
                      child: SizedBox(
                        width: context.rs(_LoginDesign.buttonWidth),
                        child: isLoading
                            ? SizedBox(
                                height: 56,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: semantic.primary.withValues(
                                      alpha: 0.7,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      AppShapes.radiusFull,
                                    ),
                                  ),
                                  child: Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: semantic.onPrimary,
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            : PrimaryButton(
                                label: 'Login',
                                variant: ButtonVariant.solid,
                                onPressed: _login,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
