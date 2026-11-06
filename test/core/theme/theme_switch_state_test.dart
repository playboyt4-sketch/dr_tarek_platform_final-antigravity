import 'package:dr_tarek_platform/core/theme/app_theme.dart';
import 'package:dr_tarek_platform/core/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// QA guard for the appearance contract: swapping the theme must only swap the
/// `MaterialApp` theme. It must not recreate the navigator, pop a route, or
/// discard form state. Authentication is untouched because the theme layer
/// never reads or writes auth state.

class _Harness extends ConsumerWidget {
  const _Harness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(themeControllerProvider),
      home: const _FirstPage(),
    );
  }
}

class _FirstPage extends StatelessWidget {
  const _FirstPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const _SecondPage()),
            );
          },
          child: const Text('open second page'),
        ),
      ),
    );
  }
}

class _SecondPage extends StatefulWidget {
  const _SecondPage();

  @override
  State<_SecondPage> createState() => _SecondPageState();
}

class _SecondPageState extends State<_SecondPage> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('second page')),
      body: TextField(
        key: const ValueKey('draft'),
        controller: _controller,
        decoration: const InputDecoration(labelText: 'draft answer'),
      ),
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('switching the theme keeps the route and its form state',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _Harness(),
      ),
    );

    await tester.tap(find.text('open second page'));
    await tester.pumpAndSettle();
    expect(find.text('second page'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('draft')), 'answer in progress');
    await tester.pump();
    expect(find.text('answer in progress'), findsOneWidget);

    // Light -> Dark.
    await container
        .read(themeControllerProvider.notifier)
        .setThemeMode(ThemeMode.dark);
    await tester.pumpAndSettle();

    expect(
      Theme.of(tester.element(find.text('second page'))).brightness,
      Brightness.dark,
    );
    expect(find.text('answer in progress'), findsOneWidget);
    expect(find.text('open second page'), findsNothing);

    // Dark -> Light: still the same route and the same draft.
    await container
        .read(themeControllerProvider.notifier)
        .setThemeMode(ThemeMode.light);
    await tester.pumpAndSettle();

    expect(
      Theme.of(tester.element(find.text('second page'))).brightness,
      Brightness.light,
    );
    expect(find.text('answer in progress'), findsOneWidget);
  });

  testWidgets('setThemeMode persists without rebuilding the provider scope',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _Harness(),
      ),
    );

    await container
        .read(themeControllerProvider.notifier)
        .setThemeMode(ThemeMode.dark);
    await tester.pumpAndSettle();

    // The controller kept its state and wrote the preference; a cold start
    // resolves the same value (see theme_controller_test.dart).
    expect(container.read(themeControllerProvider), ThemeMode.dark);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kThemeModePrefsKey), 'dark');
  });
}
