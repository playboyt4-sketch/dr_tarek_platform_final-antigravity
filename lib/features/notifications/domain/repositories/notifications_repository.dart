import '../entities/app_notification.dart';

abstract class NotificationsRepository {
  Future<List<AppNotification>> getNotifications({
    required String userId,
    int limit = 50,
  });

  Stream<List<AppNotification>> watchNotifications({
    required String userId,
    int limit = 50,
  });

  Future<void> markAsRead({
    required String notificationId,
  });

  Future<void> markAllAsRead({
    required String userId,
  });

  Stream<int> watchUnreadCount({
    required String userId,
  });
}
