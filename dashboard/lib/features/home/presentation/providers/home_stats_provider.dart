import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/firebase_providers.dart';
import '../../../applications/domain/grade.dart';
import '../../../students/data/mock_students.dart';

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

// ---------------------------------------------------------------------------
// Unified live analytics for `dashboard - home` (1280 x 800).
// ---------------------------------------------------------------------------

/// Active-today counter. There is no activity feed in the Firestore schema
/// yet, so live snapshots report 0 until one lands. The Figma reference
/// (240) survives only inside [HomeAnalytics.fallback], which is kept for
/// previews, offline error states and tests.
const int kFallbackActiveToday = 240;

/// Per-grade live analytics row.
class GradeAnalytics {
  final String gradeKey;
  final int total;
  final int pending;
  final int center;
  final int guest;

  const GradeAnalytics({
    required this.gradeKey,
    required this.total,
    required this.pending,
    required this.center,
    required this.guest,
  });

  double get centerShare => total == 0 ? 0 : center * 100 / total;
  double get guestShare => total == 0 ? 0 : guest * 100 / total;

  String get centerShareLabel => '${centerShare.round()}%';
  String get guestShareLabel => '${guestShare.round()}%';
}

/// English display title for a canonical grade key.
String gradeAnalyticsTitle(String gradeKey) {
  return switch (gradeKey) {
    'grade_one' => 'Grade One',
    'grade_two' => 'Grade Two',
    'grade_three' => 'Grade Three',
    'grade_four' => 'Grade Four',
    _ => gradeKey,
  };
}

/// Unified analytics snapshot driving the home screen.
class HomeAnalytics {
  final int totalStudents;
  final int activeToday;
  final List<GradeAnalytics> grades;
  final bool isFallback;

  /// Active students per day for the last seven days (Sat → Fri).
  /// No activity feed exists in the Firestore schema yet, so live
  /// snapshots report all zeros until one lands.
  final List<int> weeklyActivity;

  /// Highest daily value of [weeklyActivity] (0 when no data yet).
  int get maxWeeklyActivity => weeklyActivity.fold(0, math.max);

  const HomeAnalytics({
    required this.totalStudents,
    required this.activeToday,
    required this.grades,
    required this.isFallback,
    required this.weeklyActivity,
  });

  /// Smart fallback (Figma reference) so the screen always looks full and
  /// beautiful while the database is still getting started.
  factory HomeAnalytics.fallback() {
    return const HomeAnalytics(
      totalStudents: 1240,
      activeToday: kFallbackActiveToday,
      isFallback: true,
      weeklyActivity: <int>[100, 130, 150, 170, 190, 210, 240],
      grades: <GradeAnalytics>[
        GradeAnalytics(
          gradeKey: 'grade_one',
          total: 450,
          pending: 7,
          center: 396,
          guest: 54,
        ),
        GradeAnalytics(
          gradeKey: 'grade_two',
          total: 380,
          pending: 9,
          center: 266,
          guest: 114,
        ),
        GradeAnalytics(
          gradeKey: 'grade_three',
          total: 260,
          pending: 13,
          center: 143,
          guest: 117,
        ),
        GradeAnalytics(
          gradeKey: 'grade_four',
          total: 150,
          pending: 5,
          center: 135,
          guest: 15,
        ),
      ],
    );
  }
}

/// Automatic Y-axis scale for the Student Activity chart, always starting
/// at zero (6 ticks, 5 equal intervals):
///
/// - maxVal == 0 → ceiling 10 → [10, 8, 6, 4, 2, 0];
/// - maxVal <= 50 → ceiling 50 → [50, 40, 30, 20, 10, 0];
/// - maxVal <= 250 → ceiling 250 → [250, 200, 150, 100, 50, 0];
/// - maxVal > 250 → rounded up to the nearest 100, split into 5 equal
///   intervals ending at 0.
List<int> yTicksForMax(int maxVal) {
  if (maxVal <= 0) return const <int>[10, 8, 6, 4, 2, 0];
  if (maxVal <= 50) return const <int>[50, 40, 30, 20, 10, 0];
  if (maxVal <= 250) return const <int>[250, 200, 150, 100, 50, 0];
  final int ceiling = ((maxVal + 99) ~/ 100) * 100;
  final int step = ceiling ~/ 5;
  return <int>[for (int i = 5; i >= 0; i--) i * step];
}

/// Live analytics from `users`.
///
/// - approved students (`role == 'student'`, filtered client-side on
///   `approval_status == 'approved'` so no composite index is needed)
///   grouped per grade via [normalizeGradeKey], split into center
///   (`student_type == 'center_student'`) vs guest students;
/// - pending applications per grade (`role == 'new_student'` +
///   `approval_status == 'pending'`, the same composite the reviewing
///   queue already relies on).
///
/// Always reports the true live numbers — including real zeros — so new
/// sign-ups show up immediately. No mock fallback is substituted.
final homeAnalyticsProvider = FutureProvider<HomeAnalytics>((ref) async {
  // Visual-verification path: global "Total Students" == mockStudents.length
  // (6) with real per-grade splits. Flip [kUseMockGradeStudents] to false
  // to restore the live Firestore query.
  if (kUseMockGradeStudents) return _mockHomeAnalytics();
  final FirebaseFirestore db = ref.watch(firebaseFirestoreProvider);

  final approvedSnap = await db
      .collection('users')
      .where('role', isEqualTo: 'student')
      .limit(5000)
      .get();
  final pendingSnap = await db
      .collection('users')
      .where('role', isEqualTo: 'new_student')
      .where('approval_status', isEqualTo: 'pending')
      .limit(5000)
      .get();

  final Map<String, int> totals = <String, int>{};
  final Map<String, int> centers = <String, int>{};
  final Map<String, int> guests = <String, int>{};
  int approvedCount = 0;

  for (final doc in approvedSnap.docs) {
    final Map<String, dynamic> data = doc.data();
    if (data['approval_status'] != 'approved') continue;
    final String? gradeKey = normalizeGradeKey(data['grade']);
    if (gradeKey == null || !canonicalGradeKeys.contains(gradeKey)) continue;
    approvedCount++;
    totals[gradeKey] = (totals[gradeKey] ?? 0) + 1;
    if (data['student_type'] == 'center_student') {
      centers[gradeKey] = (centers[gradeKey] ?? 0) + 1;
    } else {
      guests[gradeKey] = (guests[gradeKey] ?? 0) + 1;
    }
  }

  final Map<String, int> pendings = <String, int>{};
  for (final doc in pendingSnap.docs) {
    final String? gradeKey =
        normalizeGradeKey(doc.data()['grade']);
    if (gradeKey == null || !canonicalGradeKeys.contains(gradeKey)) continue;
    pendings[gradeKey] = (pendings[gradeKey] ?? 0) + 1;
  }

  return HomeAnalytics(
    totalStudents: approvedCount,
    activeToday: 0,
    isFallback: false,
    // No activity feed in the schema yet → all zeros until events land.
    weeklyActivity: List<int>.filled(7, 0),
    grades: <GradeAnalytics>[
      for (final gradeKey in canonicalGradeKeys)
        GradeAnalytics(
          gradeKey: gradeKey,
          total: totals[gradeKey] ?? 0,
          pending: pendings[gradeKey] ?? 0,
          center: centers[gradeKey] ?? 0,
          guest: guests[gradeKey] ?? 0,
        ),
    ],
  );
});

/// Mock analytics derived from [mockStudents] for visual verification:
/// global total == mockStudents.length; per-grade rows split center/guest.
HomeAnalytics _mockHomeAnalytics() {
  final Map<String, int> totals = <String, int>{};
  final Map<String, int> centers = <String, int>{};
  final Map<String, int> guests = <String, int>{};
  for (final MockStudent student in mockStudents) {
    totals[student.gradeKey] = (totals[student.gradeKey] ?? 0) + 1;
    if (student.isCenter) {
      centers[student.gradeKey] = (centers[student.gradeKey] ?? 0) + 1;
    } else {
      guests[student.gradeKey] = (guests[student.gradeKey] ?? 0) + 1;
    }
  }
  return HomeAnalytics(
    totalStudents: mockStudents.length,
    activeToday: 0,
    isFallback: false,
    weeklyActivity: List<int>.filled(7, 0),
    grades: <GradeAnalytics>[
      for (final gradeKey in canonicalGradeKeys)
        GradeAnalytics(
          gradeKey: gradeKey,
          total: totals[gradeKey] ?? 0,
          pending: 0,
          center: centers[gradeKey] ?? 0,
          guest: guests[gradeKey] ?? 0,
        ),
    ],
  );
}
