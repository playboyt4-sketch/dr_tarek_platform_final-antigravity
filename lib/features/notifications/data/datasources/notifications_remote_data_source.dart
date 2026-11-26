import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/app_notification_model.dart';

class NotificationsRemoteDataSource {
  final FirebaseFirestore? _firestoreOverride;
  final FirebaseFunctions? _functionsOverride;

  NotificationsRemoteDataSource({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _firestoreOverride = firestore,
        _functionsOverride = functions;

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  FirebaseFunctions get _functions =>
      _functionsOverride ?? FirebaseFunctions.instance;

  CollectionReference<Map<String, dynamic>> get _notificationsRef =>
      _firestore.collection('notifications');

  Future<List<AppNotificationModel>> getNotifications({
    required String userId,
    int limit = 50,
  }) async {
    final snap = await _notificationsRef
        .where('user_id', isEqualTo: userId)
        .orderBy('created_at', descending: true)
        .limit(limit)
        .get();
    final items =
        snap.docs.map(AppNotificationModel.fromFirestore).toList();
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items.take(limit).toList();
  }

  Stream<List<AppNotificationModel>> watchNotifications({
    required String userId,
    int limit = 50,
  }) {
    return _notificationsRef
        .where('user_id', isEqualTo: userId)
        .orderBy('created_at', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) {
      final items =
          snap.docs.map(AppNotificationModel.fromFirestore).toList();
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return items.take(limit).toList();
    });
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

  Future<void> resetUnreadBadgeCount({required String userId}) async {
    try {
      await _functions.httpsCallable('resetUnreadNotificationsCount').call();
    } catch (_) {
      try {
        await _firestore.collection('users').doc(userId).update({
          'unread_notifications_count': 0,
        });
      } catch (_) {}
    }
  }
}
