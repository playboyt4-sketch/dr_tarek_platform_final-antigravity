import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/firebase_providers.dart';
import '../../data/repositories/lecture_access_repository_impl.dart';
import '../../domain/entities/lecture_access.dart';
import '../../domain/repositories/lecture_access_repository.dart';
import '../../domain/use_cases/lecture_access_use_cases.dart';

/// Riverpod dependency injection for per-lecture student access.
/// Widgets watch state and dispatch to use cases — never Firestore.

final lectureAccessRepositoryProvider =
    Provider<LectureAccessRepository>((ref) {
  return LectureAccessRepositoryImpl(ref.watch(firebaseFirestoreProvider));
});

final getSubjectLectureRosterUseCaseProvider =
    Provider<GetSubjectLectureRoster>((ref) {
  return GetSubjectLectureRoster(ref.watch(lectureAccessRepositoryProvider));
});

final getLectureAccessGrantsUseCaseProvider =
    Provider<GetLectureAccessGrants>((ref) {
  return GetLectureAccessGrants(ref.watch(lectureAccessRepositoryProvider));
});

final saveLectureAccessOverridesUseCaseProvider =
    Provider<SaveLectureAccessOverrides>((ref) {
  return SaveLectureAccessOverrides(
      ref.watch(lectureAccessRepositoryProvider));
});

/// Students enrolled in [subjectId] (one-shot load when the overlay
/// opens). Section never affects eligibility.
final subjectLectureRosterProvider =
    FutureProvider.family<List<LectureAccessStudent>, String>(
        (ref, subjectId) {
  return ref.watch(getSubjectLectureRosterUseCaseProvider).execute(subjectId);
});

/// Stored per-lecture overrides for [lectureId] (one-shot load when the
/// overlay opens). Missing grant = no override.
final lectureAccessGrantsProvider =
    FutureProvider.family<List<LectureAccessGrant>, String>(
        (ref, lectureId) {
  return ref
      .watch(getLectureAccessGrantsUseCaseProvider)
      .execute(lectureId);
});
