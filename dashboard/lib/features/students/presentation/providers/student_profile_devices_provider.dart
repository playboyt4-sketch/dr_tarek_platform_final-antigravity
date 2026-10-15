import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/firebase_providers.dart';
import '../../../authentication/domain/entities/dashboard_session.dart';
import '../../../authentication/presentation/providers/auth_providers.dart';
import 'student_profile_subjects_provider.dart';

/// Data layer for the Student Profile → Device tab (subject-level device
/// authorization, ADR-004).
///
/// Source of truth is Firestore, read through Riverpod providers; widgets
/// only `watch` state and dispatch to [StudentDeviceController]. No
/// Firestore access from widgets.
///
/// Model (backend `functions/src/index.ts`, collection
/// `subject_device_authorizations`):
/// - Authorization scope is Student + Subject + Device (never global).
/// - Each Subject gets its own allowance from that Subject's active
///   subscription plan (`plan_features` row `device.max_count`).
/// - Binding happens on first actual Subject access via a server-side
///   transaction; there is no automatic eviction.
/// - Guest is a computed outcome — no record is ever created for Guest, so
///   Guest can never appear as an authorized device row. Only
///   `status == 'active'` (and non-deleted) rows are rendered.
/// - The `devices` collection is a registry/audit trail only; it never
///   decides authorization. Registry rows are joined to authorizations via
///   `device_hash == sha256("$studentId|$deviceId")`, mirroring the
///   backend `computeDeviceHash` exactly.
///
/// Writes go exclusively through the audited callables
/// (`unbindSubjectDevice`, `resetStudentDevices`), which enforce
/// `requireDeviceManager` (doctor or delegated `admin_devices`)
/// server-side and write `admin_audit_log` / analytics events. The client
/// never invents permission or audit identifiers.

/// One `subject_device_authorizations` document.
class SubjectDeviceAuthorization {
  final String authorizationId;
  final String subjectId;
  final String deviceHash;
  final String status;
  final bool isDeleted;
  final DateTime? lastUsedAt;
  final String? planKeyAtBind;

  const SubjectDeviceAuthorization({
    required this.authorizationId,
    required this.subjectId,
    required this.deviceHash,
    required this.status,
    required this.isDeleted,
    required this.lastUsedAt,
    required this.planKeyAtBind,
  });

  /// Active authorizations only: revoked / soft-deleted rows (and, by
  /// construction, the Guest outcome which has no record) never render.
  bool get isActive => status == 'active' && !isDeleted;

  factory SubjectDeviceAuthorization.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> data = doc.data();
    final Object? lastUsed =
        data['last_used_at'] ?? data['authorized_at'];
    DateTime? lastUsedAt;
    if (lastUsed is Timestamp) lastUsedAt = lastUsed.toDate();
    return SubjectDeviceAuthorization(
      authorizationId: doc.id,
      subjectId: (data['subject_id'] as String?) ?? '',
      deviceHash: (data['device_hash'] as String?) ?? '',
      status: (data['status'] as String?) ?? '',
      isDeleted: data['is_deleted'] == true,
      lastUsedAt: lastUsedAt,
      planKeyAtBind: data['plan_key_at_bind'] as String?,
    );
  }
}

/// One `devices` registry row for the student (metadata only).
class StudentDeviceRecord {
  final String docId;

  /// Raw client-asserted device identity. The backend hashes this into
  /// `device_hash`; unbind passes this raw value back (the server hashes).
  final String deviceId;
  final String? deviceName;
  final String? platform;
  final String? osVersion;
  final String? appVersion;
  final DateTime? lastLogin;

  const StudentDeviceRecord({
    required this.docId,
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.osVersion,
    required this.appVersion,
    required this.lastLogin,
  });

  factory StudentDeviceRecord.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> data = doc.data();
    final Object? lastLogin = data['last_login'];
    return StudentDeviceRecord(
      docId: doc.id,
      deviceId: (data['device_id'] as String?) ?? doc.id,
      deviceName: data['device_name'] as String?,
      platform: data['platform'] as String?,
      osVersion: data['os_version'] as String?,
      appVersion: data['app_version'] as String?,
      lastLogin: lastLogin is Timestamp ? lastLogin.toDate() : null,
    );
  }
}

/// One authorized device of one Subject: the authorization truth joined
/// with the registry metadata. Every active authorization renders exactly
/// one entry; entries whose registry row is missing still render (with
/// fallback metadata) so the count never lies.
class SubjectAuthorizedDevice {
  final String authorizationId;

  /// Raw device identity for the unbind callable (never the hash).
  final String deviceId;
  final String deviceName;
  final String platform;
  final String? osVersion;
  final String? appVersion;
  final DateTime? lastAccess;

  const SubjectAuthorizedDevice({
    required this.authorizationId,
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.osVersion,
    required this.appVersion,
    required this.lastAccess,
  });

  /// Active authorizations always hold Full tier for their Subject.
  String get statusLabel => 'Full';
}

/// One Device-tab table row: a registered Subject with its own plan,
/// allowance, and authorized devices. Allowances never leak across
/// Subjects — each row resolves only its own Subject's subscription.
/// [gradeKey] is the subject's OWN catalog grade (passed straight through
/// from the registration join — never the student's current grade).
class StudentSubjectDeviceRow {
  final String subjectId;
  final String title;
  final String? gradeKey;
  final String planLabel;
  final int allowance;
  final List<SubjectAuthorizedDevice> devices;

  const StudentSubjectDeviceRow({
    required this.subjectId,
    required this.title,
    required this.gradeKey,
    required this.planLabel,
    required this.allowance,
    required this.devices,
  });

  int get activeCount => devices.length;

  /// `1/1`, `2/2` — active authorizations over this Subject's allowance.
  String get usageLabel => '$activeCount/$allowance';
}

/// Mirrors the backend `computeDeviceHash` (`sha256(userId|deviceId)`)
/// exactly so authorization rows join their registry metadata.
String deviceHashFor({
  required String studentId,
  required String deviceId,
}) {
  return sha256.convert(utf8.encode('$studentId|$deviceId')).toString();
}

/// Display fallback for a Subject allowance when the plan-matrix value is
/// not readable (documented defaults: Free 1 / Pro 1 / Max 2). This is a
/// presentation fallback only — authorization truth and enforcement stay
/// server-side; the UI never grants or denies access.
int deviceAllowanceForPlanLabel(String planLabel) {
  switch (planLabel.toUpperCase()) {
    case 'MAX':
      return 2;
    case 'PRO':
    case 'FREE':
      return 1;
    default:
      return 1;
  }
}

/// Pure combine step (unit-testable): one row per registered Subject with
/// that Subject's own active authorizations joined to registry metadata.
///
/// - Only [SubjectDeviceAuthorization.isActive] rows are attached; Guest
///   has no record by construction and revoked rows stay hidden.
/// - The allowance comes from [allowancesByPlanId] (the plan-matrix
///   `device.max_count` for the Subject's own subscription plan) and falls
///   back to [deviceAllowanceForPlanLabel] per Subject — never from
///   another Subject's plan.
List<StudentSubjectDeviceRow> buildStudentSubjectDeviceRows({
  required List<StudentSubjectRegistration> registrations,
  required Map<String, String> planIdBySubject,
  required List<SubjectDeviceAuthorization> authorizations,
  required List<StudentDeviceRecord> devices,
  required Map<String, int> allowancesByPlanId,
  required String studentId,
}) {
  final Map<String, String> hashToDeviceId = <String, String>{
    for (final StudentDeviceRecord d in devices)
      deviceHashFor(studentId: studentId, deviceId: d.deviceId): d.deviceId,
  };
  final Map<String, StudentDeviceRecord> recordByDeviceId =
      <String, StudentDeviceRecord>{
    for (final StudentDeviceRecord d in devices) d.deviceId: d,
  };
  final Map<String, List<SubjectDeviceAuthorization>> activeBySubject =
      <String, List<SubjectDeviceAuthorization>>{};
  for (final SubjectDeviceAuthorization a in authorizations) {
    if (!a.isActive || a.subjectId.isEmpty) continue;
    (activeBySubject[a.subjectId] ??= <SubjectDeviceAuthorization>[]).add(a);
  }

  final List<StudentSubjectDeviceRow> rows = <StudentSubjectDeviceRow>[];
  for (final StudentSubjectRegistration reg in registrations) {
    final List<SubjectDeviceAuthorization> active =
        activeBySubject[reg.subjectId] ?? const <SubjectDeviceAuthorization>[];
    final String? planId = planIdBySubject[reg.subjectId];
    final int allowance = (planId != null ? allowancesByPlanId[planId] : null) ??
        deviceAllowanceForPlanLabel(reg.planLabel);
    final List<SubjectAuthorizedDevice> joined = <SubjectAuthorizedDevice>[
      for (final SubjectDeviceAuthorization a in active)
        _joinDevice(
          authorization: a,
          record: recordByDeviceId[hashToDeviceId[a.deviceHash]],
        ),
    ];
    joined.sort(_compareDevices);
    rows.add(StudentSubjectDeviceRow(
      subjectId: reg.subjectId,
      title: reg.title,
      gradeKey: reg.gradeKey,
      planLabel: reg.planLabel,
      allowance: allowance,
      devices: List<SubjectAuthorizedDevice>.unmodifiable(joined),
    ));
  }
  return rows;
}

SubjectAuthorizedDevice _joinDevice({
  required SubjectDeviceAuthorization authorization,
  required StudentDeviceRecord? record,
}) {
  final String name = (record?.deviceName ?? '').trim();
  final String platform = (record?.platform ?? '').trim();
  return SubjectAuthorizedDevice(
    authorizationId: authorization.authorizationId,
    deviceId: record?.deviceId ?? '',
    deviceName: name.isEmpty ? 'Unknown device' : name,
    platform: platform.isEmpty ? 'Unknown' : platform,
    osVersion: record?.osVersion,
    appVersion: record?.appVersion,
    lastAccess: authorization.lastUsedAt ?? record?.lastLogin,
  );
}

int _compareDevices(SubjectAuthorizedDevice a, SubjectAuthorizedDevice b) {
  final DateTime? at = a.lastAccess;
  final DateTime? bt = b.lastAccess;
  if (at != null && bt != null) {
    final int cmp = bt.compareTo(at);
    if (cmp != 0) return cmp;
  } else if (at != null) {
    return -1;
  } else if (bt != null) {
    return 1;
  }
  return a.authorizationId.compareTo(b.authorizationId);
}

/// `15/09/2026 04:32 PM` day-first format used by the Device Details
/// overlay. `—` when unknown (never invented).
String formatDeviceDateTime(DateTime? date) {
  if (date == null) return '—';
  final int hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final String period = date.hour < 12 ? 'AM' : 'PM';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(date.day)}/${two(date.month)}/${date.year} '
      '${two(hour12)}:${two(date.minute)} $period';
}

/// `iOS 18.x   •   App 1.0.x` metadata line for one authorized device.
String formatDeviceOsLine(SubjectAuthorizedDevice device) {
  final String os = <String>[
    device.platform,
    if ((device.osVersion ?? '').trim().isNotEmpty) device.osVersion!.trim(),
  ].join(' ').trim();
  final String app = (device.appVersion ?? '').trim();
  return '${os.isEmpty ? '—' : os}   •   App ${app.isEmpty ? '—' : app}';
}

/// Live authorizations of one student (all Subjects).
///
/// Single-filter query only (`student_id`); status / soft-delete filters
/// are applied client-side so no composite index is required. Readable by
/// doctor or delegated `admin_devices` (firestore.rules); others observe
/// the backend denial honestly.
final studentDeviceAuthorizationsProvider =
    StreamProvider.family<List<SubjectDeviceAuthorization>, String>(
        (ref, studentId) {
  final FirebaseFirestore db = ref.watch(firebaseFirestoreProvider);
  return db
      .collection('subject_device_authorizations')
      .where('student_id', isEqualTo: studentId)
      .snapshots()
      .map((snap) => snap.docs
          .map(SubjectDeviceAuthorization.fromDoc)
          .toList(growable: false));
});

/// Live device-registry rows of one student (metadata only).
final studentDeviceRecordsProvider =
    StreamProvider.family<List<StudentDeviceRecord>, String>(
        (ref, studentId) {
  final FirebaseFirestore db = ref.watch(firebaseFirestoreProvider);
  return db
      .collection('devices')
      .where('user_id', isEqualTo: studentId)
      .snapshots()
      .map((snap) => snap.docs
          .map(StudentDeviceRecord.fromDoc)
          .toList(growable: false));
});

/// Live `device.max_count` allowance by plan document id.
///
/// Reads both `feature_value` (backend readers) and `value` (seed
/// scripts); non-numeric / missing values are skipped so the per-Subject
/// display fallback applies instead of invented data.
final deviceAllowancesProvider =
    StreamProvider<Map<String, int>>((ref) {
  final FirebaseFirestore db = ref.watch(firebaseFirestoreProvider);
  return db
      .collection('plan_features')
      .where('feature_key', isEqualTo: 'device.max_count')
      .snapshots()
      .map((snap) {
    final Map<String, int> out = <String, int>{};
    for (final doc in snap.docs) {
      final Map<String, dynamic> data = doc.data();
      final String? planId = data['plan_id'] as String?;
      final Object? raw = data['feature_value'] ?? data['value'];
      final int? allowance =
          raw is num ? raw.toInt() : int.tryParse('$raw');
      if (planId != null &&
          planId.isNotEmpty &&
          allowance != null &&
          allowance >= 1) {
        out[planId] = allowance;
      }
    }
    return out;
  });
});

/// Combined Device-tab rows for [studentId]: registrations (titles +
/// subject-scoped plans) joined with the Subject's own subscription plan,
/// its active authorizations, registry metadata, and its allowance.
///
/// Fan-in follows the [studentLedgerProvider] pattern: loading until every
/// source produced; source errors propagate honestly — except the
/// plan-matrix, which degrades to the documented per-Subject display
/// fallback when the reader lacks plan-matrix visibility (the matrix is
/// gated on content management while device management is gated on
/// `admin_devices`; authorization truth stays server-side either way).
final studentProfileDevicesProvider =
    Provider.family<AsyncValue<List<StudentSubjectDeviceRow>>, String>(
        (ref, studentId) {
  final AsyncValue<List<StudentSubjectRegistration>> regs =
      ref.watch(studentProfileSubjectsProvider(studentId));
  final AsyncValue<List<StudentSubjectSubscription>> subs =
      ref.watch(studentSubjectSubscriptionsProvider(studentId));
  final AsyncValue<List<SubjectDeviceAuthorization>> auths =
      ref.watch(studentDeviceAuthorizationsProvider(studentId));
  final AsyncValue<List<StudentDeviceRecord>> devs =
      ref.watch(studentDeviceRecordsProvider(studentId));
  final AsyncValue<Map<String, int>> allows =
      ref.watch(deviceAllowancesProvider);

  if (regs is AsyncLoading ||
      subs is AsyncLoading ||
      auths is AsyncLoading ||
      devs is AsyncLoading ||
      allows is AsyncLoading) {
    return const AsyncLoading<List<StudentSubjectDeviceRow>>();
  }
  if (regs is AsyncError) {
    return AsyncError<List<StudentSubjectDeviceRow>>(
        regs.error!, regs.stackTrace ?? StackTrace.empty);
  }
  if (subs is AsyncError) {
    return AsyncError<List<StudentSubjectDeviceRow>>(
        subs.error!, subs.stackTrace ?? StackTrace.empty);
  }
  if (auths is AsyncError) {
    return AsyncError<List<StudentSubjectDeviceRow>>(
        auths.error!, auths.stackTrace ?? StackTrace.empty);
  }
  if (devs is AsyncError) {
    return AsyncError<List<StudentSubjectDeviceRow>>(
        devs.error!, devs.stackTrace ?? StackTrace.empty);
  }
  final Map<String, int> allowances =
      allows.maybeWhen(data: (m) => m, orElse: () => const <String, int>{});
  return AsyncData<List<StudentSubjectDeviceRow>>(
    buildStudentSubjectDeviceRows(
      registrations: regs.value ?? const <StudentSubjectRegistration>[],
      planIdBySubject: <String, String>{
        for (final StudentSubjectSubscription s in subs.value ??
            const <StudentSubjectSubscription>[])
          s.subjectId: s.planId,
      },
      authorizations:
          auths.value ?? const <SubjectDeviceAuthorization>[],
      devices: devs.value ?? const <StudentDeviceRecord>[],
      allowancesByPlanId: allowances,
      studentId: studentId,
    ),
  );
});

/// Whether the current dashboard actor holds the delegated device
/// permission for [adminId]: active grant with `admin_devices == true`
/// (the exact backend key enforced by `requireDeviceManager`).
final adminDevicePermissionProvider =
    StreamProvider.family<bool, String>((ref, adminId) {
  final FirebaseFirestore db = ref.watch(firebaseFirestoreProvider);
  return db.collection('admin_permissions').doc(adminId).snapshots().map(
    (doc) {
      final Map<String, dynamic>? data = doc.data();
      if (data == null || data['is_active'] != true) return false;
      final Object? permissions = data['permissions'];
      if (permissions is! Map) return false;
      return permissions['admin_devices'] == true;
    },
  );
});

/// Whether the current actor may manage student devices (ADMIN_DEVICES).
///
/// Doctor (platform owner): full permission. Admin: only with the
/// delegated `admin_devices` grant. Unknown / loading / non-staff sessions
/// fail closed; the backend re-enforces this server-side on every write.
/// No role checks live in widgets — they read this provider.
final canManageStudentDevicesProvider =
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
  return ref.watch(adminDevicePermissionProvider(session.userId)).when(
        data: (can) => AsyncData<bool>(can),
        loading: () => const AsyncLoading<bool>(),
        error: (e, st) => AsyncError<bool>(e, st),
      );
});

/// Device writes for the Student Profile → Device tab.
///
/// - [unbindSubjectDevice] revokes ONE device for ONE Subject (per-Subject
///   unbind). Other devices, other Subjects, subscriptions, and plans are
///   untouched.
/// - [resetStudentDevices] revokes ALL active Subject-device authorizations
///   of the student (global reset). It never deletes the account, logs the
///   student out, or changes subscriptions/plans.
///
/// Backend/callable failures surface as [DeviceFailure] with the server
/// message for graceful UI display. Reason strings match the backend
/// defaults (`admin_unbind` / `reset_requested`) — no new audit vocabulary
/// is invented.
class StudentDeviceController {
  final FirebaseFunctions _functions;

  const StudentDeviceController(this._functions);

  String _message(Object error) {
    if (error is FirebaseFunctionsException) {
      final String? message = error.message;
      if (message != null && message.trim().isNotEmpty) return message;
      return switch (error.code) {
        'permission-denied' =>
          'You do not have permission to manage devices.',
        'not-found' => 'No active authorization exists for this device.',
        'invalid-argument' => 'Incomplete device information.',
        _ => 'Could not complete the device action. Try again.',
      };
    }
    if (error is DeviceFailure) return error.message;
    return 'Could not complete the device action. Try again.';
  }

  Future<void> unbindSubjectDevice({
    required String studentId,
    required String subjectId,
    required String deviceId,
  }) async {
    try {
      await _functions.httpsCallable('unbindSubjectDevice').call(
        <String, Object>{
          'studentId': studentId,
          'subjectId': subjectId,
          'deviceId': deviceId,
          'reason': 'admin_unbind',
        },
      );
    } on FirebaseFunctionsException catch (e) {
      throw DeviceFailure(_message(e));
    } catch (e) {
      throw DeviceFailure(_message(e));
    }
  }

  Future<int> resetStudentDevices({required String studentId}) async {
    try {
      final HttpsCallableResult<dynamic> result =
          await _functions.httpsCallable('resetStudentDevices').call(
        <String, Object>{
          'studentId': studentId,
          'reason': 'reset_requested',
        },
      );
      final Object? data = result.data;
      if (data is Map) {
        final Object? count = data['revokedCount'];
        if (count is num) return count.toInt();
      }
      return 0;
    } on FirebaseFunctionsException catch (e) {
      throw DeviceFailure(_message(e));
    } catch (e) {
      throw DeviceFailure(_message(e));
    }
  }
}

/// Typed failure for device management writes with a message safe to render.
class DeviceFailure implements Exception {
  const DeviceFailure(this.message);

  final String message;

  @override
  String toString() => 'DeviceFailure: $message';
}

final studentDeviceControllerProvider =
    Provider<StudentDeviceController>((ref) {
  return StudentDeviceController(ref.watch(firebaseFunctionsProvider));
});
