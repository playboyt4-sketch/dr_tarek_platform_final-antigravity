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
}
