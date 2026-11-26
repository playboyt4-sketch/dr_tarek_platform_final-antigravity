import 'package:flutter/material.dart';

import '../../core/responsive/responsive.dart';
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
  static const String archive = 'archive';
}

/// Shared menu entry definitions used by both [DashboardFullMenu] (tablet /
/// desktop) and the mobile [Drawer] in [DashboardShell].
abstract final class DashboardMenuData {
  static const List<({String label, String route})> grades =
      <({String label, String route})>[
    (label: 'Grade One', route: DashboardMenuRoutes.gradeOne),
    (label: 'Grade Two', route: DashboardMenuRoutes.gradeTwo),
    (label: 'Grade Three', route: DashboardMenuRoutes.gradeThree),
    (label: 'Grade Four', route: DashboardMenuRoutes.gradeFour),
  ];

  static const List<({String label, String route})> management =
      <({String label, String route})>[
    (label: 'Subscription', route: DashboardMenuRoutes.subscription),
    (label: 'Admins', route: DashboardMenuRoutes.admins),
    (label: 'Announcements', route: DashboardMenuRoutes.announcements),
    (label: 'Audit Logs', route: DashboardMenuRoutes.auditLogs),
    (label: 'Payments', route: DashboardMenuRoutes.payments),
    (label: 'System Settings', route: DashboardMenuRoutes.systemSettings),
    (label: 'Archive', route: DashboardMenuRoutes.archive),
  ];
}

/// Full-menu overlay for Tablet and Desktop viewports.
///
/// Expands to fill the available screen without rigid canvas dimensions or
/// scaling, and scrolls vertically if the viewport height is short.
class DashboardFullMenu extends StatelessWidget {
  final VoidCallback? onClose;
  final ValueChanged<String> onNavigate;
  final VoidCallback? onSignOut;

  const DashboardFullMenu({
    super.key,
    this.onClose,
    required this.onNavigate,
    this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFFFFF),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double width = constraints.maxWidth;
          final bool isCompact = width < AppBreakpoints.mobileMax;
          final double horizontalPadding =
              width > AppBreakpoints.desktopMin ? 80 : 32;

          return SizedBox.expand(
            child: SingleChildScrollView(
              clipBehavior: Clip.antiAlias,
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                24,
                horizontalPadding,
                40,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - 64).clamp(0.0, 2000.0),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const ResponsiveScreenHeader(),
                    SizedBox(height: isCompact ? 24 : 48),
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 920),
                        child: isCompact
                            ? _CompactMenuBody(
                                onNavigate: onNavigate,
                                onSignOut: onSignOut,
                              )
                            : _WideMenuBody(
                                onNavigate: onNavigate,
                                onSignOut: onSignOut,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WideMenuBody extends StatelessWidget {
  final ValueChanged<String> onNavigate;
  final VoidCallback? onSignOut;

  const _WideMenuBody({
    required this.onNavigate,
    this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _HoverEntry(
          label: 'Home',
          style: AppTypography.menuItem(),
          onTap: () => onNavigate(DashboardMenuRoutes.home),
        ),
        const SizedBox(height: 28),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              flex: 2,
              child: Text(
                'Grades',
                style: AppTypography.menuSection(),
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (int i = 0;
                      i < DashboardMenuData.grades.length;
                      i++) ...<Widget>[
                    if (i > 0) const SizedBox(height: 12),
                    _HoverEntry(
                      label: DashboardMenuData.grades[i].label,
                      style: AppTypography.menuSubItem(),
                      onTap: () =>
                          onNavigate(DashboardMenuData.grades[i].route),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 40),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              flex: 2,
              child: Text(
                'Management',
                style: AppTypography.menuSection(),
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (int i = 0;
                      i < DashboardMenuData.management.length;
                      i++) ...<Widget>[
                    if (i > 0) const SizedBox(height: 12),
                    _HoverEntry(
                      label: DashboardMenuData.management[i].label,
                      style: AppTypography.menuSubItem(),
                      onTap: () =>
                          onNavigate(DashboardMenuData.management[i].route),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 44),
        const Divider(height: 1, color: Color(0xFFE5E7EB)),
        const SizedBox(height: 24),
        _SignOutMenuAction(onTap: onSignOut),
      ],
    );
  }
}

class _CompactMenuBody extends StatelessWidget {
  final ValueChanged<String> onNavigate;
  final VoidCallback? onSignOut;

  const _CompactMenuBody({
    required this.onNavigate,
    this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _HoverEntry(
          label: 'Home',
          style: AppTypography.menuItem(),
          onTap: () => onNavigate(DashboardMenuRoutes.home),
        ),
        const SizedBox(height: 24),
        Text('Grades', style: AppTypography.menuSection()),
        const SizedBox(height: 12),
        for (final item in DashboardMenuData.grades) ...<Widget>[
          _HoverEntry(
            label: item.label,
            style: AppTypography.menuSubItem(),
            onTap: () => onNavigate(item.route),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 20),
        Text('Management', style: AppTypography.menuSection()),
        const SizedBox(height: 12),
        for (final item in DashboardMenuData.management) ...<Widget>[
          _HoverEntry(
            label: item.label,
            style: AppTypography.menuSubItem(),
            onTap: () => onNavigate(item.route),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 16),
        const Divider(height: 1, color: Color(0xFFE5E7EB)),
        const SizedBox(height: 16),
        _SignOutMenuAction(onTap: onSignOut),
      ],
    );
  }
}

/// Red Sign Out entry at the bottom of the dashboard menu.
class _SignOutMenuAction extends StatefulWidget {
  final VoidCallback? onTap;

  const _SignOutMenuAction({this.onTap});

  @override
  State<_SignOutMenuAction> createState() => _SignOutMenuActionState();
}

class _SignOutMenuActionState extends State<_SignOutMenuAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedOpacity(
          opacity: _hovered ? 0.72 : 1.0,
          duration: const Duration(milliseconds: 120),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const <Widget>[
              Icon(
                Icons.logout_rounded,
                size: 20,
                color: Color(0xFFDC2626),
              ),
              SizedBox(width: 10),
              Text(
                'Sign Out',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFFDC2626),
                ),
              ),
            ],
          ),
        ),
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
          child: Container(
            constraints: BoxConstraints(minHeight: master ? 44 : 32),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
