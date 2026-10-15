import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../authentication/domain/entities/auth_user.dart';
import '../../../profile/presentation/screens/student_profile_screen.dart';
import '../../../student_dashboard/domain/entities/dashboard_subject.dart';
import '../../../student_dashboard/presentation/providers/dashboard_providers.dart';
import '../../../notifications/presentation/providers/notifications_providers.dart';
import '../../../notifications/presentation/screens/notifications_list_screen.dart';
import '../../../subject_navigation/presentation/screens/subject_navigation_screen.dart';
import '../../../subject_navigation/presentation/providers/subject_navigation_providers.dart';
import '../widgets/student_home_avatar.dart';

// ---------------------------------------------------------------------------
// Design constants for "Student - home" (Figma node 134-697).
// Raw design-pixel values from Figma dev mode, consumed via context.rs() /
// context.rsV() / context.rsFont() — identical to Figma at the 393x852
// reference, proportionally preserved elsewhere.
//
// Frame map (dev mode paste):
//   canvas    393x852  grade-4-bg-canvas #DC2626 (dynamic per grade:
//             grade-1 #F59E0B, grade-2 #1D4ED8, grade-3 #15803D,
//             grade-4 #DC2626 — AppColors gradeXCanvas tokens)
//   avatar    169,63   56x77 cluster (56 circle + pill badge overlapping -9)
//   greeting  130,147  133x23 "Hi, {first}" Inter 600 16 #FFFCF7 centered
//   carousel  0,169    393x500: center card 47,50(rel) 300x400 r24
//             1px white 30%; side cards 260x340 opacity 0.60;
//             title 75,456(rel) 243x35 white 28/36 centered
//   bottombar 87,757   220x60 pill: fill #999999@17% r1000; tabs 104x52
//             (active white 15% r28, icon 20 + label 12; inactive label
//             black per Figma)
// The simulated OS status bar ("9:41", 0-50 chrome) is NOT reproduced.
//
// Covers are remote URLs (poster_url set with the subject name from the
// dashboard) — never bundled assets: Image.network with a glass
// placeholder fallback.
// ---------------------------------------------------------------------------
abstract final class _StudentHomeDesign {
  static const avatarTop = 63.0;

  static const cardWidth = 300.0;
  static const cardRadius = 24.0;
  static const cardBorder = Color(0x4DFFFFFF); // 30% white

  static const barWidth = 220.0;
  static const barHeight = 60.0;
  static const barFill = Color(0x2B999999);
  static const tabActiveFill = Color(0x26FFFFFF); // 15% white
}

/// Student Home — the landing screen after a successful student login.
///
/// Subjects come from [dashboardSubjectsProvider]; the bottom pill switches
/// between Home (Figma cover carousel) and Notifications (embedded list).
class StudentHomeScreen extends ConsumerStatefulWidget {
  final AuthUser user;

  const StudentHomeScreen({required this.user, super.key});

  @override
  ConsumerState<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends ConsumerState<StudentHomeScreen> {
  int _currentTab = 0;
  int _currentSubject = 0;

  @override
  void initState() {
    super.initState();
    // Poster warm-up: right after login lands on Home, resolve every
    // subject's lectures + display media and download the image bytes in
    // the background — subject pages then open instantly ("bullet").
    // Fire-and-forget: navigation is never gated on it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(warmUpSubjectMedia(ref, context));
    });
  }

  String get _firstName {
    final parts = widget.user.fullName.trim().split(RegExp(r'\s+'));
    return parts.isEmpty || parts.first.isEmpty
        ? widget.user.fullName
        : parts.first;
  }

  /// Arabic names get an Arabic greeting (RTL); anything else keeps "Hi,".
  bool get _isArabicName =>
      RegExp(r'[\u0600-\u06FF]').hasMatch(_firstName);

  /// Avatar badge follows the CENTERED subject card's plan (free/pro/max
  /// per subject); without subjects it falls back to the student type
  /// (guest students show GUEST, never FREE).
  UserAvatarBadge _currentBadge(List<DashboardSubject>? items) {
    if (items != null && items.isNotEmpty) {
      final safe = _currentSubject.clamp(0, items.length - 1);
      final key = items[safe].planKey?.trim().toLowerCase();
      if (key != null && key.isNotEmpty) {
        return UserAvatar.badgeFor(
          role: widget.user.role,
          planId: key,
        );
      }
    }
    return UserAvatar.badgeFor(
      role: widget.user.role,
      studentType: widget.user.studentType,
    );
  }

  /// Background follows the STUDENT's grade canvas identity tokens
  /// (الفرقة بتاعت الطالب). Unknown grades fall back to grade one.
  static Color _gradeBackground(String? grade) {
    final key = _normalizeGradeKey(grade);
    switch (key) {
      case 'grade_two':
        return AppColors.grade2Canvas;
      case 'grade_three':
        return AppColors.grade3Canvas;
      case 'grade_four':
        return AppColors.grade4Canvas;
      default:
        return AppColors.grade1Canvas;
    }
  }

  static String? _normalizeGradeKey(String? raw) {
    if (raw == null) return null;
    final text = raw.trim().toLowerCase();
    if (text.isEmpty) return null;
    const aliases = <String, String>{
      'grade_one': 'grade_one',
      'grade one': 'grade_one',
      'grade_1': 'grade_one',
      'grade 1': 'grade_one',
      '1': 'grade_one',
      'grade_two': 'grade_two',
      'grade two': 'grade_two',
      'grade_2': 'grade_two',
      'grade 2': 'grade_two',
      '2': 'grade_two',
      'grade_three': 'grade_three',
      'grade three': 'grade_three',
      'grade_3': 'grade_three',
      'grade 3': 'grade_three',
      '3': 'grade_three',
      'grade_four': 'grade_four',
      'grade four': 'grade_four',
      'grade_4': 'grade_four',
      'grade 4': 'grade_four',
      '4': 'grade_four',
    };
    if (aliases.containsKey(text)) return aliases[text];
    final folded = text
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ى', 'ي');
    if (folded.contains('اول') || folded.contains('one')) {
      return 'grade_one';
    }
    if (folded.contains('ثان') || folded.contains('two')) {
      return 'grade_two';
    }
    if (folded.contains('ثال') || folded.contains('three')) {
      return 'grade_three';
    }
    if (folded.contains('راب') || folded.contains('four')) {
      return 'grade_four';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final subjectsAsync = ref.watch(dashboardSubjectsProvider);
    final subjects = subjectsAsync.value;

    return Scaffold(
      backgroundColor: _gradeBackground(widget.user.grade),
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(height: context.rsV(_StudentHomeDesign.avatarTop)),
            // Avatar cluster (Figma 169,63 56x77): glass photo circle +
            // plan pill badge (avatar system node 190-556). The badge
            // follows the centered subject card's plan. Tapping the
            // avatar opens the Student - Profile screen (Figma 58258:1800).
            Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        StudentProfileScreen(user: widget.user),
                  ),
                ),
                child: Semantics(
                  button: true,
                  label: 'الملف الشخصي',
                  child: Tooltip(
                    message: 'الملف الشخصي',
                    child: StudentHomeAvatar(
                      badge: _currentBadge(subjects),
                      photoUrl: widget.user.profilePhoto,
                      semanticLabel: 'صورة ${widget.user.fullName}',
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: context.rsV(7)),
            // Greeting (Figma y147, 600 16 #FFFCF7 centered —
            // "Hi," for Latin names, "هاي،" (RTL) for Arabic names).
            Text(
              _isArabicName ? 'هاي، $_firstName' : 'Hi, $_firstName',
              textAlign: TextAlign.center,
              textDirection: _isArabicName
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              style: TextStyle(
                color: const Color(0xFFFFFCF7),
                fontSize: context.rsFont(16),
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: context.rsV(8)),
            // Tab content fills to the screen bottom; the pill nav floats
            // OVER it (Figma prototype) instead of docking below it.
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: switch (_currentTab) {
                      0 => _CarouselTab(
                        subjectsAsync: subjectsAsync,
                        currentSubject: subjects == null || subjects.isEmpty
                            ? 0
                            : _currentSubject.clamp(0, subjects.length - 1),
                        onPageChanged: (index) =>
                            setState(() => _currentSubject = index),
                        onOpen: (subject) => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => SubjectNavigationScreen(
                              subject: subject,
                              grade: widget.user.grade,
                            ),
                          ),
                        ),
                      ),
                      _ => NotificationsScreen(
                        studentId: widget.user.id,
                        embedded: true,
                      ),
                    },
                  ),
                  // Bottom pill (Figma 87,757 220x60 r1000) floating over
                  // the content with a 24 clearance to the screen edge.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: context.rsV(24),
                    child: Center(
                      child: _BottomPill(
                        currentTab: _currentTab,
                        studentId: widget.user.id,
                        onSelect: (index) =>
                            setState(() => _currentTab = index),
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

/// Home tab: swipeable cover carousel (Figma 0,169 393x500) with the
/// centered subject title below (white 28) and a dots indicator.
///
/// Sizing is continuous: the centered card renders at scale 1.0 and side
/// cards at 0.86 (Figma 260/300) with 0.6 opacity, interpolated from the
/// live page offset — the centered card is always the biggest.
class _CarouselTab extends ConsumerStatefulWidget {
  final AsyncValue<List<DashboardSubject>> subjectsAsync;
  final int currentSubject;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<DashboardSubject> onOpen;

  const _CarouselTab({
    required this.subjectsAsync,
    required this.currentSubject,
    required this.onPageChanged,
    required this.onOpen,
  });

  @override
  ConsumerState<_CarouselTab> createState() => _CarouselTabState();
}

class _CarouselTabState extends ConsumerState<_CarouselTab> {
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageController(
      viewportFraction:
          _StudentHomeDesign.cardWidth / kDesignWidth, // ~0.764
      initialPage: widget.currentSubject,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.subjectsAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
      error: (error, stackTrace) {
        // Debug-only diagnostics: release builds keep the generic card.
        if (kDebugMode) {
          debugPrint('dashboardSubjectsProvider failed: $error');
          debugPrint('$stackTrace');
        }
        return Center(
          child: _HomeMessageCard(
            message: 'تعذر تحميل المواد حالياً',
            actionLabel: 'إعادة المحاولة',
            onAction: () => ref.invalidate(dashboardSubjectsProvider),
          ),
        );
      },
      data: (items) {
        if (items.isEmpty) {
          return const Center(
            child: _HomeMessageCard(
              message:
                  'لا توجد مواد مفعّلة لك حالياً.\nستظهر هنا بعد تفعيل وصولك من الإدارة.',
            ),
          );
        }
        final safeIndex = widget.currentSubject.clamp(0, items.length - 1);
        return LayoutBuilder(
          builder: (context, constraints) {
            final pageWidth =
                constraints.maxWidth *
                (_StudentHomeDesign.cardWidth / kDesignWidth);
            final cardHeight = constraints.maxHeight.isFinite
                ? (constraints.maxHeight - context.rsV(110))
                      .clamp(200.0, 420.0)
                : 380.0;
            return Column(
              children: [
                SizedBox(
                  height: cardHeight,
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: items.length,
                    onPageChanged: widget.onPageChanged,
                    itemBuilder: (context, index) {
                      return AnimatedBuilder(
                        animation: _controller,
                        builder: (context, child) {
                          double distance;
                          if (_controller.hasClients &&
                              _controller
                                      .position
                                      .hasContentDimensions &&
                              _controller.page != null) {
                            distance = (_controller.page! - index).abs().clamp(
                              0.0,
                              1.0,
                            );
                          } else {
                            distance = index == safeIndex ? 0.0 : 1.0;
                          }
                          final scale = 1 - distance * 0.14;
                          final opacity = 1 - distance * 0.4;
                          return Center(
                            child: Opacity(
                              opacity: opacity,
                              child: Transform.scale(
                                scale: scale,
                                child: SizedBox(
                                  width: pageWidth - context.rs(12),
                                  height: cardHeight,
                                  child: _CoverCard(
                                    subject: items[index],
                                    onTap: index == safeIndex
                                        ? () => widget.onOpen(items[index])
                                        : () => _controller.animateToPage(
                                            index,
                                            duration: const Duration(
                                              milliseconds: 300,
                                            ),
                                            curve: Curves.easeOut,
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                SizedBox(height: context.rsV(12)),
                // Centered subject title (Figma white 28/36).
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: context.rs(24)),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Text(
                      items[safeIndex].title,
                      key: ValueKey(items[safeIndex].id),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.titleLarge(
                        context,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: context.rsV(8)),
                // Dots: one per subject, the centered card's dot highlighted.
                // Tapping a dot jumps to its card.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (int i = 0; i < items.length; i++)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _controller.animateToPage(
                          i,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        ),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: context.rs(i == safeIndex ? 16 : 8),
                          height: context.rs(8),
                          margin: EdgeInsets.symmetric(
                            horizontal: context.rs(3),
                          ),
                          decoration: BoxDecoration(
                            color: i == safeIndex
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(
                              context.rs(4),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                SizedBox(height: context.rsV(4)),
                // Clearance for the floating pill (60 pill + 24 margin).
                SizedBox(height: context.rsV(88)),
              ],
            );
          },
        );
      },
    );
  }
}

/// Center/side cover card (Figma 300x400 / 260x340 r24, 1px white 30%).
/// The cover is the dashboard `poster_url` link; a glass placeholder shows
/// while loading, on error, or when the subject has no cover.
class _CoverCard extends StatelessWidget {
  final DashboardSubject subject;
  final VoidCallback onTap;

  const _CoverCard({required this.subject, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final url = subject.thumbnailUrl;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(
        context.rs(_StudentHomeDesign.cardRadius),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(
          context.rs(_StudentHomeDesign.cardRadius),
        ),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(
              context.rs(_StudentHomeDesign.cardRadius),
            ),
            border: Border.all(
              color: _StudentHomeDesign.cardBorder,
              width: 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(
              context.rs(_StudentHomeDesign.cardRadius),
            ),
            child: url == null
                ? const _CoverPlaceholder()
                : Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const _CoverPlaceholder(),
                    loadingBuilder: (context, child, progress) =>
                        progress == null
                        ? child
                        : const _CoverPlaceholder(),
                  ),
          ),
        ),
      ),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white.withValues(alpha: 0.10),
      alignment: Alignment.center,
      child: Icon(
        Icons.image_outlined,
        size: context.rs(48),
        color: Colors.white.withValues(alpha: 0.7),
      ),
    );
  }
}

/// Bottom pill nav (Figma 220x60 r1000, fill #999999@17%): Home (active
/// white 15% pill) + Notifications (inactive black label per Figma).
class _BottomPill extends StatelessWidget {
  final int currentTab;
  final String studentId;
  final ValueChanged<int> onSelect;

  const _BottomPill({
    required this.currentTab,
    required this.studentId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: context.rs(_StudentHomeDesign.barWidth),
      height: context.rsV(_StudentHomeDesign.barHeight),
      decoration: BoxDecoration(
        color: _StudentHomeDesign.barFill,
        borderRadius: BorderRadius.circular(1000),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 15,
            offset: Offset(0, 8),
          ),
        ],
      ),
      padding: EdgeInsets.symmetric(
        horizontal: context.rs(4),
        vertical: context.rsV(4),
      ),
      child: Row(
        children: [
          Expanded(
            child: _PillTab(
              selected: currentTab == 0,
              icon: currentTab == 0
                  ? Icons.home_rounded
                  : Icons.home_outlined,
              label: 'Home',
              onTap: () => onSelect(0),
            ),
          ),
          SizedBox(width: context.rs(4)),
          Expanded(
            child: _PillTab(
              selected: currentTab == 1,
              icon: Icons.notifications_none_rounded,
              label: 'Notifications',
              badge: _NotificationsIconBadge(
                studentId: studentId,
                color: currentTab == 1 ? Colors.white : Colors.black,
              ),
              onTap: () => onSelect(1),
            ),
          ),
        ],
      ),
    );
  }
}

class _PillTab extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final Widget? badge;
  final VoidCallback onTap;

  const _PillTab({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : Colors.black;
    return Material(
      color: selected
          ? _StudentHomeDesign.tabActiveFill
          : Colors.transparent,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: context.rs(20),
              height: context.rs(20),
              child: badge ??
                  Icon(icon, size: context.rs(20), color: foreground),
            ),
            SizedBox(height: context.rsV(2)),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: context.rsFont(12),
                fontWeight: FontWeight.w400,
                height: 1.33,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bell icon with a live unread-notifications count dot for the pill tab.
class _NotificationsIconBadge extends ConsumerWidget {
  final String studentId;
  final Color color;

  const _NotificationsIconBadge({
    required this.studentId,
    this.color = Colors.black,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(userUnreadNotificationsCountProvider(studentId));
    final count = unread.value ?? 0;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Icon(
          Icons.notifications_none_rounded,
          size: 20,
          color: color,
        ),
        if (count > 0)
          Positioned(
            top: -4,
            right: -8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(8),
              ),
              constraints: const BoxConstraints(minWidth: 15),
              child: Text(
                count > 99 ? '99+' : '$count',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _HomeMessageCard extends StatelessWidget {
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _HomeMessageCard({
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppShapes.radiusXLarge),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.onSurface),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.sm),
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Streams the plan key of the student's first active subscription so the
/// avatar badge reflects the real plan (guest / free / pro / max).
final studentPlanKeyProvider =
    FutureProvider.family<String?, String>((ref, studentId) async {
      final snapshot = await FirebaseFirestore.instance
          .collection('subscriptions')
          .where('student_id', isEqualTo: studentId)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();
      if (snapshot.docs.isEmpty) return null;
      final planId = snapshot.docs.first.data()['plan_id'];
      if (planId is! String || planId.isEmpty) return null;
      final plan = await FirebaseFirestore.instance
          .collection('plans')
          .doc(planId)
          .get();
      final key = plan.data()?['plan_key'];
      return key is String ? key : null;
    });
