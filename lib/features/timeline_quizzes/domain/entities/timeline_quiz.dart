class QuizQuestion {
  final String id;
  final String questionText;
  final List<String> options;
  final int correctOptionIndex;
  final String? explanation;

  const QuizQuestion({
    required this.id,
    required this.questionText,
    required this.options,
    required this.correctOptionIndex,
    this.explanation,
  });
}

class TimelineQuiz {
  final String id;
  final String lectureId;
  final String subjectId;
  final String title;
  final int triggerTimestampSeconds;
  final bool isPostLecture;
  final List<QuizQuestion> questions;
  final DateTime createdAt;

  const TimelineQuiz({
    required this.id,
    required this.lectureId,
    required this.subjectId,
    required this.title,
    required this.triggerTimestampSeconds,
    this.isPostLecture = false,
    required this.questions,
    required this.createdAt,
  });
}

class QuizAttempt {
  final String id;
  final String quizId;
  final String studentId;
  final String lectureId;
  final Map<String, int> selectedAnswers; // questionId -> selectedOptionIndex
  final int score;
  final int totalQuestions;
  final bool skipped;
  final DateTime? submittedAt;
  final DateTime createdAt;

  const QuizAttempt({
    required this.id,
    required this.quizId,
    required this.studentId,
    required this.lectureId,
    required this.selectedAnswers,
    required this.score,
    required this.totalQuestions,
    required this.skipped,
    this.submittedAt,
    required this.createdAt,
  });
}
