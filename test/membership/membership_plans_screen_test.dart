import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dr_tarek_platform/features/authentication/domain/entities/auth_user.dart';
import 'package:dr_tarek_platform/features/membership/domain/entities/membership_plan.dart';
import 'package:dr_tarek_platform/features/membership/domain/entities/plan_feature.dart';
import 'package:dr_tarek_platform/features/membership/presentation/providers/membership_providers.dart';
import 'package:dr_tarek_platform/features/membership/presentation/screens/membership_plans_screen.dart';
import 'package:dr_tarek_platform/features/student_dashboard/presentation/providers/dashboard_providers.dart';

/// Phase 2B presentation verification: the membership browser accepts the
/// Guest student type (backend-issued `student_type = guest`) and renders
/// the Guest plan, without confusing it with Center plans.
const _guestUser = AuthUser(
  id: 'u-guest',
  fullName: 'Guest Student',
  phoneNumber: '01000000000',
  role: 'student',
  studentType: 'guest',
  approvalStatus: 'approved',
  accountStatus: 'active',
);

const _centerUser = AuthUser(
  id: 'u-center',
  fullName: 'Center Student',
  phoneNumber: '01000000001',
  role: 'student',
  studentType: 'center_student',
  approvalStatus: 'approved',
  accountStatus: 'active',
);

const _unknownUser = AuthUser(
  id: 'u-unknown',
  fullName: 'Unknown',
  phoneNumber: '01000000002',
  role: 'student',
  studentType: 'legacy_type',
  approvalStatus: 'approved',
  accountStatus: 'active',
);

const _guestPlan = MembershipPlan(
  id: 'guest',
  planName: 'Guest',
  planKey: 'free',
  studentType: 'guest',
  displayOrder: 1,
  isActive: true,
);

const _freePlan = MembershipPlan(
  id: 'free',
  planName: 'Free',
  planKey: 'free',
  studentType: 'center_student',
  displayOrder: 2,
  isActive: true,
);

Future<void> _pumpPlans(
  WidgetTester tester, {
  required AuthUser user,
  required List<MembershipPlan> plans,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        availablePlansProvider.overrideWith(
          (ref, arg) async => plans,
        ),
        planFeaturesProvider.overrideWith(
          (ref, arg) async => const <PlanFeature>[],
        ),
        dashboardSubjectsProvider.overrideWith(
          (ref) async => const [],
        ),
      ],
      child: MaterialApp(
        home: MembershipPlansScreen(user: user),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('MembershipPlansScreen — guest student type', () {
    testWidgets('guest renders the Guest plan (not the blocked state)',
        (tester) async {
      await _pumpPlans(tester, user: _guestUser, plans: const [_guestPlan]);

      expect(find.text('نوع الطالب غير مُعدّ بعد.'), findsNothing);
      expect(find.text('Guest'), findsWidgets);
      // planKey badge still shows the preserved "free" classification.
      expect(find.text('free'), findsWidgets);
    });

    testWidgets('center student keeps Center behavior', (tester) async {
      await _pumpPlans(
          tester, user: _centerUser, plans: const [_freePlan]);

      expect(find.text('نوع الطالب غير مُعدّ بعد.'), findsNothing);
      expect(find.text('Free'), findsOneWidget);
    });

    testWidgets('unknown type is still blocked', (tester) async {
      await _pumpPlans(tester, user: _unknownUser, plans: const []);

      expect(find.text('نوع الطالب غير مُعدّ بعد.'), findsOneWidget);
    });

    testWidgets('free (planKey free) does not render as Guest',
        (tester) async {
      await _pumpPlans(
          tester, user: _centerUser, plans: const [_freePlan]);

      expect(find.text('Free'), findsOneWidget);
      expect(find.text('Guest'), findsNothing);
    });
  });
}
