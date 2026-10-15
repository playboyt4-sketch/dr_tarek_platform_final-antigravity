import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dr_tarek_platform/features/student_dashboard/data/datasources/dashboard_remote_data_source.dart';
import 'package:dr_tarek_platform/features/student_dashboard/domain/entities/dashboard_subject.dart';

final DateTime _now = DateTime.utc(2026, 9, 25);

Map<String, dynamic> _doc({
  String status = 'active',
  String planId = 'plan-free',
  bool deleted = false,
  bool frozen = false,
  bool disabled = false,
  Timestamp? endDate,
}) {
  final doc = <String, dynamic>{
    'status': status,
    'plan_id': planId,
    'is_deleted': deleted,
    'is_frozen': frozen,
    'manually_disabled': disabled,
  };
  final end = endDate;
  if (end != null) doc['end_date'] = end;
  return doc;
}

void main() {
  group('bestSubscriptionVerdict ranking', () {
    test('active beats a stale free record (no first-doc-wins shadowing)', () {
      final verdict = bestSubscriptionVerdict(
        [
          _doc(status: 'expired', planId: 'plan-old-free'),
          _doc(status: 'active', planId: 'plan-pro'),
        ],
        nowUtc: _now,
      );
      expect(verdict.state, DashboardSubscriptionState.active);
      expect(verdict.planId, 'plan-pro');
    });

    test('deleted docs are ignored; empty input yields missing', () {
      final verdict = bestSubscriptionVerdict(
        [_doc(status: 'active', deleted: true)],
        nowUtc: _now,
      );
      expect(verdict.state, DashboardSubscriptionState.missing);
      expect(verdict.planId, isNull);

      final empty = bestSubscriptionVerdict(
        const <Map<String, dynamic>>[],
        nowUtc: _now,
      );
      expect(empty.state, DashboardSubscriptionState.missing);
    });

    test('rank order: active > trial > frozen > expired > disabled > inactive',
        () {
      final past = Timestamp.fromDate(_now.subtract(const Duration(days: 1)));
      // Expired outranks disciplinary-disabled and inactive …
      expect(
        bestSubscriptionVerdict(
          [
            _doc(status: 'active', endDate: past, planId: 'plan-old'),
            _doc(disabled: true),
            _doc(status: 'past'),
          ],
          nowUtc: _now,
        ).state,
        DashboardSubscriptionState.expired,
      );
      // … but frozen still outranks expired, and trial outranks frozen.
      expect(
        bestSubscriptionVerdict(
          [
            _doc(status: 'active', endDate: past, planId: 'plan-old'),
            _doc(frozen: true),
          ],
          nowUtc: _now,
        ).state,
        DashboardSubscriptionState.frozen,
      );
      expect(
        bestSubscriptionVerdict(
          [_doc(frozen: true), _doc(disabled: true), _doc(status: 'past')],
          nowUtc: _now,
        ).state,
        DashboardSubscriptionState.frozen,
      );
      expect(
        bestSubscriptionVerdict(
          [_doc(status: 'trial', planId: 'plan-trial'), _doc(frozen: true)],
          nowUtc: _now,
        ).state,
        DashboardSubscriptionState.trial,
      );
    });

    test('past end_date expires even an active status', () {
      final verdict = bestSubscriptionVerdict(
        [
          _doc(
            status: 'active',
            endDate: Timestamp.fromDate(
              _now.subtract(const Duration(days: 1)),
            ),
          ),
        ],
        nowUtc: _now,
      );
      expect(verdict.state, DashboardSubscriptionState.expired);
    });
  });

  group('resolveEntitlement matrix', () {
    test('ready only with active/trial + active plan + enabled features', () {
      for (final state in [
        DashboardSubscriptionState.active,
        DashboardSubscriptionState.trial,
      ]) {
        final verdict = resolveEntitlement(
          subscriptionState: state,
          planId: 'plan-pro',
          planKey: 'center_pro',
          planActive: true,
          hasEnabledFeatures: true,
        );
        expect(verdict.state, DashboardEntitlementState.ready);
        expect(verdict.planKey, 'center_pro');
      }
    });

    test('non-active subscriptions block without a plan key', () {
      for (final state in [
        DashboardSubscriptionState.missing,
        DashboardSubscriptionState.inactive,
        DashboardSubscriptionState.frozen,
        DashboardSubscriptionState.expired,
        DashboardSubscriptionState.disciplinaryDisabled,
      ]) {
        final verdict = resolveEntitlement(
          subscriptionState: state,
          planId: 'plan-pro',
          planKey: 'center_pro',
          planActive: true,
          hasEnabledFeatures: true,
        );
        expect(verdict.state, DashboardEntitlementState.blocked);
        expect(verdict.reason, 'subscription_unavailable');
        expect(verdict.planKey, isNull);
      }
    });

    test('missing plan id or inactive plan blocks as active_plan_missing',
        () {
      final noPlan = resolveEntitlement(
        subscriptionState: DashboardSubscriptionState.active,
        planId: null,
        planKey: null,
        planActive: false,
        hasEnabledFeatures: false,
      );
      expect(noPlan.reason, 'active_plan_missing');

      final inactivePlan = resolveEntitlement(
        subscriptionState: DashboardSubscriptionState.active,
        planId: 'plan-old',
        planKey: 'center_pro',
        planActive: false,
        hasEnabledFeatures: true,
      );
      expect(inactivePlan.reason, 'active_plan_missing');
      expect(inactivePlan.planKey, isNull);
    });

    test('disabled features block but keep the plan key surfaced', () {
      final verdict = resolveEntitlement(
        subscriptionState: DashboardSubscriptionState.active,
        planId: 'plan-pro',
        planKey: 'center_pro',
        planActive: true,
        hasEnabledFeatures: false,
      );
      expect(verdict.state, DashboardEntitlementState.blocked);
      expect(verdict.reason, 'plan_features_disabled');
      expect(verdict.planKey, 'center_pro');
    });
  });
}
