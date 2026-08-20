import 'package:flutter_test/flutter_test.dart';

import 'package:dr_tarek_platform/features/membership/domain/entities/membership_entities.dart';
import 'package:dr_tarek_platform/features/membership/domain/repositories/membership_repository.dart';
import 'package:dr_tarek_platform/features/membership/domain/services/entitlement_resolver.dart';
import 'package:dr_tarek_platform/features/subject_access/domain/entities/subject_access_assignment.dart';
import 'package:dr_tarek_platform/features/subject_access/domain/repositories/subject_access_repository.dart';

void main() {
  const studentId = 'student-1';
  const subjectId = 'subject-1';
  const featureKey = 'video_streaming';

  late FakeSubjectAccessRepository subjectAccess;
  late FakeMembershipRepository membership;
  late EntitlementResolver resolver;

  setUp(() {
    subjectAccess = FakeSubjectAccessRepository();
    membership = FakeMembershipRepository();
    resolver = EntitlementResolver(
      subjectAccessRepository: subjectAccess,
      membershipRepository: membership,
    );
  });

  test('denies before subscription when subject access is disabled', () async {
    subjectAccess.assignment = _assignment(enabled: false);

    final decision = await resolver.resolve(
      studentId: studentId,
      subjectId: subjectId,
      featureKey: featureKey,
    );

    expect(decision.isAllowed, isFalse);
    expect(decision.reason, 'subject_access_denied');
    expect(membership.getSubscriptionCalls, 0);
    expect(membership.getPlanCalls, 0);
  });

  test('denies before subscription when assignment is deleted', () async {
    subjectAccess.assignment = _assignment(isDeleted: true);

    final decision = await resolver.resolve(
      studentId: studentId,
      subjectId: subjectId,
      featureKey: featureKey,
    );

    expect(decision.isAllowed, isFalse);
    expect(decision.reason, 'subject_access_denied');
    expect(membership.getSubscriptionCalls, 0);
  });

  test('denies when subscription is missing after subject access', () async {
    subjectAccess.assignment = _assignment();

    final decision = await resolver.resolve(
      studentId: studentId,
      subjectId: subjectId,
      featureKey: featureKey,
    );

    expect(decision.isAllowed, isFalse);
    expect(decision.reason, 'subscription_missing');
    expect(membership.getSubscriptionCalls, 1);
    expect(membership.getPlanCalls, 0);
  });

  test('denies when active plan is missing after an eligible subscription',
      () async {
    subjectAccess.assignment = _assignment();
    membership.subscription = _subscription();

    final decision = await resolver.resolve(
      studentId: studentId,
      subjectId: subjectId,
      featureKey: featureKey,
    );

    expect(decision.isAllowed, isFalse);
    expect(decision.reason, 'active_plan_missing');
    expect(membership.getSubscriptionCalls, 1);
    expect(membership.getPlanCalls, 1);
    expect(membership.getPlanFeaturesCalls, 0);
  });

  test('allows only when plan feature is enabled', () async {
    subjectAccess.assignment = _assignment();
    membership.subscription = _subscription();
    membership.plan = _plan();
    membership.features = const [
      PlanFeature(
        id: 'feature-1',
        planId: 'plan-1',
        featureKey: featureKey,
        enabled: true,
      ),
    ];

    final decision = await resolver.resolve(
      studentId: studentId,
      subjectId: subjectId,
      featureKey: featureKey,
    );

    expect(decision.isAllowed, isTrue);
    expect(decision.reason, 'allowed');
    expect(decision.source, 'subject_access_subscription_plan_feature');
    expect(membership.getSubscriptionCalls, 1);
    expect(membership.getPlanCalls, 1);
    expect(membership.getPlanFeaturesCalls, 1);
  });

  test('denies when the subscription is disciplinarily disabled', () async {
    subjectAccess.assignment = _assignment();
    membership.subscription = MembershipSubscription(
      id: 'subscription-1',
      studentId: 'student-1',
      subjectId: 'subject-1',
      planId: 'plan-1',
      durationType: 'term',
      startDate: DateTime.utc(2026, 8, 1),
      endDate: DateTime.utc(2026, 12, 31),
      status: 'active',
      isFrozen: false,
      frozenAt: null,
      resumedAt: null,
      isGifted: false,
      giftedBy: null,
      renewalCount: 0,
      previousPlanId: null,
      manuallyDisabled: true,
      disabledBy: 'teacher-1',
      disabledAt: DateTime.utc(2026, 8, 10),
      disabledReason: 'إيقاف تأديبي',
    );
    membership.plan = _plan();
    membership.features = const [
      PlanFeature(
        id: 'feature-1',
        planId: 'plan-1',
        featureKey: featureKey,
        enabled: true,
      ),
    ];

    final decision = await resolver.resolve(
      studentId: studentId,
      subjectId: subjectId,
      featureKey: featureKey,
    );

    expect(decision.isAllowed, isFalse);
    expect(decision.reason, 'subscription_ineligible');
    expect(membership.getPlanFeaturesCalls, 0);
  });

  test('denies when requested plan feature is disabled', () async {
    subjectAccess.assignment = _assignment();
    membership.subscription = _subscription();
    membership.plan = _plan();
    membership.features = const [
      PlanFeature(
        id: 'feature-1',
        planId: 'plan-1',
        featureKey: featureKey,
        enabled: false,
      ),
    ];

    final decision = await resolver.resolve(
      studentId: studentId,
      subjectId: subjectId,
      featureKey: featureKey,
    );

    expect(decision.isAllowed, isFalse);
    expect(decision.reason, 'plan_feature_disabled');
  });
}

SubjectAccessAssignment _assignment({
  bool enabled = true,
  bool isDeleted = false,
}) {
  final now = DateTime.utc(2026, 8, 15);
  return SubjectAccessAssignment(
    studentId: 'student-1',
    subjectId: 'subject-1',
    enabled: enabled,
    createdAt: now,
    updatedAt: now,
    createdBy: 'teacher-1',
    updatedBy: 'teacher-1',
    isDeleted: isDeleted,
    deletedAt: isDeleted ? now : null,
    deletedBy: isDeleted ? 'teacher-1' : null,
  );
}

MembershipSubscription _subscription() {
  return MembershipSubscription(
    id: 'subscription-1',
    studentId: 'student-1',
    subjectId: 'subject-1',
    planId: 'plan-1',
    durationType: 'term',
    startDate: DateTime.utc(2026, 8, 1),
    endDate: DateTime.utc(2026, 12, 31),
    status: 'active',
    isFrozen: false,
    frozenAt: null,
    resumedAt: null,
    isGifted: false,
    giftedBy: null,
    renewalCount: 0,
    previousPlanId: null,
  );
}

MembershipPlan _plan() {
  return const MembershipPlan(
    id: 'plan-1',
    planName: 'Center Pro',
    planKey: 'center_pro',
    studentType: 'center_student',
    displayOrder: 1,
    isActive: true,
  );
}

class FakeSubjectAccessRepository implements SubjectAccessRepository {
  SubjectAccessAssignment? assignment;

  @override
  Future<SubjectAccessAssignment?> getAssignment({
    required String studentId,
    required String subjectId,
  }) async {
    return assignment;
  }

  @override
  Future<List<SubjectAccessAssignment>> getAssignmentsForStudent({
    required String studentId,
    bool includeDeleted = false,
  }) async {
    return assignment == null ? const [] : [assignment!];
  }

  @override
  Future<List<SubjectAccessAssignment>> getAssignmentsForSubject({
    required String subjectId,
    bool includeDeleted = false,
  }) async {
    return assignment == null ? const [] : [assignment!];
  }
}

class FakeMembershipRepository implements MembershipRepository {
  MembershipSubscription? subscription;
  MembershipPlan? plan;
  List<PlanFeature> features = const [];
  int getSubscriptionCalls = 0;
  int getPlanCalls = 0;
  int getPlanFeaturesCalls = 0;

  @override
  Future<MembershipSubscription?> getSubscription({
    required String studentId,
    required String subjectId,
  }) async {
    getSubscriptionCalls++;
    return subscription;
  }

  @override
  Future<MembershipPlan?> getPlan({required String planId}) async {
    getPlanCalls++;
    return plan;
  }

  @override
  Future<List<PlanFeature>> getPlanFeatures({required String planId}) async {
    getPlanFeaturesCalls++;
    return features;
  }

  @override
  Future<List<MembershipPlan>> getAvailablePlans({
    required String studentType,
  }) async => const [];

  @override
  Future<MembershipSubscription> activateFreePlan({
    required String studentId,
    required String subjectId,
    required String studentType,
  }) async => subscription!;

  @override
  Future<MembershipSubscription> upgrade({
    required String studentId,
    required String subjectId,
    required String newPlanId,
  }) async => subscription!;

  @override
  Future<MembershipSubscription> downgrade({
    required String studentId,
    required String subjectId,
    required String newPlanId,
  }) async => subscription!;

  @override
  Future<MembershipSubscription> renew({
    required String studentId,
    required String subjectId,
  }) async => subscription!;
}
