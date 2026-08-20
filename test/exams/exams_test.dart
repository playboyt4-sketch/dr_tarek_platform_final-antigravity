import 'package:flutter_test/flutter_test.dart';
import 'package:dr_tarek_platform/features/exams/data/models/exam_model.dart';
import 'package:dr_tarek_platform/features/exams/domain/entities/exam.dart';
import 'package:dr_tarek_platform/features/exams/domain/repositories/exams_repository.dart';

class InMemoryExamsRepository implements ExamsRepository {
  final List<Exam> _exams = [];
  final List<ExamAttempt> _attempts = [];

  void addExam(Exam exam) => _exams.add(exam);

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

  @override
  Future<ExamAttempt> submitExamAttempt({
    required String examId,
    required String studentId,
    required String lectureId,
    required Map<String, int> selectedAnswers,
    required List<ExamQuestion> questions,
    required int passingScore,
    required DateTime startedAt,
  }) async {
    int totalScore = 0;
    int totalPossible = 0;

    for (final q in questions) {
      totalPossible += q.points;
      if (selectedAnswers[q.id] == q.correctOptionIndex) {
        totalScore += q.points;
      }
    }

    final attempt = ExamAttempt(
      id: 'exam_att_${_attempts.length + 1}',
      examId: examId,
      studentId: studentId,
      lectureId: lectureId,
      selectedAnswers: selectedAnswers,
      score: totalScore,
      totalPossibleScore: totalPossible,
      passed: totalScore >= passingScore,
      startedAt: startedAt,
      submittedAt: DateTime.now(),
    );
    _attempts.add(attempt);
    return attempt;
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

    test('Exam submission computes score and passing threshold accurately',
        () async {
      final repo = InMemoryExamsRepository();
      const questions = [
        ExamQuestion(
          id: 'eq1',
          questionText: 'Q1',
          options: ['A', 'B'],
          correctOptionIndex: 0,
          points: 5,
        ),
        ExamQuestion(
          id: 'eq2',
          questionText: 'Q2',
          options: ['A', 'B'],
          correctOptionIndex: 1,
          points: 5,
        ),
      ];

      final attemptPass = await repo.submitExamAttempt(
        examId: 'exam_1',
        studentId: 'student_1',
        lectureId: 'lec_101',
        selectedAnswers: {'eq1': 0, 'eq2': 1},
        questions: questions,
        passingScore: 5,
        startedAt: DateTime.now(),
      );

      expect(attemptPass.score, 10);
      expect(attemptPass.passed, isTrue);

      final attemptFail = await repo.submitExamAttempt(
        examId: 'exam_1',
        studentId: 'student_2',
        lectureId: 'lec_101',
        selectedAnswers: {'eq1': 1, 'eq2': 0},
        questions: questions,
        passingScore: 5,
        startedAt: DateTime.now(),
      );

      expect(attemptFail.score, 0);
      expect(attemptFail.passed, isFalse);
    });
  });
}
