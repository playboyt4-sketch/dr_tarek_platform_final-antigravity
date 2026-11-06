import 'package:flutter/material.dart';

import '../../core/theme/app_typography.dart';

/// Route keys emitted by the full menu. The shell maps them to sections.
abstract final class DashboardMenuRoutes {
  static const String home = 'home';
  static const String gradeOne = 'gradeOne';
  static const String gradeTwo = 'gradeTwo';
  static const String gradeThree = 'gradeThree';
  static const String gradeFour = 'gradeFour';
  static const String subscription = 'subscription';
  static const String admins = 'admins';
  static const String announcements = 'announcements';
  static const String auditLogs = 'auditLogs';
  static const String payments = 'payments';
  static const String systemSettings = 'systemSettings';
}

/// Full-menu overlay — pixel-faithful to `# dashboard - full menu`
/// (DASHBOARD_FULL_MENU_SPEC.md):
///
/// - canvas 1280 x 800, pure white #FFFFFF, clipped (antiAlias);
/// - brand 540 x 80 at (370, 24), Google Sans Flex 48
///   (Regular 400 + Thin 100, black, letter spacing 0);
/// - master column at X 370: Home (370, 164, 250 x 40), Grades
///   (370, 228, 250 x 40), Management (370, 402, 250 x 49) —
///   32 px Regular 400 black;
/// - sub column at X 660 (290 gap): Frame 30 grades list at
///   (660, 236) and Frame 31 management list at (660, 410), vertical
///   auto-layout with 12 px gaps, 20 px Light 300 black rows
///   (247 x 24 each).
///
/// The unified [DashboardShell] draws the single fixed menu button at
/// (80, 24, 80 x 80) in its top layer, so this overlay no longer draws
/// its own button — the X/close control never shifts a pixel between
/// home and menu. [onClose] is kept for API compatibility (the shell's
/// fixed button owns the toggle).
///
/// Tapping any entry fires [onNavigate]; the shell closes the overlay with
/// a smooth animation and shows the target section.
class DashboardFullMenu extends StatelessWidget {
  final VoidCallback? onClose;
  final ValueChanged<String> onNavigate;

  const DashboardFullMenu({
    super.key,
    this.onClose,
    required this.onNavigate,
  });

  static const List<({String label, String route})> _grades =
      <({String label, String route})>[
    (label: 'Grade One', route: DashboardMenuRoutes.gradeOne),
    (label: 'Grade Two', route: DashboardMenuRoutes.gradeTwo),
    (label: 'Grade Three', route: DashboardMenuRoutes.gradeThree),
    (label: 'Grade Four', route: DashboardMenuRoutes.gradeFour),
  ];

  static const List<({String label, String route})> _management =
      <({String label, String route})>[
    (label: 'Subscription', route: DashboardMenuRoutes.subscription),
    (label: 'Admins', route: DashboardMenuRoutes.admins),
    (label: 'Announcements', route: DashboardMenuRoutes.announcements),
    (label: 'Audit Logs', route: DashboardMenuRoutes.auditLogs),
    (label: 'Payments', route: DashboardMenuRoutes.payments),
    (label: 'System Settings', route: DashboardMenuRoutes.systemSettings),
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFFFFF),
      child: SingleChildScrollView(
        clipBehavior: Clip.antiAlias,
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          clipBehavior: Clip.antiAlias,
          child: ClipRect(
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: 1280,
              height: 800,
              child: Stack(
                children: <Widget>[
                  // Brand 540 x 80 at (370, 24), hit-transparent.
                  // The shell's fixed top-layer button at (80, 24, 80 x 80)
                  // stays on top so open/close never shifts a pixel.
                  const Positioned(
                    left: 370,
                    top: 24,
                    width: 540,
                    height: 80,
                    child: IgnorePointer(child: _BrandLockup()),
                  ),
                  // T Home 250 x 40 at (370, 164).
                  Positioned(
                    left: 370,
                    top: 164,
                    width: 250,
                    height: 40,
                    child: _HoverEntry(
                      label: 'Home',
                      style: AppTypography.menuItem(),
                      onTap: () =>
                          onNavigate(DashboardMenuRoutes.home),
                    ),
                  ),
                  // T Grades 250 x 40 at (370, 228) — 64 below Home.
                  Positioned(
                    left: 370,
                    top: 228,
                    width: 250,
                    height: 40,
                    child: Text(
                      'Grades',
                      style: AppTypography.menuSection(),
                      maxLines: 1,
                    ),
                  ),
                  // T Management 250 x 49 at (370, 402) — 174 below Grades.
                  Positioned(
                    left: 370,
                    top: 402,
                    width: 250,
                    height: 49,
                    child: Text(
                      'Management',
                      style: AppTypography.menuSection(),
                      maxLines: 1,
                    ),
                  ),
                  // Frame 30 — grades list 250 wide at (660, 236),
                  // 8 px below the Grades cap, 12 px gaps.
                  Positioned(
                    left: 660,
                    top: 236,
                    width: 250,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        for (int i = 0; i < _grades.length; i++) ...<Widget>[
                          if (i > 0) const SizedBox(height: 12),
                          _HoverEntry(
                            label: _grades[i].label,
                            style: AppTypography.menuSubItem(),
                            onTap: () =>
                                onNavigate(_grades[i].route),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Frame 31 — management list 250 wide at (660, 410),
                  // 8 px below the Management cap, 12 px gaps.
                  Positioned(
                    left: 660,
                    top: 410,
                    width: 250,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        for (int i = 0; i < _management.length; i++) ...<Widget>[
                          if (i > 0) const SizedBox(height: 12),
                          _HoverEntry(
                            label: _management[i].label,
                            style: AppTypography.menuSubItem(),
                            onTap: () =>
                                onNavigate(_management[i].route),
                          ),
                        ],
                      ],
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
}

/// Brand lockup 540 x 80: 48 px Regular 400 + Thin 100, black, no tracking.
class _BrandLockup extends StatelessWidget {
  const _BrandLockup();

  @override
  Widget build(BuildContext context) {
    return FittedBox(
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
    );
  }
}

/// Interactive menu entry with a refined hover polish: click cursor plus a
/// soft fade to 70% opacity while hovered.
class _HoverEntry extends StatefulWidget {
  final String label;
  final TextStyle style;
  final VoidCallback onTap;

  const _HoverEntry({
    required this.label,
    required this.style,
    required this.onTap,
  });

  @override
  State<_HoverEntry> createState() => _HoverEntryState();
}

class _HoverEntryState extends State<_HoverEntry> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bool master = widget.style.fontSize == 32;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: _hovered ? 0.7 : 1.0,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: master ? 250 : 247,
            height: master ? 40 : 24,
            child: Text(
              widget.label,
              style: widget.style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}
