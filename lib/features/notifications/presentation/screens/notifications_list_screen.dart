import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../providers/notifications_providers.dart';

/// In-app notifications list backed by the notifications repository.
/// Keeps the [embedded] mode used by Student Home bottom navigation.
class NotificationsScreen extends ConsumerWidget {
  final String studentId;

  /// When true the list renders without its own Scaffold/AppBar so it can be
  /// embedded inside the Student Home bottom navigation.
  final bool embedded;
  const NotificationsScreen({
    required this.studentId,
    this.embedded = false,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final body = ref
        .watch(userNotificationsStreamProvider(studentId))
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const Center(child: Text('لا توجد إشعارات جديدة.')),
          data: (notifications) {
            if (notifications.isEmpty) {
              return const Center(child: Text('لا توجد إشعارات جديدة.'));
            }
            final unreadCount =
                notifications.where((notification) => !notification.isRead).length;
            return Column(
              children: [
                if (unreadCount > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.lg,
                      0,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'لديك $unreadCount إشعار غير مقروء',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: AppColors.muted),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => ref
                              .read(notificationsRepositoryProvider)
                              .markAllAsRead(userId: studentId),
                          icon: const Icon(Icons.done_all_rounded, size: 18),
                          label: const Text('تحديد الكل كمقروء'),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    itemCount: notifications.length,
                    itemBuilder: (_, index) {
                      final notification = notifications[index];
                      final isUnread = !notification.isRead;
                      return Card(
                        color: isUnread ? AppColors.primary.withValues(alpha: 0.04) : null,
                        child: ListTile(
                          leading: Icon(
                            isUnread
                                ? Icons.notifications_active_outlined
                                : Icons.notifications_none_rounded,
                            color: isUnread ? AppColors.primary : AppColors.muted,
                          ),
                          title: Text(
                            notification.title,
                            style: TextStyle(
                              fontWeight:
                                  isUnread ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(notification.body),
                          onTap: () {
                            if (!isUnread) return;
                            ref
                                .read(notificationsRepositoryProvider)
                                .markAsRead(notificationId: notification.id);
                          },
                          trailing: isUnread
                              ? const Icon(
                                  Icons.circle,
                                  size: 10,
                                  color: AppColors.primary,
                                )
                              : null,
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
    if (embedded) return ColoredBox(color: Colors.white, child: body);
    return Scaffold(appBar: AppBar(title: const Text('الإشعارات')), body: body);
  }
}
