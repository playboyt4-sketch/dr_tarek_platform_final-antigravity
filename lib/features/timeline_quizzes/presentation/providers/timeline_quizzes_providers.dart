import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/timeline_quizzes_remote_data_source.dart';
import '../../data/repositories/timeline_quizzes_repository_impl.dart';
import '../../domain/entities/timeline_quiz.dart';
import '../../domain/repositories/timeline_quizzes_repository.dart';

final timelineQuizzesRemoteDataSourceProvider =
    Provider<TimelineQuizzesRemoteDataSource>((ref) {
  return TimelineQuizzesRemoteDataSource();
});

final timelineQuizzesRepositoryProvider =
    Provider<TimelineQuizzesRepository>((ref) {
  final dataSource = ref.watch(timelineQuizzesRemoteDataSourceProvider);
  return TimelineQuizzesRepositoryImpl(remoteDataSource: dataSource);
});

final lectureTimelineQuizzesProvider =
    FutureProvider.family<List<TimelineQuiz>, String>((ref, lectureId) {
  final repo = ref.watch(timelineQuizzesRepositoryProvider);
  return repo.getQuizzesForLecture(lectureId: lectureId);
});
