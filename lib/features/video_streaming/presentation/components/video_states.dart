import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/playback_entities.dart';
import '../controllers/video_playback_controller.dart';

/// Owner-approved wall copy (messaging only — enforcement lives server-side).
/// Rolling-window headline (FINAL_DECISIONS §12); the remaining time is
/// always the server-authoritative expiry rendered by the widget, never a
/// hardcoded duration.
const String kWindowWallTitle = 'متاح فيديو واحد يوميًا فقط في هذه الباقة';

/// Guest zero-preview wall (owner-approved): no Pro-upgrade message here —
/// the student is directed to Center enrollment via the contact below.
const String kGuestWallTitle = 'المحتوى الكامل متاح لطلاب السنتر فقط';
const String kGuestWallMessage = 'للاشتراك، تواصل مع الرقم التالي:';
const String kGuestWallContact = '01098282915';

/// Device-blocked wall (owner-approved copy): the current device resolved
/// to the Guest tier for this Subject (unauthorized device / allowance
/// exhausted). Upgrading the plan cannot authorize a device, so this wall
/// never carries an upgrade action — the student contacts the
/// administration to bind the device (04 Features § Login From Another
/// Device). Messaging only; enforcement lives server-side.
const String kDeviceBlockedWallTitle =
    'جهازك الحالي غير مصرح له بمشاهدة هذا المحتوى — تواصل مع الإدارة لتفعيل الجهاز.';

/// Which wall the upgrade prompt shows. Pure data — see
/// [selectUpgradePromptContent].
enum UpgradeWallKind {
  /// Rolling-window block (§12): headline + server-expiry countdown + Pro.
  window,

  /// Guest zero-preview: Center-enrollment message + contact, no Pro action.
  guestCenterOnly,

  /// Device-blocked (Center student on an unauthorized device): device
  /// message, never an upgrade action — upgrading cannot bind a device.
  deviceNotAuthorized,

  /// Consumed positive preview cap: legacy minutes message + Pro action.
  previewMinutes,

  /// Unknown/malformed verdict: legacy generic paid message + Pro action.
  genericPaid,
}

/// Pure, widget-testable wall content selection (no BuildContext needed;
/// the countdown line itself stays in the widget for TimeOfDay formatting).
@immutable
class UpgradePromptContent {
  final UpgradeWallKind kind;
  final bool showProAction;
  final bool showCountdown;

  const UpgradePromptContent({
    required this.kind,
    required this.showProAction,
    required this.showCountdown,
  });
}

/// Pure selection of the upgrade-wall content. Unit-testable without a
/// widget tree or engine. Precedence mirrors enforcement severity:
/// rolling window first, then the device block (an unauthorized device can
/// never be fixed by an upgrade, so it outranks every upsell-flavored
/// wall), then immediate-zero Guest verdicts by audience, then the
/// consumed-positive-cap minutes message, then the legacy generic wall for
/// unknown or malformed verdicts (fail-soft, never a crash).
///
/// [deviceBlocked] is set only from issuance-side device signals (the
/// Guest-tier throw with no preview, or a `center` preview audience) —
/// never inferred from plan state.
UpgradePromptContent selectUpgradePromptContent({
  required bool windowBlocked,
  required String? previewAudience,
  required bool immediateZero,
  required bool stampedGuestPreview,
  required bool deviceBlocked,
}) {
  if (windowBlocked) {
    return const UpgradePromptContent(
      kind: UpgradeWallKind.window,
      showProAction: true,
      showCountdown: true,
    );
  }
  if (immediateZero && previewAudience == kPreviewAudienceGuest) {
    return const UpgradePromptContent(
      kind: UpgradeWallKind.guestCenterOnly,
      showProAction: false,
      showCountdown: false,
    );
  }
  if (deviceBlocked ||
      (immediateZero && previewAudience == kPreviewAudienceCenter)) {
    return const UpgradePromptContent(
      kind: UpgradeWallKind.deviceNotAuthorized,
      showProAction: false,
      showCountdown: false,
    );
  }
  if (stampedGuestPreview) {
    return const UpgradePromptContent(
      kind: UpgradeWallKind.previewMinutes,
      showProAction: true,
      showCountdown: false,
    );
  }
  if (previewAudience == kPreviewAudienceCenter) {
    // Consumed positive device cap (issuance echo) on a Full listing:
    // same unauthorized device, surfaced after the preview played.
    return const UpgradePromptContent(
      kind: UpgradeWallKind.deviceNotAuthorized,
      showProAction: false,
      showCountdown: false,
    );
  }
  return const UpgradePromptContent(
    kind: UpgradeWallKind.genericPaid,
    showProAction: true,
    showCountdown: false,
  );
}

class VideoLoadingState extends StatelessWidget {
  const VideoLoadingState({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.5),
      child: const Center(
        child: CircularProgressIndicator(color: AppColors.secondary),
      ),
    );
  }
}

class VideoBufferingState extends StatelessWidget {
  const VideoBufferingState({super.key});
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: Colors.white70),
    );
  }
}

class VideoErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  /// Single-pop back to the subject page (the same callback the overlay
  /// header chevron uses): a playback error must never strand the student
  /// on the player with retry as the only way out.
  final VoidCallback onBack;

  const VideoErrorState({
    required this.message,
    required this.onRetry,
    required this.onBack,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    // DECIDED (Teacher/Platform Owner): player error copy is English.
    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.secondary,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: onBack,
                  // P4: Icons.arrow_back auto-mirrors under the app's RTL
                  // Directionality (points right). Pin LTR so it always
                  // renders pointing left — standard back-arrow convention.
                  icon: const Directionality(
                    textDirection: TextDirection.ltr,
                    child: Icon(Icons.arrow_back),
                  ),
                  label: const Text('Back'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class VideoResumePrompt extends StatelessWidget {
  final VideoPlaybackController controller;

  const VideoResumePrompt({required this.controller, super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 120, // above bottom bar
      left: 20,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'استئناف من حيث توقفت؟',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(width: 16),
            TextButton(
              onPressed: () {
                controller.startOver();
              },
              child: const Text('من البداية', style: TextStyle(color: Colors.grey)),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondary,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                controller.continueWatching();
              },
              child: const Text('متابعة'),
            ),
          ],
        ),
      ),
    );
  }
}

/// FINAL_DECISIONS §11/§12: full-screen upgrade wall. Shown either when
/// the Guest per-lecture minute cap is reached (§11) or when a Center
/// Free student tries to start a DIFFERENT video inside their rolling
/// 24-hour window (§12 — [controller.dailyWindowBlocked]). Purely
/// presentational; both gates are computed/enforced server-side.
class VideoUpgradePrompt extends StatelessWidget {
  final VideoPlaybackController controller;
  final VoidCallback onUpgrade;

  /// Pops the player route (back to the subject page) when the student
  /// chooses not to upgrade — without this the wall strands them with the
  /// upgrade as the only action.
  final VoidCallback onBack;

  const VideoUpgradePrompt({
    required this.controller,
    required this.onUpgrade,
    required this.onBack,
    super.key,
  });

  /// §12: tells the student exactly WHEN the window ends as a clock time
  /// (e.g. "لا يمكنك مشاهدة فيديو آخر إلا في 9:30 PM") plus the remaining
  /// duration for clarity. Computed from the server-provided expiry.
  String? _remainingWindowText(BuildContext context) {
    final expiresAt = controller.dailyWindowExpiresAt;
    if (expiresAt == null) return null;
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining <= Duration.zero) return null;
    final clock = TimeOfDay.fromDateTime(expiresAt).format(context);
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    if (hours > 0) {
      return 'لا يمكنك مشاهدة فيديو آخر إلا في $clock (متبقّي $hours ساعة و$minutes دقيقة).';
    }
    return 'لا يمكنك مشاهدة فيديو آخر إلا في $clock (متبقّي $minutes دقيقة).';
  }

  @override
  Widget build(BuildContext context) {
    final content = selectUpgradePromptContent(
      windowBlocked: controller.dailyWindowBlocked,
      previewAudience: controller.previewAudience,
      immediateZero: controller.isPreviewBlockedAtZero,
      stampedGuestPreview: controller.resource?.isGuestPreview == true,
      deviceBlocked: controller.deviceBlocked,
    );
    final windowLine =
        content.showCountdown ? _remainingWindowText(context) : null;
    final title = switch (content.kind) {
      UpgradeWallKind.window => kWindowWallTitle,
      UpgradeWallKind.guestCenterOnly => kGuestWallTitle,
      UpgradeWallKind.deviceNotAuthorized => kDeviceBlockedWallTitle,
      UpgradeWallKind.previewMinutes =>
        'انتهت الدقائق المجانية المسموح بها لهذه المحاضرة.',
      UpgradeWallKind.genericPaid => 'هذا المحتوى متاح لمشتركي الباقة المدفوعة.',
    };
    return Positioned.fill(
      child: Container(
        color: Colors.black87,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, color: Colors.white, size: 48),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            // Guest zero-preview: enrollment contact instead of any
            // upgrade action.
            if (content.kind == UpgradeWallKind.guestCenterOnly) ...[
              const SizedBox(height: 8),
              const Text(
                kGuestWallMessage,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 4),
              const Text(
                kGuestWallContact,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            // §12 nicety: remaining time on the currently-open video.
            if (windowLine != null) ...[
              const SizedBox(height: 8),
              Text(
                windowLine,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
            if (content.showProAction) ...[
              const SizedBox(height: 20),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      minimumSize: const Size(140, 48),
                      shape: const StadiumBorder(),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: onBack,
                    child: const Text('رجوع'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.secondary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(140, 48),
                      shape: const StadiumBorder(),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: onUpgrade,
                    child: const Text('الترقية إلى Pro'),
                  ),
                ],
              ),
            ],
            if (!content.showProAction) ...[
              const SizedBox(height: 20),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                  minimumSize: const Size(140, 48),
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onPressed: onBack,
                child: const Text('رجوع'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
