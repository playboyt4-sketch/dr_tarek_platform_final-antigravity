class MembershipPlan {
  final String id;
  final String planName;
  final String planKey;
  final String studentType;
  final int displayOrder;
  final bool isActive;

  const MembershipPlan({
    required this.id,
    required this.planName,
    required this.planKey,
    required this.studentType,
    required this.displayOrder,
    required this.isActive,
  });

  /// Guest-plan identity (Phase 1 backend: plans/guest).
  ///
  /// Never inferred from [planKey] alone: both the Guest plan and
  /// the Center Free plan (plans/free, Phase 4) carry plan_key "free".
  /// The document ID plus the plan's student type jointly identify
  /// the Guest plan.
  bool get isGuestPlan => id == 'guest' && studentType == 'guest';

  /// Center-plan identity: any plan scoped to center students.
  bool get isCenterPlan => studentType == 'center_student';
}
