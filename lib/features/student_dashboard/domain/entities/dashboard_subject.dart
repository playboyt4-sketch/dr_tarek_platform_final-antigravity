enum DashboardSubjectAccessState { enabled, disabled }

enum DashboardSubscriptionState {
  active,
  trial,
  missing,
  inactive,
  frozen,
  expired,
  disciplinaryDisabled,
}

enum DashboardEntitlementState { ready, blocked }

class DashboardSubject {
  final String id;
  final String title;
  final String? subtitle;
  final String? thumbnailUrl;
  final int displayOrder;
  final DashboardSubjectAccessState subjectAccessState;
  final DashboardSubscriptionState subscriptionState;
  final DashboardEntitlementState entitlementState;
  final String? entitlementReason;

  const DashboardSubject({
    required this.id,
    required this.title,
    this.subtitle,
    this.thumbnailUrl,
    required this.displayOrder,
    this.subjectAccessState = DashboardSubjectAccessState.enabled,
    this.subscriptionState = DashboardSubscriptionState.active,
    this.entitlementState = DashboardEntitlementState.ready,
    this.entitlementReason,
  });

  bool get canOpen =>
      subjectAccessState == DashboardSubjectAccessState.enabled &&
      entitlementState == DashboardEntitlementState.ready;
}
