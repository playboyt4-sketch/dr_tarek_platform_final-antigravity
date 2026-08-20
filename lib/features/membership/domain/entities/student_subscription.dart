enum AcademicTermLifecycle { upcoming, active, expired, frozen }

class MembershipSubscription {
  final String id;
  final String studentId;
  final String subjectId;
  final String planId;
  final String durationType;
  final DateTime startDate;
  final DateTime? endDate;
  final String status;
  final bool isFrozen;
  final DateTime? frozenAt;
  final DateTime? resumedAt;
  final bool isGifted;
  final String? giftedBy;
  final int renewalCount;
  final String? previousPlanId;
  final bool manuallyDisabled;
  final String? disabledBy;
  final DateTime? disabledAt;
  final String? disabledReason;

  AcademicTermLifecycle get termLifecycle {
    if (isFrozen) return AcademicTermLifecycle.frozen;
    final now = DateTime.now();
    if (now.isBefore(startDate)) return AcademicTermLifecycle.upcoming;
    if (endDate == null || now.isBefore(endDate!)) {
      return AcademicTermLifecycle.active;
    }
    return AcademicTermLifecycle.expired;
  }

  bool get isWithinAcademicTerm =>
      termLifecycle == AcademicTermLifecycle.active;

  const MembershipSubscription({
    required this.id,
    required this.studentId,
    required this.subjectId,
    required this.planId,
    required this.durationType,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.isFrozen,
    required this.frozenAt,
    required this.resumedAt,
    required this.isGifted,
    required this.giftedBy,
    required this.renewalCount,
    required this.previousPlanId,
    this.manuallyDisabled = false,
    this.disabledBy,
    this.disabledAt,
    this.disabledReason,
  });
}
