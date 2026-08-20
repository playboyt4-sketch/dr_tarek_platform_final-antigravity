import 'package:flutter_test/flutter_test.dart';
import 'package:dr_tarek_platform/features/timeline_quizzes/data/models/timeline_quiz_model.dart';
import 'package:dr_tarek_platform/features/timeline_quizzes/domain/entities/timeline_quiz.dart';
import 'package:dr_tarek_platform/features/timeline_quizzes/domain/repositories/timeline_quizzes_repository.dart';

class InMemoryTimelineQuizzesRepository implements TimelineQuizzesRepository {
  final List<TimelineQuiz> _quizzes = [];
  final List<QuizAttempt> _attempts = [];

  void addQuiz(TimelineQuiz quiz) => _quizzes.add(quiz);

  @override
  Future<QuizAttempt?> getLatestAttempt({
    required String quizId,
    required String studentId,
  }) async {
    return _attempts
        .where((a) => a.quizId == quizId && a.studentId == studentId)
        .lastOrNull;
  }

  @override
  Future<List<TimelineQuiz>> getQuizzesForLecture({required String lectureId}) async {
    return _quizzes.where((q) => q.lectureId == lectureId).toList();
  }

  @override
  Future<QuizAttempt> submitAttempt({
    required String quizId,
    required String studentId,
    required String lectureId,
    required Map<String, int> selectedAnswers,
    required List<QuizQuestion> questions,
    required bool skipped,
  }) async {
    int score = 0;
    if (!skipped) {
      for (final q in questions) {
        if (selectedAnswers[q.id] == q.correctOptionIndex) {
          score++;
        }
      }
    }

    final attempt = QuizAttempt(
      id: 'att_${_attempts.length + 1}',
      quizId: quizId,
      studentId: studentId,
      lectureId: lectureId,
      selectedAnswers: selectedAnswers,
      score: score,
      totalQuestions: questions.length,
      skipped: skipped,
      submittedAt: DateTime.now(),
      createdAt: DateTime.now(),
    );
    _attempts.add(attempt);
    return attempt;
  }
}

void main() {
  group('Timeline Quizzes Feature Tests', () {
    test('TimelineQuizModel parses questions and triggers', () {
      final map = {
        'lecture_id': 'lec_101',
        'subject_id': 'sub_202',
        'title': 'Mid-lecture Checkpoint',
        'trigger_timestamp_seconds': 600,
        'is_post_lecture': false,
        'questions': [
          {
            'id': 'q1',
            'question_text': 'What is 2 + 2?',
            'options': ['3', '4', '5'],
            'correct_option_index': 1,
            'explanation': 'Basic arithmetic',
          }
        ],
      };

      final quiz = TimelineQuizModel.fromMap('quiz_1', map);
      expect(quiz.id, 'quiz_1');
      expect(quiz.triggerTimestampSeconds, 600);
      expect(quiz.isPostLecture, isFalse);
      expect(quiz.questions.length, 1);
      expect(quiz.questions.first.correctOptionIndex, 1);
    });

    test('Quiz optional skip allows student to continue without blocking',
        () async {
      final repo = InMemoryTimelineQuizzesRepository();
      const questions = [
        QuizQuestion(
          id: 'q1',
          questionText: 'Question 1',
          options: ['A', 'B'],
          correctOptionIndex: 0,
        ),
      ];

      final skippedAttempt = await repo.submitAttempt(
        quizId: 'quiz_1',
        studentId: 'student_1',
        lectureId: 'lec_101',
        selectedAnswers: {},
        questions: questions,
        skipped: true,
      );

      expect(skippedAttempt.skipped, isTrue);
      expect(skippedAttempt.score, 0);

      final answeredAttempt = await repo.submitAttempt(
        quizId: 'quiz_1',
        studentId: 'student_1',
        lectureId: 'lec_101',
        selectedAnswers: {'q1': 0},
        questions: questions,
        skipped: false,
      );

      expect(answeredAttempt.skipped, isFalse);
      expect(answeredAttempt.score, 1);
    });
  });
}
