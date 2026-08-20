import '../entities/auth_user.dart';
import '../repositories/auth_repository.dart';

class RegisterUseCase {
  final AuthRepository repository;

  const RegisterUseCase(this.repository);

  Future<AuthUser> execute({
    required String fullName,
    required String phoneNumber,
    String? profilePhoto,
    required String grade,
    String? customGroupId,
    String? customGroupName,
    required String password,
  }) {
    return repository.register(
      fullName: fullName,
      phoneNumber: phoneNumber,
      profilePhoto: profilePhoto,
      grade: grade,
      customGroupId: customGroupId,
      customGroupName: customGroupName,
      password: password,
    );
  }
}
