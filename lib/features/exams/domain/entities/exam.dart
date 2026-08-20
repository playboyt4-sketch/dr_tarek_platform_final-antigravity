class ExamQuestion {
  final String id;
  final String questionText;
  final List<String> options;
  final int correctOptionIndex;
  final int points;
  final String? explanation;

  const ExamQuestion({
    required this.id,
    required this.questionText,
    required this.options,
    required this.correctOptionIndex,
    this.points = 1,
    this.explanation,
  });
}

class Exam {
  final String id;
  final String lectureId;
  final String subjectId;
  final String title;
  final String description;
  final int durationMinutes;
  final int passingScore;
  final int totalScore;
  final List<ExamQuestion> questions;
  final bool isPublished;
  final DateTime createdAt;

  const Exam({
    required this.id,
    required this.lectureId,
    required this.subjectId,
    required this.title,
    required this.description,
    required this.durationMinutes,
    required this.passingScore,
    required this.totalScore,
    required this.questions,
    required this.isPublished,
    required this.createdAt,
  });
}

class ExamAttempt {
  final String id;
  final String examId;
  final String studentId;
  final String lectureId;
  final Map<String, int> selectedAnswers;
  final int score;
  final int totalPossibleScore;
  final bool passed;
  final DateTime startedAt;
  final DateTime? submittedAt;

  const ExamAttempt({
    required this.id,
    required this.examId,
    required this.studentId,
    required this.lectureId,
    required this.selectedAnswers,
    required this.score,
    required this.totalPossibleScore,
    required this.passed,
    required this.startedAt,
    this.submittedAt,
  });
}
