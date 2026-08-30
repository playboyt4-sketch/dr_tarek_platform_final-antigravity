import '../entities/dashboard_session.dart';
import '../repositories/auth_repository.dart';

/// Authenticates a dashboard user through the repository.
class LoginUseCase {
  final AuthRepository _repository;

  const LoginUseCase(this._repository);

  Future<DashboardSession> execute({
    required String phoneNumber,
    required String password,
  }) =>
      _repository.login(
        phoneNumber: phoneNumber,
        password: password,
      );
}
