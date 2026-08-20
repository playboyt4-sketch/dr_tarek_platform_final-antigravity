import '../entities/auth_user.dart';

abstract class AuthRepository {
  Future<AuthUser> login({
    required String phoneNumber,
    required String password,
  });

  Future<AuthUser> register({
    required String fullName,
    required String phoneNumber,
    String? profilePhoto,
    required String grade,
    String? customGroupId,
    String? customGroupName,
    required String password,
  });

  Future<AuthUser?> getCurrentUser();

  Future<void> logout();
}
