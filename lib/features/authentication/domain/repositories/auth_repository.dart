import '../entities/auth_user.dart';

class StaffDirectoryEntryEntity {
  final String displayName;
  final String roleKind; // 'dr' | 'admin'

  const StaffDirectoryEntryEntity({
    required this.displayName,
    required this.roleKind,
  });
}

abstract class AuthRepository {
  Future<AuthUser> login({
    required String phoneNumber,
    required String password,
  });

  /// Lists active platform staff (owner + admins) for the pre-login gate.
  Future<List<StaffDirectoryEntryEntity>> listStaffDirectory();

  /// Signs a staff member in with display name + password.
  Future<AuthUser> staffLogin({
    required String displayName,
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
