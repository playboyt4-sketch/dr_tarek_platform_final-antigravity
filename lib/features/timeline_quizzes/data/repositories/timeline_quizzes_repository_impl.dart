import '../../domain/entities/timeline_quiz.dart';
import '../../domain/repositories/timeline_quizzes_repository.dart';
import '../datasources/timeline_quizzes_remote_data_source.dart';

class TimelineQuizzesRepositoryImpl implements TimelineQuizzesRepository {
  final TimelineQuizzesRemoteDataSource remoteDataSource;

  TimelineQuizzesRepositoryImpl({required this.remoteDataSource});

  @override
  Future<List<TimelineQuiz>> getQuizzesForLecture({required String lectureId}) {
    return remoteDataSource.getQuizzesForLecture(lectureId: lectureId);
  }

  @override
  Future<QuizAttempt?> getLatestAttempt({
    required String quizId,
    required String studentId,
  }) {
    return remoteDataSource.getLatestAttempt(
      quizId: quizId,
      studentId: studentId,
    );
  }

  @override
  Future<QuizAttempt> submitAttempt({
    required String quizId,
    required String studentId,
    required String lectureId,
    required Map<String, int> selectedAnswers,
    required List<QuizQuestion> questions,
    required bool skipped,
  }) {
    return remoteDataSource.submitAttempt(
      quizId: quizId,
      studentId: studentId,
      lectureId: lectureId,
      selectedAnswers: selectedAnswers,
      questions: questions,
      skipped: skipped,
    );
  }
}
