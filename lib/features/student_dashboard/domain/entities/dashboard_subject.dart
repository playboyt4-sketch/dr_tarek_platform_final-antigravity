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

  /// Canonical subject catalog grade (`grade_one` … `grade_four`) read
  /// from the `subjects` doc `grade` field. This is the SUBJECT's own
  /// grade (e.g. الفرقة الأولى) — never the student's grade. A student
  /// in grade N may hold subjects from prior grades (FINAL_DECISIONS §13),
  /// so the subject page header must show this, not a hardcoded fallback.
  final String? gradeKey;

  /// `plan_key` of the subject's subscription plan (free/pro/max/guest),
  /// resolved from the `plans` doc. Drives per-subject UI such as the
  /// Student Home avatar badge, which follows the centered card's plan.
  final String? planKey;
  final int displayOrder;
  final DashboardSubjectAccessState subjectAccessState;
  final DashboardSubscriptionState subscriptionState;
  final DashboardEntitlementState entitlementState;
  final String? entitlementReason;

  /// Arabic display label for [gradeKey] (e.g. `الفرقة الأولى`).
  /// Null when the subject doc carries no parseable grade.
  String? get gradeLabel {
    switch (gradeKey) {
      case 'grade_one':
        return 'الفرقة الأولى';
      case 'grade_two':
        return 'الفرقة الثانية';
      case 'grade_three':
        return 'الفرقة الثالثة';
      case 'grade_four':
        return 'الفرقة الرابعة';
      default:
        return null;
    }
  }

  const DashboardSubject({
    required this.id,
    required this.title,
    this.subtitle,
    this.thumbnailUrl,
    this.gradeKey,
    this.planKey,
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
