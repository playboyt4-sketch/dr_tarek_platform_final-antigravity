import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';

/// Payment receipt / invoice dialog with formatted layout and manual WhatsApp text sharing.
class PaymentReceiptDialog extends StatelessWidget {
  final String receiptId;
  final String studentName;
  final String studentPhone;
  final String subjectTitle;
  final num amountPaid;
  final String paymentDate;
  final String paymentMethod;
  final String? loggedBy;

  const PaymentReceiptDialog({
    required this.receiptId,
    required this.studentName,
    required this.studentPhone,
    required this.subjectTitle,
    required this.amountPaid,
    required this.paymentDate,
    this.paymentMethod = 'كاش / خارج المنصة',
    this.loggedBy,
    super.key,
  });

  String _formatWhatsAppMessage() {
    return '''
🧾 *إيصال سداد - منصة د. طارق*
---------------------------------
*رقم الإيصال:* $receiptId
*اسم الطالب:* $studentName
*رقم الهاتف:* $studentPhone
*المادة:* $subjectTitle
*المبلغ المسدد:* $amountPaid ج.م
*طريقة الدفع:* $paymentMethod
*التاريخ:* $paymentDate
---------------------------------
شكراً لاشتراككم معنا!
''';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long_rounded, color: AppColors.primary, size: 28),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'إيصال سداد رسمي',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(height: 24),
            _ReceiptRow(label: 'رقم الإيصال:', value: receiptId),
            _ReceiptRow(label: 'اسم الطالب:', value: studentName),
            _ReceiptRow(label: 'رقم الهاتف:', value: studentPhone),
            _ReceiptRow(label: 'المادة:', value: subjectTitle),
            _ReceiptRow(label: 'طريقة الدفع:', value: paymentMethod),
            _ReceiptRow(label: 'التاريخ:', value: paymentDate),
            if (loggedBy != null && loggedBy!.isNotEmpty)
              _ReceiptRow(label: 'المسؤول:', value: loggedBy!),
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'المبلغ الإجمالي:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    '$amountPaid ج.م',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _formatWhatsAppMessage()));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم نسخ نص الفاتورة لمشاركتها يدوياً عبر واتساب.')),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('نسخ للواتساب'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.check),
                    label: const Text('تم'),
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

class _ReceiptRow extends StatelessWidget {
  final String label;
  final String value;

  const _ReceiptRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
