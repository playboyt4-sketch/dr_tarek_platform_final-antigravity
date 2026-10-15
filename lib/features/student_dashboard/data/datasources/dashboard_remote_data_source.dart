import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/dashboard_subject.dart';

/// Ranked subscription verdict for one (student, subject) pair.
typedef SubscriptionVerdict = ({
  DashboardSubscriptionState state,
  String? planId,
});

/// Entitlement verdict for one (student, subject) pair.
typedef EntitlementVerdict = ({
  DashboardEntitlementState state,
  String? reason,
  String? planKey,
});

/// Subscription rank: active (0) > trial (1) > frozen (2) > expired (3) >
/// disciplinary-disabled (4) > inactive (5). A stale doc (e.g. an old FREE
/// record next to a current PRO one) must never shadow the usable
/// subscription — first-doc-wins did exactly that.
int subscriptionRank(SubscriptionVerdict verdict) {
  return switch (verdict.state) {
    DashboardSubscriptionState.active => 0,
    DashboardSubscriptionState.trial => 1,
    DashboardSubscriptionState.frozen => 2,
    DashboardSubscriptionState.expired => 3,
    DashboardSubscriptionState.disciplinaryDisabled => 4,
    _ => 5,
  };
}

/// Pure verdict for ONE subscription document's data (no I/O).
///
/// [nowUtc] is injected so expiry is unit-testable; production passes
/// `DateTime.now().toUtc()`.
SubscriptionVerdict verdictForSubscriptionDoc(
  Map<String, dynamic> data, {
  required DateTime nowUtc,
}) {
  final Object? endDate = data['end_date'];
  final bool expired = endDate is Timestamp &&
      endDate.toDate().toUtc().isBefore(nowUtc);
  if (expired) {
    return (
      state: DashboardSubscriptionState.expired,
      planId: _text(data['plan_id']),
    );
  }
  if (data['manually_disabled'] == true) {
    return (
      state: DashboardSubscriptionState.disciplinaryDisabled,
      planId: _text(data['plan_id']),
    );
  }
  if (data['is_frozen'] == true) {
    return (
      state: DashboardSubscriptionState.frozen,
      planId: _text(data['plan_id']),
    );
  }
  if (data['status'] == 'active') {
    return (
      state: DashboardSubscriptionState.active,
      planId: _text(data['plan_id']),
    );
  }
  if (data['status'] == 'trial') {
    return (
      state: DashboardSubscriptionState.trial,
      planId: _text(data['plan_id']),
    );
  }
  return (
    state: DashboardSubscriptionState.inactive,
    planId: _text(data['plan_id']),
  );
}

/// Pure best-verdict fold across every non-deleted doc of one
/// (student, subject) pair. Deleted docs are ignored; an empty input
/// yields `missing`.
SubscriptionVerdict bestSubscriptionVerdict(
  List<Map<String, dynamic>> documents, {
  required DateTime nowUtc,
}) {
  SubscriptionVerdict? best;
  var bestRank = 1 << 30;
  for (final data in documents) {
    if (data['is_deleted'] == true) continue;
    final verdict = verdictForSubscriptionDoc(data, nowUtc: nowUtc);
    final rank = subscriptionRank(verdict);
    if (rank < bestRank) {
      best = verdict;
      bestRank = rank;
      if (rank == 0) break;
    }
  }
  return best ?? (state: DashboardSubscriptionState.missing, planId: null);
}

/// Pure entitlement fold from already-fetched facts (no I/O).
///
/// [planActive] is whether the resolved plan doc exists and is active;
/// [hasEnabledFeatures] is whether at least one enabled `plan_features`
/// doc exists for the plan. Mirrors the previous inline semantics exactly,
/// including surfacing [planKey] when features are disabled.
EntitlementVerdict resolveEntitlement({
  required DashboardSubscriptionState subscriptionState,
  required String? planId,
  required String? planKey,
  required bool planActive,
  required bool hasEnabledFeatures,
}) {
  if (subscriptionState != DashboardSubscriptionState.active &&
      subscriptionState != DashboardSubscriptionState.trial) {
    return (
      state: DashboardEntitlementState.blocked,
      reason: 'subscription_unavailable',
      planKey: null,
    );
  }
  if (planId == null || planId.isEmpty) {
    return (
      state: DashboardEntitlementState.blocked,
      reason: 'active_plan_missing',
      planKey: null,
    );
  }
  if (!planActive) {
    return (
      state: DashboardEntitlementState.blocked,
      reason: 'active_plan_missing',
      planKey: null,
    );
  }
  if (!hasEnabledFeatures) {
    return (
      state: DashboardEntitlementState.blocked,
      reason: 'plan_features_disabled',
      planKey: planKey,
    );
  }
  return (
    state: DashboardEntitlementState.ready,
    reason: null,
    planKey: planKey,
  );
}

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

/// Normalizes any known subject `grade` spelling to its canonical key
/// (`grade_one` … `grade_four`): canonical keys, `grade_N` / bare digits,
/// English labels and Arabic labels (الفرقة الأولى … الرابعة).
/// Returns null when unparseable (legacy untagged subject).
String? _normalizeSubjectGradeKey(Object? raw) {
  if (raw is! String) return null;
  final text = raw.trim().toLowerCase();
  if (text.isEmpty) return null;
  if (text == 'grade_one' ||
      text == 'grade one' ||
      text == 'grade_1' ||
      text == 'grade 1' ||
      text == '1') {
    return 'grade_one';
  }
  if (text == 'grade_two' ||
      text == 'grade two' ||
      text == 'grade_2' ||
      text == 'grade 2' ||
      text == '2') {
    return 'grade_two';
  }
  if (text == 'grade_three' ||
      text == 'grade three' ||
      text == 'grade_3' ||
      text == 'grade 3' ||
      text == '3') {
    return 'grade_three';
  }
  if (text == 'grade_four' ||
      text == 'grade four' ||
      text == 'grade_4' ||
      text == 'grade 4' ||
      text == '4') {
    return 'grade_four';
  }
  final folded = text
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا')
      .replaceAll('آ', 'ا')
      .replaceAll('ى', 'ي');
  if (folded.contains('اول') || folded.contains('one')) return 'grade_one';
  if (folded.contains('ثان') || folded.contains('two')) return 'grade_two';
  if (folded.contains('ثال') || folded.contains('three')) return 'grade_three';
  if (folded.contains('راب') || folded.contains('four')) return 'grade_four';
  return null;
}

class DashboardRemoteDataSource {
  final FirebaseFirestore firestore;

  const DashboardRemoteDataSource({required this.firestore});

  /// Accessible subjects for Student Home / Student Profile subjects.
  ///
  /// Latency discipline: exactly FIVE sequential Firestore waves no matter
  /// how many subjects the student holds — (1) assignments, (2) subject
  /// docs in parallel, (3) subscription queries in parallel, (4) distinct
  /// plan docs in parallel, (5) distinct plan-features queries in parallel.
  /// The previous per-subject sequential waterfall issued 1 + 4×n round
  /// trips (subject + subscriptions + plan + features per subject), which
  /// kept the home carousel on a spinner for seconds on web. Plan reads
  /// are additionally deduplicated: co-subjects on one plan share a single
  /// plan + features read.
  ///
  /// Fault isolation is preserved per subject: one unreadable/denied doc
  /// skips that subject and keeps the rest.
  Future<List<DashboardSubject>> getAccessibleSubjects({
    required String studentId,
  }) async {
    final assignments = await firestore
        .collection('subject_access_assignments')
        .where('student_id', isEqualTo: studentId)
        .where('is_deleted', isEqualTo: false)
        .get();

    // Student Home shows only enabled, non-deleted subject access.
    final List<String> subjectIds = <String>[];
    for (final doc in assignments.docs) {
      final data = doc.data();
      if (data['enabled'] != true) continue;
      final sid = data['subject_id'];
      if (sid is String && sid.isNotEmpty && !subjectIds.contains(sid)) {
        subjectIds.add(sid);
      }
    }
    if (subjectIds.isEmpty) return <DashboardSubject>[];
    final nowUtc = DateTime.now().toUtc();

    // Wave 1 — subject docs in parallel.
    final subjectDocs = await Future.wait(
      subjectIds.map(_guardSubjectDoc),
      eagerError: false,
    );
    final Map<String, Map<String, dynamic>> liveSubjects =
        <String, Map<String, dynamic>>{};
    for (final entry in subjectDocs) {
      if (entry == null) continue;
      final data = entry.data;
      if (data['is_deleted'] == true || data['is_visible'] != true) continue;
      liveSubjects[entry.id] = data;
    }
    if (liveSubjects.isEmpty) return <DashboardSubject>[];

    // Wave 2 — subscription queries in parallel.
    final subsLists = await Future.wait(
      liveSubjects.keys.map(
        (sid) => _guardSubscriptionDocs(studentId: studentId, subjectId: sid),
      ),
      eagerError: false,
    );
    final Map<String, SubscriptionVerdict> verdicts =
        <String, SubscriptionVerdict>{};
    final Set<String> planIds = <String>{};
    int index = 0;
    for (final sid in liveSubjects.keys) {
      final verdict = bestSubscriptionVerdict(
        subsLists[index],
        nowUtc: nowUtc,
      );
      index++;
      verdicts[sid] = verdict;
      final planId = verdict.planId;
      if ((verdict.state == DashboardSubscriptionState.active ||
              verdict.state == DashboardSubscriptionState.trial) &&
          planId != null &&
          planId.isNotEmpty) {
        planIds.add(planId);
      }
    }

    // Wave 3 — distinct plan docs in parallel.
    final planDocs = await Future.wait(
      planIds.map(_guardPlanDoc),
      eagerError: false,
    );
    final Map<String, Map<String, dynamic>?> plansById =
        <String, Map<String, dynamic>?>{};
    int planIndex = 0;
    for (final planId in planIds) {
      plansById[planId] = planDocs[planIndex];
      planIndex++;
    }

    // Wave 4 — distinct plan-features probes in parallel (enabled only:
    // the student rule allows listing ENABLED features, so the query
    // itself filters — otherwise a single disabled feature doc denies
    // the entire query).
    final activePlanIds = <String>[
      for (final planId in planIds)
        if (plansById[planId]?['is_active'] == true) planId,
    ];
    final featuresLists = await Future.wait(
      activePlanIds.map(_guardPlanFeatures),
      eagerError: false,
    );
    final Map<String, bool> hasFeatures = <String, bool>{};
    for (var i = 0; i < activePlanIds.length; i++) {
      hasFeatures[activePlanIds[i]] = featuresLists[i].isNotEmpty;
    }

    final subjects = <DashboardSubject>[];
    for (final sid in liveSubjects.keys) {
      final data = liveSubjects[sid]!;
      final verdict = verdicts[sid]!;
      final planId = verdict.planId;
      final planData = planId == null ? null : plansById[planId];
      final entitlement = resolveEntitlement(
        subscriptionState: verdict.state,
        planId: planId,
        planKey:
            planData == null ? null : _text(planData['plan_key']),
        planActive: planData != null && planData['is_active'] == true,
        hasEnabledFeatures:
            planId != null && (hasFeatures[planId] ?? false),
      );
      subjects.add(
        DashboardSubject(
          id: sid,
          title:
              _text(data['title']) ??
              _text(data['subject_name']) ??
              'مادة تعليمية',
          subtitle: _text(data['description']),
          thumbnailUrl:
              _text(data['poster_url']) ??
              _text(data['thumbnail_url']) ??
              _text(data['image_url']) ??
              _text(data['cover_url']),
          gradeKey: _normalizeSubjectGradeKey(data['grade']),
          displayOrder: (data['display_order'] as num?)?.toInt() ?? 0,
          planKey: entitlement.planKey,
          subjectAccessState: DashboardSubjectAccessState.enabled,
          subscriptionState: verdict.state,
          entitlementState: entitlement.state,
          entitlementReason: entitlement.reason,
        ),
      );
    }

    subjects.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    return subjects;
  }

  /// Guarded subject-doc fetch: `null` on missing/denied reads so the
  /// caller skips the subject (fault isolation).
  Future<({String id, Map<String, dynamic> data})?> _guardSubjectDoc(
    String subjectId,
  ) async {
    try {
      final snap =
          await firestore.collection('subjects').doc(subjectId).get();
      if (!snap.exists) return null;
      return (
        id: snap.id,
        data: snap.data() ?? const <String, dynamic>{},
      );
    } catch (_) {
      return null;
    }
  }

  /// Guarded subscription-docs fetch (non-deleted only, max 5 docs).
  Future<List<Map<String, dynamic>>> _guardSubscriptionDocs({
    required String studentId,
    required String subjectId,
  }) async {
    try {
      final snap = await firestore
          .collection('subscriptions')
          .where('student_id', isEqualTo: studentId)
          .where('subject_id', isEqualTo: subjectId)
          .limit(5)
          .get();
      return <Map<String, dynamic>>[
        for (final doc in snap.docs)
          if (doc.data()['is_deleted'] != true) doc.data(),
      ];
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  /// Guarded plan-doc fetch: `null` on missing/denied reads (reads are
  /// entitlement-gated server-side; a denial blocks the subject, never
  /// the whole list).
  Future<Map<String, dynamic>?> _guardPlanDoc(String planId) async {
    try {
      final snap = await firestore.collection('plans').doc(planId).get();
      if (!snap.exists) return null;
      return snap.data();
    } catch (_) {
      return null;
    }
  }

  /// Guarded enabled-features probe (existence only).
  Future<List<Map<String, dynamic>>> _guardPlanFeatures(
    String planId,
  ) async {
    try {
      final snap = await firestore
          .collection('plan_features')
          .where('plan_id', isEqualTo: planId)
          .where('enabled', isEqualTo: true)
          .limit(1)
          .get();
      return <Map<String, dynamic>>[for (final doc in snap.docs) doc.data()];
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }
}
