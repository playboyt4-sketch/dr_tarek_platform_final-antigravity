import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dr_tarek_platform/features/membership/data/datasources/membership_remote_data_source.dart';
import 'package:dr_tarek_platform/features/membership/domain/entities/membership_entities.dart';
import 'package:dr_tarek_platform/features/membership/domain/repositories/membership_repository.dart';
import 'package:dr_tarek_platform/features/membership/presentation/providers/membership_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _StreamingMembershipRepository implements MembershipRepository {
  final StreamController<MembershipSubscription?> subController =
      StreamController<MembershipSubscription?>.broadcast();
  final Map<String, StreamController<List<PlanFeature>>> featureControllers =
      <String, StreamController<List<PlanFeature>>>{};

  MembershipSubscription? latestSub;
  final Map<String, List<PlanFeature>> featuresByPlan =
      <String, List<PlanFeature>>{};

  StreamController<List<PlanFeature>> _controllerFor(String planId) =>
      featureControllers.putIfAbsent(
        planId,
        () => StreamController<List<PlanFeature>>.broadcast(),
      );

  void emitSubscription(MembershipSubscription? sub) {
    latestSub = sub;
    subController.add(sub);
  }

  void emitFeatures(String planId, List<PlanFeature> features) {
    featuresByPlan[planId] = features;
    _controllerFor(planId).add(features);
  }

  @override
  Future<MembershipSubscription?> getSubscription({
    required String studentId,
    required String subjectId,
  }) async => latestSub;

  @override
  Stream<MembershipSubscription?> watchSubscription({
    required String studentId,
    required String subjectId,
  }) => subController.stream;

  @override
  Future<List<PlanFeature>> getPlanFeatures({required String planId}) async =>
      featuresByPlan[planId] ?? const <PlanFeature>[];

  @override
  Stream<List<PlanFeature>> watchPlanFeatures({required String planId}) =>
      _controllerFor(planId).stream;

  @override
  Future<MembershipPlan?> getPlan({required String planId}) async => null;

  @override
  Stream<MembershipPlan?> watchPlan({required String planId}) =>
      Stream.value(null);

  @override
  Future<List<MembershipPlan>> getAvailablePlans({
    required String studentType,
  }) async => const [];

  @override
  Future<MembershipSubscription> activateFreePlan({
    required String studentId,
    required String subjectId,
    required String studentType,
  }) => throw UnimplementedError();

  @override
  Future<MembershipSubscription> upgrade({
    required String studentId,
    required String subjectId,
    required String newPlanId,
  }) => throw UnimplementedError();

  @override
  Future<MembershipSubscription> downgrade({
    required String studentId,
    required String subjectId,
    required String newPlanId,
  }) => throw UnimplementedError();

  @override
  Future<MembershipSubscription> renew({
    required String studentId,
    required String subjectId,
  }) => throw UnimplementedError();

  void dispose() {
    subController.close();
    for (final c in featureControllers.values) {
      c.close();
    }
  }
}

MembershipSubscription _makeSub({required String id, required String planId}) =>
    MembershipSubscription(
      id: id,
      studentId: 'stu-1',
      subjectId: 'sub-1',
      planId: planId,
      durationType: 'semester',
      startDate: DateTime(2026),
      endDate: DateTime(2027),
      status: 'active',
      isFrozen: false,
      frozenAt: null,
      resumedAt: null,
      isGifted: false,
      giftedBy: null,
      renewalCount: 0,
      previousPlanId: null,
    );

void main() {
  group('MembershipRemoteDataSource.selectBestSubscription', () {
    test('ignores deleted/archived docs and ranks pro over free', () {
      final selected = MembershipRemoteDataSource.selectBestSubscription([
        MapEntry('deleted_max', {
          'student_id': 'stu-1',
          'subject_id': 'sub-1',
          'plan_id': 'max',
          'status': 'active',
          'is_deleted': true,
          'start_date': Timestamp.fromDate(DateTime(2026)),
        }),
        MapEntry('free_sub', {
          'student_id': 'stu-1',
          'subject_id': 'sub-1',
          'plan_id': 'free',
          'status': 'active',
          'is_deleted': false,
          'start_date': Timestamp.fromDate(DateTime(2026)),
        }),
        MapEntry('pro_sub', {
          'student_id': 'stu-1',
          'subject_id': 'sub-1',
          'plan_id': 'pro',
          'status': 'active',
          'is_deleted': false,
          'start_date': Timestamp.fromDate(DateTime(2026)),
        }),
      ]);

      expect(selected?.id, 'pro_sub');
      expect(selected?.planId, 'pro');
    });

    test('prefers canonical pro over legacy plan_center_pro', () {
      final selected = MembershipRemoteDataSource.selectBestSubscription([
        MapEntry('stub_sub', {
          'student_id': 'stu-1',
          'subject_id': 'sub-1',
          'plan_id': 'plan_center_pro',
          'status': 'active',
          'is_deleted': false,
          'start_date': Timestamp.fromDate(DateTime(2026)),
        }),
        MapEntry('canonical_sub', {
          'student_id': 'stu-1',
          'subject_id': 'sub-1',
          'plan_id': 'pro',
          'status': 'active',
          'is_deleted': false,
          'start_date': Timestamp.fromDate(DateTime(2026)),
        }),
      ]);

      expect(selected?.id, 'canonical_sub');
      expect(selected?.planId, 'pro');
    });
  });

  group('Real-time membership providers', () {
    test('updates subscription and plan features immediately on stream push', () async {
      final repo = _StreamingMembershipRepository();
      addTearDown(repo.dispose);

      final container = ProviderContainer(
        overrides: [membershipRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      const args = (studentId: 'stu-1', subjectId: 'sub-1');
      final subEvents = <String?>[];
      final containerSub = container.listen(
        activeSubscriptionProvider(args),
        (_, next) {
          if (next.hasValue) subEvents.add(next.value?.planId);
        },
        fireImmediately: true,
      );
      addTearDown(containerSub.close);

      // Listen on pro & free features
      final pdfAccessEvents = <bool>[];
      final pdfListener = container.listen(
        featureAccessProvider((planId: 'pro', featureKey: 'pdf.access')),
        (_, next) {
          if (next.hasValue) pdfAccessEvents.add(next.requireValue);
        },
        fireImmediately: true,
      );
      addTearDown(pdfListener.close);

      repo.emitSubscription(_makeSub(id: 's1', planId: 'free'));
      await Future<void>.delayed(Duration.zero);
      expect(subEvents.last, 'free');

      // Upgrade in Firestore -> stream emits pro immediately without restart.
      repo.emitSubscription(_makeSub(id: 's1', planId: 'pro'));
      repo.emitFeatures('pro', const [
        PlanFeature(
          id: 'pro_pdf_access',
          planId: 'pro',
          featureKey: 'pdf.access',
          enabled: true,
        ),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(subEvents.last, 'pro');
      expect(pdfAccessEvents.last, isTrue);
    });
  });
}
