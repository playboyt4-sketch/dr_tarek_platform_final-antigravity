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

  Future<void> submitAnswer(String answer) async {
    if (state.isSubmitting || state.isFinished) return;
    
    final currentQ = state.currentQuestion;
    if (currentQ == null) return;
    
    if (state.selectedAnswers.containsKey(currentQ.id)) return; // Already answered

    state = state.copyWith(isSubmitting: true, errorMessage: null);
    try {
      dynamic result;
      if (params.type == 'quiz') {
        final repo = ref.read(timelineQuizzesRepositoryProvider);
        result = await repo.evaluateAnswer(
          attemptId: params.attemptId,
          questionId: currentQ.id,
          answer: answer,
        );
      } else {
        final repo = ref.read(examsRepositoryProvider);
        result = await repo.evaluateAnswer(
          attemptId: params.attemptId,
          questionId: currentQ.id,
          answer: answer,
        );
      }

      final isCorrect = result.correct;
      final explanation = result.explanation;

      final newAnswers = Map<String, String>.from(state.selectedAnswers)..[currentQ.id] = answer;
      final newStatuses = Map<String, bool>.from(state.correctStatuses)..[currentQ.id] = isCorrect;
      final newExplanations = Map<String, String>.from(state.explanations);
      if (explanation != null) {
        newExplanations[currentQ.id] = explanation;
      }

      state = state.copyWith(
        isSubmitting: false,
        selectedAnswers: newAnswers,
        correctStatuses: newStatuses,
        explanations: newExplanations,
      );
    } catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: 'Failed to submit answer: $e',
      );
    }
  }

  void nextQuestion() {
    if (state.isLastQuestion) return;
    state = state.copyWith(
      currentIndex: state.currentIndex + 1,
      errorMessage: null,
    );
  }

  Future<void> finalizeAttempt() async {
    if (state.isSubmitting || state.isFinished) return;

    state = state.copyWith(isSubmitting: true, errorMessage: null);
    try {
      dynamic result;
      if (params.type == 'quiz') {
        final repo = ref.read(timelineQuizzesRepositoryProvider);
        result = await repo.submitQuizAnswers(
          attemptId: params.attemptId,
          answers: state.selectedAnswers,
        );
      } else {
        final repo = ref.read(examsRepositoryProvider);
        result = await repo.submitExamAnswers(
          attemptId: params.attemptId,
          answers: state.selectedAnswers,
        );
      }

      state = state.copyWith(
        isSubmitting: false,
        isFinished: true,
        finalScore: result.score,
        totalMarks: result.totalMarks,
        needsManualGrading: result.needsManualGrading,
      );
    } catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: 'Failed to finalize attempt: $e',
      );
    }
  }
}
