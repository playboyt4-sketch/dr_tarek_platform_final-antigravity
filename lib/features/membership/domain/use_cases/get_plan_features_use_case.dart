import '../entities/membership_entities.dart';
import '../repositories/membership_repository.dart';

class GetPlanFeaturesUseCase {
  final MembershipRepository repository;

  const GetPlanFeaturesUseCase(this.repository);

  Future<List<PlanFeature>> execute({required String planId}) {
    return repository.getPlanFeatures(planId: planId);
  }
}
