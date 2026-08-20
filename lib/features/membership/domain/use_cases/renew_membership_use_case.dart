import '../entities/membership_entities.dart';
import '../repositories/membership_repository.dart';

class RenewMembershipUseCase {
  final MembershipRepository repository;

  const RenewMembershipUseCase(this.repository);

  Future<MembershipSubscription> execute({
    required String studentId,
    required String subjectId,
  }) {
    return repository.renew(studentId: studentId, subjectId: subjectId);
  }
}
