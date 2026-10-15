import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drtarek_dashboard/features/subscription/presentation/providers/subscription_matrix_provider.dart';
import 'package:drtarek_dashboard/features/subscription/presentation/screens/subscription_screen.dart';

const List<SubscriptionPlan> _fakePlans = <SubscriptionPlan>[
  SubscriptionPlan(id: 'guest', label: 'Guest'),
  SubscriptionPlan(id: 'free', label: 'FREE'),
  SubscriptionPlan(id: 'pro', label: 'PRO'),
  SubscriptionPlan(id: 'max', label: 'MAX'),
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
  bool isDoctor = true,
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
        home: Scaffold(body: SubscriptionScreen(isDoctor: isDoctor))),
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
      expect(find.text('FREE'), findsOneWidget);
      expect(find.text('PRO'), findsOneWidget);
      expect(find.text('MAX'), findsOneWidget);
    });

    testWidgets('renders category pills and feature rows of selected plan',
        (WidgetTester tester) async {
      await _pumpScreen(tester, _FakeActions());

      expect(find.text('Video & Media'), findsWidgets);
      expect(find.text('Pdf & documents'), findsWidgets);
      expect(find.text('Learning & Assessment'), findsWidgets);
      expect(find.text('Video access'), findsOneWidget);
      expect(find.text('Video Rolling Window'), findsOneWidget);
      expect(find.text('Video Rolling hours'), findsOneWidget);
      expect(find.text('Video Limited Duration'), findsOneWidget);
      expect(find.text('Video Preview Duration'), findsOneWidget);
      expect(find.text('Video Resolution'), findsOneWidget);
      expect(find.text('X2.00'), findsOneWidget);
      expect(find.text('Block Root & Emulators'), findsOneWidget);
      expect(find.text('Exam Retake Attempts Limit'), findsOneWidget);
      expect(find.byType(CupertinoSwitch), findsWidgets);
    });

    testWidgets('tapping a plan pill keeps per-plan matrix isolation',
        (WidgetTester tester) async {
      final _FakeActions actions = _FakeActions();
      await _pumpScreen(tester, actions);

      // Matrix of the default (guest) plan renders.
      expect(find.text('Video access'), findsOneWidget);

      // Switch to PRO: the same catalog renders for the new plan and a
      // toggle writes with planId == pro (never a shared local map).
      await tester.tap(find.text('PRO'));
      await tester.pumpAndSettle();

      expect(find.text('Video access'), findsOneWidget);

      final Finder speedSwitch =
          find.byKey(const Key('switch-video.playback_speed.x2_0'));
      await tester.ensureVisible(speedSwitch);
      await tester.pumpAndSettle();
      await tester.tap(speedSwitch);
      await tester.pumpAndSettle();

      expect(actions.calls, hasLength(1));
      expect(actions.calls.single.planId, 'pro');
      expect(actions.calls.single.featureKey, 'video.playback_speed.x2_0');
      expect(actions.calls.single.enabled, isTrue);
    });

    testWidgets('toggling a switch calls setPlanFeature',
        (WidgetTester tester) async {
      final _FakeActions actions = _FakeActions();
      await _pumpScreen(tester, actions);

      final Finder speedSwitch =
          find.byKey(const Key('switch-video.playback_speed.x2_0'));
      expect(speedSwitch, findsOneWidget);

      await tester.ensureVisible(speedSwitch);
      await tester.pumpAndSettle();
      await tester.tap(speedSwitch);
      await tester.pumpAndSettle();

      expect(actions.calls, hasLength(1));
      expect(actions.calls.single.planId, 'guest');
      expect(actions.calls.single.featureKey, 'video.playback_speed.x2_0');
      expect(actions.calls.single.enabled, isTrue);
    });

    testWidgets('admin sessions see rolling-window rows locked',
        (WidgetTester tester) async {
      // No lock label exists in the Figma spec: the documented lock
      // representation is the standard disabled-control state on exactly
      // the Doctor-only monetization rows (backend SENSITIVE_PLAN_FEATURES).
      final _FakeActions actions = _FakeActions();
      await _pumpScreen(tester, actions, isDoctor: false);

      final Finder rollingSwitch =
          find.byKey(const Key('rolling-window-switch'));
      expect(rollingSwitch, findsOneWidget);
      expect(
        tester.widget<Switch>(rollingSwitch).onChanged,
        isNull,
      );

      final Finder hoursBadge = find.byKey(const Key('rolling-hours-badge'));
      expect(hoursBadge, findsOneWidget);
      expect(
        tester.widget<TextFormField>(hoursBadge).enabled,
        isFalse,
      );

      // Ordinary rows stay interactive for delegated admins.
      expect(
        find.byWidgetPredicate(
          (Widget widget) => widget is Switch && widget.onChanged != null,
        ),
        findsWidgets,
      );
    });

    testWidgets('extra non-canonical plans are never shown',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const List<SubscriptionPlan> plansWithExtras = <SubscriptionPlan>[
        SubscriptionPlan(id: 'guest', label: 'Guest'),
        SubscriptionPlan(id: 'free', label: 'FREE'),
        SubscriptionPlan(id: 'pro', label: 'PRO'),
        SubscriptionPlan(id: 'max', label: 'MAX'),
        SubscriptionPlan(id: 'bundle_basic', label: 'باقة السنتر الأساسية'),
        SubscriptionPlan(id: 'bundle_max', label: 'باقة الشاملة (Max)'),
      ];
      final _FakeActions actions = _FakeActions();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            subscriptionPlansProvider
                .overrideWith((ref) => Stream.value(plansWithExtras)),
            subscriptionMatrixProvider.overrideWith(
                (ref, String planId) => Stream.value(_fakeMatrix)),
            subscriptionActionsProvider.overrideWithValue(actions),
          ],
          child: const MaterialApp(
              home: Scaffold(body: SubscriptionScreen(isDoctor: true))),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Guest'), findsOneWidget);
      expect(find.text('FREE'), findsOneWidget);
      expect(find.text('PRO'), findsOneWidget);
      expect(find.text('MAX'), findsOneWidget);
      expect(find.text('باقة السنتر الأساسية'), findsNothing);
      expect(find.text('باقة الشاملة (Max)'), findsNothing);
    });

    testWidgets('number badges show each plan’s own value',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      Map<String, PlanFeatureState> matrixFor(String planId) {
        final int hours = planId == 'free' ? 48 : 24;
        return <String, PlanFeatureState>{
          'video.access':
              const PlanFeatureState(key: 'video.access', enabled: true),
          'video.rolling_window.enabled': const PlanFeatureState(
              key: 'video.rolling_window.enabled', enabled: true),
          'video.rolling_window.hours': PlanFeatureState(
              key: 'video.rolling_window.hours',
              enabled: true,
              value: hours),
        };
      }

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            subscriptionPlansProvider
                .overrideWith((ref) => Stream.value(_fakePlans)),
            subscriptionMatrixProvider.overrideWith(
                (ref, String planId) => Stream.value(matrixFor(planId))),
            subscriptionActionsProvider
                .overrideWithValue(_FakeActions()),
          ],
          child: const MaterialApp(
              home: Scaffold(body: SubscriptionScreen(isDoctor: true))),
        ),
      );
      await tester.pumpAndSettle();

      Finder hoursBadge() =>
          find.byKey(const Key('rolling-hours-badge'));
      String badgeText() =>
          tester.widget<TextFormField>(hoursBadge()).controller?.text ??
          '';

      // Guest tab shows guest's own hours.
      expect(badgeText(), '24');

      // FREE tab shows free's own hours — never guest's value.
      await tester.tap(find.text('FREE'));
      await tester.pumpAndSettle();
      expect(badgeText(), '48');

      // Back to guest: guest's value again.
      await tester.tap(find.text('Guest'));
      await tester.pumpAndSettle();
      expect(badgeText(), '24');
    });

    testWidgets('manual scroll follows the active category tab',
        (WidgetTester tester) async {
      await _pumpScreen(tester, _FakeActions());

      Color? tabColor(String label) =>
          tester.widget<Text>(find.text(label)).style?.color;

      // Initial position: Video & Media selected.
      expect(tabColor('Video & Media'), Colors.white);
      expect(tabColor('Profile & Account'),
          const Color(0xFF4B5563));

      // Scroll to the very bottom: the last section owns the tab.
      final Finder scroller = find.byWidgetPredicate(
        (Widget widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.vertical,
      );
      expect(scroller, findsOneWidget);
      await tester.drag(scroller, const Offset(0, -12000));
      await tester.pumpAndSettle();
      await tester.drag(scroller, const Offset(0, -12000));
      await tester.pumpAndSettle();

      expect(tabColor('Profile & Account'), Colors.white);
      expect(tabColor('Video & Media'), const Color(0xFF4B5563));
    });

    testWidgets('switching plans keeps the active section in view',
        (WidgetTester tester) async {
      await _pumpScreen(tester, _FakeActions());

      bool tabSelected(String label) =>
          tester.widget<Text>(find.text(label)).style?.color ==
          Colors.white;
      bool sectionVisible(String rowTitle) {
        final Offset center = tester.getCenter(find.text(rowTitle));
        return center.dy >= 0 && center.dy <= 800;
      }

      // Go to the PDF section via its tab.
      await tester.tap(find.text('Pdf & documents'));
      await tester.pumpAndSettle();
      expect(tabSelected('Pdf & documents'), isTrue);
      expect(sectionVisible('PDF access'), isTrue);

      // Switch plan: same section stays selected AND visible,
      // so plans can be compared section-by-section.
      await tester.tap(find.text('PRO'));
      await tester.pumpAndSettle();

      expect(tabSelected('Pdf & documents'), isTrue);
      expect(sectionVisible('PDF access'), isTrue);
      expect(sectionVisible('Video access'), isFalse);
    });
  });
}
