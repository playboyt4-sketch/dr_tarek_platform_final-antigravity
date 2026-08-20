import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/app_notification.dart';

class AppNotificationModel extends AppNotification {
  const AppNotificationModel({
    required super.id,
    required super.userId,
    required super.title,
    required super.body,
    required super.type,
    super.priority = 'normal',
    super.mediaType = 'none',
    super.mediaUrl,
    super.isRead = false,
    required super.createdAt,
  });

  factory AppNotificationModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return AppNotificationModel.fromMap(doc.id, data);
  }

  factory AppNotificationModel.fromMap(
      String id, Map<String, dynamic> data) {
    final createdTimestamp = data['created_at'] as Timestamp?;
    final readTimestamp = data['read_at'];
    final isRead = data['is_read'] == true || readTimestamp != null;

    return AppNotificationModel(
      id: id,
      userId: (data['user_id'] as String?) ?? '',
      title: (data['title'] as String?) ?? '',
      body: (data['body'] as String?) ?? '',
      type: (data['type'] as String?) ??
          (data['notification_type'] as String?) ??
          'Announcements',
      priority: (data['priority'] as String?) ?? 'normal',
      mediaType: (data['media_type'] as String?) ?? 'none',
      mediaUrl: data['media_url'] as String?,
      isRead: isRead,
      createdAt: createdTimestamp?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'title': title,
      'body': body,
      'type': type,
      'notification_type': type,
      'priority': priority,
      'media_type': mediaType,
      if (mediaUrl != null) 'media_url': mediaUrl,
      'is_read': isRead,
      'created_at': FieldValue.serverTimestamp(),
    };
  }
}
