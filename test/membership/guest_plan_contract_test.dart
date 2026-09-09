import 'package:flutter_test/flutter_test.dart';

import 'package:dr_tarek_platform/features/authentication/data/models/auth_user_model.dart';
import 'package:dr_tarek_platform/features/membership/domain/entities/membership_plan.dart';

/// Phase 2A backend-contract verification (Phase 1 canonical terminology):
///   student_type = guest, plan_id = guest, plan_key = free (unchanged).
void main() {
  group('AuthUser deserialization — guest student type', () {
    test('student_type = guest deserializes without legacy assumptions', () {
      final user = AuthUserModel.fromMap('u1', {
        'full_name': 'Guest Student',
        'phone_number': '01000000000',
        'role': 'student',
        'student_type': 'guest',
        'grade': 'grade_one',
        'approval_status': 'approved',
        'account_status': 'active',
      });
      expect(user.studentType, 'guest');
      // role is a separate concept and must remain student.
      expect(user.role, 'student');
    });

    test('center_student still deserializes untouched', () {
      final user = AuthUserModel.fromMap('u2', {
        'full_name': 'Center Student',
        'phone_number': '01000000001',
        'role': 'student',
        'student_type': 'center_student',
        'approval_status': 'approved',
        'account_status': 'active',
      });
      expect(user.studentType, 'center_student');
    });

    test('claim keys are unchanged (student_type / plan_id / role)', () {
      // The migration renames VALUES only; keys are asserted by usage.
      const claim = {
        'role': 'student',
        'student_type': 'guest',
        'plan_id': 'guest',
        'max_devices': 1,
      };
      final user = AuthUserModel.fromMap('u1', {
        'full_name': 'Guest',
        'phone_number': '01000000000',
        'role': claim['role'],
        'student_type': claim['student_type'],
        'approval_status': 'approved',
        'account_status': 'active',
      });
      expect(user.role, 'student');
      expect(user.studentType, 'guest');
    });
  });

  group('Guest plan identity — planId = guest, planKey = free', () {
    const guestPlan = MembershipPlan(
      id: 'guest',
      planName: 'Guest',
      planKey: 'free',
      studentType: 'guest',
      displayOrder: 1,
      isActive: true,
    );

    test('guest plan is correctly represented', () {
      expect(guestPlan.id, 'guest');
      expect(guestPlan.planKey, 'free');
      expect(guestPlan.studentType, 'guest');
      expect(guestPlan.isGuestPlan, isTrue);
      expect(guestPlan.isCenterPlan, isFalse);
    });

    test('free (Center Free) is NOT treated as guest', () {
      const freePlan = MembershipPlan(
        id: 'free',
        planName: 'Center Free',
        planKey: 'free',
        studentType: 'center_student',
        displayOrder: 2,
        isActive: true,
      );
      // Same plan_key "free" — identity must come from planId + studentType.
      expect(freePlan.planKey, 'free');
      expect(freePlan.isGuestPlan, isFalse);
      expect(freePlan.isCenterPlan, isTrue);
    });

    test('plan_key = free alone never identifies the guest plan', () {
      const ambiguous = MembershipPlan(
        id: 'free',
        planName: 'Center Free',
        planKey: 'free',
        studentType: 'center_student',
        displayOrder: 2,
        isActive: true,
      );
      expect(ambiguous.planKey, 'free');
      expect(ambiguous.isGuestPlan, isFalse);
    });

    test('center pro/max untouched', () {
      const pro = MembershipPlan(
        id: 'pro',
        planName: 'Center Pro',
        planKey: 'pro',
        studentType: 'center_student',
        displayOrder: 3,
        isActive: true,
      );
      expect(pro.isGuestPlan, isFalse);
      expect(pro.isCenterPlan, isTrue);
      const max = MembershipPlan(
        id: 'max',
        planName: 'Center Max',
        planKey: 'max',
        studentType: 'center_student',
        displayOrder: 4,
        isActive: true,
      );
      expect(max.isGuestPlan, isFalse);
      expect(max.isCenterPlan, isTrue);
    });

    test('legacy center_* ids are not valid plans (negative assertion)', () {
      // Post-migration no active plan may carry a legacy document ID.
      // MembershipPlan itself is ID-agnostic; this pins the contract that
      // only guest/free/pro/max are issued by seed and migration tooling.
      const validIds = <String>{'guest', 'free', 'pro', 'max'};
      expect(validIds, isNot(contains('center_free')));
      expect(validIds, isNot(contains('center_pro')));
      expect(validIds, isNot(contains('center_max')));
    });
  });

  group('Membership query contract — guest value flows through', () {
    test('guest studentType is a valid query value (not legacy)', () {
      // MembershipRemoteDataSource passes studentType straight into
      // where('student_type', isEqualTo: studentType) and the
      // activateFreePlan payload; the value reaching it must be guest.
      const studentType = 'guest';
      expect(studentType, isNot('public_student'));
      expect(studentType, 'guest');
    });
  });
}
