import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/exams_remote_data_source.dart';
import '../../data/repositories/exams_repository_impl.dart';
import '../../domain/entities/exam.dart';
import '../../domain/repositories/exams_repository.dart';

final examsRemoteDataSourceProvider = Provider<ExamsRemoteDataSource>((ref) {
  return ExamsRemoteDataSource();
});

final examsRepositoryProvider = Provider<ExamsRepository>((ref) {
  final dataSource = ref.watch(examsRemoteDataSourceProvider);
  return ExamsRepositoryImpl(remoteDataSource: dataSource);
});

final lectureExamProvider =
    FutureProvider.family<Exam?, String>((ref, lectureId) {
  final repo = ref.watch(examsRepositoryProvider);
  return repo.getExamForLecture(lectureId: lectureId);
});

final publishedExamsStreamProvider = StreamProvider.autoDispose<List<Exam>>(
  (ref) => ref.watch(examsRepositoryProvider).watchPublishedExams(),
);