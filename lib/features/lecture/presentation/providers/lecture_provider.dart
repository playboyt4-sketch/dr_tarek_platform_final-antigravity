import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/lecture_remote_data_source.dart';
import '../../data/repositories/lecture_repository_impl.dart';
import '../../domain/entities/lecture.dart';
import '../../domain/entities/lecture_resource.dart';
import '../../domain/repositories/lecture_repository.dart';

final lectureRepositoryProvider = Provider<LectureRepository>(
  (ref) => LectureRepositoryImpl(
    remoteDataSource: LectureRemoteDataSource(),
  ),
);

final lecturesForSectionProvider = FutureProvider.family
    .autoDispose<List<Lecture>, String>((ref, sectionId) {
  return ref
      .read(lectureRepositoryProvider)
      .getLecturesForSection(sectionId);
});

final lectureResourcesProvider = FutureProvider.family
    .autoDispose<List<LectureResource>, String>((ref, lectureId) {
  return ref
      .read(lectureRepositoryProvider)
      .getResourcesForLecture(lectureId);
});
