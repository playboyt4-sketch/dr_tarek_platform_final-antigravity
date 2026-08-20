import '../entities/exam.dart';

abstract class ExamsRepository {
  Future<Exam?> getExamForLecture({
    required String lectureId,
  });

  Future<List<Exam>> getExamsForSubject({
    required String subjectId,
  });

  Future<ExamAttempt?> getLatestAttempt({
    required String examId,
    required String studentId,
  });

  Future<ExamAttempt> submitExamAttempt({
    required String examId,
    required String studentId,
    required String lectureId,
    required Map<String, int> selectedAnswers,
    required List<ExamQuestion> questions,
    required int passingScore,
    required DateTime startedAt,
  });
}
