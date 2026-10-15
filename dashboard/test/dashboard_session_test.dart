import 'package:flutter_test/flutter_test.dart';

import 'package:drtarek_dashboard/features/authentication/domain/entities/dashboard_session.dart';

/// ADR-005 role matrix for [DashboardSession.isStaff].
///
/// doctor = Doctor (Platform Owner), full access.
/// admin  = delegated administrator, admitted pending approval only.
/// No `teacher` compatibility: a stale `teacher` claim is NOT staff.
void main() {
  group('DashboardSession.isStaff (ADR-005)', () {
    test('doctor + approved → ALLOW', () {
      expect(
        const DashboardSession(userId: 'd1', role: 'doctor', approved: true)
            .isStaff,
        isTrue,
      );
    });

    test('teacher + approved → DENY (no legacy compatibility)', () {
      expect(
        const DashboardSession(userId: 't1', role: 'teacher', approved: true)
            .isStaff,
        isFalse,
      );
    });

    test('admin + approved → ALLOW', () {
      expect(
        const DashboardSession(userId: 'a1', role: 'admin', approved: true)
            .isStaff,
        isTrue,
      );
    });

    test('doctor + unapproved → DENY', () {
      expect(
        const DashboardSession(userId: 'd1', role: 'doctor', approved: false)
            .isStaff,
        isFalse,
      );
    });

    test('admin + unapproved → DENY', () {
      expect(
        const DashboardSession(userId: 'a1', role: 'admin', approved: false)
            .isStaff,
        isFalse,
      );
    });

    test('student → DENY', () {
      expect(
        const DashboardSession(userId: 's1', role: 'student', approved: true)
            .isStaff,
        isFalse,
      );
    });

    test('null/unknown role → DENY', () {
      expect(
        const DashboardSession(userId: 'x1', role: null, approved: true)
            .isStaff,
        isFalse,
      );
      expect(
        const DashboardSession(userId: 'x2', role: 'owner', approved: true)
            .isStaff,
        isFalse,
      );
      expect(
        const DashboardSession(userId: 'x3', role: 'dr', approved: true)
            .isStaff,
        isFalse,
      );
    });
  });
}
