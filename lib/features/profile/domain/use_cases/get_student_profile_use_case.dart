import '../../../authentication/domain/entities/auth_user.dart';
import '../repositories/profile_repository.dart';

class GetStudentProfileUseCase {
  final ProfileRepository repository;

  const GetStudentProfileUseCase(this.repository);

  Future<AuthUser> execute({
    required String studentId,
  }) async {
    return repository.getStudentProfile(studentId);
  }
}
