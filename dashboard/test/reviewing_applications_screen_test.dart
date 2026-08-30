import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drtarek_dashboard/core/widgets/dashboard_filter_dropdown.dart';
import 'package:drtarek_dashboard/features/applications/domain/entities/join_application.dart';
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
  List<JoinApplication> applications,
) async {
  tester.view.physicalSize = const Size(1440, 1024);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        joinApplicationsProvider
            .overrideWith((ref) => Stream.value(applications)),
      ],
      child: const MaterialApp(home: ReviewingApplicationsScreen()),
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
}
