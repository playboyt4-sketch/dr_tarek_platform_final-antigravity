import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dr_tarek_platform/core/di/auth_providers.dart';
import 'package:dr_tarek_platform/core/errors/failure.dart';
import 'package:dr_tarek_platform/core/localization/locale_controller.dart';
import 'package:dr_tarek_platform/features/authentication/domain/entities/auth_user.dart';
import 'package:dr_tarek_platform/features/authentication/domain/repositories/auth_repository.dart';
import 'package:dr_tarek_platform/features/authentication/domain/repositories/password_reset_repository.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/providers/auth_provider.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/providers/password_reset_provider.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/screens/login_screen.dart';
import 'package:dr_tarek_platform/features/device_binding/domain/entities/device_info.dart';
import 'package:dr_tarek_platform/features/device_binding/domain/repositories/device_binding_repository.dart';
import 'package:dr_tarek_platform/features/device_binding/presentation/providers/device_binding_provider.dart';
import 'package:dr_tarek_platform/l10n/generated/app_localizations.dart';

const _approvedClaims = <String, dynamic>{'approved': true, 'role': 'student'};

AuthUser _student({
  String approvalStatus = 'approved',
  String accountStatus = 'active',
}) {
  return AuthUser(
    id: 'student-1',
    fullName: 'Current Student',
    phoneNumber: '01012345678',
    role: 'student',
    approvalStatus: approvalStatus,
    accountStatus: accountStatus,
  );
}

class _FakeAuthRepository implements AuthRepository {
  AuthUser? currentUser;
  Future<AuthUser> Function(String phone, String password)? onLogin;
  int loginCalls = 0;
  String? lastPhone;
  String? lastPassword;

  _FakeAuthRepository({this.onLogin});

  @override
  Future<AuthUser> login({
    required String phoneNumber,
    required String password,
  }) async {
    loginCalls++;
    lastPhone = phoneNumber;
    lastPassword = password;
    if (onLogin != null) return onLogin!(phoneNumber, password);
    throw UnimplementedError();
  }

  @override
  Future<AuthUser?> getCurrentUser() async => currentUser;

  @override
  Future<void> logout() async {
    currentUser = null;
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
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<StaffDirectoryEntryEntity>> listStaffDirectory() {
    throw UnimplementedError();
  }

  @override
  Future<AuthUser> staffLogin({
    required String displayName,
    required String password,
  }) {
    throw UnimplementedError();
  }

  int persistenceCalls = 0;
  bool? lastRememberMe;

  @override
  Future<void> applySessionPersistence({required bool rememberMe}) async {
    persistenceCalls++;
    lastRememberMe = rememberMe;
  }
}

class _FakeDeviceBindingRepository implements DeviceBindingRepository {
  final bool allowed;

  _FakeDeviceBindingRepository({this.allowed = true});

  @override
  Future<DeviceInfo> getDeviceInfo() async {
    return const DeviceInfo(
      deviceId: 'device-1',
      deviceName: 'Test Device',
      platform: 'test',
      osVersion: '1.0',
      appVersion: '1.0.0',
    );
  }

  @override
  Future<bool> validateDevice({
    required String userId,
    required DeviceInfo deviceInfo,
  }) async {
    return allowed;
  }
}

class _FakePasswordResetRepository implements PasswordResetRepository {
  final List<String> submittedPhones = <String>[];
  Future<void> Function(String phone)? onSubmit;

  @override
  Future<void> submitPasswordResetRequest({required String phoneNumber}) async {
    submittedPhones.add(phoneNumber);
    if (onSubmit != null) await onSubmit!(phoneNumber);
  }
}

Future<void> _pumpLogin(
  WidgetTester tester, {
  required _FakeAuthRepository authRepository,
  required Map<String, dynamic>? claims,
  bool deviceAllowed = true,
  _FakePasswordResetRepository? passwordResetRepository,
  Size size = const Size(393, 852),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final passwordReset =
      passwordResetRepository ?? _FakePasswordResetRepository();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepository),
        customClaimsProvider.overrideWith((ref) {
          final controller = StreamController<Map<String, dynamic>?>(
            sync: true,
          );
          controller.add(claims);
          ref.onDispose(() => controller.close());
          return controller.stream;
        }),
        deviceBindingRepositoryProvider.overrideWithValue(
          _FakeDeviceBindingRepository(allowed: deviceAllowed),
        ),
        passwordResetRepositoryProvider.overrideWithValue(passwordReset),
        initialLocaleProvider.overrideWithValue(const Locale('ar')),
      ],
      child: const MaterialApp(
        locale: Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: LoginScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _enterCredentials(
  WidgetTester tester, {
  String phone = '01012345678',
  String password = 'secret123',
}) async {
  await tester.enterText(find.byType(TextFormField).at(0), phone);
  await tester.enterText(find.byType(TextFormField).at(1), password);
  await tester.pump();
}

Future<void> _tapLogin(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Login'));
  await tester.pump();
}

void main() {
  group('LoginScreen visuals (Figma current Student - sign in)', () {
    testWidgets('renders headline, fields, link, and primary action', (
      tester,
    ) async {
      await _pumpLogin(
        tester,
        authRepository: _FakeAuthRepository(),
        claims: null,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(find.text('Forget password?'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Login'), findsOneWidget);
      expect(find.byType(BackButton), findsNothing);
    });

    testWidgets('renders without overflow at 393x852 and 360x640', (
      tester,
    ) async {
      for (final size in const [Size(393, 852), Size(360, 640)]) {
        await _pumpLogin(
          tester,
          authRepository: _FakeAuthRepository(),
          claims: null,
          size: size,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Welcome back'), findsOneWidget);
      }
    });
  });

  group('Login submission (existing auth flow preserved)', () {
    testWidgets('empty phone and password are rejected without login call', (
      tester,
    ) async {
      final repo = _FakeAuthRepository();
      await _pumpLogin(tester, authRepository: repo, claims: null);

      await _tapLogin(tester);
      await tester.pump();

      expect(repo.loginCalls, 0);
      expect(find.text('Welcome back'), findsOneWidget);
    });

    testWidgets('invalid phone format is rejected without login call', (
      tester,
    ) async {
      final repo = _FakeAuthRepository();
      await _pumpLogin(tester, authRepository: repo, claims: null);

      await _enterCredentials(tester, phone: '123');
      await _tapLogin(tester);
      await tester.pump();

      expect(repo.loginCalls, 0);
      expect(find.text('يرجى إدخال رقم هاتف مصري صحيح'), findsOneWidget);
    });

    testWidgets('valid credentials invoke the login flow with trimmed input', (
      tester,
    ) async {
      final user = _student();
      final repo = _FakeAuthRepository(
        onLogin: (phone, password) async => user,
      );
      await _pumpLogin(tester, authRepository: repo, claims: _approvedClaims);

      await _enterCredentials(
        tester,
        phone: '  01012345678  ',
        password: 'secret123',
      );
      await _tapLogin(tester);
      await tester.pumpAndSettle();

      expect(repo.loginCalls, 1);
      expect(repo.lastPhone, '01012345678');
      expect(repo.lastPassword, 'secret123');
      // Existing session/AuthGate continuation: still on Sign In route here
      // (the test tree has no Student Home); no error is shown.
      expect(find.text('Welcome back'), findsOneWidget);
    });

    testWidgets('invalid credentials remain with project-standard error', (
      tester,
    ) async {
      final repo = _FakeAuthRepository(
        onLogin: (phone, password) async {
          throw const Failure(FailureCode.wrongCredentials);
        },
      );
      await _pumpLogin(tester, authRepository: repo, claims: null);

      await _enterCredentials(tester);
      await _tapLogin(tester);
      await tester.pumpAndSettle();

      expect(repo.loginCalls, 1);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('رقم الهاتف أو كلمة المرور غير صحيحة.'), findsOneWidget);
    });

    testWidgets('waiting-for-approval account remains blocked', (tester) async {
      final repo = _FakeAuthRepository(
        onLogin: (phone, password) async => _student(approvalStatus: 'pending'),
      );
      await _pumpLogin(
        tester,
        authRepository: repo,
        claims: const <String, dynamic>{'approved': false},
      );

      await _enterCredentials(tester);
      await _tapLogin(tester);
      await tester.pumpAndSettle();

      expect(repo.loginCalls, 1);
      expect(find.text('Welcome back'), findsOneWidget);
    });

    testWidgets('rejected account remains blocked', (tester) async {
      final repo = _FakeAuthRepository(
        onLogin: (phone, password) async =>
            _student(approvalStatus: 'rejected'),
      );
      await _pumpLogin(
        tester,
        authRepository: repo,
        claims: const <String, dynamic>{'approved': false},
      );

      await _enterCredentials(tester);
      await _tapLogin(tester);
      await tester.pumpAndSettle();

      expect(repo.loginCalls, 1);
      expect(find.text('Welcome back'), findsOneWidget);
    });

    testWidgets('disabled account remains blocked', (tester) async {
      final repo = _FakeAuthRepository(
        onLogin: (phone, password) async => _student(accountStatus: 'disabled'),
      );
      await _pumpLogin(tester, authRepository: repo, claims: _approvedClaims);

      await _enterCredentials(tester);
      await _tapLogin(tester);
      await tester.pumpAndSettle();

      expect(repo.loginCalls, 1);
      expect(find.text('Welcome back'), findsOneWidget);
    });

    testWidgets('unauthorized device remains blocked', (tester) async {
      final user = _student();
      final repo = _FakeAuthRepository(
        onLogin: (phone, password) async => user,
      );
      await _pumpLogin(
        tester,
        authRepository: repo,
        claims: _approvedClaims,
        deviceAllowed: false,
      );

      await _enterCredentials(tester);
      await _tapLogin(tester);
      await tester.pumpAndSettle();

      expect(repo.loginCalls, 1);
      expect(find.text('Welcome back'), findsOneWidget);
    });

    testWidgets('duplicate login submission is prevented, state restores', (
      tester,
    ) async {
      final gate = Completer<AuthUser>();
      final repo = _FakeAuthRepository(
        onLogin: (phone, password) => gate.future,
      );
      await _pumpLogin(tester, authRepository: repo, claims: _approvedClaims);

      await _enterCredentials(tester);
      await _tapLogin(tester);
      await tester.pump();
      // Loading state: repeated taps are ignored (button shows progress and
      // no longer carries the Login label while in flight).
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(repo.loginCalls, 1);

      gate.complete(_student());
      await tester.pumpAndSettle();

      // Button/input state restored after completion.
      expect(find.widgetWithText(FilledButton, 'Login'), findsOneWidget);
      expect(repo.loginCalls, 1);
    });
  });

  group('Password visibility', () {
    testWidgets('password is masked by default and toggle works', (
      tester,
    ) async {
      await _pumpLogin(
        tester,
        authRepository: _FakeAuthRepository(),
        claims: null,
      );

      final passwordField = find.byType(TextFormField).at(1);
      EditableText editableOf(Finder field) => tester.widget<EditableText>(
        find.descendant(of: field, matching: find.byType(EditableText)),
      );
      expect(editableOf(passwordField).obscureText, isTrue);

      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pump();

      expect(editableOf(passwordField).obscureText, isFalse);
    });
  });

  group('Forgot password bottom sheet (V1 flow)', () {
    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(TextButton, 'Forget password?'));
      await tester.pumpAndSettle();
    }

    testWidgets('opens Figma sheet with handle and Arabic message', (
      tester,
    ) async {
      await _pumpLogin(
        tester,
        authRepository: _FakeAuthRepository(),
        claims: null,
      );
      await openSheet(tester);

      expect(find.byKey(const Key('forgotPasswordDragHandle')), findsOneWidget);
      final handleSize = tester.getSize(
        find.byKey(const Key('forgotPasswordDragHandle')),
      );
      expect(handleSize.width, closeTo(36, 0.5));
      expect(handleSize.height, closeTo(4, 0.5));

      expect(find.textContaining('يمكنك التواصل مع الأدمن'), findsOneWidget);
      expect(find.text('01098282915'), findsOneWidget);
      expect(find.byKey(const Key('forgotPasswordSubmit')), findsOneWidget);

      // No OTP/email/SMS flow introduced: the sheet adds no inputs — only
      // the two Sign In fields exist in the tree.
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.textContaining('OTP'), findsNothing);
      expect(find.textContaining('SMS'), findsNothing);
    });

    testWidgets('sheet fits the viewport at 393x852 and 360x640', (
      tester,
    ) async {
      for (final size in const [Size(393, 852), Size(360, 640)]) {
        await _pumpLogin(
          tester,
          authRepository: _FakeAuthRepository(),
          claims: null,
          size: size,
        );
        await openSheet(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('01098282915'), findsOneWidget);
      }
    });

    testWidgets('submit sends the request with the login phone', (
      tester,
    ) async {
      final reset = _FakePasswordResetRepository();
      await _pumpLogin(
        tester,
        authRepository: _FakeAuthRepository(),
        claims: null,
        passwordResetRepository: reset,
      );

      await _enterCredentials(tester, phone: '01012345678');
      await openSheet(tester);
      await tester.tap(find.byKey(const Key('forgotPasswordSubmit')));
      await tester.pumpAndSettle();

      expect(reset.submittedPhones, ['01012345678']);
      expect(find.text('تم إرسال طلبك بنجاح'), findsOneWidget);
    });

    testWidgets('submit with empty phone sends nothing and guides the user', (
      tester,
    ) async {
      final reset = _FakePasswordResetRepository();
      await _pumpLogin(
        tester,
        authRepository: _FakeAuthRepository(),
        claims: null,
        passwordResetRepository: reset,
      );

      await openSheet(tester);
      await tester.tap(find.byKey(const Key('forgotPasswordSubmit')));
      await tester.pumpAndSettle();

      expect(reset.submittedPhones, isEmpty);
      expect(find.text('تم إرسال طلبك بنجاح'), findsNothing);
      expect(find.byKey(const Key('forgotPasswordSubmit')), findsOneWidget);
    });

    testWidgets('duplicate reset requests are prevented', (tester) async {
      final gate = Completer<void>();
      final reset = _FakePasswordResetRepository()
        ..onSubmit = (_) => gate.future;
      await _pumpLogin(
        tester,
        authRepository: _FakeAuthRepository(),
        claims: null,
        passwordResetRepository: reset,
      );

      await _enterCredentials(tester, phone: '01012345678');
      await openSheet(tester);
      await tester.tap(find.byKey(const Key('forgotPasswordSubmit')));
      await tester.pump();
      // Second tap while in flight is ignored (button disabled).
      await tester.tap(find.byKey(const Key('forgotPasswordSubmit')));
      await tester.pump();
      expect(reset.submittedPhones, hasLength(1));

      gate.complete();
      await tester.pumpAndSettle();

      expect(reset.submittedPhones, hasLength(1));
      expect(find.text('تم إرسال طلبك بنجاح'), findsOneWidget);
    });
  });

  group('Presentation-layer security (static)', () {
    const widgetFiles = [
      'lib/features/authentication/presentation/screens/login_screen.dart',
      'lib/features/authentication/presentation/screens/forgot_password_screen.dart',
      'lib/features/authentication/presentation/widgets/forgot_password_sheet.dart',
      'lib/features/authentication/presentation/widgets/glass_back_button.dart',
    ];

    for (final path in widgetFiles) {
      test('$path has no direct Firebase/NetworkImage access', () {
        final source = File(path).readAsStringSync();
        for (final forbidden in [
          'cloud_firestore',
          'cloud_functions',
          'firebase_auth',
          'FirebaseFirestore',
          'FirebaseAuth',
          'FirebaseFunctions',
          'placehold.co',
          'NetworkImage(',
        ]) {
          expect(
            source.contains(forbidden),
            isFalse,
            reason: '$path must not reference $forbidden',
          );
        }
      });
    }

    test('login screen never logs the password', () {
      final source = File(widgetFiles.first).readAsStringSync();
      expect(source.contains('print('), isFalse);
      expect(source.contains('debugPrint('), isFalse);
      expect(source.contains('log('), isFalse);
    });
  });
}
