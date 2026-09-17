import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/theme/app_typography.dart';
import '../providers/student_profile_payments_provider.dart';

/// Financial summary + action strip (`Frame 187`, Figma: 864 wide,
/// centered): settlement [status badge] + numbers capsule
/// (Net Total / Paid / Balance) + `Add Payment` + `Print Invoice`.
///
/// Tapping the numbers capsule opens the Teacher-only financial-account
/// editor via [onEditAccount]; visuals are unchanged.
class StudentFinancialSummaryBar extends StatelessWidget {
  final StudentLedger ledger;
  final Color accent;
  final VoidCallback onAddPayment;
  final VoidCallback onPrintInvoice;
  final VoidCallback onEditAccount;

  const StudentFinancialSummaryBar({
    super.key,
    required this.ledger,
    required this.accent,
    required this.onAddPayment,
    required this.onPrintInvoice,
    required this.onEditAccount,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 830,
      child: Row(
        children: <Widget>[
          _StatusBadge(status: ledger.status),
          const SizedBox(width: 16),
          // Loose fit (not Expanded): the capsule hugs its content so the
          // status chip stays packed with the pill group per Figma
          // Frame 187, instead of being stranded at the strip's left edge
          // by a stretched capsule. Texts still ellipsize on narrow widths.
          Flexible(
            child: InkWell(
              onTap: onEditAccount,
              borderRadius: BorderRadius.circular(28),
              child: _NumbersCapsule(ledger: ledger),
            ),
          ),
          const SizedBox(width: 16),
          _AddPaymentButton(accent: accent, onTap: onAddPayment),
          const SizedBox(width: 12),
          _PrintInvoiceButton(onTap: onPrintInvoice),
        ],
      ),
    );
  }
}

/// Settlement badge (height 32, radius 28, padding 10 horizontal /
/// 6 vertical): 6 px dot + 14 px Regular status label on the
/// status-tinted fill, vertically centered with no text clipping.
class _StatusBadge extends StatelessWidget {
  final PaymentStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final PaymentStatusStyle style = PaymentStatusStyle.of(status);
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Color(style.background),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: Color(style.dot),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            status.label,
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w400,
              fontVariations: const <FontVariation>[
                FontVariation('wght', 400),
              ],
              color: Color(style.foreground),
            ),
          ),
        ],
      ),
    );
  }
}

/// Numbers capsule (border #979797, radius 28): gray `Net Total` pill +
/// green `Paid Amount` + red `Balance Due`, all 14 px.
class _NumbersCapsule extends StatelessWidget {
  final StudentLedger ledger;

  const _NumbersCapsule({required this.ledger});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF979797), width: 1),
      ),
      child: Row(
        children: <Widget>[
          Flexible(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF979797),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Text(
                'Net Total : ${formatEgp(ledger.netTotal)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  fontVariations: <FontVariation>[FontVariation('wght', 400)],
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              'Paid Amount : ${formatEgp(ledger.paidAmount)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 14,
                fontWeight: FontWeight.w400,
                fontVariations: <FontVariation>[FontVariation('wght', 400)],
                color: Color(0xFF15803D),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              'Balance Due : ${formatEgp(ledger.balanceDue)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 14,
                fontWeight: FontWeight.w400,
                fontVariations: <FontVariation>[FontVariation('wght', 400)],
                color: Color(0xFFDC2626),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddPaymentButton extends StatelessWidget {
  final Color accent;
  final VoidCallback onTap;

  const _AddPaymentButton({required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(28),
        ),
        alignment: Alignment.center,
        child: const Text(
          'Add Payment',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w400,
            fontVariations: <FontVariation>[FontVariation('wght', 400)],
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _PrintInvoiceButton extends StatelessWidget {
  final VoidCallback onTap;

  const _PrintInvoiceButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SvgPicture.asset(
              'assets/images/Frame.svg',
              width: 16,
              height: 16,
              colorFilter: const ColorFilter.mode(
                Color(0xFF374151),
                BlendMode.srcIn,
              ),
              semanticsLabel: 'Print invoice',
              placeholderBuilder: (BuildContext context) => const Icon(
                Icons.print_outlined,
                size: 16,
                color: Color(0xFF374151),
              ),
              errorBuilder: (
                BuildContext context,
                Object error,
                StackTrace? stackTrace,
              ) =>
                  const Icon(
                Icons.print_outlined,
                size: 16,
                color: Color(0xFF374151),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Print Invoice',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 14,
                fontWeight: FontWeight.w400,
                fontVariations: <FontVariation>[
                  FontVariation('wght', 400),
                ],
                color: Color(0xFF374151),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
