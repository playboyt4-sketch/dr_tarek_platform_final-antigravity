import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/firebase_providers.dart';
import '../../../applications/domain/grade.dart';
import '../../data/mock_students.dart';
import 'student_profile_subjects_provider.dart' show planDisplayForKey;

/// Honest per-student plan summary for the grade Students list.
///
/// There is deliberately NO single "student plan": a subscription belongs
/// to a (student, subject) pair (Feature 14, ADR-004), so one student can
/// hold FREE on one subject and MAX on another simultaneously. This type
/// only counts the true distribution of the student's REGISTERED subjects
/// (non-deleted assignments joined with the live subject catalog — the
/// exact Subjects-tab axis), with tiers resolved from the active,
/// non-deleted subscriptions — display-only, never authorization input.
class StudentPlanSummary {
  /// Distinct registered subjects (matches the Subjects-tab row count).
  final int subjects;

  /// Distinct registered subjects with an active subscription at the tier.
  /// `free + pro + max + unknown` always equals [subjects].
  final int free;
  final int pro;
  final int max;

  /// Active subscriptions whose plan document is missing, plus
  /// registered subjects with no active subscription at all (broken rows
  /// showing "بدون خطة نشطة" inside): counted in [subjects] but in no
  /// tier bucket, so the row never silently undercounts.
  final int unknown;

  const StudentPlanSummary({
    this.subjects = 0,
    this.free = 0,
    this.pro = 0,
    this.max = 0,
    this.unknown = 0,
  });

  static const StudentPlanSummary empty = StudentPlanSummary();

  bool get hasActivePlan => subjects > 0;
  bool get hasFree => free > 0;
  bool get hasPro => pro > 0;
  bool get hasMax => max > 0;

  /// Single-line truthful rendering, e.g.
  /// "3 subjects · 1 FREE, 1 PRO, 1 MAX" or "No active plan".
  String get displayText {
    if (!hasActivePlan) return 'No active plan';
    final List<String> tiers = <String>[
      if (free > 0) '$free FREE',
      if (pro > 0) '$pro PRO',
      if (max > 0) '$max MAX',
      if (unknown > 0) '$unknown other',
    ];
    return '$subjects subject${subjects == 1 ? '' : 's'} · ${tiers.join(', ')}';
  }

  /// Tier-keyword search over the true distribution (matches the
  /// "Search by Plan (FREE / PRO / MAX)" scope): a keyword matches when
  /// the student holds at least one active subscription at that tier;
  /// "no active" matches students with none.
  bool matchesPlanQuery(String needle) {
    final String q = needle.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (!hasActivePlan) return 'no active plan'.contains(q);
    return (hasFree && 'free'.contains(q)) ||
        (hasPro && 'pro'.contains(q)) ||
        (hasMax && 'max'.contains(q));
  }
}

/// One row of the grade students table.
///
/// [planSummary] is the display-only distribution of the student's live
/// subject subscriptions (see [StudentPlanSummary]) — never a single
/// authoritative "student plan" (retired model, ADR-004).
class GradeStudent {
  final String id;
  final String name;
  final bool isCenter;
  final StudentPlanSummary planSummary;
  final bool isActive;
  final String lastSignIn;

  /// Phone is optional: present for mock rows, best-effort for live docs
  /// (`phone_number` / `phone` keys vary across writers).
  final String? phone;

  /// Student avatar URL (`users.profile_photo`, written by the app's
  /// profile-photo upload). Null when the student never uploaded a photo.
  final String? photoUrl;

  const GradeStudent({
    required this.id,
    required this.name,
    required this.isCenter,
    this.planSummary = StudentPlanSummary.empty,
    required this.isActive,
    required this.lastSignIn,
    this.phone,
    this.photoUrl,
  });

  String get typeLabel => isCenter ? 'Center' : 'Guest';
  String get statusLabel => isActive ? 'Active' : 'Inactive';

  /// Defensive parse of identity/status keys (name/phone/status spellings
  /// vary across writers). Plan data is deliberately NOT read here: the
  /// legacy `plan` / `plan_key` / `subscription_plan` scalars on `users`
  /// docs are never written by the backend (registration and approval
  /// write no such field) and silently defaulted every student to FREE.
  /// The true distribution is attached by [_fetchLive] from live
  /// `subscriptions` rows (see [buildStudentPlanSummaries]).
  factory GradeStudent.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> data = doc.data();
    final String rawName = (data['full_name'] as String?) ??
        (data['display_name'] as String?) ??
        (data['name'] as String? ) ??
        '';
    final String? rawPhoto = (data['profile_photo'] as String?) ??
        (data['photo_url'] as String?) ??
        (data['avatar_url'] as String?);
    return GradeStudent(
      id: doc.id,
      name: rawName.trim().isEmpty ? 'Unknown student' : rawName.trim(),
      isCenter: data['student_type'] == 'center_student',
      isActive: _normalizeActive(data),
      lastSignIn: _formatLastSignIn(data),
      phone: (data['phone_number'] as String?) ?? (data['phone'] as String?),
      photoUrl: rawPhoto?.trim().isEmpty == true ? null : rawPhoto?.trim(),
    );
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

  // Honest plan data, read live — never denormalized onto `users` (a
  // stored copy is exactly the drift class that produced the flat "FREE"
  // column this replaces). Cost per list load: 1 `users` query above +
  // ceil(n/10) single-field `whereIn` subscription queries + 1 `plans`
  // query; status/is_deleted are filtered client-side so no composite
  // index is required (same discipline as the profile providers).
  final Map<String, StudentPlanSummary> summaries =
      await _fetchPlanSummaries(db, <String>[for (final s in students) s.id]);
  final List<GradeStudent> withPlans = <GradeStudent>[
    for (final GradeStudent s in students)
      GradeStudent(
        id: s.id,
        name: s.name,
        isCenter: s.isCenter,
        planSummary: summaries[s.id] ?? StudentPlanSummary.empty,
        isActive: s.isActive,
        lastSignIn: s.lastSignIn,
        phone: s.phone,
        photoUrl: s.photoUrl,
      ),
  ];

  return GradeStudentsData(
    gradeKey: gradeKey,
    students: withPlans,
    pendingCount: pending,
    breakdown: buildPlanBreakdown(withPlans),
    isFallback: false,
  );
}

/// Live per-student plan summaries for [studentIds].
///
/// One single-field `whereIn` query per chunk of 10 ids (Firestore limit),
/// then the same active-subscription criteria as the profile Subjects tab
/// (`status == 'active'`, `is_deleted != true`) applied client-side, with
/// tiers resolved through the data-driven `plans` collection exactly like
/// the profile join — so the list can never disagree with the Subjects tab.
///
/// Consistency rule (fixes 5-vs-4 drift): the Subjects tab lists exactly
/// the non-deleted `subject_access_assignments` joined with the live
/// `subjects` catalog. A `removeSubject` (Delete) only archives the
/// assignment and leaves the `subscriptions` row orphaned, and a deleted
/// platform Subject likewise orphans its subscriptions. Counting raw
/// subscriptions therefore overcounts vs the tab. To stay identical, this
/// fetch also reads assignments + the non-deleted subject catalog and
/// counts ONLY the intersection (registered + catalog-valid), with
/// assignment-without-subscription rows surfaced as `unknown` so the
/// outer `N subjects` always equals the inner table row count.
Future<Map<String, StudentPlanSummary>> _fetchPlanSummaries(
  FirebaseFirestore db,
  List<String> studentIds,
) async {
  if (studentIds.isEmpty) return const <String, StudentPlanSummary>{};
  final List<({String studentId, String subjectId, String planId})> subs =
      <({String studentId, String subjectId, String planId})>[];
  final List<({String studentId, String subjectId})> assignments =
      <({String studentId, String subjectId})>[];
  for (int i = 0; i < studentIds.length; i += 10) {
    final List<String> chunk = studentIds.sublist(
      i,
      i + 10 > studentIds.length ? studentIds.length : i + 10,
    );
    final QuerySnapshot<Map<String, dynamic>> subSnap = await db
        .collection('subscriptions')
        .where('student_id', whereIn: chunk)
        .get();
    for (final doc in subSnap.docs) {
      final Map<String, dynamic> data = doc.data();
      if (data['status'] != 'active' || data['is_deleted'] == true) continue;
      subs.add((
        studentId: (data['student_id'] as String?) ?? '',
        subjectId: (data['subject_id'] as String?) ?? doc.id,
        planId: (data['plan_id'] as String?) ?? '',
      ));
    }
    final QuerySnapshot<Map<String, dynamic>> assignSnap = await db
        .collection('subject_access_assignments')
        .where('student_id', whereIn: chunk)
        .get();
    for (final doc in assignSnap.docs) {
      final Map<String, dynamic> data = doc.data();
      if (data['is_deleted'] == true) continue;
      final String sid = (data['student_id'] as String?) ?? '';
      final String subj = (data['subject_id'] as String?) ?? doc.id;
      if (sid.isEmpty || subj.isEmpty) continue;
      assignments.add((studentId: sid, subjectId: subj));
    }
  }
  final QuerySnapshot<Map<String, dynamic>> plansSnap =
      await db.collection('plans').get();
  final Map<String, String> planLabels = <String, String>{
    for (final doc in plansSnap.docs)
      doc.id: planDisplayForKey(doc.data()['plan_key'] as String?),
  };
  // Live non-deleted subject catalog: same authority as the Subjects tab
  // join (which skips assignments whose subject document is gone).
  Set<String>? validSubjectIds;
  try {
    final QuerySnapshot<Map<String, dynamic>> subjectsSnap = await db
        .collection('subjects')
        .where('is_deleted', isEqualTo: false)
        .get();
    validSubjectIds = <String>{for (final doc in subjectsSnap.docs) doc.id};
  } catch (_) {
    validSubjectIds = null;
  }
  return buildStudentPlanSummaries(
    subscriptions: subs,
    planLabels: planLabels,
    assignments: assignments,
    validSubjectIds: validSubjectIds,
  );
}

/// Pure combine step (unit-testable): folds active subscription rows into
/// one [StudentPlanSummary] per student, keyed by student id. Students
/// with no rows are absent from the map (callers use
/// [StudentPlanSummary.empty]); tiers follow the same
/// [planDisplayForKey] labels as the Subjects tab.
///
/// When [assignments] is supplied (live path), the count axis is the
/// Subjects-tab axis: registered = non-deleted assignments intersected
/// with [validSubjectIds] when provided. Orphaned subscriptions (no
/// matching assignment, or subject deleted platform-side) are ignored so
/// the outer `N subjects` always equals the inner table row count.
/// Assignments with no active subscription (broken rows showing
/// "بدون خطة نشطة" inside) count toward `subjects` + `unknown` so the
/// totals still match instead of undercounting.
///
/// When [assignments] is null (legacy/tests), falls back to the old
/// subscriptions-only axis.
Map<String, StudentPlanSummary> buildStudentPlanSummaries({
  required List<({String studentId, String subjectId, String planId})>
      subscriptions,
  required Map<String, String> planLabels,
  List<({String studentId, String subjectId})>? assignments,
  Set<String>? validSubjectIds,
}) {
  if (assignments == null) {
    final Map<String, Set<String>> freeByStudent = <String, Set<String>>{};
    final Map<String, Set<String>> proByStudent = <String, Set<String>>{};
    final Map<String, Set<String>> maxByStudent = <String, Set<String>>{};
    final Map<String, Set<String>> unknownByStudent = <String, Set<String>>{};
    final Map<String, Set<String>> subjectsByStudent = <String, Set<String>>{};
    for (final sub in subscriptions) {
      if (sub.studentId.isEmpty) continue;
      subjectsByStudent
          .putIfAbsent(sub.studentId, () => <String>{})
          .add(sub.subjectId);
      final String label = planLabels[sub.planId] ?? '';
      final Map<String, Set<String>> bucket = switch (label) {
        'FREE' => freeByStudent,
        'PRO' => proByStudent,
        'MAX' => maxByStudent,
        _ => unknownByStudent,
      };
      bucket.putIfAbsent(sub.studentId, () => <String>{}).add(sub.subjectId);
    }
    final Map<String, StudentPlanSummary> out = <String, StudentPlanSummary>{};
    for (final String studentId in subjectsByStudent.keys) {
      out[studentId] = StudentPlanSummary(
        subjects: subjectsByStudent[studentId]!.length,
        free: freeByStudent[studentId]?.length ?? 0,
        pro: proByStudent[studentId]?.length ?? 0,
        max: maxByStudent[studentId]?.length ?? 0,
        unknown: unknownByStudent[studentId]?.length ?? 0,
      );
    }
    return out;
  }
  // Registered axis: assignments ∩ catalog.
  final Map<String, Set<String>> registeredByStudent =
      <String, Set<String>>{};
  for (final a in assignments) {
    if (a.studentId.isEmpty || a.subjectId.isEmpty) continue;
    if (validSubjectIds != null && !validSubjectIds.contains(a.subjectId)) {
      continue;
    }
    registeredByStudent
        .putIfAbsent(a.studentId, () => <String>{})
        .add(a.subjectId);
  }
  // Plan per (student, subject): last active subscription wins, same as
  // the Subjects-tab join (planBySubject map overwrite).
  final Map<String, Map<String, String>> planByStudentSubject =
      <String, Map<String, String>>{};
  for (final sub in subscriptions) {
    if (sub.studentId.isEmpty || sub.subjectId.isEmpty) continue;
    if (validSubjectIds != null && !validSubjectIds.contains(sub.subjectId)) {
      continue;
    }
    final Set<String>? registered = registeredByStudent[sub.studentId];
    if (registered == null || !registered.contains(sub.subjectId)) continue;
    (planByStudentSubject.putIfAbsent(sub.studentId, () => <String, String>{}))
        [sub.subjectId] = planLabels[sub.planId] ?? '';
  }
  final Map<String, StudentPlanSummary> out = <String, StudentPlanSummary>{};
  for (final MapEntry<String, Set<String>> entry
      in registeredByStudent.entries) {
    final String studentId = entry.key;
    final Set<String> subjects = entry.value;
    if (subjects.isEmpty) continue;
    int free = 0, pro = 0, max = 0, unknown = 0;
    final Map<String, String> planMap =
        planByStudentSubject[studentId] ?? const <String, String>{};
    for (final String subjectId in subjects) {
      final String? label =
          planMap.containsKey(subjectId) ? planMap[subjectId] : null;
      switch (label) {
        case 'FREE':
          free++;
          break;
        case 'PRO':
          pro++;
          break;
        case 'MAX':
          max++;
          break;
        default:
          // null (no active subscription) or unrecognized plan key.
          unknown++;
      }
    }
    out[studentId] = StudentPlanSummary(
      subjects: subjects.length,
      free: free,
      pro: pro,
      max: max,
      unknown: unknown,
    );
  }
  return out;
}

/// Grade-level tier breakdown on ONE consistent axis: live subscription
/// data (see [StudentPlanSummary]). Each bucket counts students holding
/// at least one active subscription at that tier, so a student with plans
/// on several subjects appears in every tier they hold — bucket shares
/// may therefore sum past 100%, which is correct, not a bug. Students
/// with no active subscription fall in "No active plan". Student type
/// (Center/Guest) is a separate axis shown in the Type column, never a
/// plan proxy.
List<PlanBreakdownRow> buildPlanBreakdown(List<GradeStudent> students) {
  int freeCount = 0, pro = 0, max = 0, noPlan = 0;
  for (final GradeStudent student in students) {
    final StudentPlanSummary summary = student.planSummary;
    if (!summary.hasActivePlan) {
      noPlan++;
      continue;
    }
    if (summary.hasFree) freeCount++;
    if (summary.hasPro) pro++;
    if (summary.hasMax) max++;
  }
  int share(int count) =>
      students.isEmpty ? 0 : ((count * 100) / students.length).round();
  // Labels name the counting unit explicitly: each tier bucket is a
  // STUDENT headcount (students holding >=1 active subscription at the
  // tier), never a subject count. 'No active plan' needs no qualifier —
  // it is inherently a student-count concept.
  return <PlanBreakdownRow>[
    PlanBreakdownRow(
        label: 'Students with FREE',
        count: freeCount,
        share: share(freeCount)),
    PlanBreakdownRow(
        label: 'Students with PRO', count: pro, share: share(pro)),
    PlanBreakdownRow(
        label: 'Students with MAX', count: max, share: share(max)),
    PlanBreakdownRow(
        label: 'No active plan', count: noPlan, share: share(noPlan)),
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
        return student.planSummary.matchesPlanQuery(needle);
      case StudentSearchScope.status:
        return student.statusLabel.toLowerCase().contains(needle);
    }
  }

  return students.where(matches).toList(growable: false);
}

/// Search scope mirror kept in the data layer so filtering stays
/// unit-testable without importing presentation widgets.
enum StudentSearchScope { name, type, plan, status }
