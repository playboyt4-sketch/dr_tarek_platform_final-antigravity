import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/notifications_remote_data_source.dart';
import '../../data/repositories/notifications_repository_impl.dart';
import '../../domain/entities/app_notification.dart';
import '../../domain/repositories/notifications_repository.dart';

final notificationsRemoteDataSourceProvider =
    Provider<NotificationsRemoteDataSource>((ref) {
  return NotificationsRemoteDataSource();
});

final notificationsRepositoryProvider =
    Provider<NotificationsRepository>((ref) {
  final dataSource = ref.watch(notificationsRemoteDataSourceProvider);
  return NotificationsRepositoryImpl(remoteDataSource: dataSource);
});

final userNotificationsStreamProvider =
    StreamProvider.family<List<AppNotification>, String>((ref, userId) {
  final repo = ref.watch(notificationsRepositoryProvider);
  return repo.watchNotifications(userId: userId);
});

final userUnreadNotificationsCountProvider =
    StreamProvider.family<int, String>((ref, userId) {
  final repo = ref.watch(notificationsRepositoryProvider);
  return repo.watchUnreadCount(userId: userId);
});
