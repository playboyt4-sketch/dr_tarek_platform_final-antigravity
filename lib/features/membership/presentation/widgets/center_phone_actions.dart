import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';

/// Normalizes an Egyptian mobile/landline number for WhatsApp `wa.me` links.
///
/// Strips non-digit characters and converts local `01XXXXXXXXX` numbers
/// to `201XXXXXXXXX` (without a leading `+` or `0`).
String normalizeEgyptianWhatsAppNumber(String rawPhone) {
  final digits = rawPhone.replaceAll(RegExp(r'[^\d]'), '');
  if (digits.isEmpty) return '';
  if (digits.startsWith('01')) {
    return '20${digits.substring(1)}';
  }
  if (digits.startsWith('20')) {
    return digits;
  }
  if (digits.startsWith('0')) {
    return '20${digits.substring(1)}';
  }
  return digits;
}

Uri buildPhoneCallUri(String rawPhone) {
  final cleaned = rawPhone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
  return Uri(scheme: 'tel', path: cleaned);
}

Uri buildWhatsAppUri(String rawPhone) {
  final normalized = normalizeEgyptianWhatsAppNumber(rawPhone);
  return Uri.parse('https://wa.me/$normalized');
}

/// Interactive row of touch-friendly Copy, Call, and WhatsApp buttons
/// displayed alongside the Center support phone number.
class CenterPhoneActions extends StatelessWidget {
  final String phoneNumber;
  final bool darkSurface;

  /// Optional test seam for verifying external URI launches without platform channels.
  final Future<bool> Function(Uri uri)? launchUriOverride;

  const CenterPhoneActions({
    required this.phoneNumber,
    this.darkSurface = false,
    this.launchUriOverride,
    super.key,
  });

  Future<void> _copyPhone(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: phoneNumber));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('تم نسخ الرقم')),
      );
  }

  Future<void> _openExternal(BuildContext context, Uri uri) async {
    final launched = launchUriOverride != null
        ? await launchUriOverride!(uri)
        : await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('تعذر فتح التطبيق المطلوب على هذا الجهاز.')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = darkSurface
        ? Colors.white38
        : AppColors.primary.withValues(alpha: 0.25);
    final textColor = darkSurface ? Colors.white : AppColors.onSurface;
    final buttonStyle = OutlinedButton.styleFrom(
      foregroundColor: textColor,
      side: BorderSide(color: borderColor),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      minimumSize: const Size(0, 40),
      tapTargetSize: MaterialTapTargetSize.padded,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
    );

    return Column(
      crossAxisAlignment:
          darkSurface ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          phoneNumber,
          textDirection: TextDirection.ltr,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            height: 1.6,
            color: textColor,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment:
              darkSurface ? WrapAlignment.center : WrapAlignment.start,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('center_phone_copy_btn'),
              style: buttonStyle,
              icon: const Icon(Icons.copy_rounded, size: 17),
              label: const Text('نسخ'),
              onPressed: () => _copyPhone(context),
            ),
            OutlinedButton.icon(
              key: const ValueKey('center_phone_call_btn'),
              style: buttonStyle,
              icon: Icon(
                Icons.call_rounded,
                size: 17,
                color: darkSurface ? const Color(0xFF93C5FD) : AppColors.primary,
              ),
              label: const Text('اتصال'),
              onPressed: () => _openExternal(context, buildPhoneCallUri(phoneNumber)),
            ),
            OutlinedButton.icon(
              key: const ValueKey('center_phone_whatsapp_btn'),
              style: buttonStyle,
              icon: const Icon(
                Icons.chat_rounded,
                size: 17,
                color: Color(0xFF10B981),
              ),
              label: const Text('واتساب'),
              onPressed: () => _openExternal(context, buildWhatsAppUri(phoneNumber)),
            ),
          ],
        ),
      ],
    );
  }
}
