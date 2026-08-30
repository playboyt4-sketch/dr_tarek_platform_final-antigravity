import '../../domain/entities/assessment_question.dart';
class AssessmentTakingState {
  final bool isLoading;
  final bool isSubmitting;
  final bool isFinished;
  final String? errorMessage;
  
  final List<AssessmentQuestion> questions;
  final int currentIndex;
  
  // Keyed by questionId
  final Map<String, String> selectedAnswers;
  
  // Keyed by questionId
  final Map<String, bool> correctStatuses;
  
  // Keyed by questionId
  final Map<String, String> explanations;

  // Final result metrics
  final int? finalScore;
  final int? totalMarks;
  final bool? needsManualGrading;

  const AssessmentTakingState({
    this.isLoading = true,
    this.isSubmitting = false,
    this.isFinished = false,
    this.errorMessage,
    this.questions = const [],
    this.currentIndex = 0,
    this.selectedAnswers = const {},
    this.correctStatuses = const {},
    this.explanations = const {},
    this.finalScore,
    this.totalMarks,
    this.needsManualGrading,
  });

  AssessmentQuestion? get currentQuestion =>
      questions.isNotEmpty && currentIndex < questions.length
          ? questions[currentIndex]
          : null;

  bool get isCurrentQuestionAnswered =>
      currentQuestion != null && selectedAnswers.containsKey(currentQuestion!.id);

  bool get isCurrentQuestionCorrect =>
      currentQuestion != null && correctStatuses[currentQuestion!.id] == true;
      
  String? get currentExplanation =>
      currentQuestion != null ? explanations[currentQuestion!.id] : null;

  bool get isLastQuestion => currentIndex == questions.length - 1;

  AssessmentTakingState copyWith({
    bool? isLoading,
    bool? isSubmitting,
    bool? isFinished,
    String? errorMessage,
    List<AssessmentQuestion>? questions,
    int? currentIndex,
    Map<String, String>? selectedAnswers,
    Map<String, bool>? correctStatuses,
    Map<String, String>? explanations,
    int? finalScore,
    int? totalMarks,
    bool? needsManualGrading,
  }) {
    return AssessmentTakingState(
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      isFinished: isFinished ?? this.isFinished,
      errorMessage: errorMessage ?? this.errorMessage,
      questions: questions ?? this.questions,
      currentIndex: currentIndex ?? this.currentIndex,
      selectedAnswers: selectedAnswers ?? this.selectedAnswers,
      correctStatuses: correctStatuses ?? this.correctStatuses,
      explanations: explanations ?? this.explanations,
      finalScore: finalScore ?? this.finalScore,
      totalMarks: totalMarks ?? this.totalMarks,
      needsManualGrading: needsManualGrading ?? this.needsManualGrading,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AssessmentTakingState &&
          runtimeType == other.runtimeType &&
          isLoading == other.isLoading &&
          isSubmitting == other.isSubmitting &&
          isFinished == other.isFinished &&
          errorMessage == other.errorMessage &&
          currentIndex == other.currentIndex &&
          finalScore == other.finalScore &&
          totalMarks == other.totalMarks &&
          needsManualGrading == other.needsManualGrading;

  @override
  int get hashCode =>
      isLoading.hashCode ^
      isSubmitting.hashCode ^
      isFinished.hashCode ^
      errorMessage.hashCode ^
      currentIndex.hashCode ^
      finalScore.hashCode ^
      totalMarks.hashCode ^
      needsManualGrading.hashCode;
}
