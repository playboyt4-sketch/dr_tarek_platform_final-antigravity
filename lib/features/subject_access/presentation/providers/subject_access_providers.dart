import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/subject_access_remote_data_source.dart';
import '../../data/repositories/subject_access_repository_impl.dart';
import '../../domain/entities/subject_access_assignment.dart';
import '../../domain/repositories/subject_access_repository.dart';
import '../../domain/repositories/subject_access_mutation_repository.dart';

final subjectAccessRemoteDataSourceProvider =
    Provider<SubjectAccessRemoteDataSource>((ref) {
      return SubjectAccessRemoteDataSource(
        firestore: FirebaseFirestore.instance,
        functions: FirebaseFunctions.instance,
      );
    });

final subjectAccessRepositoryProvider = Provider<SubjectAccessRepository>((
  ref,
) {
  final remoteDataSource = ref.watch(subjectAccessRemoteDataSourceProvider);
  return SubjectAccessRepositoryImpl(
    remoteDataSource: remoteDataSource,
    mutationDataSource: remoteDataSource,
  );
});

final subjectAccessMutationRepositoryProvider =
    Provider<SubjectAccessMutationRepository>((ref) {
      final remoteDataSource = ref.watch(subjectAccessRemoteDataSourceProvider);
      return SubjectAccessRepositoryImpl(
        remoteDataSource: remoteDataSource,
        mutationDataSource: remoteDataSource,
      );
    });

final subjectAccessAssignmentProvider =
    FutureProvider.family<
      SubjectAccessAssignment?,
      ({String studentId, String subjectId})
    >((ref, params) {
      return ref
          .watch(subjectAccessRepositoryProvider)
          .getAssignment(
            studentId: params.studentId,
            subjectId: params.subjectId,
          );
    });

final studentSubjectAccessAssignmentsProvider =
    FutureProvider.family<List<SubjectAccessAssignment>, String>((
      ref,
      studentId,
    ) {
      return ref
          .watch(subjectAccessRepositoryProvider)
          .getAssignmentsForStudent(studentId: studentId);
    });

final subjectAccessAssignmentsForSubjectProvider =
    FutureProvider.family<List<SubjectAccessAssignment>, String>((
      ref,
      subjectId,
    ) {
      return ref
          .watch(subjectAccessRepositoryProvider)
          .getAssignmentsForSubject(subjectId: subjectId);
    });
