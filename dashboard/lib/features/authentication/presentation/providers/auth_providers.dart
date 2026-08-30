import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/firebase_providers.dart';
import '../../data/datasources/custom_token_remote_data_source.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/entities/dashboard_session.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/use_cases/login_use_case.dart';

final customTokenRemoteDataSourceProvider = Provider<CustomTokenRemoteDataSource>(
  (ref) => CustomTokenRemoteDataSource(
    ref.watch(firebaseAuthProvider),
    ref.watch(firebaseFunctionsProvider),
  ),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepositoryImpl(ref.watch(customTokenRemoteDataSourceProvider)),
);

final loginUseCaseProvider = Provider<LoginUseCase>(
  (ref) => LoginUseCase(ref.watch(authRepositoryProvider)),
);

/// Emits the live Firebase session, resolving claims after every auth state
/// change. `null` means no authenticated user.
final sessionProvider = StreamProvider<DashboardSession?>((ref) async* {
  final auth = ref.watch(firebaseAuthProvider);
  await for (final user in auth.authStateChanges()) {
    if (user == null) {
      yield null;
      continue;
    }
    final idToken = await user.getIdTokenResult(true);
    final claims = idToken.claims ?? const <String, dynamic>{};
    yield DashboardSession(
      userId: user.uid,
      role: claims['role'] as String?,
      approved: claims['approved'] == true,
    );
  }
});
