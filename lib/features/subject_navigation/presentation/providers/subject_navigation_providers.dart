import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/subject_navigation_remote_data_source.dart';
import '../../data/repositories/subject_navigation_repository_impl.dart';
import '../../domain/entities/subject_learning_entities.dart';
import '../../domain/repositories/subject_navigation_repository.dart';

final subjectNavigationRepositoryProvider =
    Provider<SubjectNavigationRepository>((ref) {
      return SubjectNavigationRepositoryImpl(
        remoteDataSource: SubjectNavigationRemoteDataSource(
          firestore: FirebaseFirestore.instance,
        ),
      );
    });

final subjectSectionsProvider =
    FutureProvider.family<List<LearningSection>, String>(
      (ref, subjectId) =>
          ref.watch(subjectNavigationRepositoryProvider).getSections(subjectId),
    );

final sectionLecturesProvider =
    FutureProvider.family<List<LectureSummary>, String>(
      (ref, sectionId) =>
          ref.watch(subjectNavigationRepositoryProvider).getLectures(sectionId),
    );
