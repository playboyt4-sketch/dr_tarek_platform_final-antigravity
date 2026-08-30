import '../../domain/entities/assessment_submit_result.dart';
import '../../domain/entities/exam.dart';
import '../../domain/repositories/exams_repository.dart';
import '../datasources/exams_remote_data_source.dart';

class ExamsRepositoryImpl implements ExamsRepository {
  final ExamsRemoteDataSource remoteDataSource;

  ExamsRepositoryImpl({required this.remoteDataSource});

  @override
  Stream<List<Exam>> watchPublishedExams() => remoteDataSource.watchPublishedExams();

  @override
  Future<String> startExamAttempt({required String examId, required String studentId}) {
    return remoteDataSource.startAttempt(assessmentId: examId, studentId: studentId);
  }

  @override
  Future<AssessmentSubmitResult> submitExamAnswers({required String attemptId, required Map<String, String> answers}) {
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
  Future<Exam?> getExamForLecture({required String lectureId}) {
    return remoteDataSource.getExamForLecture(lectureId: lectureId);
  }

  @override
  Future<List<Exam>> getExamsForSubject({required String subjectId}) {
    return remoteDataSource.getExamsForSubject(subjectId: subjectId);
  }

  @override
  Future<ExamAttempt?> getLatestAttempt({
    required String examId,
    required String studentId,
  }) {
    return remoteDataSource.getLatestAttempt(
      examId: examId,
      studentId: studentId,
    );
  }
}
