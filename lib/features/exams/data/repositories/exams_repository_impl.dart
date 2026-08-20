import '../../domain/entities/exam.dart';
import '../../domain/repositories/exams_repository.dart';
import '../datasources/exams_remote_data_source.dart';

class ExamsRepositoryImpl implements ExamsRepository {
  final ExamsRemoteDataSource remoteDataSource;

  ExamsRepositoryImpl({required this.remoteDataSource});

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

  @override
  Future<ExamAttempt> submitExamAttempt({
    required String examId,
    required String studentId,
    required String lectureId,
    required Map<String, int> selectedAnswers,
    required List<ExamQuestion> questions,
    required int passingScore,
    required DateTime startedAt,
  }) {
    return remoteDataSource.submitExamAttempt(
      examId: examId,
      studentId: studentId,
      lectureId: lectureId,
      selectedAnswers: selectedAnswers,
      questions: questions,
      passingScore: passingScore,
      startedAt: startedAt,
    );
  }
}
