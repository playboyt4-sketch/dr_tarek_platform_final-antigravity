import 'package:flutter_test/flutter_test.dart';
import 'package:dr_tarek_platform/features/notifications/data/models/app_notification_model.dart';
import 'package:dr_tarek_platform/features/notifications/domain/entities/app_notification.dart';
import 'package:dr_tarek_platform/features/notifications/domain/repositories/notifications_repository.dart';

class InMemoryNotificationsRepository implements NotificationsRepository {
  final List<AppNotification> _notifications = [];

  void addNotification(AppNotification notification) {
    _notifications.add(notification);
  }

  @override
  Future<List<AppNotification>> getNotifications({
    required String userId,
    int limit = 50,
  }) async {
    return _notifications.where((n) => n.userId == userId).take(limit).toList();
  }

  @override
  Future<void> markAllAsRead({required String userId}) async {
    for (int i = 0; i < _notifications.length; i++) {
      if (_notifications[i].userId == userId) {
        final old = _notifications[i];
        _notifications[i] = AppNotification(
          id: old.id,
          userId: old.userId,
          title: old.title,
          body: old.body,
          type: old.type,
          priority: old.priority,
          mediaType: old.mediaType,
          mediaUrl: old.mediaUrl,
          isRead: true,
          createdAt: old.createdAt,
        );
      }
    }
  }

  @override
  Future<void> markAsRead({required String notificationId}) async {
    final index = _notifications.indexWhere((n) => n.id == notificationId);
    if (index != -1) {
      final old = _notifications[index];
      _notifications[index] = AppNotification(
        id: old.id,
        userId: old.userId,
        title: old.title,
        body: old.body,
        type: old.type,
        priority: old.priority,
        mediaType: old.mediaType,
        mediaUrl: old.mediaUrl,
        isRead: true,
        createdAt: old.createdAt,
      );
    }
  }

  @override
  Stream<List<AppNotification>> watchNotifications({
    required String userId,
    int limit = 50,
  }) {
    return Stream.value(
      _notifications.where((n) => n.userId == userId).take(limit).toList(),
    );
  }

  @override
  Stream<int> watchUnreadCount({required String userId}) {
    return Stream.value(
      _notifications.where((n) => n.userId == userId && !n.isRead).length,
    );
  }
}

void main() {
  group('Notifications Feature Tests', () {
    test('AppNotificationModel parses announcements, priority, and media', () {
      final map = {
        'user_id': 'student_123',
        'title': 'New lecture released',
        'body': 'Lecture 4 is now available in your course.',
        'type': 'Lecture',
        'priority': 'critical',
        'media_type': 'video',
        'media_url': 'https://storage.googleapis.com/preview.mp4',
        'is_read': false,
      };

      final notif = AppNotificationModel.fromMap('notif_1', map);
      expect(notif.id, 'notif_1');
      expect(notif.title, 'New lecture released');
      expect(notif.priority, 'critical');
      expect(notif.mediaType, 'video');
      expect(notif.isRead, isFalse);
    });

    test('NotificationsRepository manages read status and unread count',
        () async {
      final repo = InMemoryNotificationsRepository();

      repo.addNotification(
        AppNotification(
          id: 'n1',
          userId: 'student_1',
          title: 'Welcome',
          body: 'Welcome to the platform',
          type: 'Announcements',
          createdAt: DateTime.now(),
        ),
      );
      repo.addNotification(
        AppNotification(
          id: 'n2',
          userId: 'student_1',
          title: 'Exam Scheduled',
          body: 'Midterm exam is tomorrow',
          type: 'Lecture',
          createdAt: DateTime.now(),
        ),
      );

      final unreadCountBefore = await repo.watchUnreadCount(userId: 'student_1').first;
      expect(unreadCountBefore, 2);

      await repo.markAsRead(notificationId: 'n1');
      final unreadCountAfterOne =
          await repo.watchUnreadCount(userId: 'student_1').first;
      expect(unreadCountAfterOne, 1);

      await repo.markAllAsRead(userId: 'student_1');
      final unreadCountAfterAll =
          await repo.watchUnreadCount(userId: 'student_1').first;
      expect(unreadCountAfterAll, 0);
    });
  });
}
