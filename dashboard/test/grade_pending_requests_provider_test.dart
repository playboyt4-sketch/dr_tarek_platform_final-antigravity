import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drtarek_dashboard/core/di/firebase_providers.dart';
import 'package:drtarek_dashboard/features/students/presentation/providers/grade_pending_requests_provider.dart';

/// Provider contract: live Firestore rows only. An empty queue yields an
/// empty list (the table renders its empty state); failures propagate to
/// the UI error state. No placeholder students are ever synthesized.
void main() {
  group('gradePendingRequestsProvider', () {
    test('empty queue yields an empty list, never placeholder students',
        () async {
      final FakeFirebaseFirestore fake = FakeFirebaseFirestore();
      final ProviderContainer container = ProviderContainer(
        overrides: [
          firebaseFirestoreProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);

      final List<PendingRequestRow> rows = await container.read(
        gradePendingRequestsProvider('grade_one').future,
      );

      expect(rows, isEmpty);
      expect(
        rows.where((PendingRequestRow row) =>
            row.application.fullName == 'Ahmed gamal mousa'),
        isEmpty,
      );
    });

    test('maps live pending docs for the requested grade only', () async {
      final FakeFirebaseFirestore fake = FakeFirebaseFirestore();
      await fake.collection('users').add(<String, dynamic>{
        'role': 'new_student',
        'approval_status': 'pending',
        'grade': 'Grade One',
        'full_name': 'Real Applicant',
        'phone_number': '01000000009',
        'student_type': 'center_student',
        'device_model': 'Pixel 8',
        'created_at': Timestamp.fromDate(DateTime(2026, 9, 1)),
      });
      await fake.collection('users').add(<String, dynamic>{
        'role': 'new_student',
        'approval_status': 'pending',
        'grade': 'Grade Two',
        'full_name': 'Other Grade Applicant',
        'phone_number': '01000000008',
        'student_type': 'guest',
        'created_at': Timestamp.fromDate(DateTime(2026, 9, 2)),
      });
      await fake.collection('users').add(<String, dynamic>{
        'role': 'student',
        'approval_status': 'approved',
        'grade': 'Grade One',
        'full_name': 'Approved Student',
        'phone_number': '01000000007',
        'student_type': 'center_student',
        'created_at': Timestamp.fromDate(DateTime(2026, 9, 3)),
      });

      final ProviderContainer container = ProviderContainer(
        overrides: [
          firebaseFirestoreProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);

      final List<PendingRequestRow> rows = await container.read(
        gradePendingRequestsProvider('grade_one').future,
      );

      expect(rows, hasLength(1));
      expect(rows.first.application.fullName, 'Real Applicant');
      expect(rows.first.application.phone, '01000000009');
      expect(rows.first.deviceLabel, 'Pixel 8');
      expect(rows.first.requestDate, '1/9/2026');
    });
  });
}
