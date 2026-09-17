import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../applications/domain/grade.dart';
import '../../../students/presentation/providers/subject_details_provider.dart';
import '../../../students/presentation/widgets/add_lecture_overlay.dart';
import '../providers/home_stats_provider.dart';
import '../widgets/quick_announcement_dialog.dart';

/// Figma reference constants (`dashboard - home`, 1280 x 800) that have no
/// live source yet: weekly activity curve + grade accent colors.
abstract final class HomeFigmaData {
  static const int totalStudents = 1240;
  static const int activeToday = 240;

  /// Weekly activity curve: starts at 100, peaks 240 on Friday.
  static const List<double> weeklyActivity = <double>[
    100, 130, 150, 170, 190, 210, 240,
  ];

  static const List<String> weekDays = <String>[
    'Sat', 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri',
  ];

  static const List<int> yTicks = <int>[80, 120, 160, 200, 220, 240];
}

/// Accent color per canonical grade key (matches the pie sectors).
Color accentForGrade(String gradeKey) {
  return switch (gradeKey) {
    'grade_one' => AppColors.gradeOne,
    'grade_two' => AppColors.gradeTwo,
    'grade_three' => AppColors.gradeThree,
    'grade_four' => AppColors.gradeFour,
    _ => AppColors.headingInk,
  };
}

class GradeBreakdown {
  final String title;
  final int total;
  final int pending;
  final int center;
  final String centerShare;
  final int guest;
  final String guestShare;
  final Color accent;

  const GradeBreakdown({
    required this.title,
    required this.total,
    required this.pending,
    required this.center,
    required this.centerShare,
    required this.guest,
    required this.guestShare,
    required this.accent,
  });

  factory GradeBreakdown.fromAnalytics(GradeAnalytics analytics) {
    return GradeBreakdown(
      title: gradeAnalyticsTitle(analytics.gradeKey),
      total: analytics.total,
      pending: analytics.pending,
      center: analytics.center,
      centerShare: analytics.centerShareLabel,
      guest: analytics.guest,
      guestShare: analytics.guestShareLabel,
      accent: accentForGrade(analytics.gradeKey),
    );
  }
}

/// Dashboard home (`dashboard - home`, 1280 x 800, white, 80 px margins).
///
/// - header: brand 540 x 80 at X 370 / Y 24, Google Sans Flex 48
///   (400 + 100). The unified [DashboardShell] draws the single fixed
///   menu button at (80, 24, 80 x 80); this screen only reserves the
///   80 + 210 spacer so the brand never shifts a pixel;
/// - middle (Y 136): pie card 250 x 304 + four grade cards 395 x 140
///   in a 2 x 2 grid, driven by [homeAnalyticsProvider] with the Figma
///   fallback while the database is still getting started;
/// - bottom (Y 472): upload 250 x 210 + announcement 250 x 210 +
///   activity 537 x 306. The two pills open functional quick-action
///   dialogs (upload lecture / broadcast announcement).
///
/// [onMenuPressed] is kept for API compatibility but ignored — the
/// shell's fixed top-layer button owns open/close. [onNavigate]
/// optionally routes grade cards.
class DashboardHomeScreen extends ConsumerWidget {
  final VoidCallback? onMenuPressed;
  final ValueChanged<String>? onNavigate;

  const DashboardHomeScreen({
    super.key,
    this.onMenuPressed,
    this.onNavigate,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Centered 1280 canvas → 1120 content ⇒ 80 px offset each side.
    // Inner left padding is 0 so the pie card (top) and the upload card
    // (bottom) both start at canvas X: 80px, exactly under the shell's
    // fixed menu button at left: 80, top: 24, 80 x 80.
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 24, 0, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _HomeHeader(),
                // 24 + 80 = 104; gap 32 → analytics Y 136.
                const SizedBox(height: 32),
                const _TopAnalytics(),
                // 136 + 304 = 440; gap 32 → bottom Y 472.
                const SizedBox(height: 32),
                const _BottomSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- header

class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) {
    // Centered-canvas geometry (shell provides fixed 1280 x 800,
    // centered): content is 1120 wide → 80 px centering offset on each
    // side. Header is 80 (shell button spacer) + 210 (gap) + 540
    // (brand) = 830. Brand X = 80 (centering) + 80 + 210 = 370,
    // Y = 24 (outer padding) — matches the unified (370, 24) in all
    // fixed-canvas screens. No outer left margin is added here so the
    // shell's centering is never pushed left.
    // Both the gap and the brand flex down proportionally on narrow
    // viewports (e.g. 811 px with DevTools open) so the Row never
    // overflows; at full width the 210/540 caps restore exact positions.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Spacer matching the shell's fixed button: X 80 / Y 24, 80 x 80.
        const SizedBox(width: 80, height: 80),
        // 80 + 80 = 160; gap 210 → logo X 370.
        Flexible(
          flex: 210,
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: 210, minWidth: 8),
            child: const SizedBox(width: double.infinity, height: 80),
          ),
        ),
        // 540 x 80 brand, 48 px, scales down gracefully when squeezed.
        Flexible(
          flex: 540,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: SizedBox(
              height: 80,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text.rich(
                  TextSpan(
                    children: <TextSpan>[
                      TextSpan(
                        text: 'Tarek el araby ',
                        style: AppTypography.homeBrandHeavy(fontSize: 48),
                      ),
                      TextSpan(
                        text: 'Platform',
                        style: AppTypography.homeBrandLight(fontSize: 48),
                      ),
                    ],
                  ),
                  maxLines: 1,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------- top analytics

class _TopAnalytics extends ConsumerWidget {
  const _TopAnalytics();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<HomeAnalytics> analyticsAsync =
        ref.watch(homeAnalyticsProvider);
    return analyticsAsync.when(
      // Fixed-size skeleton keeps the 1280 x 800 geometry stable.
      loading: () => const _TopAnalyticsSkeleton(),
      // The screen always stays full and beautiful.
      error: (Object error, StackTrace stackTrace) =>
          _TopAnalyticsContent(analytics: HomeAnalytics.fallback()),
      data: (HomeAnalytics analytics) =>
          _TopAnalyticsContent(analytics: analytics),
    );
  }
}

class _TopAnalyticsSkeleton extends StatelessWidget {
  const _TopAnalyticsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 30,
      runSpacing: 24,
      crossAxisAlignment: WrapCrossAlignment.start,
      children: <Widget>[
        Container(
          width: 250,
          height: 304,
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        SizedBox(
          width: 810,
          child: Wrap(
            spacing: 20,
            runSpacing: 24,
            children: <Widget>[
              for (int i = 0; i < 4; i++)
                Container(
                  width: 395,
                  height: 140,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TopAnalyticsContent extends StatelessWidget {
  final HomeAnalytics analytics;

  const _TopAnalyticsContent({required this.analytics});

  @override
  Widget build(BuildContext context) {
    final List<GradeBreakdown> grades = <GradeBreakdown>[
      for (final grade in analytics.grades)
        GradeBreakdown.fromAnalytics(grade),
    ];
    return Wrap(
      spacing: 30,
      runSpacing: 24,
      crossAxisAlignment: WrapCrossAlignment.start,
      children: <Widget>[
        // Pie chart card: first in the Wrap at content X: 0
        // ⇒ canvas X: 80px, same vertical line as the menu button
        // and the upload card. # Frame 42: 250 x 304, radius 28.
        Container(
          width: 250,
          height: 304,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppColors.inputStroke, width: 1),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _PieChart(analytics: analytics),
              const SizedBox(height: 8),
              _PieTotal(total: analytics.totalStudents),
            ],
          ),
        ),
        // 2 x 2 grade grid: 395 x 140 each (790 + 304 + gaps ≈ 1120).
        SizedBox(
          width: 810,
          child: Wrap(
            spacing: 20,
            runSpacing: 24,
            children: <Widget>[
              for (final grade in grades) _GradeCard(data: grade),
            ],
          ),
        ),
      ],
    );
  }
}

class _PieChart extends StatelessWidget {
  final HomeAnalytics analytics;

  const _PieChart({required this.analytics});

  int _countFor(String gradeKey) {
    for (final GradeAnalytics grade in analytics.grades) {
      if (grade.gradeKey == gradeKey) return grade.total;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    // Reference diameter 242; rendered slightly smaller so the total
    // caption below still fits the 304 card.
    const double size = 200;

    // Real per-grade student counts (100% dynamic, no fixed shares).
    final int gradeOneCount = _countFor('grade_one');
    final int gradeTwoCount = _countFor('grade_two');
    final int gradeThreeCount = _countFor('grade_three');
    final int gradeFourCount = _countFor('grade_four');
    final int total =
        gradeOneCount + gradeTwoCount + gradeThreeCount + gradeFourCount;

    // a) No students → empty circle, no colored sectors, no % labels.
    if (total == 0) {
      return SizedBox(
        width: size,
        height: size,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFF9FAFB),
            border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
          ),
        ),
      );
    }

    // b) Real students → one sector per grade that actually has students,
    // each keeping its own canonical color and real share.
    const List<Color> gradeColors = <Color>[
      Color(0xFFF59E0B), // grade_one (yellow)
      Color(0xFF1D4ED8), // grade_two (blue)
      Color(0xFF15803D), // grade_three (green)
      Color(0xFFDC2626), // grade_four (red)
    ];
    final List<int> counts = <int>[
      gradeOneCount,
      gradeTwoCount,
      gradeThreeCount,
      gradeFourCount,
    ];

    final List<double> fractions = <double>[];
    final List<Color> colors = <Color>[];
    final List<String> labels = <String>[];
    for (int i = 0; i < counts.length; i++) {
      final int gradeCount = counts[i];
      if (gradeCount <= 0) continue;
      final double sweepAngle = (gradeCount / total) * 2 * math.pi;
      final int percentage = (gradeCount / total * 100).round();
      fractions.add(sweepAngle / (2 * math.pi));
      colors.add(gradeColors[i]);
      labels.add('$percentage%');
    }

    double cumulative = -math.pi / 2;
    final List<_PieLabel> labelsPos = <_PieLabel>[];
    for (int i = 0; i < fractions.length; i++) {
      final double mid = cumulative + fractions[i] * math.pi;
      labelsPos.add(
        _PieLabel(
          alignment: Alignment(
            math.cos(mid) * 0.55,
            math.sin(mid) * 0.55,
          ),
          text: labels[i],
        ),
      );
      cumulative += fractions[i] * 2 * math.pi;
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: <Widget>[
          CustomPaint(
            size: const Size(size, size),
            painter: _PiePainter(fractions: fractions, colors: colors),
          ),
          for (final label in labelsPos)
            Align(
              alignment: label.alignment,
              child: Text(
                label.text,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PieLabel {
  final Alignment alignment;
  final String text;

  const _PieLabel({required this.alignment, required this.text});
}

class _PiePainter extends CustomPainter {
  final List<double> fractions;
  final List<Color> colors;

  const _PiePainter({required this.fractions, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    // Empty state is handled by [_PieChart] (light circle widget), so
    // nothing is painted here when there are no sectors.
    if (fractions.isEmpty || colors.isEmpty) return;
    final Offset center = size.center(Offset.zero);
    final double radius = size.shortestSide / 2;
    double start = -math.pi / 2;
    for (int i = 0; i < fractions.length; i++) {
      final double sweep = fractions[i] * 2 * math.pi;
      if (sweep <= 0) continue;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep,
        true,
        Paint()..color = colors[i % colors.length],
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _PiePainter oldDelegate) =>
      oldDelegate.fractions != fractions || oldDelegate.colors != colors;
}

class _PieTotal extends StatelessWidget {
  final int total;

  const _PieTotal({required this.total});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Frame 40.
        Text('Total Students', style: AppTypography.totalCaption()),
        Text('$total', style: AppTypography.totalValue()),
      ],
    );
  }
}

class _GradeCard extends StatelessWidget {
  final GradeBreakdown data;

  const _GradeCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 395,
      height: 140,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: data.accent, width: 1.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(data.title, style: AppTypography.gradeTitle()),
                const SizedBox(height: 8),
                Text('Total Students', style: AppTypography.gradeLabel()),
                Text('${data.total}', style: AppTypography.gradeValue()),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text('Pending ${data.pending}',
                  style: AppTypography.gradeLabel()),
              const SizedBox(height: 6),
              Text('Center ${data.center} (${data.centerShare})',
                  style: AppTypography.gradeValue(fontSize: 13)),
              const SizedBox(height: 6),
              Text('Guest ${data.guest} (${data.guestShare})',
                  style: AppTypography.gradeValue(fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------- bottom

class _BottomSection extends ConsumerWidget {
  const _BottomSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Fixed 1120 split: 250 + 24 + 250 + 24 + remainder. Each card clips
    // its own content, so announcement text can never bleed into the
    // activity chart.
    return SizedBox(
      width: 1120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _QuickActionCard(
            icon: SvgPicture.asset(
              'assets/images/Upload.svg',
              width: 24,
              height: 24,
              semanticsLabel: 'Upload icon',
            ),
            title: 'Quick Upload',
            description: 'Add new video, PDFs & assign to grades',
            buttonText: '+ Upload Now',
            onTap: () => _openQuickAdd(context),
          ),
          const SizedBox(width: 24),
          _QuickActionCard(
            icon: SvgPicture.asset(
              'assets/images/notifications.svg',
              width: 24,
              height: 24,
              semanticsLabel: 'Notifications icon',
            ),
            title: 'Send Announcement',
            description: 'Broadcast notifications to students',
            buttonText: 'Send Notice ->',
            onTap: () => showQuickAnnouncementDialog(context),
          ),
          const SizedBox(width: 24),
          const Expanded(
            child: _StudentActivityCard(),
          ),
        ],
      ),
    );
  }

  /// Figma prototype: `+ Upload Now` opens the Quick Add New Lecture
  /// overlay (node 886-980) directly. Grade/Subject/Section selection
  /// lives inside that overlay; there is no intermediate picker.
  Future<void> _openQuickAdd(BuildContext context) async {
    final String gradeKey = canonicalGradeKeys.first;
    await AddLectureOverlay.show(
      context,
      subjectId: '',
      gradeKey: gradeKey,
      tab: SubjectContentTab.lectures,
      initialOrder: 1,
      gradeColor: accentForGrade(gradeKey),
    );
  }
}

/// Unified quick-action card (250 x 210) used for both Quick Upload
/// and Send Announcement.
///
/// Single `Column` geometry so both buttons sit at the exact same
/// vertical offset: icon 24x24 → gap 12 → title → gap 6 → description
/// → gap 16 → pill button. No `Stack`/`Positioned`, no per-card gaps.
class _QuickActionCard extends StatelessWidget {
  final Widget icon;
  final String title;
  final String description;
  final String buttonText;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.buttonText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      height: 210,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.actionCardFill,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.actionCardStroke, width: 1.5),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(width: 24, height: 24, child: icon),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              fontVariations: <FontVariation>[FontVariation('wght', 600)],
              color: Colors.black,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w400,
              fontVariations: <FontVariation>[FontVariation('wght', 400)],
              color: Color(0xFF6B7280),
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 16),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onTap,
              child: Semantics(
                button: true,
                label: buttonText,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.pillFill,
                    borderRadius: BorderRadius.circular(9999),
                  ),
                  child: Text(
                    buttonText,
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      fontVariations: <FontVariation>[
                        FontVariation('wght', 400),
                      ],
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StudentActivityCard extends ConsumerWidget {
  const _StudentActivityCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HomeAnalytics analytics =
        ref.watch(homeAnalyticsProvider).maybeWhen(
              data: (HomeAnalytics a) => a,
              orElse: HomeAnalytics.fallback,
            );
    final int activeToday = analytics.activeToday;
    final List<int> weeklyActivity = analytics.weeklyActivity;
    final int maxVal = weeklyActivity.fold(0, math.max);
    final List<int> yTicks = yTicksForMax(maxVal);
    return Container(
      height: 306,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.inputStroke, width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Student Activity',
                        style: AppTypography.chartTitle()),
                    Text('Last 7 days',
                        style: AppTypography.totalCaption()),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text('$activeToday',
                      style: AppTypography.totalValue(fontSize: 28)),
                  const Text(
                    'Active Today',
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 14,
                      color: AppColors.activityGreen,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _ActivityChart(
              weeklyActivity: weeklyActivity,
              activeToday: activeToday,
              yTicks: yTicks,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityChart extends StatelessWidget {
  final List<int> weeklyActivity;
  final int activeToday;
  final List<int> yTicks;

  const _ActivityChart({
    required this.weeklyActivity,
    required this.activeToday,
    required this.yTicks,
  });

  // Grid area height. Ticks are always 6 uniform steps from the ceiling
  // down to 0, so Column(spaceBetween) centers every number exactly on
  // its 1px line — no separate Y widget to drift.
  static const double gridHeight = 180;

  @override
  Widget build(BuildContext context) {
    // No real data → clean quiet grid only, no line at all.
    final bool showCurve =
        activeToday != 0 && weeklyActivity.fold(0, math.max) > 0;
    final int ceiling = yTicks.first;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          height: gridHeight,
          width: double.infinity,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              // 6 uniform rows: number + line pixel-locked in one Row.
              Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  for (final int tick in yTicks)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        SizedBox(
                          width: 36,
                          child: Text(
                            '$tick',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontFamily: 'GoogleSansFlex',
                              fontSize: 12,
                              height: 1.0,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            height: 1,
                            color: const Color(0xFFE5E7EB),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              // Real-data curve over the grid, starting where the grid
              // lines start (X: 48 = 36 number + 12 gap).
              if (showCurve)
                Positioned(
                  left: 48,
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: CustomPaint(
                    painter: _ActivityCurvePainter(
                      values: weeklyActivity,
                      ceiling: ceiling,
                    ),
                    child: Container(),
                  ),
                ),
            ],
          ),
        ),
        // Weekdays fully below the grid, aligned with the lines.
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.only(left: 48),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              for (final day in HomeFigmaData.weekDays)
                Text(
                  day,
                  style: const TextStyle(
                    fontFamily: 'GoogleSansFlex',
                    fontSize: 12,
                    height: 1.0,
                    color: Color(0xFF6B7280),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Dynamic curve painter: smooth cubic-bezier black curve (2.5px,
/// #111827) + Friday end dot, mapped onto the auto-scaled grid
/// (0 at the bottom row … ceiling at the top row).
class _ActivityCurvePainter extends CustomPainter {
  final List<int> values;
  final int ceiling;

  const _ActivityCurvePainter({
    required this.values,
    required this.ceiling,
  });

  Offset _pointAt(int i, Size size) {
    final double x = values.length == 1
        ? size.width / 2
        : i * size.width / (values.length - 1);
    // Grid rows are uniform from 0..ceiling; edge rows sit half a label
    // (~6px) inside the box, mirrored here so points hit the lines.
    const double edgePad = 6;
    final double span = size.height - edgePad * 2;
    final double t = ceiling <= 0
        ? 0.0
        : (values[i] / ceiling).clamp(0.0, 1.0).toDouble();
    return Offset(x, edgePad + (1 - t) * span);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final Offset start = _pointAt(0, size);
    final Path path = Path()..moveTo(start.dx, start.dy);
    for (int i = 0; i < values.length - 1; i++) {
      final Offset p0 = _pointAt(i == 0 ? i : i - 1, size);
      final Offset p1 = _pointAt(i, size);
      final Offset p2 = _pointAt(i + 1, size);
      final Offset p3 =
          _pointAt(i + 2 >= values.length ? i + 1 : i + 2, size);
      final Offset c1 = p1 + (p2 - p0) / 6;
      final Offset c2 = p2 - (p3 - p1) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF111827)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(
      _pointAt(values.length - 1, size),
      4,
      Paint()..color = const Color(0xFF111827),
    );
  }

  @override
  bool shouldRepaint(covariant _ActivityCurvePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.ceiling != ceiling;
}
