import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/membership_entities.dart';

class MembershipRemoteDataSource {
  final FirebaseFirestore firestore;
  final FirebaseFunctions functions;

  const MembershipRemoteDataSource({
    required this.firestore,
    required this.functions,
  });

  Future<MembershipSubscription> activateFreePlan({
    required String studentId,
    required String subjectId,
    required String studentType,
  }) async {
    await functions.httpsCallable('activateFreePlan').call({
      'studentId': studentId,
      'subjectId': subjectId,
      'studentType': studentType,
    });

    final subscription = await getActiveSubscription(
      studentId: studentId,
      subjectId: subjectId,
    );

    if (subscription == null) {
      throw StateError(
        'Free plan activation did not create an active subscription.',
      );
    }

    return subscription;
  }

  Future<MembershipSubscription> downgrade({
    required String studentId,
    required String subjectId,
    required String newPlanId,
  }) async {
    await functions.httpsCallable('downgrade').call({
      'studentId': studentId,
      'subjectId': subjectId,
      'newPlanId': newPlanId,
    });

    final subscription = await getActiveSubscription(
      studentId: studentId,
      subjectId: subjectId,
    );

    if (subscription == null) {
      throw StateError('Downgrade did not leave an active subscription.');
    }

    return subscription;
  }

  Future<MembershipSubscription> renew({
    required String studentId,
    required String subjectId,
  }) async {
    await functions.httpsCallable('renew').call({
      'studentId': studentId,
      'subjectId': subjectId,
    });

    final subscription = await getActiveSubscription(
      studentId: studentId,
      subjectId: subjectId,
    );

    if (subscription == null) {
      throw StateError('Renewal did not leave an active subscription.');
    }

    return subscription;
  }

  Future<MembershipSubscription> upgrade({
    required String studentId,
    required String subjectId,
    required String newPlanId,
  }) async {
    await functions.httpsCallable('upgrade').call({
      'studentId': studentId,
      'subjectId': subjectId,
      'newPlanId': newPlanId,
    });
    final subscription = await getActiveSubscription(
      studentId: studentId,
      subjectId: subjectId,
    );
    if (subscription == null) {
      throw StateError('Upgrade did not leave an active subscription.');
    }
    return subscription;
  }

  Future<MembershipPlan?> getPlan({required String planId}) async {
    final doc = await firestore.collection('plans').doc(planId).get();
    if (!doc.exists) return null;

    final data = doc.data()!;
    return MembershipPlan(
      id: doc.id,
      planName: data['plan_name'] as String? ?? '',
      planKey: data['plan_key'] as String? ?? '',
      studentType: data['student_type'] as String? ?? '',
      displayOrder: (data['display_order'] as num?)?.toInt() ?? 0,
      isActive: data['is_active'] == true,
    );
  }

  Future<List<MembershipPlan>> getPlans({required String studentType}) async {
    final snapshot = await firestore
        .collection('plans')
        .where('student_type', isEqualTo: studentType)
        .where('is_active', isEqualTo: true)
        .orderBy('display_order')
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();

      return MembershipPlan(
        id: doc.id,
        planName: data['plan_name'] as String? ?? '',
        planKey: data['plan_key'] as String? ?? '',
        studentType: data['student_type'] as String? ?? '',
        displayOrder: (data['display_order'] as num?)?.toInt() ?? 0,
        isActive: data['is_active'] == true,
      );
    }).toList();
  }

  Future<MembershipSubscription?> getActiveSubscription({
    required String studentId,
    required String subjectId,
  }) async {
    final snapshot = await firestore
        .collection('subscriptions')
        .where('student_id', isEqualTo: studentId)
        .where('subject_id', isEqualTo: subjectId)
        .where('status', isEqualTo: 'active')
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) {
      return null;
    }

    final doc = snapshot.docs.first;
    final data = doc.data();

    return MembershipSubscription(
      id: doc.id,
      studentId: data['student_id'] as String? ?? '',
      subjectId: data['subject_id'] as String? ?? '',
      planId: data['plan_id'] as String? ?? '',
      durationType: data['duration_type'] as String? ?? '',
      startDate: (data['start_date'] as Timestamp).toDate(),
      endDate: (data['end_date'] as Timestamp?)?.toDate(),
      status: data['status'] as String? ?? '',
      isFrozen: data['is_frozen'] == true,
      frozenAt: (data['frozen_at'] as Timestamp?)?.toDate(),
      resumedAt: (data['resumed_at'] as Timestamp?)?.toDate(),
      isGifted: data['is_gifted'] == true,
      giftedBy: data['gifted_by'] as String?,
      renewalCount: (data['renewal_count'] as num?)?.toInt() ?? 0,
      previousPlanId: data['previous_plan_id'] as String?,
      manuallyDisabled: data['manually_disabled'] == true,
      disabledBy: data['disabled_by'] as String?,
      disabledAt: (data['disabled_at'] as Timestamp?)?.toDate(),
      disabledReason: data['disabled_reason'] as String?,
    );
  }

  Future<List<PlanFeature>> getPlanFeatures({required String planId}) async {
    final snapshot = await firestore
        .collection('plan_features')
        .where('plan_id', isEqualTo: planId)
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();

      return PlanFeature(
        id: doc.id,
        planId: data['plan_id'] as String? ?? '',
        featureKey: data['feature_key'] as String? ?? '',
        enabled: data['enabled'] == true,
        featureValue: data['feature_value'],
      );
    }).toList();
  }
}
