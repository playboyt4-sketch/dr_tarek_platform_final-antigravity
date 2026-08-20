import '../entities/membership_entities.dart';
import '../repositories/membership_repository.dart';

class ActivateFreePlanUseCase {
  final MembershipRepository repository;

  const ActivateFreePlanUseCase(this.repository);

  Future<MembershipSubscription> execute({
    required String studentId,
    required String subjectId,
    required String studentType,
  }) {
    return repository.activateFreePlan(
      studentId: studentId,
      subjectId: subjectId,
      studentType: studentType,
    );
  }
}
