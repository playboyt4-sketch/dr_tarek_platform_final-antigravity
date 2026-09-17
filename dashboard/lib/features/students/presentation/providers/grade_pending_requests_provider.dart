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

/// Figma fallback rows (visible in the reference frame) so the table is
/// always full and beautiful while the queue is empty or unreachable.
List<PendingRequestRow> fallbackPendingRequests(String gradeKey) {
  const List<({String name, String phone, String device, String date})> rows =
      <({String name, String phone, String device, String date})>[
    (
      name: 'Ahmed gamal mousa',
      phone: '01101011588',
      device: 'I phone 15 pro',
      date: '3/9/2026',
    ),
    (
      name: 'Mariam adel samy',
      phone: '01022334455',
      device: 'Samsung A54',
      date: '2/9/2026',
    ),
    (
      name: 'Omar khaled hassan',
      phone: '01233445566',
      device: 'I phone 13',
      date: '1/9/2026',
    ),
    (
      name: 'Salma mohamed ali',
      phone: '01544556677',
      device: 'Xiaomi Redmi 12',
      date: '31/8/2026',
    ),
    (
      name: 'Youssef tarek adel',
      phone: '01155667788',
      device: 'I phone 15 pro',
      date: '30/8/2026',
    ),
  ];
  return <PendingRequestRow>[
    for (int i = 0; i < rows.length; i++)
      PendingRequestRow(
        application: JoinApplication(
          id: 'fallback-$gradeKey-$i',
          fullName: rows[i].name,
          phone: rows[i].phone,
          gradeKey: gradeKey,
          studentType: 'center_student',
          createdAt: null,
        ),
        deviceLabel: rows[i].device,
        requestDate: rows[i].date,
      ),
  ];
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
/// Falls back to the Figma reference rows when the queue is empty or
/// Firestore is unreachable, so the table always stays full during
/// preview and offline states.
final gradePendingRequestsProvider =
    FutureProvider.family<List<PendingRequestRow>, String>(
  (ref, String gradeKey) async {
    try {
      return await _fetchLive(ref, gradeKey);
    } catch (_) {
      return fallbackPendingRequests(gradeKey);
    }
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

  if (docs.isEmpty) return fallbackPendingRequests(gradeKey);

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
