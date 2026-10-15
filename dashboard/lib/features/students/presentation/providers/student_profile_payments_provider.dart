import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/firebase_providers.dart';

/// Settlement state derived from the ledger totals.
enum PaymentStatus {
  unpaid,
  partial,
  paid,
}

/// Presentation of a [PaymentStatus] badge (see [PaymentStatusStyle]).
extension PaymentStatusLabel on PaymentStatus {
  String get label => switch (this) {
        PaymentStatus.paid => 'Fully Paid',
        PaymentStatus.partial => 'Partially Paid',
        PaymentStatus.unpaid => 'Unpaid',
      };
}

/// Badge colors for a [PaymentStatus] (plain data to keep `material`
/// out of the provider layer; widgets map these hexes to [Color]).
///
/// Labels: paid → `Fully Paid`, partial → `Partially Paid`,
/// unpaid → `Unpaid`. Fills follow the 100-scale pairs (emerald /
/// amber / red) with matching 700-scale ink + dot.
class PaymentStatusStyle {
  final int background;
  final int foreground;
  final int dot;

  const PaymentStatusStyle({
    required this.background,
    required this.foreground,
    required this.dot,
  });

  static PaymentStatusStyle of(PaymentStatus status) => switch (status) {
        PaymentStatus.paid => const PaymentStatusStyle(
            background: 0xFFD1FAE5,
            foreground: 0xFF059669,
            dot: 0xFF059669,
          ),
        PaymentStatus.partial => const PaymentStatusStyle(
            background: 0xFFFEF3C7,
            foreground: 0xFFB45309,
            dot: 0xFFB45309,
          ),
        PaymentStatus.unpaid => const PaymentStatusStyle(
            background: 0xFFFEE2E2,
            foreground: 0xFFB91C1C,
            dot: 0xFFB91C1C,
          ),
      };
}

/// Canonical payment method (Payment Transcription ADR).
///
/// Wire values are exactly `cash` / `e_wallet` / `instapay` / `bank`;
/// the method is descriptive only — no payment logic may depend on it.
/// `bank` is kept verbatim as the Figma payment history displays it.
enum PaymentMethod {
  cash,
  eWallet,
  instapay,
  bank,
}

/// Canonical wire value (`cash`, `e_wallet`, `instapay`, `bank`).
extension PaymentMethodWire on PaymentMethod {
  String get wire => switch (this) {
        PaymentMethod.cash => 'cash',
        PaymentMethod.eWallet => 'e_wallet',
        PaymentMethod.instapay => 'instapay',
        PaymentMethod.bank => 'bank',
      };

  /// Figma display label (`Cash`, `E-Wallet`, `InstaPay`, `Bank`).
  String get label => switch (this) {
        PaymentMethod.cash => 'Cash',
        PaymentMethod.eWallet => 'E-Wallet',
        PaymentMethod.instapay => 'InstaPay',
        PaymentMethod.bank => 'Bank',
      };

  /// Parses a transcribed wire value (case-insensitive, trimmed).
  /// Returns null for missing/unknown values (legacy rows predate the
  /// approved transcription schema and render as `—`).
  static PaymentMethod? parse(Object? raw) {
    if (raw is! String) return null;
    switch (raw.trim().toLowerCase()) {
      case 'cash':
        return PaymentMethod.cash;
      case 'e_wallet':
      case 'ewallet':
      case 'e-wallet':
        return PaymentMethod.eWallet;
      case 'instapay':
      case 'insta_pay':
      case 'insta-pay':
        return PaymentMethod.instapay;
      case 'bank':
        return PaymentMethod.bank;
      default:
        return null;
    }
  }
}

/// One transcribed payment from the approved `payment_logs` collection.
///
/// The transaction is student-level. `subjectId` carries the legacy
/// `subject_id` memo when present on historical rows and is never used
/// for totals, caps, or grouping.
class StudentPayment {
  final String id;
  final String subjectId;
  final DateTime date;
  final int amountEgp;
  final PaymentMethod? method;
  final String collectedBy;
  final String receiptNumber;
  final String? notes;

  const StudentPayment({
    required this.id,
    required this.subjectId,
    required this.date,
    required this.amountEgp,
    required this.method,
    required this.collectedBy,
    required this.receiptNumber,
    required this.notes,
  });

  /// Display label for the transcribed method; legacy rows without an
  /// approved method render as `—` instead of invented data.
  String get methodLabel => method?.label ?? '—';

  /// Defensive parse against the approved `payment_logs` schema
  /// (`onPaymentLogged` contract). Unparseable amounts resolve to 0
  /// (ignored by totals) instead of throwing, so one malformed row can
  /// never fail the whole ledger stream.
  factory StudentPayment.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> data = doc.data();
    final String collector =
        ((data['collected_by'] as String?) ?? '').trim();
    final String receipt =
        ((data['receipt_number'] as String?) ?? '').trim();
    return StudentPayment(
      id: doc.id,
      subjectId: (data['subject_id'] as String?) ?? '',
      date: _parseDate(
        data['payment_date'] ?? data['created_at'],
      ),
      amountEgp: _parseAmount(data['amount']),
      method: PaymentMethodWire.parse(data['payment_method']),
      collectedBy: collector.isEmpty ? '—' : collector,
      receiptNumber: receipt,
      notes: (data['notes'] as String?)?.trim(),
    );
  }

  static DateTime _parseDate(Object? raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is String && raw.isNotEmpty) {
      final DateTime? parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed;
    }
    return DateTime.now();
  }

  static int _parseAmount(Object? raw) {
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw) ?? 0;
    return 0;
  }
}

/// The single student-level financial record
/// (`student_financial_accounts/{studentId}`).
///
/// Price/Discount are Doctor-entered for the student; Net = Price −
/// Discount. Accounting is independent from membership/subscriptions.
/// A missing record resolves to a zero Net instead of invented values.
class StudentFinancialAccount {
  final String studentId;
  final int priceEgp;
  final int discountEgp;
  final int netEgp;

  const StudentFinancialAccount({
    required this.studentId,
    required this.priceEgp,
    required this.discountEgp,
    required this.netEgp,
  });

  factory StudentFinancialAccount.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> data = doc.data() ?? <String, dynamic>{};
    final int price = _asInt(data['price_egp']);
    final int discount = _asInt(data['discount_egp']);
    final Object? netRaw = data['net_egp'];
    final int net = netRaw is num
        ? netRaw.toInt()
        : (price - discount).clamp(0, 1 << 31);
    return StudentFinancialAccount(
      studentId: (data['student_id'] as String?) ?? doc.id,
      priceEgp: price,
      discountEgp: discount,
      netEgp: net,
    );
  }

  static int _asInt(Object? raw) {
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw) ?? 0;
    return 0;
  }
}

/// Full financial picture for one student (student-level only).
class StudentLedger {
  final StudentFinancialAccount? account;
  final List<StudentPayment> payments;

  const StudentLedger({
    required this.account,
    required this.payments,
  });

  const StudentLedger.empty()
      : account = null,
        payments = const <StudentPayment>[];

  /// Net Total = the student financial account Net (0 when no account).
  int get netTotal => account?.netEgp ?? 0;

  int get _rawPaid =>
      payments.fold(0, (total, payment) => total + payment.amountEgp);

  /// Paid Amount = Σ recorded payments, clamped so a Paid > Net state is
  /// never displayed (server guards new writes; the clamp covers legacy
  /// rows transcribed before the over-Net rule).
  int get paidAmount {
    final int raw = _rawPaid;
    if (netTotal <= 0) return raw;
    return raw > netTotal ? netTotal : raw;
  }

  /// Balance Due = Net Total − Paid Amount (floored at 0).
  int get balanceDue =>
      (netTotal - paidAmount).clamp(0, 1 << 31);

  PaymentStatus get status {
    if (paidAmount > 0 && balanceDue > 0) return PaymentStatus.partial;
    if (balanceDue == 0 && netTotal > 0) return PaymentStatus.paid;
    return PaymentStatus.unpaid;
  }
}

/// Pure ledger assembly (unit-testable): the student financial account
/// plus the transcribed payments. No Subject participates.
StudentLedger buildStudentLedger({
  required StudentFinancialAccount? account,
  required List<StudentPayment> payments,
}) {
  return StudentLedger(
    account: account,
    payments: List<StudentPayment>.unmodifiable(payments),
  );
}

/// `500 EGP` money format used across the Payments tab.
String formatEgp(int amount) => '$amount EGP';

/// `9/9/2026` day-first format used by the history table.
String formatLedgerDate(DateTime date) =>
    '${date.day}/${date.month}/${date.year}';

const List<String> _months = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// `Sep 9, 2026` format used by the Add Payment date field.
String formatDialogDate(DateTime date) =>
    '${_months[date.month - 1]} ${date.day}, ${date.year}';

/// Pure oldest → newest sort (unit-testable): display order for the
/// Payment History table. The Firestore query is where-only (no composite
/// index required); ordering happens here.
List<StudentPayment> sortPaymentsOldestNewest(
  List<StudentPayment> payments,
) {
  final List<StudentPayment> sorted = List<StudentPayment>.of(payments)
    ..sort((a, b) => a.date.compareTo(b.date));
  return sorted;
}

/// Transcribed payments for one student (approved `payment_logs`
/// collection).
///
/// Where-only query (`student_id`); soft-delete filtering and oldest →
/// newest ordering are applied client-side so no composite index is
/// required (the approved `payment_logs` index only covers DESC).
final studentPaymentsProvider =
    StreamProvider.family<List<StudentPayment>, String>((ref, studentId) {
  final FirebaseFirestore db = ref.watch(firebaseFirestoreProvider);
  return db
      .collection('payment_logs')
      .where('student_id', isEqualTo: studentId)
      .snapshots()
      .map(
        (QuerySnapshot<Map<String, dynamic>> snap) {
          return sortPaymentsOldestNewest(
            snap.docs
                .where((doc) => doc.data()['is_deleted'] != true)
                .map(StudentPayment.fromDoc)
                .toList(growable: false),
          );
        },
      );
});

/// The single student-level financial record
/// (`student_financial_accounts/{studentId}`).
///
/// Direct document read (no composite index required); a missing or
/// soft-deleted document resolves to null (zero Net downstream).
final studentFinancialAccountProvider =
    StreamProvider.family<StudentFinancialAccount?, String>(
        (ref, studentId) {
  final FirebaseFirestore db = ref.watch(firebaseFirestoreProvider);
  return db
      .collection('student_financial_accounts')
      .doc(studentId)
      .snapshots()
      .map(
        (DocumentSnapshot<Map<String, dynamic>> snap) {
          if (!snap.exists) return null;
          final Map<String, dynamic> data =
              snap.data() ?? <String, dynamic>{};
          if (data['is_deleted'] == true) return null;
          return StudentFinancialAccount.fromDoc(snap);
        },
      );
});

/// Ledger provider: joins the student financial account (price/discount)
/// with the transcribed payments into one [StudentLedger]. Loading/error
/// states of the underlying streams propagate honestly.
final studentLedgerProvider =
    Provider.family<AsyncValue<StudentLedger>, String>((ref, studentId) {
  final AsyncValue<StudentFinancialAccount?> account =
      ref.watch(studentFinancialAccountProvider(studentId));
  final AsyncValue<List<StudentPayment>> pays =
      ref.watch(studentPaymentsProvider(studentId));
  if (account is AsyncLoading || pays is AsyncLoading) {
    return const AsyncLoading<StudentLedger>();
  }
  if (account is AsyncError) {
    // TEMPORARY diagnostic: identifies which fan-in source failed the
    // ledger. Does not alter propagation. Remove once root cause is fixed.
    debugPrint(
      '[PaymentsLedger] account failed (${account.error.runtimeType}): ${account.error}',
    );
    return AsyncError<StudentLedger>(
        account.error!, account.stackTrace ?? StackTrace.empty);
  }
  if (pays is AsyncError) {
    // TEMPORARY diagnostic: see above.
    debugPrint(
      '[PaymentsLedger] pays failed (${pays.error.runtimeType}): ${pays.error}',
    );
    return AsyncError<StudentLedger>(pays.error!, pays.stackTrace ?? StackTrace.empty);
  }
  return AsyncData<StudentLedger>(
    buildStudentLedger(
      account: account is AsyncData<StudentFinancialAccount?>
          ? account.value
          : null,
      payments: pays.value ?? const <StudentPayment>[],
    ),
  );
});

/// Payment writes for the Student Profile → Payments tab.
///
/// Records via the approved `onPaymentLogged` callable (Doctor-only,
/// transcription of external paper records) and corrects via the
/// approved `correctPaymentLog` callable (Doctor-only, in-place).
/// The financial account goes through `setStudentFinancialAccount`
/// (Doctor-only, one account per student). Backend/callable failures
/// surface as [PaymentFailure] with the server message for graceful
/// UI display.
class StudentPaymentsController {
  final FirebaseFunctions _functions;

  const StudentPaymentsController(this._functions);

  /// Generates the client-side receipt reference for a manually
  /// transcribed external payment (same `R-<millis>` convention as the
  /// approved student-app logging flow).
  static String newReceiptNumber() =>
      'R-${DateTime.now().millisecondsSinceEpoch}';

  /// Records a student-level payment (no Subject is sent or derived).
  Future<void> recordPayment({
    required String studentId,
    required DateTime date,
    required int amountEgp,
    required PaymentMethod method,
    required String collectedBy,
    String? notes,
    String? receiptNumber,
  }) async {
    if (amountEgp <= 0) {
      throw const PaymentFailure('Enter an amount greater than zero.');
    }
    if (collectedBy.trim().isEmpty) {
      throw const PaymentFailure('Enter the collector name.');
    }
    final String trimmedNotes = notes?.trim() ?? '';
    try {
      await _functions.httpsCallable('onPaymentLogged').call(
        <String, Object>{
          'studentId': studentId,
          'amount': amountEgp,
          'receiptNumber': receiptNumber ?? newReceiptNumber(),
          'paymentMethod': method.wire,
          'collectorName': collectedBy.trim(),
          'paymentDate': date.toIso8601String(),
          if (trimmedNotes.isNotEmpty) 'notes': trimmedNotes,
        },
      );
    } on FirebaseFunctionsException catch (e) {
      final String? message = e.message;
      throw PaymentFailure(
        message != null && message.trim().isNotEmpty
            ? message
            : 'Could not record the payment (${e.code}).',
      );
    } catch (e) {
      throw PaymentFailure('Could not record the payment. $e');
    }
  }

  /// Doctor-only in-place correction. Only non-null fields are sent;
  /// student linkage and `created_by` are never touched.
  Future<void> correctPayment({
    required String paymentId,
    int? amountEgp,
    PaymentMethod? method,
    String? collectedBy,
    DateTime? date,
    String? receiptNumber,
    String? notes,
  }) async {
    final Map<String, Object> payload = <String, Object>{
      'paymentId': paymentId,
    };
    if (amountEgp != null) payload['amount'] = amountEgp;
    if (method != null) payload['paymentMethod'] = method.wire;
    if (collectedBy != null) payload['collectorName'] = collectedBy.trim();
    if (date != null) payload['paymentDate'] = date.toIso8601String();
    if (receiptNumber != null) {
      payload['receiptNumber'] = receiptNumber.trim();
    }
    if (notes != null) payload['notes'] = notes.trim();
    try {
      await _functions.httpsCallable('correctPaymentLog').call(payload);
    } on FirebaseFunctionsException catch (e) {
      final String? message = e.message;
      throw PaymentFailure(
        message != null && message.trim().isNotEmpty
            ? message
            : 'Could not correct the payment (${e.code}).',
      );
    } catch (e) {
      throw PaymentFailure('Could not correct the payment. $e');
    }
  }

  /// Doctor-only create/update of the student's single financial
  /// account via `setStudentFinancialAccount`.
  Future<void> setAccount({
    required String studentId,
    required int priceEgp,
    required int discountEgp,
  }) async {
    try {
      await _functions.httpsCallable('setStudentFinancialAccount').call(
        <String, Object>{
          'studentId': studentId,
          'priceEgp': priceEgp,
          'discountEgp': discountEgp,
        },
      );
    } on FirebaseFunctionsException catch (e) {
      final String? message = e.message;
      throw PaymentFailure(
        message != null && message.trim().isNotEmpty
            ? message
            : 'Could not save the financial record (${e.code}).',
      );
    } catch (e) {
      throw PaymentFailure('Could not save the financial record. $e');
    }
  }
}

/// Typed failure for payment operations with a message safe to render.
class PaymentFailure implements Exception {
  const PaymentFailure(this.message);

  final String message;

  @override
  String toString() => 'PaymentFailure: $message';
}

final studentPaymentsControllerProvider =
    Provider<StudentPaymentsController>((ref) {
  return StudentPaymentsController(ref.watch(firebaseFunctionsProvider));
});
