import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/theme/app_typography.dart';
import '../providers/student_profile_payments_provider.dart';

/// Validated result of the Add Payment dialog (persistence is owned by
/// the caller — the dialog only collects + validates input).
///
/// The payment is recorded against the student's balance; it carries no
/// Subject linkage (per the Figma `#add payment` overlay, which shows no
/// Subject field).
class AddPaymentResult {
  final DateTime date;
  final PaymentMethod method;
  final int amountEgp;
  final String collectedBy;

  const AddPaymentResult({
    required this.date,
    required this.method,
    required this.amountEgp,
    required this.collectedBy,
  });
}

/// Validated result of the Correct Payment dialog: the same record keeps
/// its identity; only the supplied fields are corrected in place.
class CorrectPaymentResult {
  final String paymentId;
  final DateTime date;
  final PaymentMethod method;
  final int amountEgp;
  final String collectedBy;
  final String notes;
  final String receiptNumber;

  const CorrectPaymentResult({
    required this.paymentId,
    required this.date,
    required this.method,
    required this.amountEgp,
    required this.collectedBy,
    required this.notes,
    required this.receiptNumber,
  });
}

/// Overlay `#add payment` (Figma: 600 wide, white, radius 24):
/// title + close icon, red balance banner, fields
/// (date picker / method dropdown / numeric amount with EGP /
/// collector), Cancel + Save Payment footer.
///
/// Figma-visible fields only: Payment Date, Payment Method,
/// Payment Amount, Collected By. No Subject selector, no Notes, no
/// Receipt Number in Add mode.
///
/// The collector is never auto-filled: transcription copies the physical
/// collector's name from the paper record, never the signed-in user.
///
/// Returns the validated [AddPaymentResult] on save, null on
/// dismiss/cancel. [balanceDue] caps the accepted amount.
Future<AddPaymentResult?> showAddPaymentDialog(
  BuildContext context, {
  required Color accent,
  required int balanceDue,
}) {
  return showGeneralDialog<AddPaymentResult>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.25),
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    transitionDuration: const Duration(milliseconds: 150),
    transitionBuilder: (
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child,
    ) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );
    },
    pageBuilder: (
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
    ) {
      return Center(
        child: Material(
          color: Colors.transparent,
          child: _PaymentForm(
            accent: accent,
            balanceDue: balanceDue,
            title: 'Add Payment',
            saveLabel: 'Save Payment',
          ),
        ),
      );
    },
  );
}

/// Correction overlay for one transcribed payment: same visual language
/// as Add Payment; the subject is fixed (linkage is immutable) and the
/// stored receipt is editable. Returns [CorrectPaymentResult] on save.
Future<CorrectPaymentResult?> showCorrectPaymentDialog(
  BuildContext context, {
  required Color accent,
  required StudentPayment payment,
  required String subjectTitle,
}) {
  return showGeneralDialog<CorrectPaymentResult>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.25),
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    transitionDuration: const Duration(milliseconds: 150),
    transitionBuilder: (
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child,
    ) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );
    },
    pageBuilder: (
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
    ) {
      return Center(
        child: Material(
          color: Colors.transparent,
          child: _PaymentForm.correct(
            accent: accent,
            payment: payment,
            subjectTitle: subjectTitle,
          ),
        ),
      );
    },
  );
}

class _PaymentForm extends StatefulWidget {
  final Color accent;
  final int balanceDue;
  final String title;
  final String saveLabel;
  final StudentPayment? editing;
  final String subjectTitle;

  const _PaymentForm({
    required this.accent,
    required this.balanceDue,
    required this.title,
    required this.saveLabel,
    this.editing,
    this.subjectTitle = '',
  });

  const _PaymentForm.correct({
    required Color accent,
    required StudentPayment payment,
    required String subjectTitle,
  }) : this(
          accent: accent,
          balanceDue: 0,
          title: 'Correct Payment',
          saveLabel: 'Save Correction',
          editing: payment,
          subjectTitle: subjectTitle,
        );

  bool get _isEditing => editing != null;

  @override
  State<_PaymentForm> createState() => _PaymentFormState();
}

class _PaymentFormState extends State<_PaymentForm> {
  late DateTime _date;
  PaymentMethod? _method;
  late TextEditingController _amountController;
  late TextEditingController _collectorController;
  late TextEditingController _notesController;
  late TextEditingController _receiptController;
  String? _formError;

  @override
  void initState() {
    super.initState();
    final StudentPayment? editing = widget.editing;
    _date = editing?.date ?? DateTime.now();
    // Add mode starts unselected so the Figma `Select Method` placeholder
    // shows; correction keeps the record's stored method (or Cash legacy).
    _method = editing?.method ?? (widget._isEditing ? PaymentMethod.cash : null);
    _amountController = TextEditingController(
      text: editing != null
          ? '${editing.amountEgp}'
          : (widget.balanceDue > 0 ? '${widget.balanceDue}' : ''),
    );
    // Never auto-filled: the collector name is transcribed from paper.
    _collectorController = TextEditingController(
      text: editing != null && editing.collectedBy != '—'
          ? editing.collectedBy
          : '',
    );
    _notesController = TextEditingController(text: editing?.notes ?? '');
    _receiptController =
        TextEditingController(text: editing?.receiptNumber ?? '');
  }

  @override
  void dispose() {
    _amountController.dispose();
    _collectorController.dispose();
    _notesController.dispose();
    _receiptController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(now) ? now : _date,
      firstDate: DateTime(now.year - 5),
      // Transcribed paper dates are today or past — future is blocked.
      lastDate: now,
    );
    if (picked != null && mounted) {
      setState(() => _date = picked);
    }
  }

  void _save() {
    final int? amount = int.tryParse(_amountController.text.trim());
    String? error;
    if (amount == null || amount <= 0) {
      error = 'Enter a valid amount.';
    } else if (!widget._isEditing && amount > widget.balanceDue) {
      error = 'Amount cannot exceed the balance due.';
    }
    if (error == null && _method == null) {
      error = 'Select a payment method.';
    }
    final String collector = _collectorController.text.trim();
    if (error == null && collector.isEmpty) {
      error = 'Enter the collector name.';
    }
    if (error == null && collector.length > 100) {
      error = 'Collector name must be at most 100 characters.';
    }
    final String notes = _notesController.text.trim();
    if (error == null && notes.length > 500) {
      error = 'Notes must be at most 500 characters.';
    }
    String receipt = '';
    if (widget._isEditing) {
      receipt = _receiptController.text.trim();
      if (error == null && receipt.isEmpty) {
        error = 'Enter the receipt number.';
      }
    }
    setState(() => _formError = error);
    if (error != null) return;
    if (widget._isEditing) {
      Navigator.of(context).pop(
        CorrectPaymentResult(
          paymentId: widget.editing!.id,
          date: _date,
          method: _method!,
          amountEgp: amount!,
          collectedBy: collector,
          notes: notes,
          receiptNumber: receipt,
        ),
      );
    } else {
      Navigator.of(context).pop(
        AddPaymentResult(
          date: _date,
          method: _method!,
          amountEgp: amount!,
          collectedBy: collector,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isEditing = widget._isEditing;
    return Container(
      width: 600,
      height: isEditing ? 772 : 700,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Header Y 24: title + close.
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 32,
                    fontWeight: FontWeight.w400,
                    fontVariations: <FontVariation>[
                      FontVariation('wght', 400),
                    ],
                    color: Colors.black,
                  ),
                ),
              ),
              InkWell(
                onTap: () => Navigator.of(context).pop(),
                borderRadius: BorderRadius.circular(9999),
                child: SvgPicture.asset(
                  'assets/images/close.svg',
                  width: 24,
                  height: 24,
                  semanticsLabel: 'Close',
                ),
              ),
            ],
          ),
          // Balance banner Y 100.
          const SizedBox(height: 36),
          Center(
            child: Text(
              'Balance Due : ${formatEgp(widget.balanceDue)}',
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 14,
                fontWeight: FontWeight.w400,
                fontVariations: <FontVariation>[FontVariation('wght', 400)],
                color: Color(0xFFDC2626),
              ),
            ),
          ),
          // Fields Y 154 (container 520, spacing 16). Figma-visible Add
          // fields only: Payment Date / Payment Method / Payment Amount /
          // Collected By. Correction mode additionally shows the frozen
          // legacy subject memo (only when the record carries one),
          // Notes, and Receipt.
          const SizedBox(height: 36),
          if (isEditing && widget.subjectTitle.isNotEmpty)
            _FieldRow(
              label: 'Subject',
              child: _StaticBox(text: widget.subjectTitle),
            ),
          if (isEditing && widget.subjectTitle.isNotEmpty)
            const SizedBox(height: 16),
          _FieldRow(
            label: 'Payment Date',
            child: _DateBox(date: _date, onTap: _pickDate),
          ),
          const SizedBox(height: 16),
          _FieldRow(
            label: 'Payment Method',
            child: _MethodBox(
              method: _method,
              onChanged: (value) {
                if (value != null) setState(() => _method = value);
              },
            ),
          ),
          const SizedBox(height: 16),
          _FieldRow(
            label: 'Payment Amount',
            child: _InputBox(
              controller: _amountController,
              hint: widget.balanceDue > 0 && !isEditing
                  ? '${widget.balanceDue} EGP'
                  : '0 EGP',
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              suffix: 'EGP',
            ),
          ),
          if (_formError != null) ...<Widget>[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 160),
              child: Text(
                _formError!,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 12,
                  color: Color(0xFFDC2626),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          _FieldRow(
            label: 'Collected By',
            child: _InputBox(
              controller: _collectorController,
              hint: 'Collector name',
              maxLength: 100,
            ),
          ),
          if (isEditing) ...<Widget>[
            const SizedBox(height: 16),
            _FieldRow(
              label: 'Notes',
              child: _InputBox(
                controller: _notesController,
                hint: 'Optional notes',
                maxLength: 500,
              ),
            ),
            const SizedBox(height: 16),
            _FieldRow(
              label: 'Receipt',
              child: _InputBox(
                controller: _receiptController,
                hint: 'Receipt number',
              ),
            ),
          ],
          const Spacer(),
          // Footer: Cancel 88 x 32 + Save 112 x 32.
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              SizedBox(
                width: 88,
                height: 32,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black,
                    padding: EdgeInsets.zero,
                    side: const BorderSide(
                      color: Color(0xFF979797),
                      width: 1,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9999),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      fontVariations: <FontVariation>[
                        FontVariation('wght', 400),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 112,
                height: 32,
                child: ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.accent,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9999),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    widget.saveLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      fontVariations: <FontVariation>[
                        FontVariation('wght', 400),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Label (136 px, 14 px) + 360 x 45 input row.
class _FieldRow extends StatelessWidget {
  final String label;
  final Widget child;

  const _FieldRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 136,
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w400,
              fontVariations: <FontVariation>[FontVariation('wght', 400)],
              color: Color(0xFF111827),
            ),
          ),
        ),
        const SizedBox(width: 24),
        child,
      ],
    );
  }
}

BoxDecoration _inputDecoration({double radius = 10}) {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
  );
}

/// Read-only date box (360 x 45): formatted date + dropdown arrow that
/// opens the [showDatePicker].
class _DateBox extends StatelessWidget {
  final DateTime date;
  final VoidCallback onTap;

  const _DateBox({required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 360,
        height: 45,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: _inputDecoration(),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                formatDialogDate(date),
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 14,
                  color: Color(0xFF111827),
                ),
              ),
            ),
            SvgPicture.asset(
              'assets/images/keyboard_arrow_down.svg',
              width: 20,
              height: 20,
              semanticsLabel: 'Pick a date',
            ),
          ],
        ),
      ),
    );
  }
}

/// Static read-only box (360 x 45) for immutable values (subject in
/// correction mode — record linkage never changes).
class _StaticBox extends StatelessWidget {
  final String text;

  const _StaticBox({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 360,
      height: 45,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      decoration: _inputDecoration(),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 14,
          color: Color(0xFF6B7280),
        ),
      ),
    );
  }
}

/// Method dropdown (360 x 45): Cash / E-Wallet / InstaPay / Bank + arrow.
///
/// Values are the canonical transcription enum; labels are the Figma
/// display labels (`Bank` kept verbatim). The method is descriptive
/// only. A null [method] renders the Figma `Select Method` placeholder.
class _MethodBox extends StatelessWidget {
  final PaymentMethod? method;
  final ValueChanged<PaymentMethod?> onChanged;

  const _MethodBox({required this.method, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 360,
      height: 45,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: _inputDecoration(),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<PaymentMethod>(
          value: method,
          isExpanded: true,
          hint: const Text(
            'Select Method',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 14,
              color: Color(0xFF9CA3AF),
            ),
          ),
          onChanged: onChanged,
          icon: SvgPicture.asset(
            'assets/images/keyboard_arrow_down.svg',
            width: 20,
            height: 20,
            semanticsLabel: 'Pick a method',
          ),
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 14,
            color: Color(0xFF111827),
          ),
          items: <DropdownMenuItem<PaymentMethod>>[
            for (final PaymentMethod option in PaymentMethod.values)
              DropdownMenuItem<PaymentMethod>(
                value: option,
                child: Text(option.label),
              ),
          ],
        ),
      ),
    );
  }
}

/// Text input box (360 x 45, radius 12) with optional EGP suffix and
/// optional length cap (counter hidden to preserve the Figma look).
class _InputBox extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? suffix;
  final int? maxLength;

  const _InputBox({
    required this.controller,
    required this.hint,
    this.keyboardType = TextInputType.text,
    this.inputFormatters,
    this.suffix,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 360,
      height: 45,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: _inputDecoration(radius: 12),
      alignment: Alignment.center,
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        maxLength: maxLength,
        style: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 14,
          color: Color(0xFF111827),
        ),
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          hintText: hint,
          hintStyle: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 14,
            color: Color(0xFF9CA3AF),
          ),
          suffixText: suffix,
          suffixStyle: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 14,
            color: Color(0xFF6B7280),
          ),
          counterText: '',
        ),
      ),
    );
  }
}
