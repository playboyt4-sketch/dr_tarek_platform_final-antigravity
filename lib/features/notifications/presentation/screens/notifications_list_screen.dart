import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/responsive/responsive.dart';
import '../../domain/entities/app_notification.dart';
import '../providers/notifications_providers.dart';

// ---------------------------------------------------------------------------
// Design constants for the "Notification" sheet (Figma node 616-5855).
// Raw dev-mode values, scaled via rs()/rsV()/rsFont() — identical to Figma
// at the 393 reference width, proportionally preserved elsewhere.
//
// Frame map (dev mode paste, 393x679 sheet):
//   panel     translucent #FFFCF7 @30% (0x4CFFFCF7), 1px white 35% border,
//             top radius 24 (square bottom — it docks into the home tab)
//   handle    36x4 #E5E7EB r9999, centered, 12 from top
//   list      padding h14 v16, gap 8
//   card      min-height 64, padding 14, glass white 4% r23 + soft shadows;
//             thumb 38, Title 15 w590 white / Message 15 w400 white,
//             time 15 #4C4C4C top-end (e.g. "9:41 AM")
// Behavior is unchanged: live stream, tap marks read, unread cards render
// a touch brighter. Arabic copy renders RTL inside the LTR card row.
// ---------------------------------------------------------------------------
abstract final class _NotificationDesign {
  static const panelFill = Color(0x4CFFFCF7);
  static const panelBorder = Color(0x59FFFFFF); // 35% white
  static const handleColor = Color(0xFFE5E7EB);
  static const cardFill = Color(0x0AFFFFFF); // 4% white
  static const cardUnreadFill = Color(0x12FFFFFF); // 7% white
  static const timeColor = Color(0xFF4C4C4C);
}

/// In-app notifications list backed by the notifications repository.
///
/// [embedded] renders the bare sheet (for the Student Home tab, above the
/// shared pill nav); otherwise a standalone Scaffold with an AppBar.
class NotificationsScreen extends ConsumerWidget {
  final String studentId;

  /// When true the sheet renders without its own Scaffold/AppBar so it can
  /// be embedded inside the Student Home bottom navigation.
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
          loading: () => const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
          error: (error, _) {
            if (kDebugMode) debugPrint('notifications stream failed: $error');
            return _ErrorState(
              onRetry: () =>
                  ref.invalidate(userNotificationsStreamProvider(studentId)),
            );
          },
          data: (notifications) {
            if (notifications.isEmpty) return const _EmptyState();
            return Column(
              children: [
                // Drag handle (Figma 36x4, 12 from panel top).
                SizedBox(height: context.rsV(12)),
                Container(
                  width: context.rs(36),
                  height: context.rsV(4),
                  decoration: BoxDecoration(
                    color: _NotificationDesign.handleColor,
                    borderRadius: BorderRadius.circular(context.rs(9999)),
                  ),
                ),
                // Cards (Figma padding h14, top 16; bottom clears the
                // floating pill: 60 pill + 24 margin + 16 breathing room).
                Expanded(
                  child: ListView.separated(
                    physics: const ClampingScrollPhysics(),
                    padding: EdgeInsets.only(
                      left: context.rs(14),
                      right: context.rs(14),
                      top: context.rsV(16),
                      bottom: context.rsV(100),
                    ),
                    itemCount: notifications.length,
                    separatorBuilder: (_, _) =>
                        SizedBox(height: context.rsV(8)),
                    itemBuilder: (_, index) => _NotificationCard(
                      notification: notifications[index],
                      onTap: () {
                        final item = notifications[index];
                        if (!item.isRead) {
                          ref
                              .read(notificationsRepositoryProvider)
                              .markAsRead(notificationId: item.id);
                        }
                        _openDetails(context, item);
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        );

    // Frosted glass: blur everything behind the translucent panel so the
    // sheet reads as glass (like the Figma prototype), not flat tint.
    final sheet = ClipRRect(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(context.rs(24)),
        topRight: Radius.circular(context.rs(24)),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: _NotificationDesign.panelFill,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(context.rs(24)),
              topRight: Radius.circular(context.rs(24)),
            ),
            border: Border.all(
              color: _NotificationDesign.panelBorder,
              width: 1,
            ),
          ),
          child: body,
        ),
      ),
    );

    if (embedded) return sheet;
    return Scaffold(
      appBar: AppBar(title: const Text('الإشعارات')),
      body: SafeArea(child: sheet),
    );
  }
}

/// One glass card (Figma min-height 64, padding 14, white 4% r23).
/// LTR row per Figma: 38 thumb, title/message column, time top-end.
class _NotificationCard extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;

  const _NotificationCard({
    required this.notification,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(context.rs(23)),
        child: InkWell(
          borderRadius: BorderRadius.circular(context.rs(23)),
          onTap: onTap,
          child: Ink(
            padding: EdgeInsets.all(context.rs(14)),
            decoration: BoxDecoration(
              color: notification.isRead
                  ? _NotificationDesign.cardFill
                  : _NotificationDesign.cardUnreadFill,
              borderRadius: BorderRadius.circular(context.rs(23)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x05000000),
                  blurRadius: 15,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: context.rsV(64) - context.rs(28),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Thumb(notification: notification),
                  SizedBox(width: context.rs(10)),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          notification.title,
                          textAlign: TextAlign.start,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: context.rsFont(15),
                            fontWeight: FontWeight.w600,
                            height: 1.13,
                          ),
                        ),
                        SizedBox(height: context.rsV(2)),
                        Text(
                          notification.body,
                          textAlign: TextAlign.start,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: context.rsFont(15),
                            fontWeight: FontWeight.w400,
                            height: 1.20,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: context.rs(10)),
                  Text(
                    _formatTime(notification.createdAt),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: _NotificationDesign.timeColor,
                      fontSize: context.rsFont(15),
                      fontWeight: FontWeight.w400,
                      height: 1.13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// "9:41 AM" style stamp from Figma (no intl dependency needed).
  static String _formatTime(DateTime at) {
    final hour12 = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final minute = at.minute.toString().padLeft(2, '0');
    return '$hour12:$minute ${at.hour < 12 ? 'AM' : 'PM'}';
  }
}

/// 38 thumb: media image when present, bell glyph on glass otherwise.
class _Thumb extends StatelessWidget {
  final AppNotification notification;

  const _Thumb({required this.notification});

  @override
  Widget build(BuildContext context) {
    final side = context.rs(38);
    final radius = BorderRadius.circular(context.rs(12));
    final url = notification.mediaUrl;
    final hasImage =
        notification.mediaType != 'none' &&
        url != null &&
        url.trim().isNotEmpty;
    return Container(
      width: side,
      height: side,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: radius,
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: hasImage
          ? Image.network(
              url,
              width: side,
              height: side,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const _BellGlyph(),
            )
          : const _BellGlyph(),
    );
  }
}

class _BellGlyph extends StatelessWidget {
  const _BellGlyph();

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.notifications_none_rounded,
      size: context.rs(20),
      color: Colors.white.withValues(alpha: 0.85),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'لا توجد إشعارات جديدة.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'تعذر تحميل الإشعارات.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white),
          ),
          SizedBox(height: context.rsV(8)),
          TextButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
        ],
      ),
    );
  }
}

/// Details overlay: bottom sheet with the full message content —
/// title, complete body, timestamp, type/priority chips, and the media
/// image when the notification carries one.
Future<void> _openDetails(
  BuildContext context,
  AppNotification notification,
) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(sheetContext).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF7),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(sheetContext.rs(24)),
          topRight: Radius.circular(sheetContext.rs(24)),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: EdgeInsets.only(
          left: sheetContext.rs(24),
          right: sheetContext.rs(24),
          top: sheetContext.rsV(12),
          bottom: MediaQuery.of(sheetContext).padding.bottom +
              sheetContext.rsV(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: sheetContext.rs(36),
                height: sheetContext.rsV(4),
                decoration: BoxDecoration(
                  color: _NotificationDesign.handleColor,
                  borderRadius: BorderRadius.circular(
                    sheetContext.rs(9999),
                  ),
                ),
              ),
            ),
            SizedBox(height: sheetContext.rsV(16)),
            _DetailsMedia(notification: notification),
            Row(
              children: [
                _DetailChip(label: notification.type),
                if (notification.priority.toLowerCase() == 'critical') ...[
                  SizedBox(width: sheetContext.rs(8)),
                  _DetailChip(
                    label: 'عاجل',
                    background: const Color(0xFFDC2626),
                    foreground: Colors.white,
                  ),
                ],
              ],
            ),
            SizedBox(height: sheetContext.rsV(12)),
            Text(
              notification.title,
              style: TextStyle(
                color: Colors.black,
                fontSize: sheetContext.rsFont(20),
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
            SizedBox(height: sheetContext.rsV(4)),
            Text(
              _formatFullTime(notification.createdAt),
              style: TextStyle(
                color: const Color(0xFF6B7280),
                fontSize: sheetContext.rsFont(13),
                fontWeight: FontWeight.w400,
              ),
            ),
            SizedBox(height: sheetContext.rsV(12)),
            Text(
              notification.body,
              style: TextStyle(
                color: const Color(0xFF1F2937),
                fontSize: sheetContext.rsFont(15),
                fontWeight: FontWeight.w400,
                height: 1.6,
              ),
            ),
            SizedBox(height: sheetContext.rsV(20)),
            Align(
              alignment: Alignment.center,
              child: TextButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: const Text('إغلاق'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

String _formatFullTime(DateTime at) {
  final hour12 = at.hour % 12 == 0 ? 12 : at.hour % 12;
  final minute = at.minute.toString().padLeft(2, '0');
  final day = at.day.toString().padLeft(2, '0');
  final month = at.month.toString().padLeft(2, '0');
  return '$day/$month/${at.year} • $hour12:$minute ${at.hour < 12 ? 'AM' : 'PM'}';
}

class _DetailChip extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;

  const _DetailChip({
    required this.label,
    this.background = const Color(0xFFF3F4F6),
    this.foreground = const Color(0xFF374151),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: context.rs(12),
        vertical: context.rsV(4),
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(context.rs(999)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: context.rsFont(12),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DetailsMedia extends StatelessWidget {
  final AppNotification notification;

  const _DetailsMedia({required this.notification});

  @override
  Widget build(BuildContext context) {
    final url = notification.mediaUrl;
    if (notification.mediaType == 'none' ||
        url == null ||
        url.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.only(bottom: context.rsV(16)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(context.rs(16)),
        child: Image.network(
          url,
          width: double.infinity,
          height: context.rsV(200),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              const SizedBox.shrink(),
        ),
      ),
    );
  }
}
