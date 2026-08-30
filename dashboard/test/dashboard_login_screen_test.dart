import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drtarek_dashboard/core/errors/failure.dart';
import 'package:drtarek_dashboard/features/authentication/domain/entities/dashboard_session.dart';
import 'package:drtarek_dashboard/features/authentication/domain/repositories/auth_repository.dart';
import 'package:drtarek_dashboard/features/authentication/presentation/providers/auth_providers.dart';
import 'package:drtarek_dashboard/features/authentication/presentation/screens/dashboard_login_screen.dart';

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({this.result, this.error});

  final DashboardSession? result;
  final Object? error;

  int loginCalls = 0;

  @override
  Future<DashboardSession> login({
    required String phoneNumber,
    required String password,
  }) async {
    loginCalls++;
    if (error != null) throw error!;
    return result!;
  }

  @override
  Future<void> logout() async {}
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  _FakeAuthRepository? repo,
  Size size = const Size(1440, 1024),
}) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (repo != null) authRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(home: DashboardLoginScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders Figma composition at reference viewport',
      (WidgetTester tester) async {
    await _pumpScreen(tester);

    expect(find.text('Tarek el araby Platform'), findsOneWidget);
    expect(find.text('Login'), findsWidgets);
    expect(find.text('Welcome back please login your account'),
        findsOneWidget);
    expect(find.text('Phone Number'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Remember me'), findsOneWidget);
    expect(find.text('Created by Tarek el araby'), findsOneWidget);
    expect(find.byIcon(Icons.smartphone_outlined), findsOneWidget);
  });

  testWidgets('password visibility toggle switches eye state',
      (WidgetTester tester) async {
    await _pumpScreen(tester);

    expect(find.byIcon(Icons.visibility), findsOneWidget);

    await tester.tap(find.byIcon(Icons.visibility));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.visibility_off), findsOneWidget);
  });

  testWidgets('validation errors show safe field-level messages',
      (WidgetTester tester) async {
    await _pumpScreen(
      tester,
      repo: _FakeAuthRepository(
        result: const DashboardSession(
          userId: 'u1',
          role: 'admin',
          approved: true,
        ),
      ),
    );

    await tester.tap(find.text('Login').last);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('valid Egyptian phone number'),
      findsOneWidget,
    );
  });

  testWidgets('invalid credentials show user-facing message without raw '
      'Firebase text', (WidgetTester tester) async {
    await _pumpScreen(
      tester,
      repo: _FakeAuthRepository(
        error: const Failure(FailureCode.wrongCredentials),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'Phone Number').first,
      '01001234567',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password').first,
      'wrong-pass',
    );
    await tester.tap(find.text('Login').last);
    await tester.pumpAndSettle();

    expect(find.text('Incorrect phone number or password.'), findsOneWidget);
  });

  testWidgets('remember me checkbox toggles', (WidgetTester tester) async {
    await _pumpScreen(tester);

    expect(
      find.descendant(
        of: find.widgetWithText(InkWell, 'Remember me'),
        matching: find.byIcon(Icons.check_box_outline_blank),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Remember me'));
    await tester.pumpAndSettle();

    // After toggling, the checked Material glyph appears.
    expect(find.byIcon(Icons.check_box), findsOneWidget);
  });

  testWidgets('layout scrolls on short viewports without clipping the card',
      (WidgetTester tester) async {
    await _pumpScreen(tester, size: const Size(1024, 600));

    expect(find.text('Tarek el araby Platform'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
