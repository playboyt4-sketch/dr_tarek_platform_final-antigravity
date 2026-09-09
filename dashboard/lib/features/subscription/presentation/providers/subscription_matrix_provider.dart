import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/firebase_providers.dart';

/// Canonical plan order for the plans nav bar (Figma `Subscription` frame).
/// Plan identities (document IDs); 'free' stays the shared plan_key of the
/// Guest plan and the Center Free plan and must never identify a plan
/// on its own.
const List<String> subscriptionPlanOrder = <String>[
  'guest',
  'free',
  'pro',
  'max',
];

/// English nav labels matching the Figma `plans nav icons` frame.
const Map<String, String> subscriptionPlanLabels = <String, String>{
  'guest': 'Guest',
  'free': 'Center FREE',
  'pro': 'Center PRO',
  'max': 'Center MAX',
};

/// One membership plan row (`plans` collection).
class SubscriptionPlan {
  final String id;
  final String label;

  const SubscriptionPlan({required this.id, required this.label});

  factory SubscriptionPlan.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> data = doc.data();
    final String? title = data['title'] as String?;
    return SubscriptionPlan(
      id: doc.id,
      label: subscriptionPlanLabels[doc.id] ?? title ?? doc.id,
    );
  }

  /// Fallback plans when Firestore is unreachable — same ids, Figma labels.
  static List<SubscriptionPlan> fallback() => <SubscriptionPlan>[
        for (final String id in subscriptionPlanOrder)
          SubscriptionPlan(id: id, label: subscriptionPlanLabels[id]!),
      ];
}

/// One `plan_features` row: toggle state + optional configured value.
///
/// Reads both `value` (seed scripts) and `feature_value` (legacy
/// entitlement readers); writes keep both in sync server-side.
class PlanFeatureState {
  final String key;
  final bool enabled;
  final Object? value;

  const PlanFeatureState({
    required this.key,
    required this.enabled,
    this.value,
  });

  factory PlanFeatureState.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> data = doc.data();
    return PlanFeatureState(
      key: (data['feature_key'] as String?) ?? doc.id,
      enabled: data['enabled'] == true,
      value: data['value'] ?? data['feature_value'],
    );
  }
}

/// Core academic period row for the term strip.
class CorePeriodState {
  final String id;
  final String label;
  final bool isActive;

  const CorePeriodState({
    required this.id,
    required this.label,
    required this.isActive,
  });

  factory CorePeriodState.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> data = doc.data();
    return CorePeriodState(
      id: doc.id,
      label: (data['label'] as String?) ?? doc.id,
      isActive:
          data['status'] == 'active' && data['is_deleted'] != true,
    );
  }
}

/// Plans nav bar source — ordered, canonical plans first.
final subscriptionPlansProvider =
    StreamProvider<List<SubscriptionPlan>>((ref) {
  final FirebaseFirestore firestore = ref.watch(firebaseFirestoreProvider);
  return firestore
      .collection('plans')
      .orderBy('display_order')
      .snapshots()
      .map((QuerySnapshot<Map<String, dynamic>> snap) {
    if (snap.docs.isEmpty) return SubscriptionPlan.fallback();
    final List<SubscriptionPlan> ordered = <SubscriptionPlan>[
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snap.docs)
        SubscriptionPlan.fromDoc(doc),
    ]..sort((a, b) {
        final int ai = subscriptionPlanOrder.indexOf(a.id);
        final int bi = subscriptionPlanOrder.indexOf(b.id);
        return (ai == -1 ? 99 : ai).compareTo(bi == -1 ? 99 : bi);
      });
    return ordered;
  });
});

/// Feature Matrix of one plan, keyed by `feature_key`.
final subscriptionMatrixProvider =
    StreamProvider.family<Map<String, PlanFeatureState>, String>(
        (ref, String planId) {
  final FirebaseFirestore firestore = ref.watch(firebaseFirestoreProvider);
  return firestore
      .collection('plan_features')
      .where('plan_id', isEqualTo: planId)
      .snapshots()
      .map((QuerySnapshot<Map<String, dynamic>> snap) {
    return <String, PlanFeatureState>{
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snap.docs)
        PlanFeatureState.fromDoc(doc).key: PlanFeatureState.fromDoc(doc),
    };
  });
});

/// Core academic periods for the term strip (start/end buttons).
final corePeriodsProvider = StreamProvider<List<CorePeriodState>>((ref) {
  final FirebaseFirestore firestore = ref.watch(firebaseFirestoreProvider);
  return firestore
      .collection('academic_periods')
      .where('is_core', isEqualTo: true)
      .snapshots()
      .map((QuerySnapshot<Map<String, dynamic>> snap) => <CorePeriodState>[
            for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
                in snap.docs)
              CorePeriodState.fromDoc(doc),
          ]);
});

/// Server writes for the Subscription section.
///
/// Every toggle/value edit goes through the audited `setPlanFeature`
/// callable; term start/end goes through the teacher-only
/// `setAcademicPeriodStatus` callable. Client writes to `plan_features`
/// stay denied in `firestore.rules`, so there is no direct-write path.
class SubscriptionActions {
  final FirebaseFunctions _functions;

  const SubscriptionActions(this._functions);

  Future<void> setFeature({
    required String planId,
    required String featureKey,
    required bool enabled,
    Object? value,
    String valueType = 'boolean',
  }) {
    return _functions.httpsCallable('setPlanFeature').call(
      <String, Object?>{
        'planId': planId,
        'featureKey': featureKey,
        'enabled': enabled,
        if (value case final Object v) 'value': v,
        'valueType': valueType,
      },
    );
  }

  Future<void> setTermStatus({
    required String periodId,
    required bool activate,
  }) {
    return _functions
        .httpsCallable('setAcademicPeriodStatus')
        .call(<String, Object?>{
      'periodId': periodId,
      'status': activate ? 'active' : 'ended',
    });
  }
}

final subscriptionActionsProvider =
    Provider<SubscriptionActions>((ref) {
  return SubscriptionActions(ref.watch(firebaseFunctionsProvider));
});
