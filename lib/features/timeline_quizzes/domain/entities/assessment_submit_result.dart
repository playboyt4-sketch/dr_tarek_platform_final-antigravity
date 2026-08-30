/// Server-graded submission outcome returned by submitAssessmentAttempt.
class AssessmentSubmitResult {
  final bool submitted;
  final int? score;
  final int totalMarks;
  final double? percentage;
  final bool needsManualGrading;

  const AssessmentSubmitResult({
    required this.submitted,
    required this.score,
    required this.totalMarks,
    required this.percentage,
    required this.needsManualGrading,
  });
}