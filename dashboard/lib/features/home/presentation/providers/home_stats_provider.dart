import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/firebase_providers.dart';

/// Live platform counters shown on the dashboard home "Analytics &
/// Reports" section (Figma frame 457:421 — the crypto artwork there is a
/// template placeholder; these stats are the real content).
class HomeStats {
  final int students;
  final int subjects;
  final int pendingApplications;
  final int staff;

  const HomeStats({
    required this.students,
    required this.subjects,
    required this.pendingApplications,
    required this.staff,
  });
}

/// Aggregated counts. Each query keeps a single filter so no composite
/// indexes are required; pending = students − approved.
final homeStatsProvider = FutureProvider<HomeStats>((ref) async {
  final FirebaseFirestore db = ref.watch(firebaseFirestoreProvider);

  final studentsSnap = await db
      .collection('users')
      .where('role', whereIn: <String>['student', 'new_student'])
      .count()
      .get();
  final approvedSnap = await db
      .collection('users')
      .where('approval_status', isEqualTo: 'approved')
      .count()
      .get();
  final subjectsSnap = await db
      .collection('subjects')
      .where('is_deleted', isEqualTo: false)
      .count()
      .get();
  final staffSnap = await db
      .collection('users')
      .where('role', whereIn: <String>['admin', 'teacher'])
      .count()
      .get();

  final students = studentsSnap.count ?? 0;
  final approved = approvedSnap.count ?? 0;

  return HomeStats(
    students: students,
    subjects: subjectsSnap.count ?? 0,
    pendingApplications: students - approved < 0 ? 0 : students - approved,
    staff: staffSnap.count ?? 0,
  );
});
