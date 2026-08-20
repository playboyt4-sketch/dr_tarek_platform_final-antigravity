enum EntitlementOutcome { allow, deny }

class EntitlementDecision {
  final EntitlementOutcome outcome;
  final String studentId;
  final String subjectId;
  final String featureKey;
  final String reason;
  final String source;

  const EntitlementDecision({
    required this.outcome,
    required this.studentId,
    required this.subjectId,
    required this.featureKey,
    required this.reason,
    required this.source,
  });

  bool get isAllowed => outcome == EntitlementOutcome.allow;

  const EntitlementDecision.allow({
    required String studentId,
    required String subjectId,
    required String featureKey,
    required String source,
  }) : this(
         outcome: EntitlementOutcome.allow,
         studentId: studentId,
         subjectId: subjectId,
         featureKey: featureKey,
         reason: 'allowed',
         source: source,
       );

  const EntitlementDecision.deny({
    required String studentId,
    required String subjectId,
    required String featureKey,
    required String reason,
    String source = 'subject_access_subscription_plan_feature',
  }) : this(
         outcome: EntitlementOutcome.deny,
         studentId: studentId,
         subjectId: subjectId,
         featureKey: featureKey,
         reason: reason,
         source: source,
       );
}
