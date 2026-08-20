import '../../domain/entities/app_notification.dart';
import '../../domain/repositories/notifications_repository.dart';
import '../datasources/notifications_remote_data_source.dart';

class NotificationsRepositoryImpl implements NotificationsRepository {
  final NotificationsRemoteDataSource remoteDataSource;

  NotificationsRepositoryImpl({required this.remoteDataSource});

  @override
  Future<List<AppNotification>> getNotifications({
    required String userId,
    int limit = 50,
  }) {
    return remoteDataSource.getNotifications(userId: userId, limit: limit);
  }

  @override
  Stream<List<AppNotification>> watchNotifications({
    required String userId,
    int limit = 50,
  }) {
    return remoteDataSource.watchNotifications(userId: userId, limit: limit);
  }

  @override
  Future<void> markAsRead({required String notificationId}) {
    return remoteDataSource.markAsRead(notificationId: notificationId);
  }

  @override
  Future<void> markAllAsRead({required String userId}) {
    return remoteDataSource.markAllAsRead(userId: userId);
  }

  @override
  Stream<int> watchUnreadCount({required String userId}) {
    return remoteDataSource.watchUnreadCount(userId: userId);
  }
}
