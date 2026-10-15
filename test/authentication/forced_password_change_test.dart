import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dr_tarek_platform/features/authentication/domain/entities/auth_user.dart';
import 'package:dr_tarek_platform/features/authentication/domain/entities/session_state.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/providers/session_provider.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/screens/auth_gate.dart';
import 'package:dr_tarek_platform/l10n/generated/app_localizations.dart';

/// Student-only forced-password-change coverage.
///
/// Approved behavior: a STUDENT whose claims carry
/// `force_password_change == true` must be routed to the mandatory
/// password-change flow instead of normal content. Doctor/Admin must
/// never enter the forced state.
void main() {
  AuthUser user({
    String role = 'student',
    String approvalStatus = 'approved',
    String accountStatus = 'active',
  }) {
    return AuthUser(
      id: 'user-1',
      fullName: 'Test User',
      phoneNumber: '01000000000',
      role: role,
      approvalStatus: approvalStatus,
      accountStatus: accountStatus,
    );
  }

  group('resolveAccountSessionState forced password change', () {
    test('flag false + student -> null (normal Authenticated path)', () {
      final state = resolveAccountSessionState(
        user: user(),
        claims: const {'approved': true, 'force_password_change': false},
      );

      expect(state, isNull);
    });

    test('missing flag + student -> null', () {
      final state = resolveAccountSessionState(
        user: user(),
        claims: const {'approved': true},
      );

      expect(state, isNull);
    });

    test('flag true + student -> SessionForcePasswordChange', () {
      final state = resolveAccountSessionState(
        user: user(),
        claims: const {'approved': true, 'force_password_change': true},
      );

      expect(state, isA<SessionForcePasswordChange>());
    });

    test('flag true + admin -> NOT forced', () {
      final state = resolveAccountSessionState(
        user: user(role: 'admin'),
        claims: const {'approved': true, 'force_password_change': true},
      );

      expect(state, isNull);
    });

    test('flag true + doctor -> NOT forced', () {
      final state = resolveAccountSessionState(
        user: user(role: 'doctor'),
        claims: const {'approved': true, 'force_password_change': true},
      );

      expect(state, isNull);
    });

    test('non-bool flag value -> NOT forced (strict == true)', () {
      final state = resolveAccountSessionState(
        user: user(),
        claims: const {'approved': true, 'force_password_change': 'true'},
      );

      expect(state, isNull);
    });

    test('disabled takes precedence over forced state', () {
      final state = resolveAccountSessionState(
        user: user(accountStatus: 'disabled'),
        claims: const {'approved': true, 'force_password_change': true},
      );

      expect(state, isA<SessionDisabled>());
    });

    test('rejected takes precedence over forced state', () {
      final state = resolveAccountSessionState(
        user: user(approvalStatus: 'rejected'),
        claims: const {'approved': false, 'force_password_change': true},
      );

      expect(state, isA<SessionRejected>());
    });

    test('pending approval takes precedence over forced state', () {
      final state = resolveAccountSessionState(
        user: user(approvalStatus: 'pending'),
        claims: const {'approved': false, 'force_password_change': true},
      );

      expect(state, isA<SessionPendingApproval>());
    });
  });

  group('AuthGate forced password change', () {
    Future<void> pumpGate(WidgetTester tester, SessionState state) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('ar'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: AuthGate(sessionState: AsyncData<SessionState>(state)),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('forced state renders mandatory UI, not app content', (
      tester,
    ) async {
      await pumpGate(
        tester,
        SessionForcePasswordChange(user: user(approvalStatus: 'approved')),
      );

      expect(find.text('تغيير كلمة المرور مطلوب'), findsWidgets);
      expect(find.text('تغيير كلمة المرور'), findsOneWidget);
      expect(find.text('تسجيل الخروج'), findsOneWidget);
      // Normal student home must be unreachable.
      expect(find.text('الرئيسية'), findsNothing);
      expect(find.text('لوحة الإدارة'), findsNothing);
    });

    testWidgets('change button opens blocking temp-password dialog', (
      tester,
    ) async {
      await pumpGate(
        tester,
        SessionForcePasswordChange(user: user(approvalStatus: 'approved')),
      );

      await tester.tap(find.text('تغيير كلمة المرور'));
      await tester.pumpAndSettle();

      expect(find.text('كلمة المرور المؤقتة (الحالية)'), findsOneWidget);
      expect(find.text('حفظ ومتابعة'), findsOneWidget);
    });
  });
}
