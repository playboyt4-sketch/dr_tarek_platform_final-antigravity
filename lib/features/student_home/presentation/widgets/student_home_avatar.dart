import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/user_avatar.dart';

// ---------------------------------------------------------------------------
// Figma-exact student header avatar (Student - home cluster + avatar
// system node 190-556). Raw dev-mode values, scaled via rs()/rsV()/rsFont():
// identical to Figma at the 393x852 reference.
//
// Geometry (design px):
//   cluster   56x77 slot: 56 photo circle + 21 badge slot (no outer panel —
//             the dev-mode glass frame around the cluster is intentionally
//             omitted per owner request)
//   photo     56x56 circle, gradient (0.16,-0.09)->(0.84,1.09)
//             white 28% -> 4%, r28, 1px white 45% ring, photo cover.
//             (The dev-mode halo shadow around the circle is intentionally
//             omitted per owner request.)
//   badge     52.75x21 slot, pill at top -9 (9px overlap): padding h13 v4,
//             gradient (0.11,-0.20)->(0.89,1.20), 1px white 40% border,
//             r999, shadow black 55% blur 16 offset (0,8) spread -6,
//             label 10.5 w800 letterSpacing 0.30 white
//
// Badge fill per plan (avatar system): guest uses the Figma blues
// (#6FC3FF -> #3D8FE0 @94%); dr/admin/free/pro/max reuse the shared
// AppColors badge pairs so the system stays single-sourced.
// ---------------------------------------------------------------------------
class StudentHomeAvatar extends StatelessWidget {
  final String? photoUrl;
  final UserAvatarBadge badge;
  final String? semanticLabel;

  const StudentHomeAvatar({
    required this.badge,
    this.photoUrl,
    this.semanticLabel,
    super.key,
  });

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
      UserAvatarBadge.pro => (
        'PRO',
        (AppColors.avatarBadgeProStart, AppColors.avatarBadgeProEnd),
      ),
      UserAvatarBadge.max => (
        'MAX',
        (AppColors.avatarBadgeMaxStart, AppColors.avatarBadgeMaxEnd),
      ),
      // Figma dev-mode gradient (0xEF = 94% alpha).
      UserAvatarBadge.guest => (
        'GUEST',
        (const Color(0xEF6FC3FF), const Color(0xEF3D8FE0)),
      ),
    };

    return Semantics(
      label: semanticLabel ?? label,
      image: photoUrl?.isNotEmpty == true,
      child: SizedBox(
        width: context.rs(56),
        height: context.rsV(77),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _PhotoCircle(photoUrl: photoUrl),
            SizedBox(
              width: context.rs(52.75),
              height: context.rsV(21),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    top: context.rsV(-9),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: context.rs(13),
                        vertical: context.rsV(4),
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: const Alignment(0.11, -0.20),
                          end: const Alignment(0.89, 1.20),
                          colors: [colors.$1, colors.$2],
                        ),
                        borderRadius: BorderRadius.circular(
                          context.rs(999),
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.40),
                          width: 1,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x8C000000),
                            blurRadius: 16,
                            offset: Offset(0, 8),
                            spreadRadius: -6,
                          ),
                        ],
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: context.rsFont(10.50),
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.30,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoCircle extends StatelessWidget {
  final String? photoUrl;

  const _PhotoCircle({required this.photoUrl});

  @override
  Widget build(BuildContext context) {
    // Uniform circle scale: width AND height from the same factor so the
    // 56 circle + 21 badge slot always fit the 77 panel — mixing rs() for
    // the diameter with rsV() heights overflowed on short viewports.
    final diameter =
        56.0 * math.min(context.textScale, context.heightScale);
    return SizedBox(
      width: diameter,
      height: diameter,
      child: Stack(
        children: [
          Container(
            width: diameter,
            height: diameter,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: const Alignment(0.16, -0.09),
                end: const Alignment(0.84, 1.09),
                colors: [
                  Colors.white.withValues(alpha: 0.28),
                  Colors.white.withValues(alpha: 0.04),
                ],
              ),
              borderRadius: BorderRadius.circular(context.rs(28)),
            ),
            child: photoUrl?.isNotEmpty == true
                ? Image.network(
                    photoUrl!,
                    width: diameter,
                    height: diameter,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        _Placeholder(diameter: diameter),
                    loadingBuilder: (context, child, progress) =>
                        progress == null
                        ? child
                        : _Placeholder(diameter: diameter),
                  )
                : _Placeholder(diameter: diameter),
          ),
          Container(
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(context.rs(28)),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.45),
                width: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  final double diameter;

  const _Placeholder({required this.diameter});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white.withValues(alpha: 0.05),
      alignment: Alignment.center,
      child: Icon(
        Icons.person_outline,
        size: diameter * 0.52,
        color: Colors.white.withValues(alpha: 0.85),
      ),
    );
  }
}
