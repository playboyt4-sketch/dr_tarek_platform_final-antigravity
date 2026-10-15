import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The ring describes the user's role, independently from the subscription badge.
enum UserAvatarRole {
  doctor,
  admin,
  studentExternal,
  studentInternal;

  factory UserAvatarRole.fromAuthValues(String role, String? studentType) {
    if (role == 'doctor') return UserAvatarRole.doctor;
    if (role == 'admin') return UserAvatarRole.admin;
    return studentType == 'internal' ||
            studentType == 'center' ||
            studentType == 'سنتر'
        ? UserAvatarRole.studentInternal
        : UserAvatarRole.studentExternal;
  }
}

enum UserAvatarBadge { dr, admin, free, pro, max, guest }

class UserAvatar extends StatelessWidget {
  final String? photoUrl;
  final UserAvatarRole role;
  final UserAvatarBadge? planBadge;
  final double size;
  final String? semanticLabel;

  const UserAvatar({
    required this.role,
    this.photoUrl,
    this.planBadge,
    this.size = AppShapes.avatarDiameter,
    this.semanticLabel,
    super.key,
  });

  factory UserAvatar.fromAuthValues({
    required String role,
    required String? studentType,
    required String? photoUrl,
    String? planId,
    double size = AppShapes.avatarDiameter,
    String? semanticLabel,
  }) {
    final parsedRole = UserAvatarRole.fromAuthValues(role, studentType);
    return UserAvatar(
      photoUrl: photoUrl,
      role: parsedRole,
      planBadge: _badgeFor(
        role: role,
        studentType: studentType,
        planId: planId,
      ),
      size: size,
      semanticLabel: semanticLabel,
    );
  }

  /// Public badge resolution for Figma-exact avatar renderers (e.g. the
  /// Student Home header) that draw their own geometry instead of [UserAvatar].
  /// Guest-type students always resolve to [UserAvatarBadge.guest], never free.
  static UserAvatarBadge badgeFor({
    required String role,
    String? studentType,
    String? planId,
  }) => _badgeFor(role: role, studentType: studentType, planId: planId);
  static UserAvatarBadge _badgeFor({
    required String role,
    String? studentType,
    String? planId,
  }) {
    if (role == 'doctor') return UserAvatarBadge.dr;
    if (role == 'admin') return UserAvatarBadge.admin;
    // Guest-type students always show the GUEST badge (never FREE),
    // regardless of any plan record.
    if (studentType?.trim().toLowerCase() == 'guest') {
      return UserAvatarBadge.guest;
    }
    // Canonical plan_key matching mirrors the dashboard
    // (`planDisplayForKey`): keys are `public_free` / `center_free` /
    // `center_pro` / `center_max` — never bare tier names — so matching is
    // by `_tier` suffix, not equality.
    final key = (planId ?? '').trim().toLowerCase();
    if (key.endsWith('_max') || key == 'max' || key == 'maximum') {
      return UserAvatarBadge.max;
    }
    if (key.endsWith('_pro') || key == 'pro') {
      return UserAvatarBadge.pro;
    }
    if (key.endsWith('_guest') || key == 'guest') {
      return UserAvatarBadge.guest;
    }
    // `_free`, bare `free`, and anything unknown render as FREE.
    return UserAvatarBadge.free;
  }

  @override
  Widget build(BuildContext context) {
    final badge = role == UserAvatarRole.doctor
        ? UserAvatarBadge.dr
        : (planBadge ?? UserAvatarBadge.free);
    return Semantics(
      label: semanticLabel ?? badge.name.toUpperCase(),
      image: photoUrl?.isNotEmpty == true,
      child: SizedBox(
        width: size,
        height: size + 12,
        child: Stack(
          alignment: Alignment.topCenter,
          clipBehavior: Clip.none,
          children: [
            CustomPaint(
              size: Size.square(size),
              painter: _AvatarRingPainter(role: role),
              child: Padding(
                padding: const EdgeInsets.all(AppShapes.avatarRingWidth + 1),
                child: ClipOval(
                  child: photoUrl?.isNotEmpty == true
                      ? Image.network(
                          photoUrl!,
                          width: size,
                          height: size,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _Placeholder(size: size),
                        )
                      : _Placeholder(size: size),
                ),
              ),
            ),
            Positioned(
              bottom: AppShapes.avatarBadgeBottomOffset,
              child: _AvatarBadge(badge: badge),
            ),
          ],
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  final double size;

  const _Placeholder({required this.size});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.avatarGlass,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.person_outline,
        size: size * .52,
        color: Colors.white.withValues(alpha: .9),
      ),
    );
  }
}

class _AvatarBadge extends StatelessWidget {
  final UserAvatarBadge badge;

  const _AvatarBadge({required this.badge});

  @override
  Widget build(BuildContext context) {
    final (label, colors) = switch (badge) {
      UserAvatarBadge.dr => (
        'DR',
        (AppColors.avatarBadgeDrStart, AppColors.avatarBadgeDrEnd),
      ),
      UserAvatarBadge.admin => (
        'ADMIN',
        (AppColors.avatarBadgeAdminStart, AppColors.avatarBadgeAdminEnd),
      ),
      UserAvatarBadge.free => (
        'FREE',
        (AppColors.avatarBadgeFreeStart, AppColors.avatarBadgeFreeEnd),
      ),
      // Guest badge shares the blue family (Figma: #6FC3FF → #3D8FE0
      // gradient, white 40% stroke, Cairo 800) — only the label differs
      // from FREE.
      UserAvatarBadge.guest => (
        'GUEST',
        (AppColors.avatarBadgeFreeStart, AppColors.avatarBadgeFreeEnd),
      ),
      UserAvatarBadge.pro => (
        'PRO',
        (AppColors.avatarBadgeProStart, AppColors.avatarBadgeProEnd),
      ),
      UserAvatarBadge.max => (
        'MAX',
        (AppColors.avatarBadgeMaxStart, AppColors.avatarBadgeMaxEnd),
      ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppShapes.radiusCircular),
        gradient: LinearGradient(colors: [colors.$1, colors.$2]),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppShapes.avatarBadgeHorizontalPadding,
          vertical: AppShapes.avatarBadgeVerticalPadding,
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}

class _AvatarRingPainter extends CustomPainter {
  final UserAvatarRole role;

  const _AvatarRingPainter({required this.role});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius =
        math.min(size.width, size.height) / 2 - AppShapes.avatarRingWidth;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = AppShapes.avatarRingWidth
      ..color = switch (role) {
        UserAvatarRole.doctor => AppColors.avatarTeacherRing,
        UserAvatarRole.admin => AppColors.avatarAdminRing,
        UserAvatarRole.studentExternal => AppColors.avatarExternalRing,
        UserAvatarRole.studentInternal => AppColors.avatarInternalRing,
      };
    final glow = role == UserAvatarRole.studentExternal
        ? null
        : (paint..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    if (glow != null) canvas.drawCircle(center, radius, glow);
    paint.maskFilter = null;
    if (role == UserAvatarRole.doctor) {
      canvas.drawCircle(center, radius, paint);
    } else {
      final path = Path()
        ..addOval(Rect.fromCircle(center: center, radius: radius));
      final dashed = role == UserAvatarRole.admin;
      for (final metric in path.computeMetrics()) {
        var distance = 0.0;
        while (distance < metric.length) {
          final segment = dashed ? 7.0 : 1.8;
          final gap = dashed ? 4.0 : 4.0;
          canvas.drawPath(
            metric.extractPath(
              distance,
              math.min(distance + segment, metric.length),
            ),
            paint,
          );
          distance += segment + gap;
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AvatarRingPainter oldDelegate) =>
      oldDelegate.role != role;
}
