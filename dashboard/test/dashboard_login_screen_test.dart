import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drtarek_dashboard/core/errors/failure.dart';
import 'package:drtarek_dashboard/features/authentication/domain/entities/dashboard_session.dart';
import 'package:drtarek_dashboard/features/authentication/domain/repositories/auth_repository.dart';
import 'package:drtarek_dashboard/features/authentication/presentation/providers/auth_providers.dart';
import 'package:drtarek_dashboard/features/authentication/presentation/screens/dashboard_login_screen.dart';
import 'package:drtarek_dashboard/features/authentication/presentation/widgets/password_visibility_toggle.dart';

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

/// Matches an [SvgPicture.asset] for the given asset path.
Finder _svgAsset(String assetName) => find.byWidgetPredicate(
      (Widget widget) =>
          widget is SvgPicture &&
          widget.bytesLoader is SvgAssetLoader &&
          (widget.bytesLoader as SvgAssetLoader).assetName == assetName,
    );

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
    // Figma Dev Mode trailing icons (SVG, per spec).
    expect(_svgAsset('assets/images/Smartphone.svg'), findsOneWidget);
    expect(_svgAsset('assets/images/Eye.svg'), findsOneWidget);
    expect(
      _svgAsset('assets/images/check_box_outline_blank.svg'),
      findsOneWidget,
    );
  });

  testWidgets('password visibility toggle switches eye state',
      (WidgetTester tester) async {
    await _pumpScreen(tester);

    expect(_svgAsset('assets/images/Eye.svg'), findsOneWidget);

    await tester.tap(find.byType(PasswordVisibilityToggle));
    await tester.pumpAndSettle();

    expect(_svgAsset('assets/images/Eye off.svg'), findsOneWidget);
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

    await tester.tap(find.text('login'));
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
    await tester.tap(find.text('login'));
    await tester.pumpAndSettle();

    expect(find.text('Incorrect phone number or password.'), findsOneWidget);
  });

  testWidgets('remember me checkbox toggles', (WidgetTester tester) async {
    await _pumpScreen(tester);

    expect(
      _svgAsset('assets/images/check_box_outline_blank.svg'),
      findsOneWidget,
    );
    await tester.tap(find.text('Remember me'));
    await tester.pumpAndSettle();

    // After toggling, the checked SVG glyph appears.
    expect(_svgAsset('assets/images/check_box.svg'), findsOneWidget);
  });

  testWidgets('layout scrolls on short viewports without clipping the card',
      (WidgetTester tester) async {
    await _pumpScreen(tester, size: const Size(1024, 600));

    expect(find.text('Tarek el araby Platform'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
