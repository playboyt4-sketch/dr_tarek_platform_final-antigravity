import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/security/biometric_lock_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../authentication/domain/entities/auth_user.dart';
import '../../../authentication/presentation/providers/auth_provider.dart';
import '../../../membership/presentation/widgets/center_phone_actions.dart';
import '../../../student_dashboard/domain/entities/dashboard_subject.dart';
import '../../../student_dashboard/presentation/providers/dashboard_providers.dart';
import '../../../video_streaming/presentation/components/video_states.dart';
import '../../domain/entities/delete_account_result.dart';
import '../providers/profile_providers.dart';
import '../widgets/change_password_dialog.dart';
import '../widgets/profile_edit_sheet.dart';

// ---------------------------------------------------------------------------
// Design constants for "Student - Profile" (Figma node 58258:1800).
// Raw design-pixel values from Figma dev mode, consumed via context.rs() /
// context.rsV() / context.rsFont() — identical to Figma at the 393x852
// reference, proportionally preserved elsewhere.
//
// Frame map (dev mode paste):
//   canvas    393x852  grade-4-bg-canvas #DC2626 (dynamic per grade:
//             grade-1 #F59E0B, grade-2 #1D4ED8, grade-3 #15803D,
//             grade-4 #DC2626 — AppColors gradeXCanvas tokens)
//   back      24,64    44x44 glass circle (white 25%, white 35% ring)
//   header    24,122   345 capsule, white 15% r9999: 100x100 avatar
//             (gradient white 28%->4%, 1px white 45% ring) + 185 text
//             column (name/grade/phone, 14 white) + 24 edit icon
//   password  24,238   345 white pill r28, 14 grade-canvas text
//   subjects  24,300   345x258: transparent box (1px #D0D0D0 r12) with
//             overlapping grade-canvas "Subjects" tab (92x46, 20 white)
//             + rows (title 20 white + plan 20 white)
//   delete    21,768   345 white pill r28, 14 grade-canvas text
// The simulated OS status bar ("9:41", 0-50 chrome) is NOT reproduced.
// ---------------------------------------------------------------------------
abstract final class _StudentProfileDesign {
  static const gutter = 24.0;
  static const backTop = 14.0;
  static const backSize = 44.0;
  static const avatarSize = 100.0;
  static const subjectsBoxBorder = Color(0xFFD0D0D0);
}

/// Student Profile — opened by tapping the avatar on Student Home.
///
/// Header (name/grade/phone/avatar) and the Subjects rows render live data:
/// identity from [user], subjects + per-subject plans from
/// [dashboardSubjectsProvider]. Photo edit, Change password and
/// Delete My Account reuse the existing profile flows.
class StudentProfileScreen extends ConsumerStatefulWidget {
  final AuthUser user;
  const StudentProfileScreen({required this.user, super.key});

  @override
  ConsumerState<StudentProfileScreen> createState() =>
      _StudentProfileScreenState();
}

class _StudentProfileScreenState extends ConsumerState<StudentProfileScreen> {
  String? _photoUrl;
  late String _fullName;
  bool _isTogglingBiometric = false;

  @override
  void initState() {
    super.initState();
    _photoUrl = widget.user.profilePhoto;
    _fullName = widget.user.fullName;
  }

  @override
  void didUpdateWidget(covariant StudentProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Session reload (after name/photo save) rebuilds this screen with a
    // fresh AuthUser — sync the header immediately instead of keeping the
    // stale initState snapshot until a manual refresh.
    if (oldWidget.user.fullName != widget.user.fullName) {
      _fullName = widget.user.fullName;
    }
    if (oldWidget.user.profilePhoto != widget.user.profilePhoto) {
      _photoUrl = widget.user.profilePhoto;
    }
  }

  /// Background follows the per-grade canvas identity tokens (same mapping
  /// as Student Home). Unknown grades fall back to grade one.
  static Color _gradeBackground(String? grade) {
    switch (grade?.trim().toLowerCase()) {
      case 'grade_two':
      case 'grade two':
      case 'grade_2':
      case 'grade2':
      case '2':
      case 'الفرقة الثانية':
        return AppColors.grade2Canvas;
      case 'grade_three':
      case 'grade three':
      case 'grade_3':
      case 'grade3':
      case '3':
      case 'الفرقة الثالثة':
        return AppColors.grade3Canvas;
      case 'grade_four':
      case 'grade four':
      case 'grade_4':
      case 'grade4':
      case '4':
      case 'الفرقة الرابعة':
        return AppColors.grade4Canvas;
      default:
        return AppColors.grade1Canvas;
    }
  }

  /// Figma header/empty-state grade label ("Grade Four"). Unknown grades
  /// render "غير محددة" — never an invented grade.
  static String _gradeLabel(String? grade) {
    switch (grade?.trim().toLowerCase()) {
      case 'grade_one':
      case 'grade one':
      case 'grade_1':
      case 'grade1':
      case '1':
      case 'الفرقة الأولى':
      case 'الفرقه الاولي':
        return 'Grade One';
      case 'grade_two':
      case 'grade two':
      case 'grade_2':
      case 'grade2':
      case '2':
      case 'الفرقة الثانية':
        return 'Grade Two';
      case 'grade_three':
      case 'grade three':
      case 'grade_3':
      case 'grade3':
      case '3':
      case 'الفرقة الثالثة':
        return 'Grade Three';
      case 'grade_four':
      case 'grade four':
      case 'grade_4':
      case 'grade4':
      case '4':
      case 'الفرقة الرابعة':
        return 'Grade Four';
      default:
        return 'غير محددة';
    }
  }

  /// Figma subject-row plan label (FREE / PRO / MAX / GUEST); subjects
  /// without a resolved plan render "—", never an invented tier.
  static String _planLabel(String? planKey) {
    final key = (planKey ?? '').trim().toLowerCase();
    if (key.isEmpty) return '—';
    if (key.endsWith('_max') || key == 'max' || key == 'maximum') {
      return 'MAX';
    }
    if (key.endsWith('_pro') || key == 'pro') return 'PRO';
    if (key.endsWith('_guest') || key == 'guest') return 'GUEST';
    if (key.endsWith('_free') || key == 'free') return 'FREE';
    return '—';
  }

  static bool _isUpgradeEligible(String? planKey) {
    final label = _planLabel(planKey);
    return label == 'FREE' || label == 'PRO';
  }

  static void _showSubjectUpgradeSheet(
    BuildContext context, {
    required DashboardSubject subject,
    required String planLabel,
  }) {
    final nextTierText = planLabel == 'FREE'
        ? 'يمكنك الترقية إلى باقة Pro أو Max لهذه المادة.'
        : 'يمكنك الترقية إلى باقة Max لهذه المادة.';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.workspace_premium_rounded,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'ترقية اشتراك المادة',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'إغلاق',
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subject.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'الباقة الحالية: $planLabel — $nextTierText',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'لترقية اشتراكك وتفعيله فوراً بعد تأكيد الدفع، تواصل مع إدارة المنصة:',
                    style: TextStyle(fontSize: 14, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  const CenterPhoneActions(phoneNumber: kGuestWallContact),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Opens the "profile edit" bottom sheet (Figma 58258:1891). Persisted
  /// photo/name changes refresh the header immediately via the callbacks.
  Future<void> _openEditSheet() async {
    final user = widget.user;
    await showProfileEditSheet(
      context,
      userId: user.id,
      fullName: _fullName,
      phoneNumber: user.phoneNumber,
      photoUrl: _photoUrl,
      canvas: _gradeBackground(user.grade),
      onPhotoUpdated: (url) {
        if (!mounted) return;
        setState(() => _photoUrl = url);
      },
      onNameUpdated: (name) {
        if (!mounted) return;
        setState(() => _fullName = name);
      },
    );
  }

  Future<void> _openChangePassword() async {
    await showDialog<bool>(
      context: context,
      builder: (_) => const ChangePasswordDialog(),
    );
  }

  Future<void> _onToggleBiometricLock(bool nextValue) async {
    if (_isTogglingBiometric) return;
    setState(() => _isTogglingBiometric = true);
    try {
      if (nextValue) {
        final verified = await ref
            .read(biometricLockServiceProvider)
            .authenticate(
              localizedReason: 'يرجى تأكيد هويتك لتفعيل قفل التطبيق',
            );
        if (!mounted) return;
        if (!verified) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تعذر التحقق من الهوية، لم يتم تفعيل القفل'),
            ),
          );
          return;
        }
        await ref.read(biometricLockEnabledProvider.notifier).setEnabled(true);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تفعيل قفل التطبيق بـ Face ID / البصمة'),
          ),
        );
      } else {
        await ref
            .read(biometricLockEnabledProvider.notifier)
            .setEnabled(false);
      }
    } finally {
      if (mounted) {
        setState(() => _isTogglingBiometric = false);
      }
    }
  }

  Future<void> _showDeleteAccountDialog() async {
    final l10n = AppLocalizations.of(context);
    final passwordController = TextEditingController();
    bool obscurePassword = true;
    bool isLoading = false;
    String? errorMessage;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(l10n.deleteAccountDialogTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.deleteAccountDialogWarning,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                Text(l10n.deleteAccountDialogDescription),
                const SizedBox(height: 24),
                TextField(
                  controller: passwordController,
                  obscureText: obscurePassword,
                  decoration: InputDecoration(
                    labelText: l10n.deleteAccountPasswordLabel,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () => setDialogState(
                        () => obscurePassword = !obscurePassword,
                      ),
                    ),
                  ),
                  enabled: !isLoading,
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.actionCancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: isLoading || passwordController.text.isEmpty
                  ? null
                  : () async {
                      setDialogState(() {
                        isLoading = true;
                        errorMessage = null;
                      });
                      final result = await ref
                          .read(deleteMyAccountUseCaseProvider)
                          .execute(password: passwordController.text);
                      if (!ctx.mounted) return;
                      if (result is DeleteAccountResult) {
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop();
                        }
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(l10n.deleteAccountSuccessMessage),
                            ),
                          );
                          await ref.read(authProvider.notifier).logout();
                        }
                      } else {
                        // Handle failure
                        final failure = result as Failure;
                        String friendlyMessage;
                        if (failure.code == FailureCode.wrongCredentials) {
                          friendlyMessage = l10n.errorWrongCredentials;
                        } else if (failure.code ==
                            FailureCode.tooManyRequests) {
                          // Use backend message if it contains lock duration
                          friendlyMessage =
                              failure.debugDetail?.contains('minute') == true
                              ? failure.debugDetail!
                              : l10n.errorTooManyRequests;
                        } else if (failure.code ==
                            FailureCode.permissionDenied) {
                          friendlyMessage = l10n.errorPermissionDenied;
                        } else {
                          friendlyMessage = l10n.errorGeneric;
                        }
                        setDialogState(() {
                          isLoading = false;
                          errorMessage = friendlyMessage;
                        });
                      }
                    },
              child: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(l10n.deleteAccountConfirmButton),
            ),
          ],
        ),
      ),
    );
  }

  bool _showDangerZone(AuthUser user) {
    return user.role == 'student' || user.role == 'new_student';
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final canvas = _gradeBackground(user.grade);
    final subjectsAsync = ref.watch(dashboardSubjectsProvider);
    final biometricSupported =
        ref.watch(biometricSupportedProvider).asData?.value ?? false;
    final biometricLockEnabled = ref.watch(biometricLockEnabledProvider);

    return Scaffold(
      backgroundColor: canvas,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: context.contentMaxWidth),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: context.rs(_StudentProfileDesign.gutter),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Figma reserves ~50px of status-bar chrome above the back
                  // button (24,64). Real devices get it from SafeArea; on
                  // notch-less platforms (web/desktop) the safe padding is
                  // zero, so the chrome gap is emulated there — otherwise
                  // the arrow hugs the viewport top edge.
                  const _TopChromeGap(),
                  // Back (Figma 24,64 44x44 glass circle). Pinned to LTR so
                  // the arrow always points left like Figma — the ambient
                  // RTL mirrors `arrow_back` to point right.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: _GlassCircleButton(
                        tooltip: 'رجوع',
                        icon: Icons.arrow_back_rounded,
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                  ),
                  SizedBox(height: context.rsV(10)),
                  // Header capsule (Figma 24,122 345 white 15% r9999).
                  _HeaderCard(
                    fullName: _fullName,
                    gradeLabel: _gradeLabel(user.grade),
                    phone: user.phoneNumber,
                    photoUrl: _photoUrl,
                    onEdit: _openEditSheet,
                  ),
                  SizedBox(height: context.rsV(12)),
                  // Change password (Figma 24,238 345 white pill r28).
                  _WhitePillButton(
                    label: 'Change password',
                    foreground: canvas,
                    onTap: _openChangePassword,
                  ),
                  SizedBox(height: context.rsV(12)),
                  // Subjects panel: takes only the space it needs and scrolls
                  // internally if the student has many subjects — the outer
                  // profile page stays fixed with zero unwanted scroll.
                  Flexible(
                    child: _SubjectsPanel(
                      canvas: canvas,
                      subjectsAsync: subjectsAsync,
                      onRetry: () => ref.invalidate(dashboardSubjectsProvider),
                    ),
                  ),
                  if (biometricSupported) ...[
                    SizedBox(height: context.rsV(12)),
                    _BiometricLockTile(
                      canvas: canvas,
                      enabled: biometricLockEnabled,
                      busy: _isTogglingBiometric,
                      onChanged: _onToggleBiometricLock,
                    ),
                  ],
                  SizedBox(height: context.rsV(14)),
                  // Account actions (white pills like the rest of the
                  // screen — the blue outlined style clashed with the
                  // grade canvas).
                  _WhitePillButton(
                    label: 'Logout',
                    foreground: canvas,
                    onTap: () => ref.read(authProvider.notifier).logout(),
                  ),
                  if (_showDangerZone(user)) ...[
                    SizedBox(height: context.rsV(10)),
                    // Delete My Account (Figma 21,768 345 white pill r28).
                    _WhitePillButton(
                      label: 'Delete My Account',
                      foreground: canvas,
                      onTap: _showDeleteAccountDialog,
                    ),
                  ],
                  SizedBox(height: context.rsV(12)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Gap above the back button: Figma's 14px below its 50px status chrome.
///
/// [SafeArea] already insets real notches; [MediaQuery] padding is zero on
/// notch-less platforms (web/desktop), where the 36px chrome emulation
/// keeps the button off the viewport top (14 + 36 = 50, the Figma chrome).
class _TopChromeGap extends StatelessWidget {
  const _TopChromeGap();

  @visibleForTesting
  static double gapFor(double safeTopPadding, double rsV14, double rsV36) {
    return rsV14 + (safeTopPadding <= 0 ? rsV36 : 0);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: gapFor(
        MediaQuery.paddingOf(context).top,
        context.rsV(_StudentProfileDesign.backTop),
        context.rsV(36),
      ),
    );
  }
}

/// Back-button glass circle (Figma 44x44: white 25% fill, 1px white 35%
/// ring, white icon).
class _GlassCircleButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  const _GlassCircleButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final diameter = context.rs(_StudentProfileDesign.backSize);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.25),
        shape: CircleBorder(
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: diameter,
            height: diameter,
            child: Icon(icon, color: Colors.white, size: context.rs(24)),
          ),
        ),
      ),
    );
  }
}

/// Header capsule (Figma 24,122): white 15% r9999 with the 100x100 avatar
/// (gradient white 28%->4%, 1px white 45% ring), the name/grade/phone
/// column and the edit affordance.
///
/// The row is pinned to LTR so the avatar stays on the LEFT and the edit
/// affordance on the RIGHT exactly like Figma — the app's ambient RTL
/// (Arabic locale) would otherwise mirror the whole capsule.
class _HeaderCard extends StatelessWidget {
  final String fullName;
  final String gradeLabel;
  final String phone;
  final String? photoUrl;
  final VoidCallback onEdit;

  const _HeaderCard({
    required this.fullName,
    required this.gradeLabel,
    required this.phone,
    required this.photoUrl,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(context.rs(8)),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(context.rs(9999)),
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _ProfileAvatar(photoUrl: photoUrl),
            SizedBox(width: context.rs(8)),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: context.rsFont(14),
                      fontWeight: FontWeight.w400,
                      height: 1.43,
                    ),
                  ),
                  Text(
                    gradeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: context.rsFont(14),
                      fontWeight: FontWeight.w400,
                      height: 1.43,
                    ),
                  ),
                  Text(
                    phone,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: context.rsFont(14),
                      fontWeight: FontWeight.w400,
                      height: 1.43,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: context.rs(8)),
            IconButton(
              tooltip: 'تعديل الملف الشخصي',
              onPressed: onEdit,
              icon: Icon(
                Icons.edit_square,
                color: Colors.white,
                size: context.rs(24),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 100x100 profile avatar (Figma div.avatar): gradient white 28%->4%
/// circle with a 1px white 45% ring; photo cover with a person fallback.
class _ProfileAvatar extends StatelessWidget {
  final String? photoUrl;

  const _ProfileAvatar({required this.photoUrl});

  @override
  Widget build(BuildContext context) {
    final diameter = context.rs(_StudentProfileDesign.avatarSize);
    return SizedBox(
      width: diameter,
      height: diameter,
      child: Stack(
        children: [
          Container(
            width: diameter,
            height: diameter,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: const Alignment(0.16, -0.09),
                end: const Alignment(0.84, 1.09),
                colors: [
                  Colors.white.withValues(alpha: 0.28),
                  Colors.white.withValues(alpha: 0.04),
                ],
              ),
              borderRadius: BorderRadius.circular(context.rs(9999)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x7F000000),
                  blurRadius: 20,
                  offset: Offset(0, 10),
                  spreadRadius: -10,
                ),
              ],
            ),
            child: photoUrl?.isNotEmpty == true
                ? Image.network(
                    photoUrl!,
                    width: diameter,
                    height: diameter,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        _AvatarPlaceholder(diameter: diameter),
                    loadingBuilder: (context, child, progress) =>
                        progress == null
                        ? child
                        : _AvatarPlaceholder(diameter: diameter),
                  )
                : _AvatarPlaceholder(diameter: diameter),
          ),
          Container(
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(context.rs(9999)),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.45),
                width: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarPlaceholder extends StatelessWidget {
  final double diameter;

  const _AvatarPlaceholder({required this.diameter});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white.withValues(alpha: 0.05),
      alignment: Alignment.center,
      child: Icon(
        Icons.person_outline,
        size: diameter * 0.52,
        color: Colors.white.withValues(alpha: 0.85),
      ),
    );
  }
}

/// White pill button (Figma Change password / Delete My Account: 345
/// white r28, 14 grade-canvas label).
class _BiometricLockTile extends StatelessWidget {
  final Color canvas;
  final bool enabled;
  final bool busy;
  final ValueChanged<bool> onChanged;

  const _BiometricLockTile({
    required this.canvas,
    required this.enabled,
    required this.busy,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(context.rs(28)),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: context.rs(16),
        vertical: context.rsV(6),
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Row(
          children: [
            Icon(
              Icons.face_rounded,
              color: canvas,
              size: context.rs(22),
            ),
            SizedBox(width: context.rs(10)),
            Expanded(
              child: Text(
                'قفل التطبيق بـ Face ID / البصمة',
                style: TextStyle(
                  color: canvas,
                  fontSize: context.rsFont(14),
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ),
            Switch.adaptive(
              key: const ValueKey('biometric_lock_switch'),
              value: enabled,
              activeTrackColor: canvas,
              onChanged: busy ? null : onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _WhitePillButton extends StatelessWidget {
  final String label;
  final Color foreground;
  final VoidCallback onTap;

  const _WhitePillButton({
    required this.label,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(context.rs(28)),
      child: InkWell(
        borderRadius: BorderRadius.circular(context.rs(28)),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(context.rs(10)),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: foreground,
              fontSize: context.rsFont(14),
              fontWeight: FontWeight.w400,
              height: 1.43,
            ),
          ),
        ),
      ),
    );
  }
}

/// Subjects panel — Figma-exact group (345x258 frame):
/// - box at (0, 26.01): transparent fill, 1px #D0D0D0 r12 border drawn
///   whole, so the left stroke is provably continuous;
/// - "Subjects" tab at (27.11, 0), 91.63x46 grade-canvas block (sharp
///   corners, padding 10), painted after the box so it punches its gap
///   in the top border exactly like Figma;
/// - rows at x=27.11 below the tab (gap 9): title + 12 gap + plan, 14px,
///   title wraps up to 4 lines with RTL shaping for Arabic.
///
/// Intentional deviation from Figma's 20px / 60-gap / single-line rows:
/// real subject names ("الأخلاقيات مهنة المحاسبة") are far longer than
/// Figma's "مالية متقدمة" placeholder and were truncated. 14px matches
/// the header/pill text on this screen, and 4-line wrap shows full names.
/// The box sizes itself from its content (no fixed heights) so any
/// subject count fits. Pinned to LTR (title LEFT, plan RIGHT) exactly
/// like Figma, never mirrored in RTL — same as the header capsule.
class _SubjectsPanel extends StatelessWidget {
  final Color canvas;
  final AsyncValue<List<DashboardSubject>> subjectsAsync;
  final VoidCallback onRetry;

  const _SubjectsPanel({
    required this.canvas,
    required this.subjectsAsync,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    // Pinned to LTR so the tab at physical left x=27.11 and the row
    // order (title LEFT, plan RIGHT) never mirror under Arabic RTL —
    // exactly like Figma node 58258:1800 (header capsule is also LTR).
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Bordered box (Figma: y offset 26.01, transparent, 1px #D0D0D0,
          // r12). In normal flow so it sizes the Stack from its content.
          Padding(
            padding: EdgeInsets.only(top: context.rsV(26.01)),
            child: Container(
              width: double.infinity,
              // Top padding clears the overlapping tab:
              // tab (min 46) - box offset (26.01) + 9 gap = ~29.
              // The old 17.38 left the first row ~2.6px behind the tab,
              // eating its top ("حاجات متاكلة").
              padding: EdgeInsets.fromLTRB(
                context.rs(27.11),
                context.rsV(30),
                context.rs(20),
                context.rsV(16),
              ),
              decoration: BoxDecoration(
                color: const Color(0x00D9D9D9),
                borderRadius: BorderRadius.circular(context.rs(12)),
                border: Border.all(
                  color: _StudentProfileDesign.subjectsBoxBorder,
                  width: 1,
                ),
              ),
              child: subjectsAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
                error: (error, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'تعذر تحميل المواد حالياً',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: onRetry,
                      child: const Text(
                        'إعادة المحاولة',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
                data: (items) {
                  if (items.isEmpty) {
                    return const Text(
                      'لا توجد مواد مفعّلة لك حالياً.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    );
                  }
                  return SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (int i = 0; i < items.length; i++) ...[
                        if (i > 0) SizedBox(height: context.rsV(10)),
                        Row(
                          mainAxisSize: MainAxisSize.max,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          textDirection: TextDirection.ltr,
                          children: [
                            Expanded(
                              child: Text(
                                items[i].title,
                                textDirection:
                                    RegExp(r'[\u0600-\u06FF]').hasMatch(
                                      items[i].title,
                                    )
                                    ? TextDirection.rtl
                                    : TextDirection.ltr,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.left,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: context.rsFont(14),
                                  fontWeight: FontWeight.w400,
                                  height: 1.4,
                                ),
                              ),
                            ),
                            SizedBox(width: context.rs(8)),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: context.rs(8),
                                vertical: context.rsV(2),
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                _StudentProfileScreenState._planLabel(
                                  items[i].planKey,
                                ),
                                textDirection: TextDirection.ltr,
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: context.rsFont(12),
                                  fontWeight: FontWeight.w600,
                                  height: 1.3,
                                ),
                              ),
                            ),
                            if (_StudentProfileScreenState._isUpgradeEligible(
                              items[i].planKey,
                            )) ...[
                              SizedBox(width: context.rs(6)),
                              Material(
                                key: ValueKey(
                                  'upgrade_subject_${items[i].id}',
                                ),
                                color: Colors.white.withValues(alpha: 0.24),
                                shape: const StadiumBorder(
                                  side: BorderSide(color: Color(0x80FFFFFF)),
                                ),
                                child: InkWell(
                                  customBorder: const StadiumBorder(),
                                  onTap: () => _StudentProfileScreenState
                                      ._showSubjectUpgradeSheet(
                                    context,
                                    subject: items[i],
                                    planLabel: _StudentProfileScreenState
                                        ._planLabel(items[i].planKey),
                                  ),
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: context.rs(8),
                                      vertical: context.rsV(4),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.arrow_upward_rounded,
                                          size: context.rsFont(12),
                                          color: Colors.white,
                                        ),
                                        SizedBox(width: context.rs(3)),
                                        Text(
                                          'Upgrade',
                                          maxLines: 1,
                                          softWrap: false,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: context.rsFont(11),
                                            fontWeight: FontWeight.w700,
                                            height: 1.2,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                );
                },
              ),
            ),
          ),
          // "Subjects" tab (Figma: x 27.11, min 91.63x46, padding 10,
          // grade-canvas block, sharp corners). Width sizes to content
          // (Figma width is a minimum): a fixed 91.63 clips the label on
          // fonts/renders wider than Figma metrics ("...Subje").
          Positioned(
            left: context.rs(27.11),
            top: 0,
            child: Container(
              // Auto height (min 46) instead of fixed 46: fixed height
              // clipped "Subjects" when vertical scale (rsV) shrank below
              // font scale (e.g. small web viewport with DevTools open).
              constraints: BoxConstraints(
                minWidth: context.rs(91.63),
                minHeight: context.rsV(46),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: context.rs(14),
                vertical: context.rsV(10),
              ),
              decoration: BoxDecoration(color: canvas),
              child: Center(
                child: Text(
                  'Subjects',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: context.rsFont(20),
                    fontWeight: FontWeight.w400,
                    height: 1.30,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
