import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/firebase_providers.dart';
import '../../../applications/domain/entities/join_application.dart';
import '../../../applications/domain/grade.dart';

/// One row of the grade pending-requests table.
class PendingRequestRow {
  final JoinApplication application;
  final String deviceLabel;
  final String requestDate;

  const PendingRequestRow({
    required this.application,
    required this.deviceLabel,
    required this.requestDate,
  });
}

/// Formats a request/comparison date as D/M/YYYY (spec: e.g. `3/9/2026`).
String formatRequestDate(DateTime? date) {
  if (date == null) return '—';
  return '${date.day}/${date.month}/${date.year}';
}

/// Resolves a human-readable device label for a pending user doc.
///
/// Prefers inline fields on the user doc, then falls back to the shared
/// [deviceLabels] lookup (devices collection keyed by `device_id`).
String _deviceFromUserDoc(
  Map<String, dynamic> data,
  Map<String, String> deviceLabels,
) {
  final Object? inline =
      data['device_model'] ?? data['device_name'] ?? data['device'];
  if (inline is String && inline.trim().isNotEmpty) return inline.trim();
  final Object? deviceId = data['device_id'];
  if (deviceId is String && deviceId.isNotEmpty) {
    return deviceLabels[deviceId] ?? deviceId;
  }
  return '—';
}

/// Batched lookup of device models from the `devices` collection
/// (mirrors the mobile admin students-management screen).
Future<Map<String, String>> _fetchDeviceLabels(
  FirebaseFirestore db,
  Set<String> deviceIds,
) async {
  final Map<String, String> labels = <String, String>{};
  final List<String> ids =
      deviceIds.where((String id) => id.isNotEmpty).toList();
  for (int i = 0; i < ids.length; i += 10) {
    final List<String> chunk = ids.sublist(
      i,
      i + 10 > ids.length ? ids.length : i + 10,
    );
    final QuerySnapshot<Map<String, dynamic>> snap = await db
        .collection('devices')
        .where(FieldPath.documentId, whereIn: chunk)
        .get();
    for (final doc in snap.docs) {
      final Map<String, dynamic> data = doc.data();
      final Object? model =
          data['device_model'] ?? data['model'];
      labels[doc.id] = (model is String && model.trim().isNotEmpty)
          ? model.trim()
          : doc.id;
    }
  }
  return labels;
}

/// Live pending requests for [gradeKey] from `users`
/// (`role == 'new_student'` + `approval_status == 'pending'`, filtered to
/// the grade client-side via [normalizeGradeKey] so no composite index is
/// needed beyond the queue's own).
///
/// An empty queue yields an empty list so the table renders its empty
/// state. Firestore failures propagate to the UI error state — they are
/// never replaced with placeholder students.
final gradePendingRequestsProvider =
    FutureProvider.family<List<PendingRequestRow>, String>(
  (ref, String gradeKey) async {
    return _fetchLive(ref, gradeKey);
  },
);

Future<List<PendingRequestRow>> _fetchLive(
  Ref ref,
  String gradeKey,
) async {
  final FirebaseFirestore db = ref.watch(firebaseFirestoreProvider);

  final QuerySnapshot<Map<String, dynamic>> snap = await db
      .collection('users')
      .where('role', isEqualTo: 'new_student')
      .where('approval_status', isEqualTo: 'pending')
      .limit(500)
      .get();

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
      <QueryDocumentSnapshot<Map<String, dynamic>>>[
    for (final doc in snap.docs)
      if (normalizeGradeKey(doc.data()['grade']) == gradeKey) doc,
  ];

  if (docs.isEmpty) return <PendingRequestRow>[];

  final Set<String> deviceIds = <String>{
    for (final doc in docs)
      if (doc.data()['device_id'] is String)
        (doc.data()['device_id'] as String),
  };
  final Map<String, String> deviceLabels =
      await _fetchDeviceLabels(db, deviceIds);

  return <PendingRequestRow>[
    for (final doc in docs)
      PendingRequestRow(
        application: JoinApplication.fromDoc(doc),
        deviceLabel: _deviceFromUserDoc(doc.data(), deviceLabels),
        requestDate: formatRequestDate(
          (doc.data()['created_at'] as Timestamp?)?.toDate(),
        ),
      ),
  ];
}
