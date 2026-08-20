import '../entities/membership_entities.dart';
import '../repositories/membership_repository.dart';

class ChangeMembershipPlanUseCase {
  final MembershipRepository repository;

  const ChangeMembershipPlanUseCase(this.repository);

  Future<MembershipSubscription> upgrade({
    required String studentId,
    required String subjectId,
    required String newPlanId,
  }) {
    return repository.upgrade(
      studentId: studentId,
      subjectId: subjectId,
      newPlanId: newPlanId,
    );
  }

  Future<MembershipSubscription> downgrade({
    required String studentId,
    required String subjectId,
    required String newPlanId,
  }) {
    return repository.downgrade(
      studentId: studentId,
      subjectId: subjectId,
      newPlanId: newPlanId,
    );
  }
}
