import 'package:dr_tarek_platform/features/membership/domain/entities/membership_entities.dart';
import 'package:dr_tarek_platform/features/membership/domain/repositories/membership_repository.dart';
import 'package:dr_tarek_platform/features/video_streaming/data/services/video_source_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeMembershipRepository implements MembershipRepository {
  MembershipSubscription? subscription;
  MembershipPlan? plan;
  List<PlanFeature> features = const [];

  @override
  Future<List<MembershipPlan>> getAvailablePlans({
    required String studentType,
  }) async => const [];

  @override
  Future<MembershipPlan?> getPlan({required String planId}) async => plan;

  @override
  Future<List<PlanFeature>> getPlanFeatures({required String planId}) async =>
      features;

  @override
  Future<MembershipSubscription?> getSubscription({
    required String studentId,
    required String subjectId,
  }) async => subscription;

  @override
  Future<MembershipSubscription> activateFreePlan({
    required String studentId,
    required String subjectId,
    required String studentType,
  }) => throw UnimplementedError();

  @override
  Future<MembershipSubscription> upgrade({
    required String studentId,
    required String subjectId,
    required String newPlanId,
  }) => throw UnimplementedError();

  @override
  Future<MembershipSubscription> downgrade({
    required String studentId,
    required String subjectId,
    required String newPlanId,
  }) => throw UnimplementedError();

  @override
  Future<MembershipSubscription> renew({
    required String studentId,
    required String subjectId,
  }) => throw UnimplementedError();
}

MembershipSubscription _subscription({String status = 'active'}) =>
    MembershipSubscription(
      id: 'subscription-1',
      studentId: 'student-1',
      subjectId: 'subject-1',
      planId: 'plan-1',
      durationType: 'monthly',
      startDate: DateTime(2026),
      endDate: DateTime(2026, 12, 31),
      status: status,
      isFrozen: false,
      frozenAt: null,
      resumedAt: null,
      isGifted: false,
      giftedBy: null,
      renewalCount: 0,
      previousPlanId: null,
    );

void main() {
  test('denies inactive subscriptions before video access', () async {
    final repository = _FakeMembershipRepository()
      ..subscription = _subscription(status: 'expired')
      ..features = const [
        PlanFeature(
          id: 'access',
          planId: 'plan-1',
          featureKey: 'video.access',
          enabled: true,
        ),
      ];

    final entitlement = await VideoEntitlementService(
      membershipRepository: repository,
    ).resolve(userId: 'student-1', subjectId: 'subject-1');

    expect(entitlement.allowed, isFalse);
  });

  test('denies active subscriptions without an explicit end date', () async {
    final repository = _FakeMembershipRepository()
      ..subscription = MembershipSubscription(
        id: 'subscription-open',
        studentId: 'student-1',
        subjectId: 'subject-1',
        planId: 'plan-1',
        durationType: 'monthly',
        startDate: DateTime(2026),
        endDate: null,
        status: 'active',
        isFrozen: false,
        frozenAt: null,
        resumedAt: null,
        isGifted: false,
        giftedBy: null,
        renewalCount: 0,
        previousPlanId: null,
      )
      ..features = const [
        PlanFeature(
          id: 'access',
          planId: 'plan-1',
          featureKey: 'video.access',
          enabled: true,
        ),
      ];

    final entitlement = await VideoEntitlementService(
      membershipRepository: repository,
    ).resolve(userId: 'student-1', subjectId: 'subject-1');

    expect(entitlement.allowed, isFalse);
  });

  test('returns backend quality cap from active plan features', () async {
    final repository = _FakeMembershipRepository()
      ..subscription = _subscription()
      ..features = const [
        PlanFeature(
          id: 'access',
          planId: 'plan-1',
          featureKey: 'video.access',
          enabled: true,
        ),
        PlanFeature(
          id: 'quality',
          planId: 'plan-1',
          featureKey: 'video.quality.max',
          enabled: true,
          featureValue: '720p',
        ),
      ];

    final entitlement = await VideoEntitlementService(
      membershipRepository: repository,
    ).resolve(userId: 'student-1', subjectId: 'subject-1');

    expect(entitlement.allowed, isTrue);
    expect(entitlement.maxQuality, '720p');
  });
}
