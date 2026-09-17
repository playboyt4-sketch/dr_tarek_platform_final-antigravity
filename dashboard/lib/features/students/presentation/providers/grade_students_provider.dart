import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/firebase_providers.dart';
import '../../../applications/domain/grade.dart';
import '../../data/mock_students.dart';

/// One row of the grade students table.
class GradeStudent {
  final String id;
  final String name;
  final bool isCenter;
  final String plan;
  final bool isActive;
  final String lastSignIn;

  /// Phone is optional: present for mock rows, best-effort for live docs
  /// (`phone_number` / `phone` keys vary across writers).
  final String? phone;

  const GradeStudent({
    required this.id,
    required this.name,
    required this.isCenter,
    required this.plan,
    required this.isActive,
    required this.lastSignIn,
    this.phone,
  });

  String get typeLabel => isCenter ? 'Center' : 'Guest';
  String get statusLabel => isActive ? 'Active' : 'Inactive';

  /// Defensive parse: plan/status/last-seen keys vary across writers, so
  /// several spellings are accepted before falling back to safe defaults.
  factory GradeStudent.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> data = doc.data();
    final String rawName = (data['full_name'] as String?) ??
        (data['display_name'] as String?) ??
        (data['name'] as String? ) ??
        '';
    return GradeStudent(
      id: doc.id,
      name: rawName.trim().isEmpty ? 'Unknown student' : rawName.trim(),
      isCenter: data['student_type'] == 'center_student',
      plan: _normalizePlan(data),
      isActive: _normalizeActive(data),
      lastSignIn: _formatLastSignIn(data),
      phone: (data['phone_number'] as String?) ?? (data['phone'] as String?),
    );
  }

  static String _normalizePlan(Map<String, dynamic> data) {
    final String raw = ((data['plan'] as String?) ??
            (data['plan_key'] as String?) ??
            (data['subscription_plan'] as String?) ??
            'FREE')
        .toUpperCase();
    if (raw.contains('MAX')) return 'MAX';
    if (raw.contains('PRO')) return 'PRO';
    return 'FREE';
  }

  static bool _normalizeActive(Map<String, dynamic> data) {
    final Object? active = data['is_active'] ?? data['active'];
    if (active is bool) return active;
    final Object? status = data['status'] ?? data['account_status'];
    if (status is String) {
      final String lower = status.toLowerCase();
      if (lower.contains('inactiv') || lower.contains('disabled')) {
        return false;
      }
      if (lower.contains('activ')) return true;
    }
    return data['approval_status'] == 'approved';
  }

  static String _formatLastSignIn(Map<String, dynamic> data) {
    final Object? raw = data['last_sign_in'] ??
        data['last_login'] ??
        data['last_seen'];
    DateTime? date;
    if (raw is Timestamp) {
      date = raw.toDate();
    } else if (raw is String && raw.isNotEmpty) {
      date = DateTime.tryParse(raw);
    }
    if (date == null) return '—';
    return '${date.day}/${date.month}/${date.year}';
  }
}

/// One plan-breakdown line (Frame 39).
class PlanBreakdownRow {
  final String label;
  final int count;
  final int share;

  const PlanBreakdownRow({
    required this.label,
    required this.count,
    required this.share,
  });
}

/// Full data snapshot for one grade's students section.
class GradeStudentsData {
  final String gradeKey;
  final List<GradeStudent> students;
  final int pendingCount;
  final List<PlanBreakdownRow> breakdown;
  final bool isFallback;

  const GradeStudentsData({
    required this.gradeKey,
    required this.students,
    required this.pendingCount,
    required this.breakdown,
    required this.isFallback,
  });

  int get total => students.length;
}

/// Live grade students from `users` (approved students of [gradeKey] +
/// pending-request count). Single-filter queries only — grade is matched
/// client-side via [normalizeGradeKey] so no composite index is needed.
///
/// Always reports the true live numbers — including real zeros and empty
/// tables — so new sign-ups show up immediately. No mock fallback is
/// substituted; unreachable Firestore surfaces as a provider error.
final gradeStudentsProvider = FutureProvider.family<GradeStudentsData, String>(
  (ref, String gradeKey) async {
    // Visual-verification path: serve mock rows + mock total instead of
    // Firestore. Flip [kUseMockGradeStudents] to false to go live.
    if (kUseMockGradeStudents) return mockGradeStudentsData(gradeKey);
    return _fetchLive(ref, gradeKey);
  },
);

Future<GradeStudentsData> _fetchLive(Ref ref, String gradeKey) async {
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

  final List<GradeStudent> students = <GradeStudent>[];
  for (final doc in approvedSnap.docs) {
    final Map<String, dynamic> data = doc.data();
    if (data['approval_status'] != 'approved') continue;
    if (normalizeGradeKey(data['grade']) != gradeKey) continue;
    students.add(GradeStudent.fromDoc(doc));
  }

  int pending = 0;
  for (final doc in pendingSnap.docs) {
    if (normalizeGradeKey(doc.data()['grade']) == gradeKey) pending++;
  }

  return GradeStudentsData(
    gradeKey: gradeKey,
    students: students,
    pendingCount: pending,
    breakdown: _liveBreakdown(students),
    isFallback: false,
  );
}

List<PlanBreakdownRow> _liveBreakdown(List<GradeStudent> students) {
  int freeCount = 0, pro = 0, max = 0, guestCount = 0;
  for (final GradeStudent student in students) {
    if (student.plan == 'PRO') {
      pro++;
    } else if (student.plan == 'MAX') {
      max++;
    } else if (student.isCenter) {
      freeCount++;
    } else {
      guestCount++;
    }
  }
  int share(int count) =>
      students.isEmpty ? 0 : ((count * 100) / students.length).round();
  return <PlanBreakdownRow>[
    PlanBreakdownRow(label: 'Free', count: freeCount, share: share(freeCount)),
    PlanBreakdownRow(label: 'PRO', count: pro, share: share(pro)),
    PlanBreakdownRow(label: 'MAX', count: max, share: share(max)),
    PlanBreakdownRow(label: 'Guest', count: guestCount, share: share(guestCount)),
  ];
}

/// Instant client-side filtering by [scope] + [query].
List<GradeStudent> filterStudents(
  List<GradeStudent> students,
  StudentSearchScope scope,
  String query,
) {
  final String needle = query.trim().toLowerCase();
  if (needle.isEmpty) return students;
  bool matches(GradeStudent student) {
    switch (scope) {
      case StudentSearchScope.name:
        return student.name.toLowerCase().contains(needle);
      case StudentSearchScope.type:
        return student.typeLabel.toLowerCase().contains(needle);
      case StudentSearchScope.plan:
        return student.plan.toLowerCase().contains(needle);
      case StudentSearchScope.status:
        return student.statusLabel.toLowerCase().contains(needle);
    }
  }

  return students.where(matches).toList(growable: false);
}

/// Search scope mirror kept in the data layer so filtering stays
/// unit-testable without importing presentation widgets.
enum StudentSearchScope { name, type, plan, status }
