import '../../domain/entities/assessment_submit_result.dart';
import '../../domain/entities/timeline_quiz.dart';
import '../../domain/repositories/timeline_quizzes_repository.dart';
import '../datasources/timeline_quizzes_remote_data_source.dart';

class TimelineQuizzesRepositoryImpl implements TimelineQuizzesRepository {
  final TimelineQuizzesRemoteDataSource remoteDataSource;

  TimelineQuizzesRepositoryImpl({required this.remoteDataSource});

  @override
  Stream<List<TimelineQuiz>> watchPublishedQuizzes() => remoteDataSource.watchPublishedQuizzes();

  @override
  Future<String> startQuizAttempt({required String quizId, required String studentId}) {
    return remoteDataSource.startAttempt(assessmentId: quizId, studentId: studentId);
  }

  @override
  Future<AssessmentSubmitResult> submitQuizAnswers({required String attemptId, required Map<String, String> answers}) {
    return remoteDataSource.submitAnswers(attemptId: attemptId, answers: answers);
  }

  @override
  Future<Map<String, dynamic>> evaluateAnswer({
    required String attemptId,
    required String questionId,
    required String answer,
  }) {
    return remoteDataSource.evaluateAnswer(
      attemptId: attemptId,
      questionId: questionId,
      answer: answer,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getAssessmentQuestions({required String attemptId}) {
    return remoteDataSource.getAssessmentQuestions(attemptId: attemptId);
  }

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
}
