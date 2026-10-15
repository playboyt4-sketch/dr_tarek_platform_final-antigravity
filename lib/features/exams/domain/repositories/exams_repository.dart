import '../entities/assessment_submit_result.dart';
import '../entities/exam.dart';

abstract class ExamsRepository {
  Stream<List<Exam>> watchPublishedExams();

  Future<String> startExamAttempt({required String examId, required String studentId});

  Future<AssessmentSubmitResult> submitExamAnswers({required String attemptId, required Map<String, String> answers});

  /// Securely fetches questions for an attempt without correct answers or explanations.
  Future<List<Map<String, dynamic>>> getAssessmentQuestions({
    required String attemptId,
  });

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
}
