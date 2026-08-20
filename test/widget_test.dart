import 'package:dr_tarek_platform/app/app.dart';
import 'package:dr_tarek_platform/features/authentication/domain/entities/auth_user.dart';
import 'package:dr_tarek_platform/features/authentication/domain/repositories/auth_repository.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/providers/auth_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthRepository implements AuthRepository {
  @override
  Future<AuthUser?> getCurrentUser() async => null;

  @override
  Future<AuthUser> login({
    required String phoneNumber,
    required String password,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> logout() async {}

  @override
  Future<AuthUser> register({
    required String fullName,
    required String phoneNumber,
    String? profilePhoto,
    required String grade,
    String? customGroupId,
    String? customGroupName,
    required String password,
  }) {
    throw UnimplementedError();
  }
}

void main() {
  testWidgets('Dr. Tarek Platform app loads', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
        ],
        child: const DrTarekPlatformApp(),
      ),
    );

    await tester.pump();

    expect(find.text('Tarek el araby'), findsOneWidget);
  });
}
