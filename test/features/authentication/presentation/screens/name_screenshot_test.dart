import 'package:dr_tarek_platform/core/constants/asset_paths.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/screens/new_student_name_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('capture 393x852 screenshot (golden)', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: NewStudentNameScreen(),
        ),
      ),
    );
    await tester.pump();
    // Asset-image decode is real async work: let it finish outside fake
    // async, then settle, so the golden captures decoded pixels instead
    // of a blank (still-loading) box.
    final hostContext = tester.element(find.byType(NewStudentNameScreen));
    await tester.runAsync(
      () => precacheImage(
        const AssetImage(AssetImages.newStudentNamePhoto),
        hostContext,
      ),
    );
    await tester.pumpAndSettle();

    final artSize = tester.getSize(
      find.byKey(const Key('nameIllustrationStack')),
    );
    final titleBottom =
        tester.getBottomRight(find.byKey(const Key('nameTitle'))).dy;
    final fieldTop =
        tester.getTopLeft(find.byKey(const Key('nameField'))).dy;
    // ignore: avoid_print
    print('ART ${artSize.width}x${artSize.height} '
        'aspect=${artSize.width / artSize.height} '
        'gap=${fieldTop - titleBottom}');

    await expectLater(
      find.byType(NewStudentNameScreen),
      matchesGoldenFile('goldens/name_screen_393x852.png'),
    );
  });
}
