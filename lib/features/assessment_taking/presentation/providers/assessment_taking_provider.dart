import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/assessment_question.dart';
import 'assessment_taking_state.dart';
import '../../../timeline_quizzes/presentation/providers/timeline_quizzes_providers.dart';
import '../../../exams/presentation/providers/exams_providers.dart';

class AssessmentTakingParams {
  final String attemptId;
  final String assessmentId;
  final String type; // 'quiz' or 'exam'

  AssessmentTakingParams({
    required this.attemptId,
    required this.assessmentId,
    required this.type,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AssessmentTakingParams &&
          runtimeType == other.runtimeType &&
          attemptId == other.attemptId &&
          assessmentId == other.assessmentId &&
          type == other.type;

  @override
  int get hashCode => attemptId.hashCode ^ assessmentId.hashCode ^ type.hashCode;
}

final assessmentTakingControllerProvider = NotifierProvider.family<AssessmentTakingController, AssessmentTakingState, AssessmentTakingParams>(
  AssessmentTakingController.new,
);

class AssessmentTakingController extends Notifier<AssessmentTakingState> {
  final AssessmentTakingParams params;

  AssessmentTakingController(this.params);

  @override
  AssessmentTakingState build() {
    Future.microtask(initialize);
    return const AssessmentTakingState();
  }

  Future<void> initialize() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final List<Map<String, dynamic>> rawQuestions;
      if (params.type == 'quiz') {
        final repo = ref.read(timelineQuizzesRepositoryProvider);
        rawQuestions = await repo.getAssessmentQuestions(attemptId: params.attemptId);
      } else {
        final repo = ref.read(examsRepositoryProvider);
        rawQuestions = await repo.getAssessmentQuestions(attemptId: params.attemptId);
      }

      final questions = rawQuestions.map((q) => AssessmentQuestion.fromMap(q)).toList();
      state = state.copyWith(
        isLoading: false,
        questions: questions,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// O6-B: records the selected answer locally only. There is intentionally
  /// no per-question server evaluation — correctness is computed solely by
  /// the backend at final submission ([finalizeAttempt]). The returned future
  /// exists to preserve the established async call convention at call sites.
  Future<void> submitAnswer(String answer) async {
    if (state.isSubmitting || state.isFinished) return;

    final currentQ = state.currentQuestion;
    if (currentQ == null) return;

    if (state.selectedAnswers.containsKey(currentQ.id)) return; // Already answered

    final newAnswers = Map<String, String>.from(state.selectedAnswers)..[currentQ.id] = answer;
    state = state.copyWith(selectedAnswers: newAnswers);
  }

  void nextQuestion() {
    if (state.isLastQuestion) return;
    state = state.copyWith(
      currentIndex: state.currentIndex + 1,
      errorMessage: null,
    );
  }

  /// O6-B: final submission. The authoritative score is computed
  /// server-side by `submitAssessmentAttempt`; the client only displays the
  /// returned typed result and never calculates or trusts its own score.
  /// The backend rejects repeated submissions (started-status gate), so a
  /// second finalize cannot alter the persisted grade.
  Future<void> finalizeAttempt() async {
    if (state.isSubmitting || state.isFinished) return;

    state = state.copyWith(isSubmitting: true, errorMessage: null);
    try {
      // Strongly typed per branch (quiz/exam result classes are distinct
      // types with an identical shape) — never `dynamic` property access.
      int? score;
      int? totalMarks;
      bool? needsManualGrading;
      if (params.type == 'quiz') {
        final repo = ref.read(timelineQuizzesRepositoryProvider);
        final result = await repo.submitQuizAnswers(
          attemptId: params.attemptId,
          answers: state.selectedAnswers,
        );
        score = result.score;
        totalMarks = result.totalMarks;
        needsManualGrading = result.needsManualGrading;
      } else {
        final repo = ref.read(examsRepositoryProvider);
        final result = await repo.submitExamAnswers(
          attemptId: params.attemptId,
          answers: state.selectedAnswers,
        );
        score = result.score;
        totalMarks = result.totalMarks;
        needsManualGrading = result.needsManualGrading;
      }

      state = state.copyWith(
        isSubmitting: false,
        isFinished: true,
        finalScore: score,
        totalMarks: totalMarks,
        needsManualGrading: needsManualGrading,
      );
    } catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: 'Failed to finalize attempt: $e',
      );
    }
  }
}
