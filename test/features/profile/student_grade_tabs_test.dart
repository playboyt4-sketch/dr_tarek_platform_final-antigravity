import 'package:dr_tarek_platform/features/authentication/domain/entities/auth_user.dart';
import 'package:dr_tarek_platform/features/profile/presentation/providers/profile_providers.dart';
import 'package:dr_tarek_platform/features/profile/presentation/screens/grade_one_profile_overview_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the read-only top Grade tabs: tapping a tab must never change
/// the displayed grade. The Grade Edit dialog (backed by
/// `updateStudentGrade` + provider refetch) is the only grade-change
/// mechanism; `activeGradeTab` is driven solely by `_seedFromProfile`.
void main() {
  const persistedUser = AuthUser(
    id: 'stu_001',
    fullName: 'asmaa mohamed',
    phoneNumber: '01115800180',
    role: 'student',
    studentType: 'center_student',
    grade: 'grade_two',
    approvalStatus: 'approved',
    accountStatus: 'active',
  );

  Future<void> pumpOverview(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          studentProfileProvider('stu_001')
              .overrideWithValue(const AsyncValue.data(persistedUser)),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: GradeOneProfileOverviewScreen(studentId: 'stu_001'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('top Grade tabs reflect the persisted grade', (tester) async {
    await pumpOverview(tester);

    // Persisted grade_two renders as 'Grade Two' in both the top tabs
    // and the Grade row.
    expect(find.text('Grade Two'), findsNWidgets(2));
    expect(find.text('Grade Three'), findsOneWidget);
  });

  testWidgets('tapping another top Grade tab does not change the grade',
      (tester) async {
    await pumpOverview(tester);

    // Tap the Grade Three top tab: with read-only tabs this is a no-op.
    await tester.tap(find.text('Grade Three').first);
    await tester.pumpAndSettle();

    // Still exactly one 'Grade Three' (the tab itself) and the Grade row
    // still shows the persisted 'Grade Two' — no local mutation occurred.
    expect(find.text('Grade Three'), findsOneWidget);
    expect(find.text('Grade Two'), findsNWidgets(2));
  });
}
