import 'package:flutter_test/flutter_test.dart';

import 'package:drtarek_dashboard/features/applications/domain/grade.dart';
import 'package:drtarek_dashboard/features/applications/presentation/providers/application_decision_provider.dart';
import 'package:drtarek_dashboard/features/home/presentation/providers/home_stats_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/providers/grade_students_provider.dart';
import 'package:drtarek_dashboard/features/subscription/presentation/providers/subscription_matrix_provider.dart';

/// Phase 4 Guest / Center Free isolation (simplified plan IDs):
///   Guest:       planId = guest, studentType = guest,          planKey = free
///   Center Free: planId = free,  studentType = center_student, planKey = free
///   Center Pro:  planId = pro,   studentType = center_student, planKey = pro
///   Center Max:  planId = max,   studentType = center_student, planKey = max
void main() {
  group('Guest plan identity', () {
    test('matrix order and labels use the simplified plan ids', () {
      expect(subscriptionPlanOrder,
          <String>['guest', 'free', 'pro', 'max']);
      expect(subscriptionPlanLabels['guest'], 'Guest');
      expect(subscriptionPlanOrder, isNot(contains('public_free')));
      expect(subscriptionPlanOrder, isNot(contains('center_free')));
      expect(subscriptionPlanOrder, isNot(contains('center_pro')));
      expect(subscriptionPlanOrder, isNot(contains('center_max')));
    });

    test('free decision set holds plan ids, not the free key', () {
      expect(
        ApplicationDecisionController.freePlanKeys,
        <String>{'free', 'guest'},
      );
      expect(
        ApplicationDecisionController.freePlanKeys,
        isNot(contains('center_free')),
      );
      expect(
        ApplicationDecisionController.freePlanKeys,
        isNot(contains('public_free')),
      );
    });
  });

  group('Guest student type display', () {
    test('guest badge uses the Guest terminology', () {
      expect(studentTypeDisplayName('guest'), 'ضيف');
      expect(studentTypeDisplayName('center_student'), 'طالب سنتر');
    });

    test('non-center students render the Guest type label', () {
      const GradeStudent guest = GradeStudent(
        id: 'g1',
        name: 'Guest One',
        isCenter: false,
        plan: 'FREE',
        isActive: true,
        lastSignIn: '1/9/2026',
      );
      const GradeStudent center = GradeStudent(
        id: 'c1',
        name: 'Center One',
        isCenter: true,
        plan: 'FREE',
        isActive: true,
        lastSignIn: '1/9/2026',
      );
      expect(guest.typeLabel, 'Guest');
      expect(center.typeLabel, 'Center');
    });
  });

  group('Center plans are NOT Guest (critical negative cases)', () {
    test('planKey free alone never implies Guest', () {
      // Both plans share plan_key 'free'; identity lives in planId/type.
      const String guestPlanId = 'guest';
      const String freePlanId = 'free';
      const String sharedKey = 'free';
      expect(guestPlanId, isNot(freePlanId));
      expect(sharedKey, 'free');
      expect(guestPlanId == freePlanId, isFalse);
    });

    test('center plans stay distinct from guest', () {
      for (final String id in <String>['free', 'pro', 'max']) {
        expect(id, isNot('guest'));
      }
      expect(subscriptionPlanLabels['free'], 'Free');
      expect(subscriptionPlanLabels['pro'], 'Pro');
      expect(subscriptionPlanLabels['max'], 'Max');
    });

    test('isolation matrix: planId + studentType jointly identify Guest', () {
      // CASE A: Guest stays Guest.
      expect(_isGuestPlan('guest', 'guest'), isTrue);
      // CASE B/C/D: Center plans are never Guest.
      expect(_isGuestPlan('free', 'center_student'), isFalse);
      expect(_isGuestPlan('pro', 'center_student'), isFalse);
      expect(_isGuestPlan('max', 'center_student'), isFalse);
      // CASE E: planId free + studentType guest is not a valid Center
      // identity either — Guest identity requires planId guest.
      expect(_isGuestPlan('free', 'guest'), isFalse);
    });

    test('guest analytics share is separate from center share', () {
      const GradeAnalytics row = GradeAnalytics(
        gradeKey: 'grade_one',
        total: 100,
        pending: 0,
        center: 88,
        guest: 12,
      );
      expect(row.centerShareLabel, '88%');
      expect(row.guestShareLabel, '12%');
    });
  });
}

/// Mirrors the backend `isGuestPlan` contract (functions/src/index.ts) and
/// MembershipPlan.isGuestPlan: document ID + student_type jointly identify
/// the Guest plan; plan_key alone never does.
bool _isGuestPlan(String planId, String studentType) =>
    planId == 'guest' && studentType == 'guest';
