import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/custom_token_remote_datasource.dart';
import '../../data/datasources/registration_remote_datasource.dart';
import '../../data/datasources/user_profile_remote_datasource.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/use_cases/get_current_user_use_case.dart';
import '../../domain/use_cases/login_use_case.dart';
import '../../domain/use_cases/logout_use_case.dart';
import '../../domain/use_cases/register_use_case.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final remoteDataSource = CustomTokenRemoteDataSource(
    functions: FirebaseFunctions.instance,
    firebaseAuth: FirebaseAuth.instance,
  );

  final registrationDataSource = RegistrationRemoteDataSource(
    functions: FirebaseFunctions.instance,
  );

  final userProfileDataSource = UserProfileRemoteDataSource(
    firestore: FirebaseFirestore.instance,
  );

  return AuthRepositoryImpl(
    remoteDataSource: remoteDataSource,
    registrationDataSource: registrationDataSource,
    userProfileDataSource: userProfileDataSource,
  );
});

final loginUseCaseProvider = Provider<LoginUseCase>((ref) {
  return LoginUseCase(ref.watch(authRepositoryProvider));
});

final getCurrentUserUseCaseProvider = Provider<GetCurrentUserUseCase>((ref) {
  return GetCurrentUserUseCase(ref.watch(authRepositoryProvider));
});

final logoutUseCaseProvider = Provider<LogoutUseCase>((ref) {
  return LogoutUseCase(ref.watch(authRepositoryProvider));
});

final registerUseCaseProvider = Provider<RegisterUseCase>((ref) {
  return RegisterUseCase(ref.watch(authRepositoryProvider));
});

final authProvider = AsyncNotifierProvider<AuthController, AuthUser?>(
  AuthController.new,
);

class AuthController extends AsyncNotifier<AuthUser?> {
  late final LoginUseCase _loginUseCase;
  late final GetCurrentUserUseCase _getCurrentUserUseCase;
  late final LogoutUseCase _logoutUseCase;
  late final RegisterUseCase _registerUseCase;

  @override
  Future<AuthUser?> build() async {
    _loginUseCase = ref.read(loginUseCaseProvider);
    _getCurrentUserUseCase = ref.read(getCurrentUserUseCaseProvider);
    _logoutUseCase = ref.read(logoutUseCaseProvider);
    _registerUseCase = ref.read(registerUseCaseProvider);

    return _getCurrentUserUseCase.execute();
  }

  Future<void> login({
    required String phoneNumber,
    required String password,
  }) async {
    state = const AsyncLoading();

    state = await AsyncValue.guard(
      () => _loginUseCase.execute(phoneNumber: phoneNumber, password: password),
    );
  }

  Future<void> register({
    required String fullName,
    required String phoneNumber,
    String? profilePhoto,
    required String grade,
    String? customGroupId,
    String? customGroupName,
    required String password,
  }) async {
    state = const AsyncLoading();

    state = await AsyncValue.guard(
      () => _registerUseCase.execute(
        fullName: fullName,
        phoneNumber: phoneNumber,
        profilePhoto: profilePhoto,
        grade: grade,
        customGroupId: customGroupId,
        customGroupName: customGroupName,
        password: password,
      ),
    );
  }

  Future<void> logout() async {
    state = const AsyncLoading();

    state = await AsyncValue.guard(() async {
      await _logoutUseCase.execute();
      return null;
    });
  }
}
