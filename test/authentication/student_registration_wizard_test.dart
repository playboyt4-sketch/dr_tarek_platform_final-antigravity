import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dr_tarek_platform/core/errors/failure.dart';
import 'package:dr_tarek_platform/features/authentication/domain/entities/auth_user.dart';
import 'package:dr_tarek_platform/features/authentication/domain/repositories/auth_repository.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/providers/auth_provider.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/screens/student_registration_wizard.dart';
import 'package:dr_tarek_platform/l10n/generated/app_localizations.dart';

/// Drives the REAL [StudentRegistrationWizard] UI end-to-end with a fake
/// repository standing in for the `registerNewStudent` callable.
/// Mirrors a real new student: name → phone → photo(skip) → grade →
/// password → Finish → "Application under review".
class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({this.registerError});

  final Failure? registerError;

  Map<String, dynamic>? lastRegisterArgs;
  int registerCalls = 0;

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
    registerCalls++;
    lastRegisterArgs = {
      'fullName': fullName,
      'phoneNumber': phoneNumber,
      'grade': grade,
      'password': password,
    };
    if (registerError != null) throw registerError!;
    return AuthUser(
      id: 'new-user-1',
      fullName: fullName,
      phoneNumber: phoneNumber,
      role: 'new_student',
      grade: grade,
      approvalStatus: 'pending',
      accountStatus: 'active',
    );
  }

  @override
  Future<AuthUser> login({
    required String phoneNumber,
    required String password,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<StaffDirectoryEntryEntity>> listStaffDirectory() =>
      throw UnimplementedError();

  @override
  Future<AuthUser> staffLogin({
    required String displayName,
    required String password,
  }) =>
      throw UnimplementedError();

  @override
  Future<AuthUser?> getCurrentUser() async => null;

  @override
  Future<void> logout() async {}

  @override
  Future<void> applySessionPersistence({required bool rememberMe}) async {}
}

Future<void> _pumpWizard(
  WidgetTester tester,
  _FakeAuthRepository repo,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const StudentRegistrationWizard(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Completes steps 0–4 exactly as a student would. Returns after tapping
/// Finish and settling.
Future<void> _completeWizardFlow(
  WidgetTester tester, {
  String name = 'أحمد محمد علي',
  String phone = '01001234567',
  String password = 'Aa1!aaaa',
}) async {
  // Step 0 — full name.
  await tester.enterText(find.byType(TextField), name);
  await tester.tap(find.text('Next'));
  await tester.pumpAndSettle();

  // Step 1 — phone number.
  await tester.enterText(find.byType(TextField), phone);
  await tester.tap(find.text('Next'));
  await tester.pumpAndSettle();

  // Step 2 — photo (optional, skip).
  await tester.tap(find.text('Next'));
  await tester.pumpAndSettle();

  // Step 3 — grade.
  await tester.tap(find.text('الفرقة الأولى'));
  await tester.pump();
  await tester.tap(find.text('Next'));
  await tester.pumpAndSettle();

  // Step 4 — password + confirmation.
  final fields = find.byType(TextField);
  expect(fields, findsNWidgets(2));
  await tester.enterText(fields.at(0), password);
  await tester.enterText(fields.at(1), password);
  await tester.tap(find.text('Finish'));
  await tester.pumpAndSettle();
}

void main() {
  group('StudentRegistrationWizard end-to-end (fake backend)', () {
    testWidgets('run 1: full flow creates pending account, no error', (
      tester,
    ) async {
      final repo = _FakeAuthRepository();
      await _pumpWizard(tester, repo);
      await _completeWizardFlow(tester);

      expect(repo.registerCalls, 1);
      expect(repo.lastRegisterArgs!['fullName'], 'أحمد محمد علي');
      expect(repo.lastRegisterArgs!['phoneNumber'], '01001234567');
      expect(repo.lastRegisterArgs!['grade'], 'grade_one');
      // Review screen, zero error text.
      expect(find.text('الطلب قيد المراجعة'), findsOneWidget);
      expect(find.text('رقم الهاتف أو كلمة المرور غير صحيحة.'), findsNothing);
    });

    testWidgets('run 2: different student registers cleanly (stability)', (
      tester,
    ) async {
      final repo = _FakeAuthRepository();
      await _pumpWizard(tester, repo);
      await _completeWizardFlow(
        tester,
        name: 'منى سامي حسن',
        phone: '01512345678',
        password: 'Bb2@bbbb',
      );

      expect(repo.registerCalls, 1);
      expect(repo.lastRegisterArgs!['phoneNumber'], '01512345678');
      expect(find.text('الطلب قيد المراجعة'), findsOneWidget);
      expect(find.text('رقم الهاتف أو كلمة المرور غير صحيحة.'), findsNothing);
    });

    testWidgets('run 3: already-registered phone shows the correct message', (
      tester,
    ) async {
      final repo = _FakeAuthRepository(
        registerError: const Failure(FailureCode.phoneAlreadyExists),
      );
      await _pumpWizard(tester, repo);
      await _completeWizardFlow(tester);

      expect(repo.registerCalls, 1);
      // Correct duplicate message…
      expect(
        find.text('يوجد حساب مسجل بهذا الرقم بالفعل.'),
        findsOneWidget,
      );
      // …never Login's copy, and no review screen.
      expect(find.text('رقم الهاتف أو كلمة المرور غير صحيحة.'), findsNothing);
      expect(find.text('الطلب قيد المراجعة'), findsNothing);
    });

    testWidgets('App Check failure never surfaces Login copy', (
      tester,
    ) async {
      final repo = _FakeAuthRepository(
        registerError: const Failure(FailureCode.appCheckFailed),
      );
      await _pumpWizard(tester, repo);
      await _completeWizardFlow(tester);

      expect(find.textContaining('سلامة التطبيق'), findsOneWidget);
      expect(find.text('رقم الهاتف أو كلمة المرور غير صحيحة.'), findsNothing);
      expect(find.text('الطلب قيد المراجعة'), findsNothing);
    });

    testWidgets('invalid phone is blocked client-side before any call', (
      tester,
    ) async {
      final repo = _FakeAuthRepository();
      await _pumpWizard(tester, repo);

      await tester.enterText(find.byType(TextField), 'أحمد محمد علي');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '123');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(repo.registerCalls, 0);
      expect(find.text('خطوة 2 من 5'), findsOneWidget);
    });
  });
}
