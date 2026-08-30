import 'package:flutter/material.dart';

import '../../core/responsive/responsive.dart';
import '../../core/theme/app_typography.dart';
import '../../features/applications/presentation/screens/reviewing_applications_screen.dart';
import '../../features/home/presentation/screens/dashboard_home_screen.dart';

/// Sidebar sections of the dashboard per the Figma frame 457:421:
/// Home, Grades (expandable into the four grades), Membership,
/// Administrative and Reviewing Applications.
enum DashboardSection {
  home,
  gradeOne,
  gradeTwo,
  gradeThree,
  gradeFour,
  membership,
  administrative,
  reviewing,
}

/// App shell reproducing the dashboard home composition: a ~388 px left
/// sidebar separated by a 3 px black rule, with the active top-level item
/// rendered as the black rounded pill from the design.
class DashboardShell extends StatefulWidget {
  const DashboardShell({super.key});

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  static const Map<DashboardSection, String> _gradeLabels =
      <DashboardSection, String>{
    DashboardSection.gradeOne: 'Grade One',
    DashboardSection.gradeTwo: 'Grade Two',
    DashboardSection.gradeThree: 'Grade Three',
    DashboardSection.gradeFour: 'Grade Four',
  };

  static const Map<DashboardSection, String> _sectionLabels =
      <DashboardSection, String>{
    DashboardSection.membership: 'Membership',
    DashboardSection.administrative: 'Administrative',
    DashboardSection.reviewing: 'Reviewing Applications',
  };

  DashboardSection _section = DashboardSection.home;
  bool _gradesExpanded = false;

  void _select(DashboardSection section) {
    setState(() {
      _section = section;
      if (_gradeLabels.containsKey(section)) {
        _gradesExpanded = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildSidebar(),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(rs(32), rs(48), rs(32), rs(40)),
              child: _contentFor(_section),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    final rs = context.rs;
    return Container(
      width: rs(388),
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: AppColors.ink, width: rs(3)),
        ),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.only(top: rs(189), bottom: rs(40)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _SidebarItem(
                label: 'Home',
                selected: _section == DashboardSection.home,
                onTap: () => _select(DashboardSection.home),
              ),
              _SidebarItem(
                label: 'Grades',
                selected: false,
                trailing: Icon(
                  _gradesExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: rs(40),
                  color: AppColors.ink,
                ),
                onTap: () =>
                    setState(() => _gradesExpanded = !_gradesExpanded),
              ),
              if (_gradesExpanded)
                _SidebarItem(
                  label: _gradeLabels[DashboardSection.gradeOne]!,
                  subItem: true,
                  selected: _section == DashboardSection.gradeOne,
                  onTap: () => _select(DashboardSection.gradeOne),
                ),
              if (_gradesExpanded)
                _SidebarItem(
                  label: _gradeLabels[DashboardSection.gradeTwo]!,
                  subItem: true,
                  selected: _section == DashboardSection.gradeTwo,
                  onTap: () => _select(DashboardSection.gradeTwo),
                ),
              if (_gradesExpanded)
                _SidebarItem(
                  label: _gradeLabels[DashboardSection.gradeThree]!,
                  subItem: true,
                  selected: _section == DashboardSection.gradeThree,
                  onTap: () => _select(DashboardSection.gradeThree),
                ),
              if (_gradesExpanded)
                _SidebarItem(
                  label: _gradeLabels[DashboardSection.gradeFour]!,
                  subItem: true,
                  selected: _section == DashboardSection.gradeFour,
                  onTap: () => _select(DashboardSection.gradeFour),
                ),
              _SidebarItem(
                label: _sectionLabels[DashboardSection.membership]!,
                selected: _section == DashboardSection.membership,
                onTap: () => _select(DashboardSection.membership),
              ),
              _SidebarItem(
                label: _sectionLabels[DashboardSection.administrative]!,
                selected: _section == DashboardSection.administrative,
                onTap: () => _select(DashboardSection.administrative),
              ),
              _SidebarItem(
                label: _sectionLabels[DashboardSection.reviewing]!,
                selected: _section == DashboardSection.reviewing,
                onTap: () => _select(DashboardSection.reviewing),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _contentFor(DashboardSection section) {
    switch (section) {
      case DashboardSection.home:
        return const DashboardHomeScreen();
      case DashboardSection.gradeOne:
      case DashboardSection.gradeTwo:
      case DashboardSection.gradeThree:
      case DashboardSection.gradeFour:
        return _SectionPlaceholder(title: _gradeLabels[section]!);
      case DashboardSection.membership:
        return _SectionPlaceholder(
            title: _sectionLabels[DashboardSection.membership]!);
      case DashboardSection.administrative:
        return _SectionPlaceholder(
            title: _sectionLabels[DashboardSection.administrative]!);
      case DashboardSection.reviewing:
        return const ReviewingApplicationsScreen();
    }
  }
}

class _SidebarItem extends StatelessWidget {
  final String label;
  final bool selected;
  final bool subItem;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _SidebarItem({
    required this.label,
    required this.selected,
    this.subItem = false,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    final TextStyle textStyle = subItem
        ? AppTypography.sidebarSubItem(fontSize: rs(30))
        : AppTypography.sidebarItem(fontSize: rs(34));
    final bool pillActive = selected && !subItem;
    final bool underlineActive = selected && subItem;

    return Padding(
      padding: EdgeInsets.only(bottom: rs(6)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(rs(20)),
        child: Container(
          constraints: BoxConstraints(minHeight: rs(67)),
          width: rs(290),
          padding: EdgeInsets.only(
            left: subItem ? rs(61) : rs(37),
            right: trailing != null ? rs(40) : 0,
          ),
          decoration: BoxDecoration(
            color: pillActive ? AppColors.ink : Colors.transparent,
            borderRadius: BorderRadius.circular(rs(20)),
          ),
          alignment: Alignment.centerLeft,
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: textStyle.copyWith(
                    color: pillActive ? Colors.white : AppColors.ink,
                    decoration: underlineActive
                        ? TextDecoration.underline
                        : TextDecoration.none,
                    decorationColor: AppColors.ink,
                    decorationThickness: 2,
                  ),
                ),
              ),
              if (trailing != null) ...<Widget>[
                SizedBox(width: rs(16)),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionPlaceholder extends StatelessWidget {
  final String title;

  const _SectionPlaceholder({required this.title});

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: AppTypography.sectionHeading(fontSize: rs(32))),
        SizedBox(height: rs(14)),
        Container(width: rs(880), height: rs(3), color: AppColors.ink),
        SizedBox(height: rs(60)),
        Center(
          child: Text(
            'This section is coming next.',
            style: AppTypography.statLabel(fontSize: rs(24)),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
