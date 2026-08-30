import '../../../../core/errors/failure.dart';
import '../../domain/entities/dashboard_session.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/custom_token_remote_data_source.dart';

/// Firebase-backed [AuthRepository]. The only class in the app allowed to
/// touch Firebase Auth/Functions.
class AuthRepositoryImpl implements AuthRepository {
  final CustomTokenRemoteDataSource _remoteDataSource;

  const AuthRepositoryImpl(this._remoteDataSource);

  @override
  Future<DashboardSession> login({
    required String phoneNumber,
    required String password,
  }) async {
    try {
      final user = await _remoteDataSource.login(
        phoneNumber: phoneNumber,
        password: password,
      );

      // Force refresh so freshly issued Custom Claims are available to the
      // routing layer (claims are backend-issued; never defaulted client-side).
      final idToken = await user.getIdTokenResult(true);
      final claims = idToken.claims ?? const <String, dynamic>{};

      return DashboardSession(
        userId: user.uid,
        role: claims['role'] as String?,
        approved: claims['approved'] == true,
      );
    } catch (error, stackTrace) {
      throw Failure.from(error, stackTrace);
    }
  }

  @override
  Future<void> logout() => _remoteDataSource.logout();
}
