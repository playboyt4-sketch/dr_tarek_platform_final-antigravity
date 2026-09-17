import 'package:dr_tarek_platform/app/app.dart';
import 'package:dr_tarek_platform/core/localization/locale_controller.dart';
import 'package:dr_tarek_platform/features/authentication/domain/entities/session_state.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/providers/session_provider.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/screens/splash_screen.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/screens/user_type_selection_screen.dart';
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
    await tester.pump();

    // The current SplashScreen brands first, then hands off.
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.text('Tarek el araby'), findsOneWidget);

    // Step through the logo fade (1400ms) + splash stay (800ms), then let
    // the handoff transition finish before asserting the entry gate.
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    // The entry gate renders after the splash hand-off.
    expect(find.byType(UserTypeSelectionScreen), findsOneWidget);
    expect(find.text('طالب جديد'), findsOneWidget);
    expect(find.text('طالب حالي'), findsOneWidget);
  });
}
