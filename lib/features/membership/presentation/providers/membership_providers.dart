import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/membership_remote_data_source.dart';
import '../../data/repositories/membership_repository_impl.dart';
import '../../../subject_access/presentation/providers/subject_access_providers.dart';

import '../../domain/entities/membership_entities.dart';
import '../../domain/services/entitlement_resolver.dart';
import '../../domain/repositories/membership_repository.dart';

final membershipRemoteDataSourceProvider = Provider<MembershipRemoteDataSource>(
  (ref) {
    return MembershipRemoteDataSource(
      firestore: FirebaseFirestore.instance,
      functions: FirebaseFunctions.instance,
    );
  },
);

final membershipRepositoryProvider = Provider<MembershipRepository>((ref) {
  return MembershipRepositoryImpl(
    remoteDataSource: ref.watch(membershipRemoteDataSourceProvider),
  );
});

final availablePlansProvider =
    FutureProvider.family<List<MembershipPlan>, String>((ref, studentType) {
      return ref
          .watch(membershipRepositoryProvider)
          .getAvailablePlans(studentType: studentType);
    });

final entitlementResolverProvider = Provider<EntitlementResolver>((ref) {
  return EntitlementResolver(
    subjectAccessRepository: ref.watch(subjectAccessRepositoryProvider),
    membershipRepository: ref.watch(membershipRepositoryProvider),
  );
});

final entitlementDecisionProvider =
    FutureProvider.family<
      EntitlementDecision,
      ({String studentId, String subjectId, String featureKey})
    >((ref, params) {
      return ref
          .watch(entitlementResolverProvider)
          .resolve(
            studentId: params.studentId,
            subjectId: params.subjectId,
            featureKey: params.featureKey,
          );
    });

final activeSubscriptionProvider =
    FutureProvider.family<
      MembershipSubscription?,
      ({String studentId, String subjectId})
    >((ref, params) {
      return ref
          .watch(membershipRepositoryProvider)
          .getSubscription(
            studentId: params.studentId,
            subjectId: params.subjectId,
          );
    });

final activePlanProvider = FutureProvider.family<MembershipPlan?, String>((
  ref,
  planId,
) {
  return ref.watch(membershipRepositoryProvider).getPlan(planId: planId);
});

final planFeaturesProvider = FutureProvider.family<List<PlanFeature>, String>((
  ref,
  planId,
) {
  return ref
      .watch(membershipRepositoryProvider)
      .getPlanFeatures(planId: planId);
});

final featureAccessProvider =
    FutureProvider.family<bool, ({String planId, String featureKey})>((
      ref,
      params,
    ) async {
      final features = await ref
          .watch(membershipRepositoryProvider)
          .getPlanFeatures(planId: params.planId);

      final feature = features.cast<PlanFeature?>().firstWhere(
        (item) => item?.featureKey == params.featureKey,
        orElse: () => null,
      );

      return feature?.enabled == true;
    });
