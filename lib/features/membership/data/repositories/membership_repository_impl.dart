import '../../domain/entities/membership_entities.dart';
import '../../domain/repositories/membership_repository.dart';
import '../datasources/membership_remote_data_source.dart';

class MembershipRepositoryImpl implements MembershipRepository {
  final MembershipRemoteDataSource remoteDataSource;

  const MembershipRepositoryImpl({required this.remoteDataSource});

  @override
  Future<MembershipSubscription> activateFreePlan({
    required String studentId,
    required String subjectId,
    required String studentType,
  }) {
    return remoteDataSource.activateFreePlan(
      studentId: studentId,
      subjectId: subjectId,
      studentType: studentType,
    );
  }

  @override
  Future<MembershipSubscription> downgrade({
    required String studentId,
    required String subjectId,
    required String newPlanId,
  }) {
    return remoteDataSource.downgrade(
      studentId: studentId,
      subjectId: subjectId,
      newPlanId: newPlanId,
    );
  }

  @override
  Future<MembershipSubscription> renew({
    required String studentId,
    required String subjectId,
  }) {
    return remoteDataSource.renew(studentId: studentId, subjectId: subjectId);
  }

  @override
  Future<MembershipSubscription> upgrade({
    required String studentId,
    required String subjectId,
    required String newPlanId,
  }) {
    return remoteDataSource.upgrade(
      studentId: studentId,
      subjectId: subjectId,
      newPlanId: newPlanId,
    );
  }

  @override
  Future<MembershipPlan?> getPlan({required String planId}) {
    return remoteDataSource.getPlan(planId: planId);
  }

  @override
  Future<List<MembershipPlan>> getAvailablePlans({
    required String studentType,
  }) {
    return remoteDataSource.getPlans(studentType: studentType);
  }

  @override
  Future<MembershipSubscription?> getSubscription({
    required String studentId,
    required String subjectId,
  }) {
    return remoteDataSource.getActiveSubscription(
      studentId: studentId,
      subjectId: subjectId,
    );
  }

  @override
  Future<List<PlanFeature>> getPlanFeatures({required String planId}) {
    return remoteDataSource.getPlanFeatures(planId: planId);
  }

  Future<bool> hasFeature({
    required String planId,
    required String featureKey,
  }) async {
    final features = await getPlanFeatures(planId: planId);

    final feature = features.cast<PlanFeature?>().firstWhere(
      (item) => item?.featureKey == featureKey,
      orElse: () => null,
    );

    return feature?.enabled == true;
  }
}
