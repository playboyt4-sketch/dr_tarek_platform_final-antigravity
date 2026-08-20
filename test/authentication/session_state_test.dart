import 'package:flutter_test/flutter_test.dart';

import 'package:dr_tarek_platform/features/authentication/domain/entities/auth_user.dart';
import 'package:dr_tarek_platform/features/authentication/domain/entities/session_state.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/providers/session_provider.dart';

void main() {
  AuthUser user({
    String approvalStatus = 'approved',
    String accountStatus = 'active',
  }) {
    return AuthUser(
      id: 'user-1',
      fullName: 'Test User',
      phoneNumber: '01000000000',
      role: 'student',
      approvalStatus: approvalStatus,
      accountStatus: accountStatus,
    );
  }

  group('resolveAccountSessionState', () {
    test('returns pending approval when account is not approved', () {
      final state = resolveAccountSessionState(
        user: user(approvalStatus: 'pending'),
        claims: const {'approved': false},
      );

      expect(state, isA<SessionPendingApproval>());
    });

    test('returns rejected when approval status is rejected', () {
      final state = resolveAccountSessionState(
        user: user(approvalStatus: 'rejected'),
        claims: const {'approved': false},
      );

      expect(state, isA<SessionRejected>());
    });

    test('returns disabled before evaluating approval', () {
      final state = resolveAccountSessionState(
        user: user(accountStatus: 'disabled'),
        claims: const {'approved': true},
      );

      expect(state, isA<SessionDisabled>());
    });

    test('returns null for an approved active account', () {
      final state = resolveAccountSessionState(
        user: user(),
        claims: const {'approved': true},
      );

      expect(state, isNull);
    });
  });
}
