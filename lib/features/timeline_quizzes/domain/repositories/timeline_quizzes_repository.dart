import '../entities/timeline_quiz.dart';

abstract class TimelineQuizzesRepository {
  Future<List<TimelineQuiz>> getQuizzesForLecture({
    required String lectureId,
  });

  Future<QuizAttempt?> getLatestAttempt({
    required String quizId,
    required String studentId,
  });

  Future<QuizAttempt> submitAttempt({
    required String quizId,
    required String studentId,
    required String lectureId,
    required Map<String, int> selectedAnswers,
    required List<QuizQuestion> questions,
    required bool skipped,
  });
}
