import '../entities/assessment_submit_result.dart';
import '../entities/timeline_quiz.dart';

abstract class TimelineQuizzesRepository {
  Stream<List<TimelineQuiz>> watchPublishedQuizzes();

  Future<String> startQuizAttempt({required String quizId, required String studentId});

  Future<AssessmentSubmitResult> submitQuizAnswers({
    required String attemptId,
    required Map<String, String> answers,
  });

  /// Evaluates a single answer statelessly on the server for immediate feedback.
  Future<Map<String, dynamic>> evaluateAnswer({
    required String attemptId,
    required String questionId,
    required String answer,
  });

  /// Securely fetches questions for an attempt without correct answers or explanations.
  Future<List<Map<String, dynamic>>> getAssessmentQuestions({
    required String attemptId,
  });

  Future<List<TimelineQuiz>> getQuizzesForLecture({
    required String lectureId,
  });

  Future<QuizAttempt?> getLatestAttempt({
    required String quizId,
    required String studentId,
  });
}
