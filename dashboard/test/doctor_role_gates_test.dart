import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drtarek_dashboard/core/di/firebase_providers.dart';
import 'package:drtarek_dashboard/features/authentication/domain/entities/dashboard_session.dart';
import 'package:drtarek_dashboard/features/authentication/presentation/providers/auth_providers.dart';
import 'package:drtarek_dashboard/features/home/presentation/providers/home_stats_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/providers/student_profile_devices_provider.dart';
import 'package:drtarek_dashboard/features/subscription/presentation/screens/subscription_screen.dart';

/// ADR-005 authorization-derived UI gates.
///
/// doctor = full Platform Owner behavior; delegated admin keeps existing
/// behavior; unknown/loading sessions fail closed. No `dr` RBAC role exists.

DashboardSession _session(String uid, String? role, bool approved) =>
    DashboardSession(userId: uid, role: role, approved: approved);

ProviderContainer _containerWithSession(
  DashboardSession? session, {
  Map<String, bool> deviceGrants = const <String, bool>{},
}) {
  return ProviderContainer(
    overrides: [
      sessionProvider.overrideWithValue(AsyncData<DashboardSession?>(session)),
      for (final MapEntry<String, bool> grant in deviceGrants.entries)
        adminDevicePermissionProvider(grant.key)
            .overrideWithValue(AsyncData<bool>(grant.value)),
    ],
  );
}

void main() {
  group('canManageStudentDevicesProvider (ADR-005)', () {
    test('doctor session grants full management without delegation lookup',
        () async {
      final container = _containerWithSession(_session('d1', 'doctor', true));
      addTearDown(container.dispose);
      await container.read(sessionProvider.future);

      // No adminDevicePermissionProvider override is registered: if the
      // provider consulted delegation for doctors, this would throw.
      expect(
        container.read(canManageStudentDevicesProvider),
        const AsyncData<bool>(true),
      );
    });

    test('legacy teacher session is denied', () async {
      final container = _containerWithSession(_session('t1', 'teacher', true));
      addTearDown(container.dispose);
      await container.read(sessionProvider.future);

      expect(
        container.read(canManageStudentDevicesProvider),
        const AsyncData<bool>(false),
      );
    });

    test('delegated admin keeps existing grant behavior', () async {
      final granted = _containerWithSession(
        _session('a1', 'admin', true),
        deviceGrants: <String, bool>{'a1': true},
      );
      addTearDown(granted.dispose);
      await granted.read(sessionProvider.future);
      expect(
        granted.read(canManageStudentDevicesProvider),
        const AsyncData<bool>(true),
      );

      final denied = _containerWithSession(
        _session('a1', 'admin', true),
        deviceGrants: <String, bool>{'a1': false},
      );
      addTearDown(denied.dispose);
      await denied.read(sessionProvider.future);
      expect(
        denied.read(canManageStudentDevicesProvider),
        const AsyncData<bool>(false),
      );
    });

    test('student, unapproved, null and loading sessions fail closed',
        () async {
      for (final DashboardSession? session in <DashboardSession?>[
        _session('s1', 'student', true),
        _session('d1', 'doctor', false),
        _session('a1', 'admin', false),
        null,
      ]) {
        final container = _containerWithSession(session);
        addTearDown(container.dispose);
        await container.read(sessionProvider.future);
        expect(
          container.read(canManageStudentDevicesProvider),
          const AsyncData<bool>(false),
        );
      }

      final loading = ProviderContainer(
        overrides: [
          sessionProvider.overrideWithValue(
              const AsyncLoading<DashboardSession?>()),
        ],
      );
      addTearDown(loading.dispose);
      expect(
        loading.read(canManageStudentDevicesProvider),
        isA<AsyncLoading<bool>>(),
      );
    });
  });

  group('SubscriptionScreen role flag (ADR-005)', () {
    testWidgets('builds with isDoctor true and false', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      for (final bool isDoctor in <bool>[true, false]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: SubscriptionScreen(isDoctor: isDoctor)),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(SubscriptionScreen), findsOneWidget);
      }
    });
  });

  group('homeStatsProvider staff query (ADR-005)', () {
    test('staff count includes doctor and admin, not legacy teacher',
        () async {
      final FakeFirebaseFirestore fake = FakeFirebaseFirestore();
      await fake.collection('users').doc('d1').set(<String, dynamic>{
        'role': 'doctor',
        'approval_status': 'approved',
      });
      await fake.collection('users').doc('a1').set(<String, dynamic>{
        'role': 'admin',
        'approval_status': 'approved',
      });
      await fake.collection('users').doc('t1').set(<String, dynamic>{
        'role': 'teacher',
        'approval_status': 'approved',
      });
      await fake.collection('users').doc('s1').set(<String, dynamic>{
        'role': 'student',
        'approval_status': 'approved',
      });

      final container = ProviderContainer(
        overrides: [
          firebaseFirestoreProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);

      final HomeStats stats = await container.read(homeStatsProvider.future);
      expect(stats.staff, 2);
    });
  });
}
