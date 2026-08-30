import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../authentication/domain/entities/auth_user.dart';
import '../../../student_dashboard/domain/entities/dashboard_subject.dart';
import '../../../student_dashboard/presentation/providers/dashboard_providers.dart';
import '../../domain/entities/membership_plan.dart';
import '../../domain/entities/plan_feature.dart';
import '../../presentation/providers/membership_providers.dart';

/// Membership plans browser — reads plans exclusively through
/// [availablePlansProvider] (repository-backed).
///
/// Per the approved FINAL_DECISIONS / Database v1.8 spec, payment is external
/// only: students browse plans and their current subscription states here and
/// complete activation through the administration. Activation/upgrade/renew
/// callables are intentionally admin-gated server-side.
class MembershipPlansScreen extends ConsumerWidget {
  final AuthUser user;
  const MembershipPlansScreen({required this.user, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentType = user.studentType;
    if (studentType == null ||
        (studentType != 'public_student' && studentType != 'center_student')) {
      return Scaffold(
        appBar: AppBar(title: const Text('الخطط والاشتراكات')),
        body: const Center(child: Text('نوع الطالب غير مُعدّ بعد.')),
      );
    }

    final plans = ref.watch(availablePlansProvider(studentType));
    return Scaffold(
      appBar: AppBar(title: const Text('الخطط والاشتراكات')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(availablePlansProvider(studentType));
          ref.invalidate(dashboardSubjectsProvider);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text('اشتراكاتي', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            const _MySubscriptionsSection(),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'الخطط المتاحة',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            plans.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, _) => const _InfoCard(
                icon: Icons.error_outline_rounded,
                message: 'تعذر تحميل الخطط حالياً.',
                tone: _InfoTone.warning,
              ),
              data: (items) {
                if (items.isEmpty) {
                  return const _InfoCard(
                    icon: Icons.workspace_premium_outlined,
                    message: 'لا توجد خطط متاحة حالياً.',
                    tone: _InfoTone.neutral,
                  );
                }
                final sorted = [...items]..sort(
                    (a, b) => a.displayOrder.compareTo(b.displayOrder),
                  );
                return Column(
                  children: [
                    for (final plan in sorted) ...[
                      _PlanCard(planId: plan.id, plan: plan),
                      const SizedBox(height: AppSpacing.md),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.xl),
            const _InfoCard(
              icon: Icons.support_agent_rounded,
              message:
                  'لتفعيل اشتراك أو ترقيته أو تجديده، تواصل مع إدارة المنصة '
                  'وسيتم التفعيل بعد تأكيد الدفع.',
              tone: _InfoTone.info,
            ),
          ],
        ),
      ),
    );
  }
}

class _MySubscriptionsSection extends ConsumerWidget {
  const _MySubscriptionsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subjects = ref.watch(dashboardSubjectsProvider);
    return subjects.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => const _InfoCard(
        icon: Icons.folder_off_outlined,
        message: 'لا يمكن عرض المواد حالياً.',
        tone: _InfoTone.warning,
      ),
      data: (items) {
        if (items.isEmpty) {
          return const _InfoCard(
            icon: Icons.menu_book_outlined,
            message: 'لم تُسند إليك مواد بعد. ستظهر هنا بعد إسناد المواد من الإدارة.',
            tone: _InfoTone.neutral,
          );
        }
        return Column(
          children: [
            for (final subject in items) ...[
              _SubscriptionTile(subject: subject),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
        );
      },
    );
  }
}

class _SubscriptionTile extends StatelessWidget {
  final DashboardSubject subject;

  const _SubscriptionTile({required this.subject});

  @override
  Widget build(BuildContext context) {
    final tone = _stateVisual(subject.subscriptionState);
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(Icons.school_rounded, color: tone.color),
        title: Text(subject.title),
        subtitle: Text(tone.label),
        trailing: Icon(
          tone.state == DashboardSubscriptionState.active ||
                  tone.state == DashboardSubscriptionState.trial
              ? Icons.check_circle_rounded
              : Icons.schedule_rounded,
          color: tone.color,
        ),
      ),
    );
  }

  static _StateVisual _stateVisual(DashboardSubscriptionState state) {
    return switch (state) {
      DashboardSubscriptionState.active =>
        _StateVisual('اشتراك نشط', AppColors.success, state),
      DashboardSubscriptionState.trial =>
        _StateVisual('فترة تجريبية', AppColors.info, state),
      DashboardSubscriptionState.frozen =>
        _StateVisual('الاشتراك مجمّد', AppColors.warning, state),
      DashboardSubscriptionState.expired =>
        _StateVisual('انتهى مع نهاية الفترة الدراسية', AppColors.warning, state),
      DashboardSubscriptionState.disciplinaryDisabled =>
        _StateVisual('موقوف تأديبياً', AppColors.error, state),
      DashboardSubscriptionState.inactive =>
        _StateVisual('الاشتراك غير نشط', AppColors.muted, state),
      DashboardSubscriptionState.missing =>
        _StateVisual('لا يوجد اشتراك بعد', AppColors.muted, state),
    };
  }
}

class _PlanCard extends ConsumerWidget {
  final String planId;
  final MembershipPlan plan;

  const _PlanCard({required this.planId, required this.plan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final features = ref.watch(planFeaturesProvider(planId));
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.workspace_premium_outlined,
                  color: AppColors.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    plan.planName,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppShapes.radiusSmall),
                  ),
                  child: Text(
                    plan.planKey,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: AppColors.primary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            features.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: LinearProgressIndicator(minHeight: 2),
              ),
              error: (_, _) => Text(
                'تعذر تحميل مزايا الخطة.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.muted),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return Text(
                    'لا توجد مزايا معرفة لهذه الخطة.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.muted),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final feature in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: Row(
                          children: [
                            Icon(
                              feature.enabled
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.remove_circle_outline_rounded,
                              size: 18,
                              color: feature.enabled
                                  ? AppColors.success
                                  : AppColors.muted,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                _featureLabel(feature),
                                style: TextStyle(
                                  color: feature.enabled
                                      ? AppColors.onSurface
                                      : AppColors.muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Human-readable Arabic labels for the known feature keys; unknown keys
  /// fall back to the raw key so nothing silently disappears.
  static String _featureLabel(PlanFeature feature) {
    final value = feature.featureValue;
    switch (feature.featureKey) {
      case 'offline_download':
        return feature.enabled ? 'تحميل المحاضرات للمشاهدة بدون إنترنت' : 'بدون تحميل';
      case 'video.quality.max':
        if (value is String && value.isNotEmpty) return 'أقصى جودة فيديو: $value';
        return 'الجودة القصوى للفيديو';
      default:
        if (value != null && '$value'.isNotEmpty) {
          return '${feature.featureKey}: $value';
        }
        return feature.featureKey;
    }
  }
}

enum _InfoTone { warning, info, neutral }

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String message;
  final _InfoTone tone;

  const _InfoCard({
    required this.icon,
    required this.message,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      _InfoTone.warning => AppColors.warning,
      _InfoTone.info => AppColors.info,
      _InfoTone.neutral => AppColors.muted,
    };
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(message, style: const TextStyle(height: 1.6)),
            ),
          ],
        ),
      ),
    );
  }
}

class _StateVisual {
  final String label;
  final Color color;
  final DashboardSubscriptionState state;

  const _StateVisual(this.label, this.color, this.state);
}
