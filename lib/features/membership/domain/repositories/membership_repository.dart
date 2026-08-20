import '../entities/membership_entities.dart';

abstract class MembershipRepository {
  Future<List<MembershipPlan>> getAvailablePlans({required String studentType});

  Future<MembershipPlan?> getPlan({required String planId});

  Future<List<PlanFeature>> getPlanFeatures({required String planId});

  Future<MembershipSubscription?> getSubscription({
    required String studentId,
    required String subjectId,
  });

  Future<MembershipSubscription> activateFreePlan({
    required String studentId,
    required String subjectId,
    required String studentType,
  });

  Future<MembershipSubscription> upgrade({
    required String studentId,
    required String subjectId,
    required String newPlanId,
  });

  Future<MembershipSubscription> downgrade({
    required String studentId,
    required String subjectId,
    required String newPlanId,
  });

  Future<MembershipSubscription> renew({
    required String studentId,
    required String subjectId,
  });
}
