import '../../domain/entities/auth_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/custom_token_remote_datasource.dart';
import '../datasources/registration_remote_datasource.dart';
import '../datasources/staff_auth_remote_datasource.dart';
import '../datasources/user_profile_remote_datasource.dart';
import '../models/auth_user_model.dart';

class AuthRepositoryImpl implements AuthRepository {
  final CustomTokenRemoteDataSource remoteDataSource;
  final RegistrationRemoteDataSource registrationDataSource;
  final UserProfileRemoteDataSource userProfileDataSource;
  final StaffAuthRemoteDataSource staffAuthDataSource;

  const AuthRepositoryImpl({
    required this.remoteDataSource,
    required this.registrationDataSource,
    required this.userProfileDataSource,
    required this.staffAuthDataSource,
  });

  @override
  Future<AuthUser> login({
    required String phoneNumber,
    required String password,
  }) async {
    final credential = await remoteDataSource.login(
      phoneNumber: phoneNumber,
      password: password,
    );

    final user = credential.user;

    if (user == null) {
      throw StateError('Authenticated user was not returned.');
    }

    final profile = await userProfileDataSource.getUserById(user.uid);

    if (profile == null) {
      throw StateError('User profile was not found.');
    }

    return profile;
  }

  @override
  Future<List<StaffDirectoryEntryEntity>> listStaffDirectory() async {
    final staff = await staffAuthDataSource.listStaff();
    return staff
        .map((e) => StaffDirectoryEntryEntity(
              displayName: e.displayName,
              roleKind: e.roleKind,
            ))
        .toList();
  }

  @override
  Future<AuthUser> staffLogin({
    required String displayName,
    required String password,
  }) async {
    final credential = await staffAuthDataSource.login(
      displayName: displayName,
      password: password,
    );

    final user = credential.user;
    if (user == null) {
      throw StateError('Authenticated user was not returned.');
    }

    final profile = await userProfileDataSource.getUserById(user.uid);
    if (profile == null) {
      throw StateError('User profile was not found.');
    }
    return profile;
  }

  /// Registration completes WITHOUT an authenticated session: the callable
  /// creates the account server-side as `role: "new_student"`,
  /// `approval_status: "pending"` (functions/src/index.ts registerNewStudent)
  /// and the client stays signed out until verifyPhonePassword (06 Firebase
  /// Architecture Section 3.2 — Custom Tokens). Firestore rules require
  /// signedIn() to read users/{userId}, so no profile fetch happens here;
  /// the returned entity reflects exactly what the backend wrote plus its
  /// `{userId, approvalStatus: "pending"}` response.
  @override
  Future<AuthUser> register({
    required String fullName,
    required String phoneNumber,
    String? profilePhoto,
    required String grade,
    String? customGroupId,
    String? customGroupName,
    required String password,
  }) async {
    final userId = await registrationDataSource.register(
      fullName: fullName,
      phoneNumber: phoneNumber,
      profilePhoto: profilePhoto,
      grade: grade,
      customGroupId: customGroupId,
      customGroupName: customGroupName,
      password: password,
    );

    return AuthUserModel(
      id: userId,
      fullName: fullName,
      profilePhoto: profilePhoto,
      phoneNumber: phoneNumber,
      role: 'new_student',
      grade: grade,
      approvalStatus: 'pending',
      accountStatus: 'active',
    );
  }

  @override
  Future<AuthUser?> getCurrentUser() async {
    final user = remoteDataSource.firebaseAuth.currentUser;

    if (user == null) {
      return null;
    }

    return userProfileDataSource.getUserById(user.uid);
  }

  @override
  Future<void> logout() {
    return remoteDataSource.firebaseAuth.signOut();
  }
}
