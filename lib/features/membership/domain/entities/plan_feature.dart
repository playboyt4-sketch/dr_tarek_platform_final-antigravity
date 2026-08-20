class PlanFeature {
  final String id;
  final String planId;
  final String featureKey;
  final bool enabled;
  final dynamic featureValue;

  const PlanFeature({
    required this.id,
    required this.planId,
    required this.featureKey,
    required this.enabled,
    this.featureValue,
  });
}
