import '../../domain/repositories/password_reset_repository.dart';
import '../datasources/password_reset_remote_datasource.dart';

class PasswordResetRepositoryImpl implements PasswordResetRepository {
  final PasswordResetRemoteDataSource remoteDataSource;

  const PasswordResetRepositoryImpl({required this.remoteDataSource});

  @override
  Future<void> submitPasswordResetRequest({required String phoneNumber}) {
    return remoteDataSource.submitPasswordResetRequest(
      phoneNumber: phoneNumber,
    );
  }
}
