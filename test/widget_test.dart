import 'package:dr_tarek_platform/app/app.dart';
import 'package:dr_tarek_platform/core/localization/locale_controller.dart';
import 'package:dr_tarek_platform/features/authentication/domain/entities/session_state.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/providers/session_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSessionController extends SessionController {
  final SessionState session;

  _FakeSessionController(this.session);

  @override
  Future<SessionState> build() async => session;
}

void main() {
  testWidgets('Dr. Tarek Platform app loads', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialLocaleProvider.overrideWithValue(const Locale('ar')),
          // Deterministic session: unauthenticated -> user type selection.
          sessionProvider.overrideWith(
            () => _FakeSessionController(const SessionUnauthenticated()),
          ),
        ],
        child: const DrTarekPlatformApp(),
      ),
    );
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();

    // The entry gate renders after the splash hand-off.
    expect(find.text('طالب جديد'), findsOneWidget);
    expect(find.text('طالب حالي'), findsOneWidget);
  });
}
