import 'package:flutter_test/flutter_test.dart';
import 'package:dr_tarek_platform/features/timeline_quizzes/data/models/timeline_quiz_model.dart';
import 'package:dr_tarek_platform/features/timeline_quizzes/domain/entities/assessment_submit_result.dart';
import 'package:dr_tarek_platform/features/timeline_quizzes/domain/entities/timeline_quiz.dart';
import 'package:dr_tarek_platform/features/timeline_quizzes/domain/repositories/timeline_quizzes_repository.dart';

class InMemoryTimelineQuizzesRepository implements TimelineQuizzesRepository {
  final List<TimelineQuiz> _quizzes = [];

  void addQuiz(TimelineQuiz quiz) => _quizzes.add(quiz);

  @override
  Future<QuizAttempt?> getLatestAttempt({
    required String quizId,
    required String studentId,
  }) async {
    // Attempts are server-managed; the in-memory fake keeps none.
    return null;
  }

  @override
  Stream<List<TimelineQuiz>> watchPublishedQuizzes() => throw UnimplementedError();

  @override
  Future<String> startQuizAttempt({required String quizId, required String studentId}) => throw UnimplementedError();

  @override
  Future<AssessmentSubmitResult> submitQuizAnswers({required String attemptId, required Map<String, String> answers}) => throw UnimplementedError();

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
  Future<List<TimelineQuiz>> getQuizzesForLecture({required String lectureId}) async {
    return _quizzes.where((q) => q.lectureId == lectureId).toList();
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

    test('getQuizzesForLecture returns only matching published quizzes',
        () async {
      final repo = InMemoryTimelineQuizzesRepository()
        ..addQuiz(TimelineQuizModel.fromMap('quiz_1', const {
          'lecture_id': 'lec_101',
          'title': 'Checkpoint A',
          'trigger_timestamp_seconds': 10,
          'questions': [],
        }))
        ..addQuiz(TimelineQuizModel.fromMap('quiz_2', const {
          'lecture_id': 'lec_202',
          'title': 'Checkpoint B',
          'trigger_timestamp_seconds': 20,
          'questions': [],
        }));

      final result = await repo.getQuizzesForLecture(lectureId: 'lec_101');
      expect(result.length, 1);
      expect(result.single.id, 'quiz_1');
    });
  });
}
