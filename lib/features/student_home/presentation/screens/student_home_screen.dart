import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../authentication/domain/entities/auth_user.dart';
import '../../../student_dashboard/domain/entities/dashboard_subject.dart';
import '../../../student_dashboard/presentation/providers/dashboard_providers.dart';
import '../../../student_platform/presentation/screens/student_feature_hub_screen.dart';
import '../../../notifications/presentation/providers/notifications_providers.dart';
import '../../../notifications/presentation/screens/notifications_list_screen.dart';
import '../../../subject_navigation/presentation/screens/subject_navigation_screen.dart';

/// Student Home — the landing screen after a successful student login.
///
/// Visual reference: the approved Figma frame (full colored background,
/// UserAvatar on top, "Hi, {first name}" greeting, a vertical list of
/// pill-shaped subject buttons, and a 2-item bottom navigation:
/// Home (active), Notifications).
class StudentHomeScreen extends ConsumerStatefulWidget {
  final AuthUser user;

  const StudentHomeScreen({required this.user, super.key});

  @override
  ConsumerState<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends ConsumerState<StudentHomeScreen> {
  int _currentTab = 0;

  @override
  Widget build(BuildContext context) {
    final background = _gradeBackground(widget.user.grade);

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: switch (_currentTab) {
          0 => _HomeTab(user: widget.user),
          1 => NotificationsScreen(studentId: widget.user.id, embedded: true),
          _ => StudentFeatureHubScreen(user: widget.user, embedded: true),
        },
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTab,
        onTap: (index) => setState(() => _currentTab = index),
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.muted,
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.home_rounded),
            label: AppLocalizations.of(context).navHome,
          ),
          BottomNavigationBarItem(
            icon: _NotificationsIconWithBadge(studentId: widget.user.id),
            label: AppLocalizations.of(context).navNotifications,
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.widgets_outlined),
            label: 'الميزات',
          ),
        ],
      ),
    );
  }

  /// Background color follows the approved per-grade identity tokens
  /// (درجات ألوان فرق الكلية). Unknown grades fall back to grade one.
  static Color _gradeBackground(String? grade) {
    final normalized = grade?.trim().toLowerCase();
    return switch (normalized) {
      'grade_two' || 'grade two' || '2' || 'الفرقة الثانية' => AppColors.gradeTwo,
      'grade_three' || 'grade three' || '3' || 'الفرقة الثالثة' => AppColors.gradeThree,
      'grade_four' || 'grade four' || '4' || 'الفرقة الرابعة' => AppColors.gradeFour,
      _ => AppColors.gradeOne,
    };
  }
}

class _HomeTab extends ConsumerWidget {
  final AuthUser user;

  const _HomeTab({required this.user});

  String get _firstName {
    final parts = user.fullName.trim().split(RegExp(r'\s+'));
    return parts.isEmpty || parts.first.isEmpty ? user.fullName : parts.first;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subjects = ref.watch(dashboardSubjectsProvider);
    final planKey = ref.watch(studentPlanKeyProvider(user.id)).value;

    return RefreshIndicator(
      onRefresh: () => ref.refresh(dashboardSubjectsProvider.future),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xl,
        ),
        children: [
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: UserAvatar.fromAuthValues(
              role: user.role,
              studentType: user.studentType,
              photoUrl: user.profilePhoto,
              planId: planKey,
              size: 88,
              semanticLabel: 'صورة ${user.fullName}',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Hi, $_firstName',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              shadows: [
                Shadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          subjects.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
            error: (_, _) => _HomeMessageCard(
              message: 'تعذر تحميل المواد حالياً',
              actionLabel: 'إعادة المحاولة',
              onAction: () => ref.invalidate(dashboardSubjectsProvider),
            ),
            data: (items) => items.isEmpty
                ? const _HomeMessageCard(
                    message: 'لا توجد مواد مفعّلة لك حالياً.\nستظهر هنا بعد تفعيل وصولك من الإدارة.',
                  )
                : Column(
                    children: [
                      for (final subject in items) ...[
                        _SubjectPillButton(subject: subject),
                        const SizedBox(height: AppSpacing.md),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _SubjectPillButton extends StatelessWidget {
  final DashboardSubject subject;

  const _SubjectPillButton({required this.subject});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppShapes.radiusCircular),
      elevation: 2,
      shadowColor: const Color(0x33000000),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppShapes.radiusCircular),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SubjectNavigationScreen(subject: subject),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              if (subject.thumbnailUrl != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    subject.thumbnailUrl!,
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      width: 60,
                      height: 60,
                      color: Colors.grey[200],
                      child: const Icon(Icons.image_not_supported, color: Colors.grey),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subject.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.onBackground,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Minimal subscription status line under the subject name.
                    Text(
                      _statusLabel(subject),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _statusColor(subject),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _statusLabel(DashboardSubject subject) {
    return switch (subject.subscriptionState) {
      DashboardSubscriptionState.active => 'اشتراك نشط',
      DashboardSubscriptionState.trial => 'فترة تجريبية',
      DashboardSubscriptionState.frozen => 'الاشتراك مجمّد',
      DashboardSubscriptionState.expired => 'انتهى مع نهاية الفترة الدراسية',
      DashboardSubscriptionState.disciplinaryDisabled => 'موقوف تأديبياً',
      DashboardSubscriptionState.inactive => 'الاشتراك غير نشط',
      DashboardSubscriptionState.missing => 'لا يوجد اشتراك بعد',
    };
  }

  static Color _statusColor(DashboardSubject subject) {
    return switch (subject.subscriptionState) {
      DashboardSubscriptionState.active => AppColors.success,
      DashboardSubscriptionState.trial => AppColors.info,
      DashboardSubscriptionState.missing => AppColors.muted,
      _ => AppColors.warning,
    };
  }
}

class _HomeMessageCard extends StatelessWidget {
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _HomeMessageCard({required this.message, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppShapes.radiusXLarge),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.onSurface),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.sm),
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Streams the plan key of the student's first active subscription so the
/// avatar badge reflects the real plan (free / pro / max).
final studentPlanKeyProvider = FutureProvider.family<String?, String>((ref, studentId) async {
  final snapshot = await FirebaseFirestore.instance
      .collection('subscriptions')
      .where('student_id', isEqualTo: studentId)
      .where('status', isEqualTo: 'active')
      .limit(1)
      .get();
  if (snapshot.docs.isEmpty) return null;
  final planId = snapshot.docs.first.data()['plan_id'];
  if (planId is! String || planId.isEmpty) return null;
  final plan = await FirebaseFirestore.instance.collection('plans').doc(planId).get();
  final key = plan.data()?['plan_key'];
  return key is String ? key : null;
});

/// Bell icon with a live unread-notifications count dot.
class _NotificationsIconWithBadge extends ConsumerWidget {
  final String studentId;

  const _NotificationsIconWithBadge({required this.studentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(userUnreadNotificationsCountProvider(studentId));
    final count = unread.value ?? 0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(Icons.notifications_none_rounded),
        if (count > 0)
          Positioned(
            top: -4,
            right: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(8),
              ),
              constraints: const BoxConstraints(minWidth: 15),
              child: Text(
                count > 99 ? '99+' : '$count',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
