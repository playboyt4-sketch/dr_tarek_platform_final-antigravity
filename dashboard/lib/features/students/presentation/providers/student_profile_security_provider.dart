import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/firebase_providers.dart';
import '../../../authentication/domain/entities/dashboard_session.dart';
import '../../../authentication/presentation/providers/auth_providers.dart';

/// Data layer for the Student Profile → Security tab.
///
/// Source of truth is Firestore, read through Riverpod providers; widgets
/// only `watch` state and dispatch to [StudentSecurityController]. No
/// Firestore access from widgets.
///
/// Backend model (`functions/src/index.ts`, `onSecurityEvent`):
/// - Collection `security_events`: `user_id`, `event_type`, `severity`,
///   `context` (map), `device_info` (map), `screenshot_detected`,
///   `screen_record_detected`, `action_taken`, `created_at`.
/// - Readable by doctor / `admin_devices` / `admin_analytics`
///   (firestore.rules); denials surface honestly — never invented data.
/// - There is NO `security_score` backend field and NO scoring formula in
///   V1. The status card therefore renders the score only when a supplied
///   source exists; otherwise it shows an honest "not available" state.
///   Figma sample values (e.g. `92/100`) are never hardcoded.
///
/// Password flow (direct staff-initiated reset — phone/in-person request):
/// - The authorized actor (Doctor always; Admin with delegated
///   `password.reset` grant) sets a TEMPORARY password via the existing
///   `onPasswordResetApproved(requestId, newPassword)` callable, which sets
///   `force_password_change = true`, `password_last_changed_at`, writes
///   `admin_audit_log` (`password_reset_approved`) and notifies the student.
///   The student replaces it with a permanent password on next login.
/// - The student does NOT need to submit a "Forgot Password" request from
///   the app first: when no PENDING `password_reset_requests` document
///   exists, the Dashboard creates one staff-side (allowed by
///   firestore.rules `allow create` for Doctor / `canResetPassword()`) and
///   immediately approves it in the same Save action.
/// - This client never invents permission keys, audit identifiers, or
///   password-strength business rules. Backend validation is authoritative;
///   the UI checks only empty + confirmation mismatch.

/// Severity values accepted from the backend (`security_events.severity`).
///
/// Unknown / missing values map to [SecuritySeverity.unknown] and render
/// with a neutral style. The client never invents additional severities.
enum SecuritySeverity { low, medium, high, critical, unknown }

/// Parses the raw backend severity string (case-insensitive).
SecuritySeverity parseSecuritySeverity(Object? raw) {
  final String value = '$raw'.trim().toLowerCase();
  switch (value) {
    case 'low':
      return SecuritySeverity.low;
    case 'medium':
      return SecuritySeverity.medium;
    case 'high':
      return SecuritySeverity.high;
    case 'critical':
      return SecuritySeverity.critical;
    default:
      return SecuritySeverity.unknown;
  }
}

/// One `security_events` document for the student.
class SecurityEvent {
  final String id;
  final String eventType;
  final SecuritySeverity severity;

  /// Raw severity string as stored (for faithful display of unknowns).
  final String severityLabel;
  final DateTime? createdAt;

  /// Short context summary (`context` map reduced to display text).
  final String contextSummary;

  /// Device information associated with the event (`device_info` reduced).
  final String deviceSummary;
  final String actionTaken;
  final bool screenshotDetected;
  final bool screenRecordDetected;

  const SecurityEvent({
    required this.id,
    required this.eventType,
    required this.severity,
    required this.severityLabel,
    required this.createdAt,
    required this.contextSummary,
    required this.deviceSummary,
    required this.actionTaken,
    required this.screenshotDetected,
    required this.screenRecordDetected,
  });

  /// Field mapping per spec: `event_type` → type, `severity` → severity,
  /// `created_at` → date/time, `context` → summary, `device_info` → device,
  /// `action_taken` → action. Missing values degrade to `—`, never invented.
  factory SecurityEvent.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> data = doc.data();
    final Object? severityRaw = data['severity'];
    final SecuritySeverity severity = parseSecuritySeverity(severityRaw);
    final Object? createdRaw = data['created_at'];
    DateTime? createdAt;
    if (createdRaw is Timestamp) {
      createdAt = createdRaw.toDate();
    }
    return SecurityEvent(
      id: doc.id,
      eventType: (data['event_type'] as String?)?.trim().isEmpty == true
          ? '—'
          : ((data['event_type'] as String?) ?? '—'),
      severity: severity,
      severityLabel: severity == SecuritySeverity.unknown
          ? (severityRaw == null ? '—' : '$severityRaw')
          : (severityRaw as String? ?? severity.name),
      createdAt: createdAt,
      contextSummary: flattenDetailMap(data['context']),
      deviceSummary: flattenDetailMap(data['device_info']),
      actionTaken: (data['action_taken'] as String?)?.trim().isEmpty == true
          ? '—'
          : ((data['action_taken'] as String?) ?? '—'),
      screenshotDetected: data['screenshot_detected'] == true,
      screenRecordDetected: data['screen_record_detected'] == true,
    );
  }
}

/// Reduces a backend detail map to a short display line.
///
/// Strings pass through; numbers/bools stringify; nested maps/lists join
/// their leaf values. Empty / missing maps degrade to `—`.
String flattenDetailMap(Object? raw) {
  if (raw is String) {
    return raw.trim().isEmpty ? '—' : raw.trim();
  }
  if (raw is! Map) return '—';
  final List<String> parts = <String>[];
  raw.forEach((key, value) {
    if (value == null) return;
    if (value is String) {
      if (value.trim().isNotEmpty) parts.add(value.trim());
    } else if (value is num || value is bool) {
      parts.add('$value');
    } else if (value is Map) {
      final String nested = flattenDetailMap(value);
      if (nested != '—') parts.add(nested);
    } else if (value is Iterable) {
      for (final Object? item in value) {
        final String nested = flattenDetailMap(item);
        if (nested != '—') parts.add(nested);
      }
    }
  });
  return parts.isEmpty ? '—' : parts.join(' • ');
}

/// Time-window filter for the event log overlay (UX windows only — no
/// backend semantics).
enum SecurityTimeFilter { allTime, last24Hours, last7Days, last30Days }

/// Pure, unit-testable filter over loaded [SecurityEvent]s.
///
/// - `eventType == 'All Events'` (or empty) disables the type filter; any
///   other value matches the backend `event_type` verbatim.
/// - `severity == null` disables the severity filter.
/// - Time windows compare against [DateTime.now](); events with unknown
///   timestamps are kept only under [SecurityTimeFilter.allTime].
List<SecurityEvent> filterSecurityEvents({
  required List<SecurityEvent> events,
  String eventType = 'All Events',
  SecuritySeverity? severity,
  SecurityTimeFilter time = SecurityTimeFilter.allTime,
}) {
  final DateTime now = DateTime.now();
  Duration? window;
  switch (time) {
    case SecurityTimeFilter.allTime:
      window = null;
      break;
    case SecurityTimeFilter.last24Hours:
      window = const Duration(hours: 24);
      break;
    case SecurityTimeFilter.last7Days:
      window = const Duration(days: 7);
      break;
    case SecurityTimeFilter.last30Days:
      window = const Duration(days: 30);
      break;
  }
  return <SecurityEvent>[
    for (final SecurityEvent event in events)
      if ((eventType.isEmpty ||
              eventType == 'All Events' ||
              event.eventType == eventType) &&
          (severity == null || event.severity == severity) &&
          (window == null ||
              (event.createdAt != null &&
                  now.difference(event.createdAt!).compareTo(window) <=
                      0)))
        event,
  ];
}

/// Distinct event types present in [events], sorted, for the overlay's
/// Event Type filter. Backend values only — never invented.
List<String> distinctSecurityEventTypes(List<SecurityEvent> events) {
  final Set<String> types = <String>{};
  for (final SecurityEvent event in events) {
    if (event.eventType != '—') types.add(event.eventType);
  }
  final List<String> sorted = types.toList()..sort();
  return sorted;
}

/// `17 Sep 2026 • 6:31 PM` day-first format used across the Security tab.
/// `—` when unknown (never invented).
String formatSecurityDateTime(DateTime? date) {
  if (date == null) return '—';
  const List<String> months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final int hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final String period = date.hour < 12 ? 'AM' : 'PM';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${date.day} ${months[date.month - 1]} ${date.year} • '
      '$hour12:${two(date.minute)} $period';
}

/// Live security events of one student, newest first.
///
/// Single-filter query only (`user_id`); ordering is client-side so no
/// composite index is required. Readable by doctor / `admin_devices` /
/// `admin_analytics`; backend denials propagate honestly.
final studentSecurityEventsProvider =
    StreamProvider.family<List<SecurityEvent>, String>((ref, studentId) {
  final FirebaseFirestore db = ref.watch(firebaseFirestoreProvider);
  return db
      .collection('security_events')
      .where('user_id', isEqualTo: studentId)
      .snapshots()
      .map((snap) {
    final List<SecurityEvent> events = snap.docs
        .map(SecurityEvent.fromDoc)
        .toList(growable: false);
    events.sort((a, b) {
      final DateTime? at = a.createdAt;
      final DateTime? bt = b.createdAt;
      if (at != null && bt != null) return bt.compareTo(at);
      if (at != null) return -1;
      if (bt != null) return 1;
      return a.id.compareTo(b.id);
    });
    return events;
  });
});

/// Account-level security summary read from the `users` document.
///
/// Exposes the raw `account_status` string (domain-owned, never
/// hardcoded in the UI) and `password_last_changed_at`. There is no
/// backend security score in V1, so [securityScoreLabel] is always null —
/// the UI renders an honest "not available" state.
class StudentSecuritySummary {
  final String accountStatus;
  final DateTime? passwordLastChangedAt;

  /// Always null in V1: no `security_score` backend field exists.
  final String? securityScoreLabel = null;

  const StudentSecuritySummary({
    required this.accountStatus,
    required this.passwordLastChangedAt,
  });
}

final studentSecuritySummaryProvider =
    StreamProvider.family<StudentSecuritySummary, String>((ref, studentId) {
  final FirebaseFirestore db = ref.watch(firebaseFirestoreProvider);
  return db.collection('users').doc(studentId).snapshots().map((doc) {
    final Map<String, dynamic>? data = doc.data();
    final Object? changedRaw = data?['password_last_changed_at'];
    DateTime? changedAt;
    if (changedRaw is Timestamp) changedAt = changedRaw.toDate();
    final String status = (data?['account_status'] as String?)?.trim().isEmpty == true
        ? '—'
        : ((data?['account_status'] as String?) ?? '—');
    return StudentSecuritySummary(
      accountStatus: status,
      passwordLastChangedAt: changedAt,
    );
  });
});

/// Latest PENDING `password_reset_requests` document id for [studentId],
/// or null when there is none.
///
/// The `onPasswordResetApproved` callable is request-based, so the Change
/// Password overlay approves this request. A null result simply means the
/// Dashboard will create a staff-side pending request on Save (Doctor /
/// delegated Admin may create per firestore.rules) — the student never
/// needs to submit a "Forgot Password" from the app first.
final pendingStudentPasswordResetRequestProvider =
    FutureProvider.family<String?, String>((ref, studentId) async {
  final FirebaseFirestore db = ref.watch(firebaseFirestoreProvider);
  final QuerySnapshot<Map<String, dynamic>> snap = await db
      .collection('password_reset_requests')
      .where('student_id', isEqualTo: studentId)
      .limit(50)
      .get();
  String? latestId;
  DateTime? latestAt;
  for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in snap.docs) {
    final Map<String, dynamic> data = doc.data();
    if (data['status'] != 'pending') continue;
    final Object? raw = data['requested_at'] ?? data['created_at'];
    DateTime? at;
    if (raw is Timestamp) at = raw.toDate();
    if (latestId == null ||
        (at != null && (latestAt == null || at.isAfter(latestAt)))) {
      latestId = doc.id;
      latestAt = at;
    }
  }
  return latestId;
});

/// Returns the pending request id for [studentId], creating a staff-side
/// pending request when none exists.
///
/// Schema matches firestore.rules `allow create`: only `student_id`,
/// `phone_number`, `status`, `requested_at`, `created_at` with
/// `status == 'pending'`. Timestamps are server timestamps so ordering
/// (`requested_at` / `created_at`) stays consistent with app-created rows.
Future<String> ensurePendingPasswordResetRequestId(
  FirebaseFirestore db, {
  required String studentId,
  String? phoneNumber,
}) async {
  final QuerySnapshot<Map<String, dynamic>> snap = await db
      .collection('password_reset_requests')
      .where('student_id', isEqualTo: studentId)
      .limit(50)
      .get();
  String? latestId;
  DateTime? latestAt;
  for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in snap.docs) {
    final Map<String, dynamic> data = doc.data();
    if (data['status'] != 'pending') continue;
    final Object? raw = data['requested_at'] ?? data['created_at'];
    DateTime? at;
    if (raw is Timestamp) at = raw.toDate();
    if (latestId == null ||
        (at != null && (latestAt == null || at.isAfter(latestAt)))) {
      latestId = doc.id;
      latestAt = at;
    }
  }
  if (latestId != null) return latestId;
  final Map<String, Object> payload = <String, Object>{
    'student_id': studentId,
    'status': 'pending',
    'requested_at': FieldValue.serverTimestamp(),
    'created_at': FieldValue.serverTimestamp(),
  };
  final String? phone = phoneNumber?.trim();
  if (phone != null && phone.isNotEmpty) {
    payload['phone_number'] = phone;
  }
  final DocumentReference<Map<String, dynamic>> created = await db
      .collection('password_reset_requests')
      .add(payload);
  return created.id;
}

/// Whether the current dashboard actor holds the delegated password-reset
/// permission for [adminId]: active grant with `password_reset == true` —
/// the exact key enforced by backend `requirePasswordResetManager`.
final adminPasswordResetPermissionProvider =
    StreamProvider.family<bool, String>((ref, adminId) {
  final FirebaseFirestore db = ref.watch(firebaseFirestoreProvider);
  return db.collection('admin_permissions').doc(adminId).snapshots().map(
    (doc) {
      final Map<String, dynamic>? data = doc.data();
      if (data == null || data['is_active'] != true) return false;
      final Object? permissions = data['permissions'];
      if (permissions is! Map) return false;
      return permissions['password_reset'] == true;
    },
  );
});

/// Whether the current dashboard actor may set a student's temporary
/// password.
///
/// Doctor (Platform Owner): full permission. Admin: only with the delegated
/// `password_reset` grant from the Teacher (grant/revoke at any time,
/// enforced server-side by `requirePasswordResetManager`). Unknown /
/// loading / non-staff sessions fail closed; the backend re-enforces this
/// server-side on every write. No role checks live in widgets — they read
/// this provider.
final canResetStudentPasswordProvider =
    Provider<AsyncValue<bool>>((ref) {
  final AsyncValue<DashboardSession?> sessionAsync =
      ref.watch(sessionProvider);
  if (sessionAsync is AsyncLoading) return const AsyncLoading<bool>();
  if (sessionAsync is AsyncError) {
    return AsyncError<bool>(
        sessionAsync.error!, sessionAsync.stackTrace ?? StackTrace.empty);
  }
  final DashboardSession? session = sessionAsync.value;
  if (session == null) return const AsyncData<bool>(false);
  final String? role = session.role;
  if (!(role == 'doctor' || role == 'admin') || !session.approved) {
    return const AsyncData<bool>(false);
  }
  if (role == 'doctor') return const AsyncData<bool>(true);
  return ref.watch(adminPasswordResetPermissionProvider(session.userId)).when(
        data: (can) => AsyncData<bool>(can),
        loading: () => const AsyncLoading<bool>(),
        error: (e, st) => AsyncError<bool>(e, st),
      );
});

/// Password writes for the Student Profile → Security tab.
///
/// - [approveTemporaryPassword] approves a pending reset request with the
///   Teacher-entered TEMPORARY password via the existing
///   `onPasswordResetApproved` callable. Server-side it updates the
///   password, sets `force_password_change = true`, updates
///   `password_last_changed_at`, writes `admin_audit_log` and notifies the
///   student. The client never touches password hashes, Auth Admin APIs,
///   or audit records directly.
/// - Backend/callable failures surface as [SecurityFailure] with the server
///   message for graceful UI display.
class StudentSecurityController {
  final FirebaseFunctions _functions;

  const StudentSecurityController(this._functions);

  String _message(Object error) {
    if (error is FirebaseFunctionsException) {
      final String? message = error.message;
      if (message != null && message.trim().isNotEmpty) return message;
      return switch (error.code) {
        'permission-denied' =>
          'You do not have permission to reset passwords.',
        'not-found' => 'The password reset request was not found.',
        'failed-precondition' =>
          'The password reset request is no longer pending.',
        'invalid-argument' => 'The temporary password is invalid.',
        'resource-exhausted' => 'Too many attempts. Try again later.',
        _ => 'Could not update the password. Try again.',
      };
    }
    if (error is SecurityFailure) return error.message;
    return 'Could not update the password. Try again.';
  }

  Future<void> approveTemporaryPassword({
    required String requestId,
    required String temporaryPassword,
  }) async {
    try {
      await _functions.httpsCallable('onPasswordResetApproved').call(
        <String, Object>{
          'requestId': requestId,
          'newPassword': temporaryPassword,
        },
      );
    } on FirebaseFunctionsException catch (e) {
      throw SecurityFailure(_message(e));
    } catch (e) {
      throw SecurityFailure(_message(e));
    }
  }
}

/// Typed failure for security writes with a message safe to render.
class SecurityFailure implements Exception {
  const SecurityFailure(this.message);

  final String message;

  @override
  String toString() => 'SecurityFailure: $message';
}

final studentSecurityControllerProvider =
    Provider<StudentSecurityController>((ref) {
  return StudentSecurityController(ref.watch(firebaseFunctionsProvider));
});
