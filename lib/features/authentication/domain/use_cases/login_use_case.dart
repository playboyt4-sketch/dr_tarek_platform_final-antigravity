import '../entities/auth_user.dart';
import '../repositories/auth_repository.dart';

class LoginUseCase {
  final AuthRepository repository;

  const LoginUseCase(this.repository);

  Future<AuthUser> execute({
    required String phoneNumber,
    required String password,
  }) {
    return repository.login(phoneNumber: phoneNumber, password: password);
  }
}
