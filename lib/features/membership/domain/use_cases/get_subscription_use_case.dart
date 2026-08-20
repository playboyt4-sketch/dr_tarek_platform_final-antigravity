import '../entities/membership_entities.dart';
import '../repositories/membership_repository.dart';

class GetSubscriptionUseCase {
  final MembershipRepository repository;

  const GetSubscriptionUseCase(this.repository);

  Future<MembershipSubscription?> execute({
    required String studentId,
    required String subjectId,
  }) {
    return repository.getSubscription(
      studentId: studentId,
      subjectId: subjectId,
    );
  }
}
