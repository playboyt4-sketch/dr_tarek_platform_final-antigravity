import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../domain/entities/membership_entities.dart';

// DIAGNOSIS-ONLY (video playback permission-denied): every Firestore op
// below logs op type + full path/query + exception, then rethrows.
// No behavior change. Remove once the failing rule is identified.
void _diagLogFirestore(
  String op,
  String pathOrQuery,
  Object error, [
  StackTrace? stack,
]) {
  final extra = error is FirebaseException
      ? ' code=${error.code} message=${error.message} plugin=${error.plugin}'
      : '';
  debugPrint(
    '[VIDEO-DIAG] firestore op=$op target=$pathOrQuery '
    'errorType=${error.runtimeType} error=$error$extra',
  );
}

void _diagLogCallable(
  String function,
  String payloadSummary,
  Object error,
) {
  final extra = error is FirebaseFunctionsException
      ? ' code=${error.code} message=${error.message} details=${error.details}'
      : '';
  debugPrint(
    '[VIDEO-DIAG] callable function=$function payload=$payloadSummary '
    'errorType=${error.runtimeType} error=$error$extra',
  );
}

class MembershipRemoteDataSource {
  final FirebaseFirestore firestore;
  final FirebaseFunctions functions;

  const MembershipRemoteDataSource({
    required this.firestore,
    required this.functions,
  });

  Future<MembershipSubscription> activateFreePlan({
    required String studentId,
    required String subjectId,
    required String studentType,
  }) async {
    try {
      await functions.httpsCallable('activateFreePlan').call({
        'studentId': studentId,
        'subjectId': subjectId,
        'studentType': studentType,
      });
    } catch (error) {
      _diagLogCallable('activateFreePlan',
          'studentId=$studentId subjectId=$subjectId', error);
      rethrow;
    }

    final subscription = await getActiveSubscription(
      studentId: studentId,
      subjectId: subjectId,
    );

    if (subscription == null) {
      throw StateError(
        'Free plan activation did not create an active subscription.',
      );
    }

    return subscription;
  }

  Future<MembershipSubscription> downgrade({
    required String studentId,
    required String subjectId,
    required String newPlanId,
  }) async {
    try {
      await functions.httpsCallable('downgrade').call({
        'studentId': studentId,
        'subjectId': subjectId,
        'newPlanId': newPlanId,
      });
    } catch (error) {
      _diagLogCallable('downgrade',
          'studentId=$studentId subjectId=$subjectId newPlanId=$newPlanId',
          error);
      rethrow;
    }

    final subscription = await getActiveSubscription(
      studentId: studentId,
      subjectId: subjectId,
    );

    if (subscription == null) {
      throw StateError('Downgrade did not leave an active subscription.');
    }

    return subscription;
  }

  Future<MembershipSubscription> renew({
    required String studentId,
    required String subjectId,
  }) async {
    try {
      await functions.httpsCallable('renew').call({
        'studentId': studentId,
        'subjectId': subjectId,
      });
    } catch (error) {
      _diagLogCallable(
          'renew', 'studentId=$studentId subjectId=$subjectId', error);
      rethrow;
    }

    final subscription = await getActiveSubscription(
      studentId: studentId,
      subjectId: subjectId,
    );

    if (subscription == null) {
      throw StateError('Renewal did not leave an active subscription.');
    }

    return subscription;
  }

  Future<MembershipSubscription> upgrade({
    required String studentId,
    required String subjectId,
    required String newPlanId,
  }) async {
    try {
      await functions.httpsCallable('upgrade').call({
        'studentId': studentId,
        'subjectId': subjectId,
        'newPlanId': newPlanId,
      });
    } catch (error) {
      _diagLogCallable('upgrade',
          'studentId=$studentId subjectId=$subjectId newPlanId=$newPlanId',
          error);
      rethrow;
    }
    final subscription = await getActiveSubscription(
      studentId: studentId,
      subjectId: subjectId,
    );
    if (subscription == null) {
      throw StateError('Upgrade did not leave an active subscription.');
    }
    return subscription;
  }

  MembershipPlan _mapPlanDoc(String id, Map<String, dynamic> data) {
    return MembershipPlan(
      id: id,
      planName: data['plan_name'] as String? ?? '',
      planKey: data['plan_key'] as String? ?? '',
      studentType: data['student_type'] as String? ?? '',
      displayOrder: (data['display_order'] as num?)?.toInt() ?? 0,
      isActive: data['is_active'] == true,
    );
  }

  Future<MembershipPlan?> getPlan({required String planId}) async {
    try {
      final doc = await firestore.collection('plans').doc(planId).get();
      if (!doc.exists) return null;
      return _mapPlanDoc(doc.id, doc.data()!);
    } catch (error, stack) {
      _diagLogFirestore('get', 'plans/$planId', error, stack);
      rethrow;
    }
  }

  Stream<MembershipPlan?> watchPlan({required String planId}) {
    return firestore.collection('plans').doc(planId).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return _mapPlanDoc(doc.id, doc.data()!);
    });
  }

  Future<List<MembershipPlan>> getPlans({required String studentType}) async {
    const queryDesc =
        "collection=plans where student_type==<type> && is_active==true orderBy display_order";
    try {
      final snapshot = await firestore
          .collection('plans')
          .where('student_type', isEqualTo: studentType)
          .where('is_active', isEqualTo: true)
          .orderBy('display_order')
          .get();

      return snapshot.docs
          .map((doc) => _mapPlanDoc(doc.id, doc.data()))
          .toList();
    } catch (error, stack) {
      _diagLogFirestore('query', queryDesc, error, stack);
      rethrow;
    }
  }

  static int planTierRank(String? planIdOrKey) {
    final normalized = planIdOrKey?.trim().toLowerCase() ?? '';
    if (normalized.isEmpty) return -1;
    if (normalized == 'max' || normalized.endsWith('_max')) return 3;
    if (normalized == 'pro' || normalized.endsWith('_pro')) return 2;
    if (normalized == 'free' || normalized.endsWith('_free')) return 1;
    if (normalized == 'guest' || normalized.endsWith('_guest')) return 0;
    return -1;
  }

  static bool _isCanonicalPlanId(String? planId) {
    final normalized = planId?.trim().toLowerCase() ?? '';
    return normalized == 'guest' ||
        normalized == 'free' ||
        normalized == 'pro' ||
        normalized == 'max';
  }

  static DateTime _epochDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static MembershipSubscription _mapSubscriptionDoc(
    String id,
    Map<String, dynamic> data,
  ) {
    return MembershipSubscription(
      id: id,
      studentId: data['student_id'] as String? ?? '',
      subjectId: data['subject_id'] as String? ?? '',
      planId: data['plan_id'] as String? ?? '',
      durationType: data['duration_type'] as String? ?? '',
      startDate: _epochDate(data['start_date']),
      endDate: (data['end_date'] as Timestamp?)?.toDate(),
      status: data['status'] as String? ?? '',
      isFrozen: data['is_frozen'] == true,
      frozenAt: (data['frozen_at'] as Timestamp?)?.toDate(),
      resumedAt: (data['resumed_at'] as Timestamp?)?.toDate(),
      isGifted: data['is_gifted'] == true,
      giftedBy: data['gifted_by'] as String?,
      renewalCount: (data['renewal_count'] as num?)?.toInt() ?? 0,
      previousPlanId: data['previous_plan_id'] as String?,
      manuallyDisabled: data['manually_disabled'] == true,
      disabledBy: data['disabled_by'] as String?,
      disabledAt: (data['disabled_at'] as Timestamp?)?.toDate(),
      disabledReason: data['disabled_reason'] as String?,
    );
  }

  /// Selects the authoritative active subscription across raw Firestore records,
  /// ignoring soft-deleted/archived entries and preferring non-frozen, higher
  /// plan tier, canonical plan ID, and most recently updated docs.
  static MembershipSubscription? selectBestSubscription(
    Iterable<MapEntry<String, Map<String, dynamic>>> docs,
  ) {
    final candidates = <({
      MembershipSubscription sub,
      int updatedMillis,
    })>[];

    for (final entry in docs) {
      final data = entry.value;
      if (data['is_deleted'] == true || data['is_archived'] == true) {
        continue;
      }
      final status = data['status'] as String? ?? '';
      if (status != 'active' && status != 'trial') {
        continue;
      }
      final updatedAt = _epochDate(
        data['updated_at'] ?? data['created_at'] ?? data['start_date'],
      );
      candidates.add((
        sub: _mapSubscriptionDoc(entry.key, data),
        updatedMillis: updatedAt.millisecondsSinceEpoch,
      ));
    }

    if (candidates.isEmpty) return null;

    candidates.sort((a, b) {
      final usableA =
          !a.sub.isFrozen && !a.sub.manuallyDisabled ? 1 : 0;
      final usableB =
          !b.sub.isFrozen && !b.sub.manuallyDisabled ? 1 : 0;
      if (usableB != usableA) return usableB - usableA;

      final tierDiff =
          planTierRank(b.sub.planId) - planTierRank(a.sub.planId);
      if (tierDiff != 0) return tierDiff;

      final canonicalA = _isCanonicalPlanId(a.sub.planId) ? 1 : 0;
      final canonicalB = _isCanonicalPlanId(b.sub.planId) ? 1 : 0;
      if (canonicalB != canonicalA) return canonicalB - canonicalA;

      final timeDiff = b.updatedMillis.compareTo(a.updatedMillis);
      if (timeDiff != 0) return timeDiff;

      return a.sub.id.compareTo(b.sub.id);
    });

    return candidates.first.sub;
  }

  Future<MembershipSubscription?> getActiveSubscription({
    required String studentId,
    required String subjectId,
  }) async {
    final queryDesc =
        'collection=subscriptions where student_id==$studentId && subject_id==$subjectId && status==active';
    try {
      final snapshot = await firestore
          .collection('subscriptions')
          .where('student_id', isEqualTo: studentId)
          .where('subject_id', isEqualTo: subjectId)
          .where('status', isEqualTo: 'active')
          .get();

      return selectBestSubscription(
        snapshot.docs.map((doc) => MapEntry(doc.id, doc.data())),
      );
    } catch (error, stack) {
      _diagLogFirestore('query', queryDesc, error, stack);
      rethrow;
    }
  }

  Stream<MembershipSubscription?> watchActiveSubscription({
    required String studentId,
    required String subjectId,
  }) {
    return firestore
        .collection('subscriptions')
        .where('student_id', isEqualTo: studentId)
        .where('subject_id', isEqualTo: subjectId)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map(
          (snapshot) => selectBestSubscription(
            snapshot.docs.map((doc) => MapEntry(doc.id, doc.data())),
          ),
        );
  }

  static List<PlanFeature> _mapPlanFeatures(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs.map((doc) {
      final data = doc.data();
      return PlanFeature(
        id: doc.id,
        planId: data['plan_id'] as String? ?? '',
        featureKey: data['feature_key'] as String? ?? '',
        enabled: data['enabled'] == true,
        featureValue: data['feature_value'],
      );
    }).toList();
  }

  /// Students may only read ENABLED plan features (firestore.rules mirrors
  /// this: disabled rows are not listable). Filtering here is semantically
  /// identical — every consumer treats a missing feature as disabled
  /// (`feature?.enabled == true`) — and prevents the whole query from being
  /// rejected with permission-denied when a plan contains disabled rows.
  Future<List<PlanFeature>> getPlanFeatures({required String planId}) async {
    final queryDesc =
        'collection=plan_features where plan_id==$planId && enabled==true';
    try {
      final snapshot = await firestore
          .collection('plan_features')
          .where('plan_id', isEqualTo: planId)
          .where('enabled', isEqualTo: true)
          .get();

      return _mapPlanFeatures(snapshot.docs);
    } catch (error, stack) {
      _diagLogFirestore('query', queryDesc, error, stack);
      rethrow;
    }
  }

  Stream<List<PlanFeature>> watchPlanFeatures({required String planId}) {
    return firestore
        .collection('plan_features')
        .where('plan_id', isEqualTo: planId)
        .where('enabled', isEqualTo: true)
        .snapshots()
        .map((snapshot) => _mapPlanFeatures(snapshot.docs));
  }
}
