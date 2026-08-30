import 'package:flutter_test/flutter_test.dart';
import 'package:dr_tarek_platform/features/exams/data/models/exam_model.dart';
import 'package:dr_tarek_platform/features/exams/domain/entities/assessment_submit_result.dart';
import 'package:dr_tarek_platform/features/exams/domain/entities/exam.dart';
import 'package:dr_tarek_platform/features/exams/domain/repositories/exams_repository.dart';

class InMemoryExamsRepository implements ExamsRepository {
  final List<Exam> _exams = [];
  final List<ExamAttempt> _attempts = [];

  void addExam(Exam exam) => _exams.add(exam);

  @override
  Stream<List<Exam>> watchPublishedExams() => throw UnimplementedError();

  @override
  Future<String> startExamAttempt({required String examId, required String studentId}) => throw UnimplementedError();

  @override
  Future<AssessmentSubmitResult> submitExamAnswers({required String attemptId, required Map<String, String> answers}) => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> evaluateAnswer({
    required String attemptId,
    required String questionId,
    required String answer,
  }) => throw UnimplementedError();

  @override
  Future<List<Map<String, dynamic>>> getAssessmentQuestions({
    required String attemptId,
  }) => throw UnimplementedError();

  @override
  Future<Exam?> getExamForLecture({required String lectureId}) async {
    return _exams.where((e) => e.lectureId == lectureId).firstOrNull;
  }

  @override
  Future<List<Exam>> getExamsForSubject({required String subjectId}) async {
    return _exams.where((e) => e.subjectId == subjectId).toList();
  }

  @override
  Future<ExamAttempt?> getLatestAttempt({
    required String examId,
    required String studentId,
  }) async {
    return _attempts
        .where((a) => a.examId == examId && a.studentId == studentId)
        .lastOrNull;
  }
}

void main() {
  group('Exams Feature Tests', () {
    test('ExamModel parses questions and passing score', () {
      final map = {
        'lecture_id': 'lec_101',
        'subject_id': 'sub_202',
        'title': 'End of Lecture Exam',
        'description': 'Test your knowledge on topic 1',
        'duration_minutes': 45,
        'passing_score': 10,
        'status': 'published',
        'questions': [
          {
            'id': 'eq1',
            'question_text': 'Core concept question',
            'options': ['Option 1', 'Option 2'],
            'correct_option_index': 0,
            'points': 10,
          },
          {
            'id': 'eq2',
            'question_text': 'Bonus question',
            'options': ['Option A', 'Option B'],
            'correct_option_index': 1,
            'points': 5,
          }
        ],
      };

      final exam = ExamModel.fromMap('exam_1', map);
      expect(exam.id, 'exam_1');
      expect(exam.durationMinutes, 45);
      expect(exam.isPublished, isTrue);
      expect(exam.questions.length, 2);
      expect(exam.totalScore, 15);
    });

    test('ExamModel defaults missing duration and passing score safely', () {
      final exam = ExamModel.fromMap('exam_2', const {
        'title': 'Quick Exam',
        'status': 'published',
        'questions': [
          {
            'id': 'eq1',
            'question_text': 'Q',
            'options': ['A', 'B'],
          },
        ],
      });

      expect(exam.durationMinutes, 30);
      // passing_score falls back to half of the computed total.
      expect(exam.passingScore, 0);
      expect(exam.totalScore, 1);
    });
  });
}
