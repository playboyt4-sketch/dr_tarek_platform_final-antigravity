/// In-app broadcast / announcement notification entity.
class AppNotification {
  final String id;
  final String userId;
  final String title;
  final String body;
  final String type; // Announcements, Lecture, System
  final String priority; // normal, critical
  final String mediaType; // none, image, video
  final String? mediaUrl;
  final bool isRead;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.userId,
    required this.title,
    required this.body,
    required this.type,
    this.priority = 'normal',
    this.mediaType = 'none',
    this.mediaUrl,
    this.isRead = false,
    required this.createdAt,
  });
}
