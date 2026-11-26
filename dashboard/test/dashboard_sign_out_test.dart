import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drtarek_dashboard/app/shell/dashboard_full_menu.dart';

void main() {
  testWidgets('full management menu renders Sign Out and triggers callback',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    int signOutTaps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardFullMenu(
            onNavigate: (_) {},
            onSignOut: () => signOutTaps++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign Out'), findsOneWidget);
    await tester.tap(find.text('Sign Out'));
    await tester.pumpAndSettle();

    expect(signOutTaps, 1);
  });
}
