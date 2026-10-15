import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/firebase_providers.dart';
import 'student_profile_payments_provider.dart' show PaymentFailure;
import 'student_profile_subjects_provider.dart'
    show StudentSubjectRegistration, studentProfileSubjectsProvider;

/// Data layer for the Dashboard Payments → Subjects table
/// (Manual Student-Subject Pricing authority).
///
/// Source of truth is Firestore, read through Riverpod providers; widgets
/// only `watch` state and dispatch to [StudentSubjectPricingController].
/// No Firestore access from widgets.
///
/// Model:
/// - Registration (which subjects belong to the student, with title +
///   grade) is reused from [studentProfileSubjectsProvider] — no duplicate
///   subject-loading logic lives here.
/// - Price/Discount/Net come from `student_subject_pricing`
///   (`{studentId}_{subjectId}` docs). A missing or soft-deleted pricing
///   document means "unpriced" (rendered as `—`, never an invented 0).
/// - Net displayed is the stored server-derived `net_egp`; pricing never
///   feeds Paid/Balance (those stay student-level in [StudentLedger]).
/// - Writes go exclusively through the Doctor-only
///   `setStudentSubjectPricing` callable — never direct Firestore writes.
///
/// Forbidden sources (never read here): `student_subject_accounts`,
/// `subjects.price_egp`, `subjects.discount_egp`, per-subject ledgers.

/// One Doctor-entered pricing reference for a (student, subject) pair.
///
/// Display / financial-reference only. Not a payment account, not a cap,
/// not an allocation — it never participates in payment enforcement.
class StudentSubjectPricing {
  final String subjectId;
  final int priceEgp;
  final int discountEgp;
  final int netEgp;

  const StudentSubjectPricing({
    required this.subjectId,
    required this.priceEgp,
    required this.discountEgp,
    required this.netEgp,
  });

  /// Defensive parse against the approved `student_subject_pricing`
  /// schema. Unparseable numbers resolve to 0 instead of throwing, so one
  /// malformed row can never fail the whole table stream. A stored Net is
  /// honored; when absent, Price − Discount is derived (clamped at 0).
  factory StudentSubjectPricing.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> data = doc.data();
    final int price = _asInt(data['price_egp']);
    final int discount = _asInt(data['discount_egp']);
    final Object? netRaw = data['net_egp'];
    final int net = netRaw is num
        ? netRaw.toInt()
        : (price - discount).clamp(0, 1 << 31);
    return StudentSubjectPricing(
      subjectId: (data['subject_id'] as String?) ?? doc.id,
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

/// One Subjects-table row: the student's registration joined with its
/// optional Doctor-entered pricing (`pricing == null` renders `—`).
class StudentPricedSubject {
  final String subjectId;
  final String title;
  final String? gradeKey;
  final bool enabled;
  final StudentSubjectPricing? pricing;

  const StudentPricedSubject({
    required this.subjectId,
    required this.title,
    required this.gradeKey,
    required this.enabled,
    required this.pricing,
  });
}

/// Pure join step (unit-testable): every registered subject becomes one
/// row; pricing attaches by `subjectId` when a record exists. Sorted by
/// title, mirroring the registration order.
List<StudentPricedSubject> buildStudentPricedSubjects({
  required List<StudentSubjectRegistration> registrations,
  required List<StudentSubjectPricing> pricings,
}) {
  final Map<String, StudentSubjectPricing> pricingBySubject =
      <String, StudentSubjectPricing>{
    for (final StudentSubjectPricing p in pricings) p.subjectId: p,
  };
  final List<StudentPricedSubject> rows = <StudentPricedSubject>[
    for (final StudentSubjectRegistration reg in registrations)
      StudentPricedSubject(
        subjectId: reg.subjectId,
        title: reg.title,
        gradeKey: reg.gradeKey,
        enabled: reg.enabled,
        pricing: pricingBySubject[reg.subjectId],
      ),
  ];
  rows.sort((a, b) => a.title.compareTo(b.title));
  return rows;
}

/// Live Doctor-entered pricing records of one student
/// (`student_subject_pricing`).
///
/// Single-filter query only (`student_id`); the `is_deleted` filter is
/// applied client-side so no composite index is required.
final studentSubjectPricingsProvider =
    StreamProvider.family<List<StudentSubjectPricing>, String>(
        (ref, studentId) {
  final FirebaseFirestore db = ref.watch(firebaseFirestoreProvider);
  return db
      .collection('student_subject_pricing')
      .where('student_id', isEqualTo: studentId)
      .snapshots()
      .map((snap) => snap.docs
          .where((doc) => doc.data()['is_deleted'] != true)
          .map(StudentSubjectPricing.fromDoc)
          .toList(growable: false));
});

/// Combined Subjects-table rows for the Payments tab of [studentId].
///
/// Joins the reused registration stream (catalog titles + grades) with
/// the pricing stream. Loading/error states of the underlying streams
/// propagate honestly — the same fan-in pattern as
/// `studentLedgerProvider`.
final studentPricedSubjectsProvider =
    Provider.family<AsyncValue<List<StudentPricedSubject>>, String>(
        (ref, studentId) {
  final AsyncValue<List<StudentSubjectRegistration>> regs =
      ref.watch(studentProfileSubjectsProvider(studentId));
  final AsyncValue<List<StudentSubjectPricing>> pricings =
      ref.watch(studentSubjectPricingsProvider(studentId));
  if (regs is AsyncLoading || pricings is AsyncLoading) {
    return const AsyncLoading<List<StudentPricedSubject>>();
  }
  if (regs is AsyncError) {
    return AsyncError<List<StudentPricedSubject>>(
        regs.error!, regs.stackTrace ?? StackTrace.empty);
  }
  if (pricings is AsyncError) {
    return AsyncError<List<StudentPricedSubject>>(
        pricings.error!, pricings.stackTrace ?? StackTrace.empty);
  }
  return AsyncData<List<StudentPricedSubject>>(
    buildStudentPricedSubjects(
      registrations:
          regs.value ?? const <StudentSubjectRegistration>[],
      pricings: pricings.value ?? const <StudentSubjectPricing>[],
    ),
  );
});

/// Price/Discount writes for the Payments → Subjects table.
///
/// Manual Doctor entry/correction via the approved
/// `setStudentSubjectPricing` callable (one callable for create and
/// correct on the deterministic `{studentId}_{subjectId}` document).
/// Kept separate from payment transactions: this controller never
/// records or corrects payments and never touches the student ledger.
/// Backend/callable failures surface as [PaymentFailure] with the server
/// message for graceful UI display.
class StudentSubjectPricingController {
  final FirebaseFunctions _functions;

  const StudentSubjectPricingController(this._functions);

  /// Doctor-only create/correction of one subject's manual pricing.
  /// Client-side guards mirror the server contract so obvious mistakes
  /// surface before the callable round-trip.
  Future<void> setPricing({
    required String studentId,
    required String subjectId,
    required int priceEgp,
    required int discountEgp,
  }) async {
    if (priceEgp < 0) {
      throw const PaymentFailure('Enter a valid price.');
    }
    if (discountEgp < 0) {
      throw const PaymentFailure('Enter a valid discount.');
    }
    if (discountEgp > priceEgp) {
      throw const PaymentFailure('Discount must not exceed price.');
    }
    try {
      await _functions.httpsCallable('setStudentSubjectPricing').call(
        <String, Object>{
          'studentId': studentId,
          'subjectId': subjectId,
          'priceEgp': priceEgp,
          'discountEgp': discountEgp,
        },
      );
    } on FirebaseFunctionsException catch (e) {
      final String? message = e.message;
      throw PaymentFailure(
        message != null && message.trim().isNotEmpty
            ? message
            : 'Could not save the subject pricing (${e.code}).',
      );
    } catch (e) {
      throw PaymentFailure('Could not save the subject pricing. $e');
    }
  }
}

final studentSubjectPricingControllerProvider =
    Provider<StudentSubjectPricingController>((ref) {
  return StudentSubjectPricingController(ref.watch(firebaseFunctionsProvider));
});
