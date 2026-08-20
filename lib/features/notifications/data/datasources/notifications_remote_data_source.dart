import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/app_notification_model.dart';

class NotificationsRemoteDataSource {
  final FirebaseFirestore _firestore;

  NotificationsRemoteDataSource({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _notificationsRef =>
      _firestore.collection('notifications');

  Future<List<AppNotificationModel>> getNotifications({
    required String userId,
    int limit = 50,
  }) async {
    final snap = await _notificationsRef
        .where('user_id', isEqualTo: userId)
        .limit(limit)
        .get();
    return snap.docs.map(AppNotificationModel.fromFirestore).toList();
  }

  Stream<List<AppNotificationModel>> watchNotifications({
    required String userId,
    int limit = 50,
  }) {
    return _notificationsRef
        .where('user_id', isEqualTo: userId)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(AppNotificationModel.fromFirestore).toList());
  }

  Future<void> markAsRead({required String notificationId}) async {
    await _notificationsRef.doc(notificationId).update({
      'is_read': true,
      'read_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> markAllAsRead({required String userId}) async {
    final snap = await _notificationsRef
        .where('user_id', isEqualTo: userId)
        .where('is_read', isEqualTo: false)
        .get();

    final batch = _firestore.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {
        'is_read': true,
        'read_at': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Stream<int> watchUnreadCount({required String userId}) {
    return _notificationsRef
        .where('user_id', isEqualTo: userId)
        .where('is_read', isEqualTo: false)
        .snapshots()
        .map((snap) => snap.docs.length);
  }
}
