import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure_messages.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/validators/egyptian_phone.dart';
import '../providers/password_reset_provider.dart';

/// Figma design content: the support number shown in the supplied
/// `current Student - sign in` overlay.
///
/// DISCREPANCY (reported, not silently resolved): no Admin/Support contact
/// value exists anywhere in the app configuration, providers, remote config,
/// or localization files — this is the only source of the number. Kept as a
/// private sheet-local const (not a global token, not a new config system)
/// until product confirms the canonical support-contact source.
const String _kAdminContactPhone = '01098282915';

/// Opens the existing V1 Forgot Password bottom-sheet overlay.
///
/// [phoneNumber] is the phone already typed on the Sign In form — the sheet
/// introduces no phone/email/OTP input of its own. This is NOT an automatic
/// reset: submitting records a `password_reset_requests` entry server-side
/// (via the existing `submitPasswordResetRequest` callable) so the
/// Admin/Doctor can reset the password from the Dashboard.
Future<void> showForgotPasswordSheet({
  required BuildContext context,
  required String phoneNumber,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // Explicit: drag-down and outside-tap must always dismiss.
    isDismissible: true,
    enableDrag: true,
    // Soft dim so the frosted panel reads as glass over the login screen
    // instead of vanishing into the default dark scrim.
    barrierColor: Colors.black.withValues(alpha: 0.35),
    backgroundColor: Colors.transparent,
    builder: (_) => _ForgotPasswordSheet(phoneNumber: phoneNumber),
  );
}

class _ForgotPasswordSheet extends ConsumerStatefulWidget {
  final String phoneNumber;

  const _ForgotPasswordSheet({required this.phoneNumber});

  @override
  ConsumerState<_ForgotPasswordSheet> createState() =>
      _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends ConsumerState<_ForgotPasswordSheet> {
  bool _sending = false;
  bool _submitted = false;
  String? _errorMessage;

  Future<void> _submitRequest() async {
    final phone = normalizeEgyptianPhone(widget.phoneNumber);
    if (!isValidEgyptianPhone(phone)) {
      setState(
        () => _errorMessage = 'أدخل رقم هاتفك المسجل في حقل رقم الهاتف أولاً.',
      );
      return;
    }
    setState(() {
      _sending = true;
      _errorMessage = null;
    });
    try {
      final submitted = await ref
          .read(passwordResetControllerProvider.notifier)
          .submit(phoneNumber: phone);
      if (!mounted) return;
      if (submitted) {
        setState(() => _submitted = true);
      }
    } catch (error) {
      if (!mounted) return;
      // Project-standard mapping: raw backend errors never reach the UI.
      // The backend anti-enumeration uniform success means failures here
      // are transport/validation/throttle signals only.
      setState(() => _errorMessage = friendlyErrorMessage(context, error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Figma overlay: 393x350, translucent warm off-white, white ~35% border,
    // 24px top corners, bottom-sheet presentation. Height is capped so the
    // sheet stays inside small viewports (360x640).
    final sheetHeight = context
        .rsV(350)
        .clamp(0.0, MediaQuery.sizeOf(context).height * 0.8);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      // Bottom-anchored frosted panel (was Center-anchored, which floated
      // the sheet mid-screen).
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 393),
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                height: sheetHeight,
                decoration: BoxDecoration(
                  color: const Color(0x4CFFFCF7),
                  border: Border.all(
                    color: const Color(0x59FFFFFF),
                    width: 1,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                // Explicit close affordance (web users expect it) stacked
                // over the request/success views.
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _submitted
                          ? _buildSubmittedView(context)
                          : _buildRequestView(context),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: IconButton(
                        tooltip: 'إغلاق',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Color(0xFF6B7280),
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

  Widget _buildRequestView(BuildContext context) {
    // NOTE: intentionally NOT scrollable — an inner ScrollView swallows the
    // vertical-drag gesture and breaks the sheet's drag-to-dismiss. Content
    // (~235px) always fits the 350px panel, so no scroll is needed.
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.rs(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
            SizedBox(height: context.rsV(12)),
            // Drag handle (Figma: 36x4, #E5E7EB, fully rounded, centered).
            Center(
              child: Container(
                key: const Key('forgotPasswordDragHandle'),
                width: context.rs(36),
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            SizedBox(height: context.rsV(20)),
            // Figma Arabic informational message (meaning preserved).
            const Text(
              'يمكنك التواصل مع الأدمن\nلإعادة تعيين الباسورد الخاص بكم\nعلي رقم',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Google Sans Flex',
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: Color(0xFF111827),
                height: 1.6,
              ),
            ),
            SizedBox(height: context.rsV(8)),
            const Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                _kAdminContactPhone,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Google Sans Flex',
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
            ),
            if (_errorMessage != null) ...[
              SizedBox(height: context.rsV(8)),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: context.rsFont(13),
                ),
              ),
            ],
            SizedBox(height: context.rsV(16)),
            // Explicit request action (V1 flow): submits using the phone from
            // the Sign In form. Reuses the existing 'إرسال الطلب' terminology.
            SizedBox(
              height: context.rsV(52),
              child: FilledButton(
                key: const Key('forgotPasswordSubmit'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1D4ED8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(context.rs(9999)),
                  ),
                ),
                onPressed: _sending ? null : _submitRequest,
                child: _sending
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'إرسال الطلب',
                        style: TextStyle(
                          fontFamily: 'Google Sans Flex',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
            SizedBox(height: context.rsV(16)),
          ],
        ),
      );
  }

  Widget _buildSubmittedView(BuildContext context) {
    // Reuses the existing success terminology from the V1 reset-request
    // confirmation: the request reached platform management and the password
    // is changed manually from the Dashboard. Not scrollable (see above).
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.rs(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
            SizedBox(height: context.rsV(12)),
            Center(
              child: Container(
                width: context.rs(36),
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            SizedBox(height: context.rsV(24)),
            Icon(
              Icons.mark_email_read_outlined,
              size: context.rs(56),
              color: const Color(0xFF1D4ED8),
            ),
            SizedBox(height: context.rsV(12)),
            const Text(
              'تم إرسال طلبك بنجاح',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Google Sans Flex',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827),
              ),
            ),
            SizedBox(height: context.rsV(8)),
            const Text(
              'وصل طلب استعادة كلمة المرور إلى إدارة المنصة وسيتم تغيير كلمة المرور يدويًا من لوحة التحكم.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Google Sans Flex',
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: Color(0xFF6B7280),
                height: 1.6,
              ),
            ),
            SizedBox(height: context.rsV(16)),
            SizedBox(
              height: context.rsV(52),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1D4ED8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(context.rs(9999)),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'رجوع لتسجيل الدخول',
                  style: TextStyle(
                    fontFamily: 'Google Sans Flex',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            SizedBox(height: context.rsV(16)),
          ],
        ),
      );
  }
}
