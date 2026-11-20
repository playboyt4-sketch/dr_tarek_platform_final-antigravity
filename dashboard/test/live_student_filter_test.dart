import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drtarek_dashboard/core/di/firebase_providers.dart';
import 'package:drtarek_dashboard/features/home/presentation/providers/home_stats_provider.dart';
import 'package:drtarek_dashboard/features/students/domain/live_student.dart';
import 'package:drtarek_dashboard/features/students/presentation/providers/grade_pending_requests_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/providers/grade_students_provider.dart';

/// The approved lifecycle is soft delete + audit retention: deleted rows stay
/// in `users`. These tests pin the single canonical live-student rule
/// (`is_deleted != true && account_status != 'disabled'`) across every
/// Dashboard list, queue, and counter that reads students.
void main() {
  group('isLiveStudent', () {
    test('rejects soft-deleted records', () {
      expect(
        isLiveStudent(<String, dynamic>{'is_deleted': true}),
        isFalse,
      );
    });

    test('rejects disabled accounts even without is_deleted', () {
      expect(
        isLiveStudent(<String, dynamic>{'account_status': 'disabled'}),
        isFalse,
      );
    });

    test('accepts active, non-deleted records', () {
      expect(
        isLiveStudent(<String, dynamic>{
          'is_deleted': false,
          'account_status': 'active',
        }),
        isTrue,
      );
    });

    test('treats legacy rows without lifecycle flags as live', () {
      expect(isLiveStudent(<String, dynamic>{}), isTrue);
    });
  });

  group('student lists exclude soft-deleted and disabled rows', () {
    Future<FakeFirebaseFirestore> seed() async {
      final FakeFirebaseFirestore fake = FakeFirebaseFirestore();
      // Live approved student — must render.
      await fake.collection('users').add(<String, dynamic>{
        'role': 'student',
        'approval_status': 'approved',
        'grade': 'Grade One',
        'full_name': 'Live Approved',
        'student_type': 'center_student',
        'is_deleted': false,
        'account_status': 'active',
      });
      // Soft-deleted approved student — must never render, not even inactive.
      await fake.collection('users').add(<String, dynamic>{
        'role': 'student',
        'approval_status': 'approved',
        'grade': 'Grade One',
        'full_name': 'Deleted Approved',
        'student_type': 'center_student',
        'is_deleted': true,
        'account_status': 'disabled',
      });
      // Disabled approved student without is_deleted (removeAdmin shape).
      await fake.collection('users').add(<String, dynamic>{
        'role': 'student',
        'approval_status': 'approved',
        'grade': 'Grade One',
        'full_name': 'Disabled Approved',
        'student_type': 'guest',
        'account_status': 'disabled',
      });
      // Approved student in another grade — filtered by grade key.
      await fake.collection('users').add(<String, dynamic>{
        'role': 'student',
        'approval_status': 'approved',
        'grade': 'Grade Two',
        'full_name': 'Other Grade',
        'student_type': 'guest',
        'is_deleted': false,
        'account_status': 'active',
      });
      // Pending rows: one live, one soft-deleted.
      await fake.collection('users').add(<String, dynamic>{
        'role': 'new_student',
        'approval_status': 'pending',
        'grade': 'Grade One',
        'full_name': 'Live Pending',
        'student_type': 'center_student',
        'is_deleted': false,
        'account_status': 'active',
      });
      await fake.collection('users').add(<String, dynamic>{
        'role': 'new_student',
        'approval_status': 'pending',
        'grade': 'Grade One',
        'full_name': 'Deleted Pending',
        'student_type': 'center_student',
        'is_deleted': true,
        'account_status': 'disabled',
      });
      return fake;
    }

    test('gradeStudentsProvider renders only live approved students and '
        'counts only live pending requests', () async {
      final FakeFirebaseFirestore fake = await seed();
      final ProviderContainer container = ProviderContainer(
        overrides: [
          firebaseFirestoreProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);

      final GradeStudentsData data =
          await container.read(gradeStudentsProvider('grade_one').future);

      expect(
        data.students.map((GradeStudent s) => s.name),
        <String>['Live Approved'],
      );
      expect(data.total, 1);
      expect(data.pendingCount, 1);
    });

    test('gradePendingRequestsProvider drops deleted pending requests',
        () async {
      final FakeFirebaseFirestore fake = await seed();
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
      expect(rows.first.application.fullName, 'Live Pending');
    });

    test('homeAnalyticsProvider excludes deleted/disabled students from '
        'totals and pending counts', () async {
      final FakeFirebaseFirestore fake = await seed();
      final ProviderContainer container = ProviderContainer(
        overrides: [
          firebaseFirestoreProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);

      final HomeAnalytics analytics =
          await container.read(homeAnalyticsProvider.future);
      final GradeAnalytics gradeOne = analytics.grades.firstWhere(
        (GradeAnalytics g) => g.gradeKey == 'grade_one',
      );

      // Live approved students across all grades (Live Approved +
      // Other Grade); the deleted/disabled rows are excluded.
      expect(analytics.totalStudents, 2);
      expect(gradeOne.total, 1);
      expect(gradeOne.pending, 1);
      expect(gradeOne.center, 1);
      expect(gradeOne.guest, 0);
    });

    test('homeStatsProvider counts only live student lifecycle rows',
        () async {
      final FakeFirebaseFirestore fake = await seed();
      final ProviderContainer container = ProviderContainer(
        overrides: [
          firebaseFirestoreProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);

      final HomeStats stats = await container.read(homeStatsProvider.future);

      // Live approved (2, across grades) + live pending (1); the
      // deleted/disabled rows never reach the student total.
      expect(stats.students, 3);
      expect(stats.pendingApplications, 1);
    });
  });
}
