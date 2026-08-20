import '../../domain/entities/auth_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/custom_token_remote_datasource.dart';
import '../datasources/registration_remote_datasource.dart';
import '../datasources/user_profile_remote_datasource.dart';

class AuthRepositoryImpl implements AuthRepository {
  final CustomTokenRemoteDataSource remoteDataSource;
  final RegistrationRemoteDataSource registrationDataSource;
  final UserProfileRemoteDataSource userProfileDataSource;

  const AuthRepositoryImpl({
    required this.remoteDataSource,
    required this.registrationDataSource,
    required this.userProfileDataSource,
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

    final profile = await userProfileDataSource.getUserById(userId);
    if (profile == null) {
      throw StateError('Registered user profile was not found.');
    }
    return profile;
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
