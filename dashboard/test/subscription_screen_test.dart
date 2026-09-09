import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drtarek_dashboard/features/subscription/presentation/providers/subscription_matrix_provider.dart';
import 'package:drtarek_dashboard/features/subscription/presentation/screens/subscription_screen.dart';

const List<SubscriptionPlan> _fakePlans = <SubscriptionPlan>[
  SubscriptionPlan(id: 'guest', label: 'Guest'),
  SubscriptionPlan(id: 'free', label: 'Center FREE'),
  SubscriptionPlan(id: 'pro', label: 'Center PRO'),
  SubscriptionPlan(id: 'max', label: 'Center MAX'),
];

const Map<String, PlanFeatureState> _fakeMatrix = <String, PlanFeatureState>{
  'video.access': PlanFeatureState(key: 'video.access', enabled: true),
  'video.playback_speed':
      PlanFeatureState(key: 'video.playback_speed', enabled: false),
  'video.preview_duration': PlanFeatureState(
      key: 'video.preview_duration', enabled: true, value: 5),
  'video.rolling_window.enabled': PlanFeatureState(
      key: 'video.rolling_window.enabled', enabled: false),
  'pdf.access': PlanFeatureState(key: 'pdf.access', enabled: false),
};

const List<CorePeriodState> _fakePeriods = <CorePeriodState>[
  CorePeriodState(id: 'core_term_1', label: 'Term 1', isActive: true),
  CorePeriodState(id: 'core_term_2', label: 'Term 2', isActive: false),
];

class _Call {
  final String planId;
  final String featureKey;
  final bool enabled;
  final Object? value;

  const _Call(this.planId, this.featureKey, this.enabled, this.value);
}

class _FakeActions implements SubscriptionActions {
  final List<_Call> calls = <_Call>[];
  final List<String> termCalls = <String>[];

  @override
  Future<void> setFeature({
    required String planId,
    required String featureKey,
    required bool enabled,
    Object? value,
    String valueType = 'boolean',
  }) async {
    calls.add(_Call(planId, featureKey, enabled, value));
  }

  @override
  Future<void> setTermStatus({
    required String periodId,
    required bool activate,
  }) async {
    termCalls.add('$periodId:${activate ? 'active' : 'ended'}');
  }
}

Future<ProviderScope> _pumpScreen(
  WidgetTester tester,
  _FakeActions actions, {
  bool isTeacher = true,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final ProviderScope scope = ProviderScope(
    overrides: [
      subscriptionPlansProvider
          .overrideWith((ref) => Stream.value(_fakePlans)),
      subscriptionMatrixProvider
          .overrideWith((ref, String planId) => Stream.value(_fakeMatrix)),
      corePeriodsProvider
          .overrideWith((ref) => Stream.value(_fakePeriods)),
      subscriptionActionsProvider.overrideWithValue(actions),
    ],
    child: MaterialApp(
        home: Scaffold(body: SubscriptionScreen(isTeacher: isTeacher))),
  );
  await tester.pumpWidget(scope);
  await tester.pumpAndSettle();
  return scope;
}

void main() {
  group('SubscriptionScreen', () {
    testWidgets('renders plans nav bar with the four plans',
        (WidgetTester tester) async {
      await _pumpScreen(tester, _FakeActions());

      expect(find.text('Guest'), findsOneWidget);
      expect(find.text('Center FREE'), findsOneWidget);
      expect(find.text('Center PRO'), findsOneWidget);
      expect(find.text('Center MAX'), findsOneWidget);
    });

    testWidgets('renders category pills and feature rows of selected plan',
        (WidgetTester tester) async {
      await _pumpScreen(tester, _FakeActions());

      expect(find.text('Video & Media'), findsWidgets);
      expect(find.text('Pdf & documents'), findsWidgets);
      expect(find.text('Learning & Assessment'), findsWidgets);
      expect(find.text('Video access'), findsOneWidget);
      expect(find.text('video.access'), findsOneWidget);
      expect(find.text('Video Rolling Window'), findsOneWidget);
      expect(find.text('video.rolling_window.enabled'), findsOneWidget);
      expect(find.text('X2.00'), findsOneWidget);
      expect(find.text('Block Root & Emulators'), findsOneWidget);
      expect(find.text('Exam Retake Attempts Limit'), findsOneWidget);
      expect(find.byType(CupertinoSwitch), findsWidgets);
    });

    testWidgets('tapping a plan pill switches the summary bar',
        (WidgetTester tester) async {
      await _pumpScreen(tester, _FakeActions());

      expect(
        find.textContaining('Guest — 2 of'),
        findsOneWidget,
      );
      await tester.tap(find.text('Center PRO'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Center PRO — 2 of'),
        findsOneWidget,
      );
    });

    testWidgets('toggling a switch calls setPlanFeature',
        (WidgetTester tester) async {
      final _FakeActions actions = _FakeActions();
      await _pumpScreen(tester, actions);

      final Finder speedSwitch =
          find.byKey(const Key('switch-video.playback_speed'));
      expect(speedSwitch, findsOneWidget);

      await tester.ensureVisible(speedSwitch);
      await tester.pumpAndSettle();
      await tester.tap(speedSwitch);
      await tester.pumpAndSettle();

      expect(actions.calls, hasLength(1));
      expect(actions.calls.single.planId, 'guest');
      expect(actions.calls.single.featureKey, 'video.playback_speed');
      expect(actions.calls.single.enabled, isTrue);
    });

    testWidgets('term strip shows active term with start/end buttons',
        (WidgetTester tester) async {
      await _pumpScreen(tester, _FakeActions());

      expect(find.textContaining('Active term: Term 1'), findsOneWidget);
      expect(find.text('End Term 1'), findsOneWidget);
      expect(find.text('Start Term 2'), findsOneWidget);
    });

    testWidgets('admin sessions see rolling-window rows locked',
        (WidgetTester tester) async {
      final _FakeActions actions = _FakeActions();
      await _pumpScreen(tester, actions, isTeacher: false);

      expect(
        find.text('video.rolling_window.enabled · Teacher only'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('switch-video.rolling_window.enabled')),
        findsNothing,
      );
      expect(find.text('Teacher only'), findsWidgets);

      // Ordinary rows stay interactive for delegated admins.
      expect(
        find.byKey(const Key('switch-video.playback_speed')),
        findsOneWidget,
      );
    });

    testWidgets('ending a term confirms then calls setTermStatus',
        (WidgetTester tester) async {
      final _FakeActions actions = _FakeActions();
      await _pumpScreen(tester, actions);

      await tester.tap(find.text('End Term 1'));
      await tester.pumpAndSettle();

      expect(find.text('Confirm'), findsOneWidget);
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(actions.termCalls, <String>['core_term_1:ended']);
    });
  });
}
