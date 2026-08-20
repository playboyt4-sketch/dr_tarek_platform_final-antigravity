import '../entities/membership_entities.dart';
import '../repositories/membership_repository.dart';

class GetAvailablePlansUseCase {
  final MembershipRepository repository;

  const GetAvailablePlansUseCase(this.repository);

  Future<List<MembershipPlan>> execute({required String studentType}) {
    return repository.getAvailablePlans(studentType: studentType);
  }
}
