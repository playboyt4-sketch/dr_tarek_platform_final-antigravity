import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../../core/theme/app_typography.dart';
import '../providers/grade_students_provider.dart' show GradeStudent;
import '../providers/student_profile_payments_provider.dart';
import '../providers/student_profile_subjects_provider.dart';
import '../providers/student_subject_pricing_provider.dart';
import '../screens/grade_students_screen.dart' show gradeAccent;
import '../widgets/add_payment_dialog.dart';
import '../widgets/grade_theme.dart';
import '../widgets/student_financial_summary_bar.dart';

/// Student Profile → Payments tab content (student-level finance).
///
/// Renders below the persistent profile header (inside the 830-wide
/// dynamic body): financial summary strip → payments history table.
/// Totals ([StudentLedger]) derive from the single student financial
/// account plus the transcribed payments; Add Payment records via
/// [StudentPaymentsController]; Print Invoice renders a PDF statement
/// via [buildInvoicePdf]. Tapping the summary numbers opens the
/// Doctor-only Price/Discount editor for the student account.
class StudentProfilePaymentsTab extends ConsumerStatefulWidget {
  final GradeStudent student;
  final String gradeKey;

  const StudentProfilePaymentsTab({
    super.key,
    required this.student,
    required this.gradeKey,
  });

  @override
  ConsumerState<StudentProfilePaymentsTab> createState() =>
      _StudentProfilePaymentsTabState();
}

class _StudentProfilePaymentsTabState
    extends ConsumerState<StudentProfilePaymentsTab> {
  String get _gradeKey => GradeTheme.fromKey(widget.gradeKey).gradeId;
  Color get _accent => gradeAccent(_gradeKey);
  String get _gradeLabel => GradeTheme.fromKey(_gradeKey).title;

  Future<void> _openAddPayment(StudentLedger ledger) async {
    if (!mounted) return;
    final AddPaymentResult? result = await showAddPaymentDialog(
      context,
      accent: _accent,
      balanceDue: ledger.balanceDue,
    );
    if (result == null || !mounted) return;
    try {
      await ref.read(studentPaymentsControllerProvider).recordPayment(
            studentId: widget.student.id,
            date: result.date,
            amountEgp: result.amountEgp,
            method: result.method,
            collectedBy: result.collectedBy,
          );
      ref.invalidate(studentLedgerProvider(widget.student.id));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment recorded.')),
      );
    } catch (e) {
      if (!mounted) return;
      final String text = e.toString();
      const String prefix = 'PaymentFailure: ';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            text.startsWith(prefix)
                ? text.substring(prefix.length)
                : 'Could not record the payment.',
          ),
        ),
      );
    }
  }

  Future<void> _openCorrectPayment(
    StudentPayment payment,
  ) async {
    // Display-only resolution of a historical subject memo to its title;
    // never used for finance. New subject-less payments show no subject.
    String subjectTitle = '';
    if (payment.subjectId.isNotEmpty) {
      final AsyncValue<List<StudentSubjectRegistration>> regsAsync =
          ref.read(studentProfileSubjectsProvider(widget.student.id));
      final List<StudentSubjectRegistration> regs =
          regsAsync is AsyncData<List<StudentSubjectRegistration>>
              ? regsAsync.value
              : const <StudentSubjectRegistration>[];
      for (final StudentSubjectRegistration reg in regs) {
        if (reg.subjectId == payment.subjectId) {
          subjectTitle = reg.title;
          break;
        }
      }
    }
    final CorrectPaymentResult? result = await showCorrectPaymentDialog(
      context,
      accent: _accent,
      payment: payment,
      subjectTitle: subjectTitle,
    );
    if (result == null || !mounted) return;
    try {
      await ref.read(studentPaymentsControllerProvider).correctPayment(
            paymentId: result.paymentId,
            amountEgp: result.amountEgp,
            method: result.method,
            collectedBy: result.collectedBy,
            date: result.date,
            receiptNumber: result.receiptNumber,
            notes: result.notes,
          );
      ref.invalidate(studentLedgerProvider(widget.student.id));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment corrected.')),
      );
    } catch (e) {
      if (!mounted) return;
      final String text = e.toString();
      const String prefix = 'PaymentFailure: ';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            text.startsWith(prefix)
                ? text.substring(prefix.length)
                : 'Could not correct the payment.',
          ),
        ),
      );
    }
  }

  /// Doctor-only Price/Discount editor for the student's single
  /// financial account (opened by tapping the summary numbers).
  Future<void> _openAccountEditor(StudentLedger ledger) async {
    final _AccountResult? result = await showDialog<_AccountResult>(
      context: context,
      builder: (BuildContext context) =>
          _AccountDialog(account: ledger.account),
    );
    if (result == null || !mounted) return;
    try {
      await ref.read(studentPaymentsControllerProvider).setAccount(
            studentId: widget.student.id,
            priceEgp: result.priceEgp,
            discountEgp: result.discountEgp,
          );
      ref.invalidate(studentLedgerProvider(widget.student.id));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Financial account saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      final String text = e.toString();
      const String prefix = 'PaymentFailure: ';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            text.startsWith(prefix)
                ? text.substring(prefix.length)
                : 'Could not save the financial account.',
          ),
        ),
      );
    }
  }

  /// Doctor-only Price/Discount editor for one subject's manual
  /// pricing reference (opened by tapping a Subjects-table row). Writes
  /// go through `setStudentSubjectPricing`; the student ledger is never
  /// touched by subject pricing.
  Future<void> _openPricingEditor(StudentPricedSubject row) async {
    final _SubjectPricingResult? result =
        await showDialog<_SubjectPricingResult>(
      context: context,
      builder: (BuildContext context) =>
          _SubjectPricingDialog(row: row),
    );
    if (result == null || !mounted) return;
    try {
      await ref.read(studentSubjectPricingControllerProvider).setPricing(
            studentId: widget.student.id,
            subjectId: row.subjectId,
            priceEgp: result.priceEgp,
            discountEgp: result.discountEgp,
          );
      ref.invalidate(studentPricedSubjectsProvider(widget.student.id));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Subject pricing saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      final String text = e.toString();
      const String prefix = 'PaymentFailure: ';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            text.startsWith(prefix)
                ? text.substring(prefix.length)
                : 'Could not save the subject pricing.',
          ),
        ),
      );
    }
  }

  Future<void> _printInvoice(StudentLedger ledger) async {    final Uint8List bytes = await buildInvoicePdf(
      studentName: widget.student.name,
      phone: widget.student.phone ?? '—',
      gradeLabel: _gradeLabel,
      dateLabel: widget.student.lastSignIn,
      ledger: ledger,
    );
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'invoice-${widget.student.id}.pdf',
    );
  }

  /// Guest students have no financial account and no payments — the
  /// whole tab stays empty for them (no pricing table, no summary, no
  /// Add Payment / Print Invoice actions).
  bool get _isGuest => !widget.student.isCenter;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<StudentLedger> ledgerAsync =
        ref.watch(studentLedgerProvider(widget.student.id));
    final AsyncValue<List<StudentPricedSubject>> pricedAsync =
        ref.watch(studentPricedSubjectsProvider(widget.student.id));

    if (_isGuest) {
      return SizedBox(
        width: 830,
        child: Column(
          children: <Widget>[
            Container(
              width: 830,
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: const Text(
                'Guest student — no payments, guest access only.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 14,
                  color: Color(0xFF6B7280),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: 830,
              decoration: _cardDecoration(),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No payments for guest students.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 14,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      width: 830,
      child: ledgerAsync.when(
        loading: () => const SizedBox(
          height: 200,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, stackTrace) {
          // TEMPORARY diagnostic: the real exception (Firebase code and
          // message) is printed to console; the UI below is unchanged.
          // Remove once the ledger root cause is fixed.
          debugPrint(
            '[PaymentsTab] ledger failed (${error.runtimeType}): $error',
          );
          debugPrint('[PaymentsTab] stack: $stackTrace');
          return SizedBox(
          height: 200,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text(
                  'تعذّر تحميل الحساب المالي للطالب.',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 14,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => ref.invalidate(
                    studentLedgerProvider(widget.student.id),
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
          );
        },
        data: (ledger) => Column(
          children: <Widget>[
            // Figma order: Subjects table first, then Payment Summary,
            // then Payment History. Widgets themselves are unchanged —
            // only their vertical position moved.
            // Table 1 — subjects with manual Doctor-entered
            // Price/Discount/Net (display/reference only; tapping a row
            // opens the per-subject pricing editor). Never feeds Paid or
            // Balance — those stay student-level in [StudentLedger].
            _SubjectPricingSection(
              pricedAsync: pricedAsync,
              onEdit: (row) => _openPricingEditor(row),
              onRetry: () => ref.invalidate(
                studentPricedSubjectsProvider(widget.student.id),
              ),
            ),
            const SizedBox(height: 24),
            // Financial summary + actions (Y 658). Tapping the numbers
            // opens the Doctor-only account editor; visuals unchanged.
            StudentFinancialSummaryBar(
              ledger: ledger,
              accent: _accent,
              onAddPayment: () => _openAddPayment(ledger),
              onPrintInvoice: () => _printInvoice(ledger),
              onEditAccount: () => _openAccountEditor(ledger),
            ),
            const SizedBox(height: 24),
            // Table 2 — payments history (Y 714). Tapping a row opens
            // the Doctor-only in-place correction for that record.
            _PaymentsHistoryTable(
              payments: ledger.payments,
              onCorrect: (payment) => _openCorrectPayment(payment),
            ),
          ],
        ),
      ),
    );
  }
}

/// Validated Price/Discount result for the student's single account.
class _AccountResult {
  final int priceEgp;
  final int discountEgp;

  const _AccountResult({required this.priceEgp, required this.discountEgp});
}

/// Doctor-only Price/Discount editor dialog for the student account.
class _AccountDialog extends StatefulWidget {
  final StudentFinancialAccount? account;

  const _AccountDialog({required this.account});

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  late final TextEditingController _priceController;
  late final TextEditingController _discountController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _priceController =
        TextEditingController(text: '${widget.account?.priceEgp ?? 0}');
    _discountController =
        TextEditingController(text: '${widget.account?.discountEgp ?? 0}');
  }

  @override
  void dispose() {
    _priceController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  void _save() {
    final int? price = int.tryParse(_priceController.text.trim());
    final int? discount = int.tryParse(_discountController.text.trim());
    String? error;
    if (price == null || price < 0) {
      error = 'Enter a valid price.';
    } else if (discount == null || discount < 0) {
      error = 'Enter a valid discount.';
    } else if (discount > price) {
      error = 'Discount must not exceed price.';
    }
    setState(() => _error = error);
    if (error != null) return;
    Navigator.of(context).pop(
      _AccountResult(priceEgp: price!, discountEgp: discount!),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Financial Account',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _priceController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Price (EGP)',
              suffixText: 'EGP',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _discountController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Discount (EGP)',
              suffixText: 'EGP',
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Table 1 — subjects section wrapper: renders the manual-pricing table
/// once loaded, a spinner while loading, and a retry state on error.
/// Loading/error here never blocks the summary strip or history table.
class _SubjectPricingSection extends StatelessWidget {
  final AsyncValue<List<StudentPricedSubject>> pricedAsync;
  final ValueChanged<StudentPricedSubject> onEdit;
  final VoidCallback onRetry;

  const _SubjectPricingSection({
    required this.pricedAsync,
    required this.onEdit,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return pricedAsync.when(
      loading: () => Container(
        width: 830,
        height: 120,
        decoration: _cardDecoration(),
        child: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => Container(
        width: 830,
        decoration: _cardDecoration(),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                'تعذّر تحميل أسعار المواد.',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 14,
                  color: Color(0xFF6B7280),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      data: (rows) => _SubjectPricingTable(rows: rows, onEdit: onEdit),
    );
  }
}

/// Table 1 — subjects with manual pricing (830 wide, same card language
/// as the history table): No. 56 | Subjects 222 | Grade 150 |
/// Price 120 | Discount 120 | Net 120. Unpriced rows show `—`. The Grade
/// column is 150 wide so the full `Grade Three` label at the shared 24 px
/// cell style never truncates (previously 136 wide: "Grade Thr...").
class _SubjectPricingTable extends StatelessWidget {
  final List<StudentPricedSubject> rows;
  final ValueChanged<StudentPricedSubject> onEdit;

  const _SubjectPricingTable({
    required this.rows,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 830,
      decoration: _cardDecoration(),
      child: Column(
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.all(8),
            child: Row(
              children: <Widget>[
                SizedBox(width: 56, child: _PaymentsHeaderLabel('No.')),
                SizedBox(
                    width: 222, child: _PaymentsHeaderLabel('Subjects')),
                SizedBox(width: 150, child: _PaymentsHeaderLabel('Grade')),
                SizedBox(width: 120, child: _PaymentsHeaderLabel('Price')),
                SizedBox(
                    width: 120, child: _PaymentsHeaderLabel('Discount')),
                SizedBox(width: 120, child: _PaymentsHeaderLabel('Net')),
              ],
            ),
          ),
          Container(height: 1, color: const Color(0xFFE5E7EB)),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'لا توجد مواد مسجلة لهذا الطالب بعد.',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 14,
                  color: Color(0xFF6B7280),
                ),
              ),
            )
          else
            for (int i = 0; i < rows.length; i++)
              _SubjectPricingDataRow(
                index: i,
                row: rows[i],
                onTap: () => onEdit(rows[i]),
              ),
        ],
      ),
    );
  }
}

class _SubjectPricingDataRow extends StatelessWidget {
  final int index;
  final StudentPricedSubject row;
  final VoidCallback onTap;

  const _SubjectPricingDataRow({
    required this.index,
    required this.row,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final String number = (index + 1).toString().padLeft(2, '0');
    final TextStyle style = _cellStyle();
    final StudentSubjectPricing? pricing = row.pricing;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 56,
              child:
                  Text('$number.', textAlign: TextAlign.center, style: style),
            ),
            SizedBox(
              width: 222,
              child: Text(
                row.title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
            SizedBox(
              width: 150,
              child: Text(
                GradeTheme.subjectGradeLabel(row.gradeKey),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
            SizedBox(
              width: 120,
              child: Text(
                pricing == null ? '—' : formatEgp(pricing.priceEgp),
                textAlign: TextAlign.center,
                style: style,
              ),
            ),
            SizedBox(
              width: 120,
              child: Text(
                pricing == null ? '—' : formatEgp(pricing.discountEgp),
                textAlign: TextAlign.center,
                style: style,
              ),
            ),
            SizedBox(
              width: 120,
              child: Text(
                pricing == null ? '—' : formatEgp(pricing.netEgp),
                textAlign: TextAlign.center,
                style: style,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Validated Price/Discount result for one subject's manual pricing.
class _SubjectPricingResult {
  final int priceEgp;
  final int discountEgp;

  const _SubjectPricingResult(
      {required this.priceEgp, required this.discountEgp});
}

/// Doctor-only Price/Discount editor dialog for one subject. Prefills
/// the stored pricing when present (blank/0 when unpriced); Net is
/// always server-derived and is never entered here.
class _SubjectPricingDialog extends StatefulWidget {
  final StudentPricedSubject row;

  const _SubjectPricingDialog({required this.row});

  @override
  State<_SubjectPricingDialog> createState() => _SubjectPricingDialogState();
}

class _SubjectPricingDialogState extends State<_SubjectPricingDialog> {
  late final TextEditingController _priceController;
  late final TextEditingController _discountController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _priceController =
        TextEditingController(text: '${widget.row.pricing?.priceEgp ?? 0}');
    _discountController =
        TextEditingController(text: '${widget.row.pricing?.discountEgp ?? 0}');
  }

  @override
  void dispose() {
    _priceController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  void _save() {
    final int? price = int.tryParse(_priceController.text.trim());
    final int? discount = int.tryParse(_discountController.text.trim());
    String? error;
    if (price == null || price < 0) {
      error = 'Enter a valid price.';
    } else if (discount == null || discount < 0) {
      error = 'Enter a valid discount.';
    } else if (discount > price) {
      error = 'Discount must not exceed price.';
    }
    setState(() => _error = error);
    if (error != null) return;
    Navigator.of(context).pop(
      _SubjectPricingResult(priceEgp: price!, discountEgp: discount!),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.row.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _priceController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Price (EGP)',
              suffixText: 'EGP',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _discountController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Discount (EGP)',
              suffixText: 'EGP',
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

BoxDecoration _cardDecoration() {
  return BoxDecoration(
    color: Colors.white,
    border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
    borderRadius: BorderRadius.circular(16),
    boxShadow: const <BoxShadow>[
      BoxShadow(
        color: Color(0x3F000000),
        blurRadius: 4,
        offset: Offset(0, 4),
      ),
    ],
  );
}

class _PaymentsHeaderLabel extends StatelessWidget {
  final String text;

  const _PaymentsHeaderLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontFamily: AppTypography.fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        fontVariations: <FontVariation>[FontVariation('wght', 400)],
        color: Color(0xFF6B7280),
      ),
    );
  }
}

TextStyle _cellStyle() {
  return const TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    fontVariations: <FontVariation>[FontVariation('wght', 400)],
    color: Colors.black,
  );
}

/// Table 2 — payments history (830): No. 56 | Payment Date 306 |
/// Amount 116 | Method 116 | Collected By 116.
class _PaymentsHistoryTable extends StatelessWidget {
  final List<StudentPayment> payments;
  final ValueChanged<StudentPayment> onCorrect;

  const _PaymentsHistoryTable({
    required this.payments,
    required this.onCorrect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 830,
      decoration: _cardDecoration(),
      child: Column(
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.all(8),
            child: Row(
              children: <Widget>[
                SizedBox(width: 56, child: _PaymentsHeaderLabel('No.')),
                SizedBox(
                    width: 306, child: _PaymentsHeaderLabel('Payment Date')),
                SizedBox(width: 116, child: _PaymentsHeaderLabel('Amount')),
                SizedBox(width: 116, child: _PaymentsHeaderLabel('Method')),
                SizedBox(
                    width: 116, child: _PaymentsHeaderLabel('Collected By')),
              ],
            ),
          ),
          Container(height: 1, color: const Color(0xFFE5E7EB)),
          if (payments.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'لا توجد دفعات مسجلة لهذا الطالب بعد.',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 14,
                  color: Color(0xFF6B7280),
                ),
              ),
            )
          else
            for (int i = 0; i < payments.length; i++)
              _PaymentDataRow(
                index: i,
                payment: payments[i],
                onTap: () => onCorrect(payments[i]),
              ),
        ],
      ),
    );
  }
}

class _PaymentDataRow extends StatelessWidget {
  final int index;
  final StudentPayment payment;
  final VoidCallback onTap;

  const _PaymentDataRow({
    required this.index,
    required this.payment,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final String number = (index + 1).toString().padLeft(2, '0');
    final TextStyle style = _cellStyle();
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 56,
              child: Text('$number.', textAlign: TextAlign.center, style: style),
            ),
            SizedBox(
              width: 306,
              child: Text(
                formatLedgerDate(payment.date),
                textAlign: TextAlign.center,
                style: style,
              ),
            ),
            SizedBox(
              width: 116,
              child: Text(
                formatEgp(payment.amountEgp),
                textAlign: TextAlign.center,
                style: style,
              ),
            ),
            SizedBox(
              width: 116,
              child: Text(
                payment.methodLabel,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
            SizedBox(
              width: 116,
              child: Text(
                payment.collectedBy,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Builds the printable invoice statement PDF: student header, the
/// single financial account (price/discount/net), Net/Paid/Balance
/// totals, and the payments history with dates and collectors.
Future<Uint8List> buildInvoicePdf({
  required String studentName,
  required String phone,
  required String gradeLabel,
  required String dateLabel,
  required StudentLedger ledger,
}) async {
  final pw.Document doc = pw.Document();
  final pw.TextStyle headerStyle = pw.TextStyle(
    fontSize: 10,
    fontWeight: pw.FontWeight.bold,
  );

  doc.addPage(
    pw.Page(
      build: (pw.Context context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text(
            'Tarek el araby Platform — Invoice',
            style: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Text('Student: $studentName'),
          pw.Text('Phone: $phone    Grade: $gradeLabel    Date: $dateLabel'),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headerStyle: headerStyle,
            headers: const <String>[
              'Price',
              'Discount',
              'Net'
            ],
            data: <List<String>>[
              <String>[
                formatEgp(ledger.account?.priceEgp ?? 0),
                formatEgp(ledger.account?.discountEgp ?? 0),
                formatEgp(ledger.netTotal),
              ],
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Text('Net Total: ${formatEgp(ledger.netTotal)}'),
          pw.Text('Paid Amount: ${formatEgp(ledger.paidAmount)}'),
          pw.Text('Balance Due: ${formatEgp(ledger.balanceDue)}'),
          pw.SizedBox(height: 16),
          pw.Text(
            'Payments History',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headerStyle: headerStyle,
            headers: const <String>[
              'No.',
              'Date',
              'Amount',
              'Method',
              'Collected By'
            ],
            data: <List<String>>[
              for (int i = 0; i < ledger.payments.length; i++)
                <String>[
                  '${i + 1}',
                  formatLedgerDate(ledger.payments[i].date),
                  formatEgp(ledger.payments[i].amountEgp),
                  ledger.payments[i].methodLabel,
                  ledger.payments[i].collectedBy,
                ],
            ],
          ),
        ],
      ),
    ),
  );
  return doc.save();
}
