import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../authentication/domain/entities/auth_user.dart';
import '../../domain/entities/dashboard_subject.dart';
import '../providers/dashboard_providers.dart';
import '../../../subject_navigation/presentation/providers/subject_navigation_providers.dart';
import '../../../subject_navigation/presentation/screens/subject_navigation_screen.dart';
import '../../../student_platform/presentation/screens/student_feature_hub_screen.dart';
import '../../../subject_navigation/domain/entities/subject_learning_entities.dart';
import '../../../video_streaming/domain/entities/playback_entities.dart';
import '../../../video_streaming/presentation/providers/continue_watching_provider.dart';
import '../../../video_streaming/presentation/screens/video_streaming_screen.dart';

/// TODO: replace with Figma-precise geometry when 03_UI_UX.md is Approved for this screen.
class StudentDashboardScreen extends ConsumerWidget {
  final AuthUser user;

  const StudentDashboardScreen({required this.user, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subjects = ref.watch(dashboardSubjectsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة الطالب'),
        actions: [
          IconButton(
            tooltip: 'الإشعارات',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => NotificationsScreen(studentId: user.id),
              ),
            ),
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          IconButton(
            tooltip: 'الرسائل',
            onPressed: () => _showComingSoon(context, 'مركز الرسائل'),
            icon: const Icon(Icons.chat_bubble_outline_rounded),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(dashboardSubjectsProvider.future),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            children: [
              _GreetingCard(user: user),
              const SizedBox(height: AppSpacing.xl),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'موادي التعليمية',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(dashboardSubjectsProvider),
                    child: const Text('تحديث'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              subjects.when(
                loading: () => const SizedBox(
                  height: 180,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => _ErrorCard(
                  message: 'تعذر تحميل المواد حالياً',
                  onRetry: () => ref.invalidate(dashboardSubjectsProvider),
                ),
                data: (items) => items.isEmpty
                    ? const _EmptySubjects()
                    : _SubjectCarousel(subjects: items),
              ),
              const SizedBox(height: AppSpacing.xl),
              _ContinueWatchingSection(userId: user.id),
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                label: 'فتح كل الميزات التعليمية',
                icon: Icons.apps_rounded,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => StudentFeatureHubScreen(user: user),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text('وصول سريع', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.notifications_none_rounded,
                      title: 'الإشعارات',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              NotificationsScreen(studentId: user.id),
                        ),
                      ),
                    ),
                  ),
                  if (user.studentType == 'center_student') ...[
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: _QuickAction(
                        icon: Icons.chat_bubble_outline_rounded,
                        title: 'تواصل مع الإدارة',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(studentId: user.id),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showComingSoon(BuildContext context, String title) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$title سيكون متاحاً من مركز المنصة قريباً.')),
    );
  }
}

class _GreetingCard extends StatelessWidget {
  final AuthUser user;

  const _GreetingCard({required this.user});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.primary,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            UserAvatar.fromAuthValues(
              role: user.role,
              studentType: user.studentType,
              photoUrl: user.profilePhoto,
              semanticLabel: 'صورة ${user.fullName}',
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'مرحباً بك',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  Text(
                    user.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    user.grade == null
                        ? 'ابدأ رحلة التعلم اليوم'
                        : 'استمر في رحلة التعلم',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubjectCarousel extends StatelessWidget {
  final List<DashboardSubject> subjects;

  const _SubjectCarousel({required this.subjects});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 190,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: subjects.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
        itemBuilder: (context, index) {
          final subject = subjects[index];
          return SizedBox(
            width: 250,
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: subject.canOpen
                    ? () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => SubjectNavigationScreen(
                              subject: subject,
                            ),
                          ),
                        )
                    : () => _showSubjectAccessMessage(context, subject),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: subject.thumbnailUrl == null
                          ? Container(
                              color: AppColors.primaryLight.withValues(
                                alpha: .18,
                              ),
                              child: const Icon(
                                Icons.menu_book_rounded,
                                size: 46,
                              ),
                            )
                          : Image.network(
                              subject.thumbnailUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                color: AppColors.primaryLight.withValues(
                                  alpha: .18,
                                ),
                                child: const Icon(
                                  Icons.menu_book_rounded,
                                  size: 46,
                                ),
                              ),
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            subject.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            subject.canOpen
                                ? 'متاح للتعلم'
                                : 'الوصول غير متاح حالياً',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: subject.canOpen
                                      ? AppColors.success
                                      : AppColors.muted,
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
        },
      ),
    );
  }
}

void _showSubjectAccessMessage(
  BuildContext context,
  DashboardSubject subject,
) {
  final message = switch (subject.entitlementReason) {
    'subject_access_disabled' => 'الوصول إلى هذه المادة معطل حالياً.',
    'subscription_unavailable' => 'لا يوجد اشتراك فعال لهذه المادة.',
    'active_plan_missing' => 'الخطة الحالية غير متاحة لهذه المادة.',
    'plan_features_disabled' => 'لا توجد ميزات مفعلة في الخطة الحالية.',
    _ => 'لا يمكن فتح هذه المادة حالياً.',
  };
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class _ContinueWatchingSection extends ConsumerWidget {
  final String userId;

  const _ContinueWatchingSection({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(continueWatchingProvider(userId));
    return state.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'استمر في المشاهدة',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 178,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: AppSpacing.md),
                itemBuilder: (context, index) =>
                    _ContinueWatchingCard(record: items[index], userId: userId),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ContinueWatchingCard extends ConsumerWidget {
  final PlaybackProgressRecord record;
  final String userId;

  const _ContinueWatchingCard({required this.record, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final percent = record.progressPercent.clamp(0.0, 1.0);
    final episode = LectureSummary(
      id: record.lectureId,
      title: record.lectureTitle ?? 'محاضرة',
      status: 'in_progress',
      displayOrder: 0,
      isLocked: false,
      subjectId: record.subjectId,
      sectionId: record.sectionId,
      thumbnailUrl: record.thumbnailUrl,
      duration: record.duration,
    );
    return SizedBox(
      width: 260,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: record.subjectId == null
              ? null
              : () => _openPlayer(context, ref, episode),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: record.thumbnailUrl == null
                    ? ColoredBox(
                        color: AppColors.primaryLight.withValues(alpha: .16),
                        child: const Icon(Icons.play_circle_outline, size: 42),
                      )
                    : Image.network(
                        record.thumbnailUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const ColoredBox(color: AppColors.divider),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  0,
                ),
                child: Text(
                  record.lectureTitle ?? 'محاضرة',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  4,
                  AppSpacing.md,
                  AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LinearProgressIndicator(value: percent, minHeight: 4),
                    const SizedBox(height: 4),
                    Text(
                      '${(percent * 100).round()}% • متابعة من ${_format(record.position)}',
                      style: Theme.of(context).textTheme.bodySmall,
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

  Future<void> _openPlayer(
    BuildContext context,
    WidgetRef ref,
    LectureSummary fallbackEpisode,
  ) async {
    try {
      final subjectId = record.subjectId!;
      final seasons = await ref.read(subjectSectionsProvider(subjectId).future);
      final visibleSeasons = seasons.where((item) => item.isVisible).toList();
      final loadedEpisodes = await Future.wait(
        visibleSeasons.map(
          (season) => ref.read(sectionLecturesProvider(season.id).future),
        ),
      );
      final episodes = loadedEpisodes.expand((items) => items).toList();
      if (!episodes.any((item) => item.id == fallbackEpisode.id)) {
        episodes.insert(0, fallbackEpisode);
      }
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoStreamingScreen(
            subjectId: subjectId,
            studentId: userId,
            initialEpisode: episodes.firstWhere(
              (item) => item.id == fallbackEpisode.id,
            ),
            episodes: episodes,
            seasons: visibleSeasons,
            loadEpisodes: (sectionId) =>
                ref.read(sectionLecturesProvider(sectionId).future),
          ),
        ),
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تحميل حلقات المادة الآن.')),
        );
      }
    }
  }

  String _format(Duration value) =>
      '${value.inMinutes.remainder(60).toString().padLeft(2, '0')}:${value.inSeconds.remainder(60).toString().padLeft(2, '0')}';
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: title,
      icon: icon,
      onPressed: onTap,
      variant: AppButtonVariant.outlined,
    );
  }
}

class _EmptySubjects extends StatelessWidget {
  const _EmptySubjects();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: [
            const Icon(Icons.school_outlined, size: 48, color: AppColors.muted),
            const SizedBox(height: AppSpacing.md),
            Text(
              'لا توجد مواد متاحة حالياً',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'ستظهر المواد هنا بعد تفعيل اشتراكك أو إتاحة مادة جديدة لك.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            TextButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
          ],
        ),
      ),
    );
  }
}
