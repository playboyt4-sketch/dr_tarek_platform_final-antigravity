import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/dashboard_subject.dart';

class DashboardRemoteDataSource {
  final FirebaseFirestore firestore;

  const DashboardRemoteDataSource({required this.firestore});

  Future<List<DashboardSubject>> getAccessibleSubjects({
    required String studentId,
  }) async {
    final assignments = await firestore
        .collection('subject_access_assignments')
        .where('student_id', isEqualTo: studentId)
        .where('is_deleted', isEqualTo: false)
        .get();

    final subjects = <DashboardSubject>[];
    for (final assignment in assignments.docs) {
      final assignmentData = assignment.data();
      final subjectId = assignmentData['subject_id'];
      if (subjectId is! String || subjectId.isEmpty) continue;

      // Student Home shows only enabled, non-deleted subject access.
      if (assignmentData['enabled'] != true) continue;

      final subjectSnapshot = await firestore
          .collection('subjects')
          .doc(subjectId)
          .get();
      if (!subjectSnapshot.exists) continue;

      final data = subjectSnapshot.data() ?? const <String, dynamic>{};
      if (data['is_deleted'] == true || data['is_visible'] != true) continue;

      const accessState = DashboardSubjectAccessState.enabled;
      final subscription = await _getSubscriptionState(
        studentId: studentId,
        subjectId: subjectId,
      );
      final entitlement = await _resolveEntitlement(
        accessState: accessState,
        subscriptionState: subscription.state,
        planId: subscription.planId,
      );

      subjects.add(
        DashboardSubject(
          id: subjectSnapshot.id,
          title:
              _text(data['title']) ??
              _text(data['subject_name']) ??
              'مادة تعليمية',
          subtitle: _text(data['description']),
          thumbnailUrl:
              _text(data['poster_url']) ??
              _text(data['thumbnail_url']) ??
              _text(data['image_url']),
          displayOrder: (data['display_order'] as num?)?.toInt() ?? 0,
          subjectAccessState: accessState,
          subscriptionState: subscription.state,
          entitlementState: entitlement.state,
          entitlementReason: entitlement.reason,
        ),
      );
    }

    subjects.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    return subjects;
  }

  Future<({DashboardSubscriptionState state, String? planId})>
      _getSubscriptionState({
    required String studentId,
    required String subjectId,
  }) async {
    final snapshot = await firestore
        .collection('subscriptions')
        .where('student_id', isEqualTo: studentId)
        .where('subject_id', isEqualTo: subjectId)
        .limit(5)
        .get();

    for (final document in snapshot.docs) {
      final data = document.data();
      if (data['is_deleted'] == true) continue;

      final status = data['status'];
      final endDate = data['end_date'];
      final expired = endDate is Timestamp &&
          endDate.toDate().toUtc().isBefore(DateTime.now().toUtc());
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
      if (status == 'active') {
        return (
          state: DashboardSubscriptionState.active,
          planId: _text(data['plan_id']),
        );
      }
      if (status == 'trial') {
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

    return (state: DashboardSubscriptionState.missing, planId: null);
  }

  Future<({DashboardEntitlementState state, String? reason})>
      _resolveEntitlement({
    required DashboardSubjectAccessState accessState,
    required DashboardSubscriptionState subscriptionState,
    required String? planId,
  }) async {
    if (accessState != DashboardSubjectAccessState.enabled) {
      return (
        state: DashboardEntitlementState.blocked,
        reason: 'subject_access_disabled',
      );
    }

    if (subscriptionState != DashboardSubscriptionState.active &&
        subscriptionState != DashboardSubscriptionState.trial) {
      return (
        state: DashboardEntitlementState.blocked,
        reason: 'subscription_unavailable',
      );
    }

    if (planId == null || planId.isEmpty) {
      return (
        state: DashboardEntitlementState.blocked,
        reason: 'active_plan_missing',
      );
    }

    final plan = await firestore.collection('plans').doc(planId).get();
    if (!plan.exists || plan.data()?['is_active'] != true) {
      return (
        state: DashboardEntitlementState.blocked,
        reason: 'active_plan_missing',
      );
    }

    final features = await firestore
        .collection('plan_features')
        .where('plan_id', isEqualTo: planId)
        .get();
    if (!features.docs.any((doc) => doc.data()['enabled'] == true)) {
      return (
        state: DashboardEntitlementState.blocked,
        reason: 'plan_features_disabled',
      );
    }

    return (state: DashboardEntitlementState.ready, reason: null);
  }

  String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;
}
