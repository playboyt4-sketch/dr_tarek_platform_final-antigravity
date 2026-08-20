import '../../../subject_access/domain/repositories/subject_access_repository.dart';
import '../entities/membership_entities.dart';
import '../repositories/membership_repository.dart';

class EntitlementResolver {
  final SubjectAccessRepository subjectAccessRepository;
  final MembershipRepository membershipRepository;

  const EntitlementResolver({
    required this.subjectAccessRepository,
    required this.membershipRepository,
  });

  Future<EntitlementDecision> resolve({
    required String studentId,
    required String subjectId,
    required String featureKey,
  }) async {
    final assignment = await subjectAccessRepository.getAssignment(
      studentId: studentId,
      subjectId: subjectId,
    );
    if (assignment == null ||
        assignment.isDeleted ||
        !assignment.enabled ||
        assignment.studentId != studentId ||
        assignment.subjectId != subjectId) {
      return EntitlementDecision.deny(
        studentId: studentId,
        subjectId: subjectId,
        featureKey: featureKey,
        reason: 'subject_access_denied',
        source: 'subject_access',
      );
    }

    final subscription = await membershipRepository.getSubscription(
      studentId: studentId,
      subjectId: subjectId,
    );
    if (subscription == null) {
      return EntitlementDecision.deny(
        studentId: studentId,
        subjectId: subjectId,
        featureKey: featureKey,
        reason: 'subscription_missing',
        source: 'subscription',
      );
    }

    if (!_isEligibleSubscription(subscription) ||
        subscription.studentId != studentId ||
        subscription.subjectId != subjectId) {
      return EntitlementDecision.deny(
        studentId: studentId,
        subjectId: subjectId,
        featureKey: featureKey,
        reason: 'subscription_ineligible',
        source: 'subscription',
      );
    }

    final plan = await membershipRepository.getPlan(planId: subscription.planId);
    if (plan == null || !plan.isActive || plan.id != subscription.planId) {
      return EntitlementDecision.deny(
        studentId: studentId,
        subjectId: subjectId,
        featureKey: featureKey,
        reason: 'active_plan_missing',
        source: 'active_plan',
      );
    }

    final features = await membershipRepository.getPlanFeatures(
      planId: plan.id,
    );
    final feature = features.cast<PlanFeature?>().firstWhere(
      (item) => item?.featureKey == featureKey,
      orElse: () => null,
    );
    if (feature?.enabled != true) {
      return EntitlementDecision.deny(
        studentId: studentId,
        subjectId: subjectId,
        featureKey: featureKey,
        reason: 'plan_feature_disabled',
        source: 'plan_features',
      );
    }

    return EntitlementDecision.allow(
      studentId: studentId,
      subjectId: subjectId,
      featureKey: featureKey,
      source: 'subject_access_subscription_plan_feature',
    );
  }

  bool _isEligibleSubscription(MembershipSubscription subscription) {
    if (subscription.status != 'active' && subscription.status != 'trial') {
      return false;
    }
    if (subscription.manuallyDisabled) return false;
    final endDate = subscription.endDate;
    return endDate == null || endDate.isAfter(DateTime.now());
  }
}
