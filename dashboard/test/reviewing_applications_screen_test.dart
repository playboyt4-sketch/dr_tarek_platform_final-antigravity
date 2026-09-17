import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drtarek_dashboard/core/widgets/dashboard_filter_dropdown.dart';
import 'package:drtarek_dashboard/features/applications/domain/entities/join_application.dart';
import 'package:drtarek_dashboard/features/applications/presentation/providers/application_decision_provider.dart';
import 'package:drtarek_dashboard/features/applications/presentation/providers/join_applications_provider.dart';
import 'package:drtarek_dashboard/features/applications/presentation/screens/reviewing_applications_screen.dart';

JoinApplication _app(String id, String name, String? gradeKey) =>
    JoinApplication(
      id: id,
      fullName: name,
      phone: '0100000000',
      gradeKey: gradeKey,
      studentType: 'center_student',
      createdAt: DateTime(2026, 8, 26),
    );

Future<void> _pumpScreen(
  WidgetTester tester,
  List<JoinApplication> applications, {
  List<SubjectOption> subjects = const <SubjectOption>[],
}) async {
  tester.view.physicalSize = const Size(1440, 1024);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        joinApplicationsProvider
            .overrideWith((ref) => Stream.value(applications)),
        gradeSubjectsProvider('grade_one')
            .overrideWith((ref) => Stream.value(subjects)),
        gradeSubjectsProvider('grade_two')
            .overrideWith((ref) => Stream.value(subjects)),
        gradeSubjectsProvider('grade_three')
            .overrideWith((ref) => Stream.value(subjects)),
        gradeSubjectsProvider('grade_four')
            .overrideWith((ref) => Stream.value(subjects)),
        gradeSubjectsProvider(null)
            .overrideWith((ref) => Stream.value(subjects)),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: ReviewingApplicationsScreen()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows every pending application under الكل',
      (WidgetTester tester) async {
    await _pumpScreen(tester, <JoinApplication>[
      _app('a', 'أحمد محمد', 'grade_one'),
      _app('b', 'سارة علي', 'grade_two'),
      _app('c', 'منى خالد', 'grade_three'),
    ]);

    expect(find.text('أحمد محمد'), findsOneWidget);
    expect(find.text('سارة علي'), findsOneWidget);
    expect(find.text('منى خالد'), findsOneWidget);
  });

  testWidgets('choosing الفرقة الثانية keeps only its applications',
      (WidgetTester tester) async {
    await _pumpScreen(tester, <JoinApplication>[
      _app('a', 'أحمد محمد', 'grade_one'),
      _app('b', 'سارة علي', 'grade_two'),
      _app('c', 'منى خالد', 'grade_two'),
      _app('d', 'ياسر سمير', null),
    ]);

    await tester.tap(find.byType(DashboardFilterDropdown<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الفرقة الثانية').last);
    await tester.pumpAndSettle();

    expect(find.text('أحمد محمد'), findsNothing);
    expect(find.text('ياسر سمير'), findsNothing);
    expect(find.text('سارة علي'), findsOneWidget);
    expect(find.text('منى خالد'), findsOneWidget);
  });

  testWidgets('switching back to الكل restores the full list',
      (WidgetTester tester) async {
    await _pumpScreen(tester, <JoinApplication>[
      _app('a', 'أحمد محمد', 'grade_one'),
      _app('b', 'سارة علي', 'grade_four'),
    ]);

    await tester.tap(find.byType(DashboardFilterDropdown<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الفرقة الرابعة').last);
    await tester.pumpAndSettle();
    expect(find.text('أحمد محمد'), findsNothing);

    await tester.tap(find.byType(DashboardFilterDropdown<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الكل').last);
    await tester.pumpAndSettle();

    expect(find.text('أحمد محمد'), findsOneWidget);
    expect(find.text('سارة علي'), findsOneWidget);
  });

  testWidgets('tapping مراجعة الطلب opens the decision dialog',
      (WidgetTester tester) async {
    await _pumpScreen(tester, <JoinApplication>[
      _app('a', 'أحمد محمد', 'grade_one'),
    ]);

    await tester.tap(find.text('مراجعة الطلب').first);
    await tester.pumpAndSettle();

    expect(find.text('قبول الطلب'), findsOneWidget);
    expect(find.text('رفض الطلب'), findsOneWidget);
    expect(find.text('نوع الطالب'), findsOneWidget);
    expect(find.text('باقة الاشتراك'), findsOneWidget);
    expect(find.text('المواد المصرح بها'), findsOneWidget);
    expect(find.text('تأكيد القبول'), findsOneWidget);
  });

  testWidgets('decision dialog lists grade subjects with toggles',
      (WidgetTester tester) async {
    await _pumpScreen(
      tester,
      <JoinApplication>[_app('a', 'أحمد محمد', 'grade_one')],
      subjects: const <SubjectOption>[
        SubjectOption(id: 's1', title: 'الفيزياء', gradeKey: 'grade_one'),
        SubjectOption(id: 's2', title: 'الكيمياء', gradeKey: 'grade_one'),
      ],
    );

    await tester.tap(find.text('مراجعة الطلب').first);
    await tester.pumpAndSettle();

    expect(find.text('الفيزياء'), findsOneWidget);
    expect(find.text('الكيمياء'), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(2));
  });

  testWidgets('reject tab requires a reason before confirming',
      (WidgetTester tester) async {
    await _pumpScreen(tester, <JoinApplication>[
      _app('a', 'أحمد محمد', 'grade_one'),
    ]);

    await tester.tap(find.text('مراجعة الطلب').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('رفض الطلب'));
    await tester.pumpAndSettle();

    expect(find.text('سبب الرفض'), findsOneWidget);
    await tester.tap(find.text('تأكيد الرفض'));
    await tester.pumpAndSettle();

    expect(find.text('اكتب سبب الرفض (3 أحرف على الأقل).'), findsOneWidget);
  });
}
