import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/theme/app_typography.dart';
import '../providers/grade_students_provider.dart';
import 'grade_students_screen.dart' show gradeAccent;
import 'student_profile_memberships_tab.dart';
import 'student_profile_payments_tab.dart';
import 'student_profile_device_tab.dart';
import 'student_profile_subjects_tab.dart';
import '../widgets/dashboard_brand_lockup.dart';
import '../widgets/grade_theme.dart';

/// "Grade One - Student Profile Overview" screen — the "View" destination
/// of the students data table, matching the approved Figma Dev Mode frame
/// (1280 x 800, pure white #FFFFFF, Clip.antiAlias).
///
/// Fixed-canvas vertical rhythm (left-anchored per Figma):
/// - header at top 24: 80 x 80 hamburger visual at left 80 (the shell
///   overlays its functional menu button on the same spot) + 540 x 80
///   brand at left 370 (gap 210);
/// - grade nav 660 x 40 at top 132 (border #979797, radius 28; 4 tabs
///   160 x 32, gap 4; active pill fills the grade accent, two-run
///   24 px label: "Grade " Regular + suffix Thin);
/// - category switcher 336 x 40 at top 190 (radius 28; 2 tabs 160 x 32,
///   gap 4; active tab renders its label in the grade accent);
/// - student hero 540 x 132 stadium at top 248 (4 px accent border;
///   100 x 100 avatar with gradient + Frame.svg fallback, 36 px name,
///   metadata row);
/// - sub-nav 652 x 40 at top 398 (border #979797, radius 28; 6 tabs
///   104 x 32, gap 4; active pill fills the grade accent);
/// - data rows 814 wide at top 456 (4 rows x 56, gap 16; label 176 px
///   28 px black, value 405 x 48 bordered, action 144 x 48).
///
/// Name/Phone edit inline (Edit ↔ Done); Grade/Student-type edit via the
/// 677 x 220 / 380 x 220 overlays (white, radius 24, fade 150 ms,
/// barrier black 25%). `Overview`, `Subjects`, `Memberships`, `Payments`
/// and `Device` have destinations; the remaining sub-nav pills stay static
/// until their screens land.
///
/// The passed [student] pre-fills the hero (name/phone/grade/date) and the
/// Name, Phone, Grade and Student Type rows.
class StudentProfileOverviewScreen extends StatefulWidget {
  final GradeStudent student;
  final String gradeKey;

  /// Optional network avatar for the hero. When null (or when loading
  /// fails) `assets/images/Frame.svg` renders as the fallback.
  final String? avatarUrl;

  /// Optional device label for the hero metadata row (hidden when null).
  final String? deviceLabel;

  /// Return to the students table. Retained for API compatibility with
  /// the dashboard shell; the screen itself renders no back control —
  /// navigation stays in the shell (menu / grade tabs), per Figma.
  final VoidCallback? onBack;

  /// Dashboard-level navigation out of the profile detail state.
  ///
  /// The grade selector and the Students/Subjects tabs are Dashboard
  /// Students-list controls, not profile editors: they must exit the
  /// profile (clearing the selected student in the shell) instead of
  /// mutating the displayed student's grade. Same callback shape as
  /// [SubjectDetailsScreen].
  final ValueChanged<String>? onGradeSelected;
  final VoidCallback? onStudentsTab;
  final VoidCallback? onSubjectsTab;

  /// Profile section shown first. `Overview`, `Subjects`,
  /// `Memberships`, `Payments` and `Device` have destinations; any other
  /// value falls back to `Overview`.
  final String initialNav;

  const StudentProfileOverviewScreen({
    super.key,
    required this.student,
    required this.gradeKey,
    this.avatarUrl,
    this.deviceLabel,
    this.onBack,
    this.initialNav = 'Overview',
    this.onGradeSelected,
    this.onStudentsTab,
    this.onSubjectsTab,
  });

  @override
  State<StudentProfileOverviewScreen> createState() =>
      _StudentProfileOverviewScreenState();
}

class _StudentProfileOverviewScreenState
    extends State<StudentProfileOverviewScreen> {
  static const List<String> navItems = <String>[
    'Overview',
    'Subjects',
    'Memberships',
    'Payments',
    'Device',
    'Security',
  ];

  late String _gradeKey;
  late bool _isCenter;
  late String _nav;
  late bool _studentsActive;
  bool _isEditingName = false;
  bool _isEditingPhone = false;

  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late FocusNode _nameFocus;
  late FocusNode _phoneFocus;

  /// Grade accent only — never a page background. Resolved through the
  /// shared [gradeAccent] infrastructure; unknown grades fall back to
  /// Grade One there.
  Color get _accent => gradeAccent(_gradeKey);

  String get _gradeLabel => GradeTheme.fromKey(_gradeKey).title;
  String get _typeLabel => _isCenter ? 'Center' : 'Guest';

  @override
  void initState() {
    super.initState();
    _gradeKey = GradeTheme.fromKey(widget.gradeKey).gradeId;
    _isCenter = widget.student.isCenter;
    _nav = widget.initialNav == 'Subjects' ||
            widget.initialNav == 'Memberships' ||
            widget.initialNav == 'Payments' ||
            widget.initialNav == 'Device'
        ? widget.initialNav
        : 'Overview';
    _studentsActive = true;
    _nameController = TextEditingController(text: widget.student.name);
    _phoneController =
        TextEditingController(text: widget.student.phone ?? '—');
    _nameFocus = FocusNode();
    _phoneFocus = FocusNode();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

  /// Dashboard grade selector handler: navigates the shell to the
  /// requested grade's Students list. Never mutates the displayed
  /// student's persisted `users.grade` — the shell clears the selected
  /// student on navigation. Falls back to the local preview only when
  /// no shell handler is wired (standalone/test harness).
  void selectGrade(String gradeKey) {
    final ValueChanged<String>? navigate = widget.onGradeSelected;
    if (navigate != null) {
      navigate(GradeTheme.fromKey(gradeKey).gradeId);
      return;
    }
    setState(() => _gradeKey = GradeTheme.fromKey(gradeKey).gradeId);
  }

  /// Switches the active Student Profile section. `Overview`,
  /// `Subjects`, `Memberships`, `Payments` and `Device` have destinations;
  /// the remaining pills stay static until their screens land.
  void selectNav(String nav) {
    if (nav != 'Overview' &&
        nav != 'Subjects' &&
        nav != 'Memberships' &&
        nav != 'Payments' &&
        nav != 'Device') {
      return;
    }
    setState(() => _nav = nav);
  }

  void _selectCategory(bool students) {
    if (students) {
      widget.onStudentsTab?.call();
    } else {
      widget.onSubjectsTab?.call();
    }
    if (!mounted) return;
    setState(() {
      _studentsActive = students;
      // Standalone fallback (no shell handler wired): mirror the category
      // into the profile section so the switcher stays functional.
      if (students ? widget.onStudentsTab == null : widget.onSubjectsTab == null) {
        _nav = students ? 'Overview' : 'Subjects';
      }
    });
  }

  void toggleNameEditing() {
    setState(() => _isEditingName = !_isEditingName);
    if (_isEditingName) {
      _nameFocus.requestFocus();
    } else {
      _nameFocus.unfocus();
    }
  }

  void togglePhoneEditing() {
    setState(() => _isEditingPhone = !_isEditingPhone);
    if (_isEditingPhone) {
      _phoneFocus.requestFocus();
    } else {
      _phoneFocus.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Widget canvas = Center(
            child: SizedBox(
              width: 1280,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // Header Y 24: hamburger 80 x 80 at X 80 + brand
                  // 540 x 80 at X 370 (gap 210).
                  Padding(
                    padding: const EdgeInsets.only(left: 80, right: 80, top: 24),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const <Widget>[
                        _HamburgerIcon(),
                        SizedBox(width: 210),
                        IgnorePointer(child: DashboardBrandLockup()),
                      ],
                    ),
                  ),
                  // 24 + 80 = 104; gap 28 → grade nav Y 132.
                  const SizedBox(height: 28),
                  Center(
                    child: _ProfileGradeNav(
                      gradeKey: _gradeKey,
                      onGradeSelected: selectGrade,
                    ),
                  ),
                  // 132 + 40 = 172; gap 18 → category Y 190.
                  // Persistent header: category switcher, hero card and
                  // sub-nav stay mounted for EVERY tab (Overview,
                  // Subjects, …). Only the dynamic body at Y 456 swaps:
                  // data rows for Overview, subjects table for Subjects.
                  const SizedBox(height: 18),
                  Center(
                    child: _ProfileCategoryTabs(
                      studentsActive: _studentsActive,
                      accent: _accent,
                      onSelect: _selectCategory,
                    ),
                  ),
                  // 190 + 40 = 230; gap 18 → hero Y 248.
                  const SizedBox(height: 18),
                  Center(
                    child: _StudentHeroBar(
                      student: widget.student,
                      gradeLabel: _gradeLabel,
                      accent: _accent,
                      avatarUrl: widget.avatarUrl,
                      deviceLabel: widget.deviceLabel,
                    ),
                  ),
                  // 248 + 132 = 380; gap 18 → sub-nav Y 398.
                  const SizedBox(height: 18),
                  Center(
                    child: _ProfileSubNav(
                      selected: _nav,
                      accent: _accent,
                      onSelect: selectNav,
                    ),
                  ),
                  // 398 + 40 = 438; gap 18 → dynamic body Y 456.
                  // Overview → data rows; Subjects → subjects table;
                  // Memberships → type pill + memberships table;
                  // Payments → invoiced table + summary strip + history;
                  // Device → subject device-authorization table + reset.
                  const SizedBox(height: 18),
                  if (_nav == 'Subjects')
                    Center(
                      child: SizedBox(
                        width: 830,
                        child: StudentProfileSubjectsTab(
                          student: widget.student,
                          gradeKey: _gradeKey,
                        ),
                      ),
                    )
                  else if (_nav == 'Memberships') ...<Widget>[
                    Center(
                      child: _StudentTypePill(
                        accent: _accent,
                        onTap: _showStudentTypeOverlay,
                      ),
                    ),
                    // 456 + 40 = 496; gap 18 → table Y 514.
                    const SizedBox(height: 18),
                    Center(
                      child: SizedBox(
                        width: 830,
                        child: StudentProfileMembershipsTab(
                          student: widget.student,
                          gradeKey: _gradeKey,
                        ),
                      ),
                    ),
                  ] else if (_nav == 'Payments')
                    Center(
                      child: SizedBox(
                        width: 830,
                        child: StudentProfilePaymentsTab(
                          student: widget.student,
                          gradeKey: _gradeKey,
                        ),
                      ),
                    )
                  else if (_nav == 'Device')
                    Center(
                      child: SizedBox(
                        width: 830,
                        child: StudentProfileDeviceTab(
                          student: widget.student,
                          gradeKey: _gradeKey,
                        ),
                      ),
                    )
                  else
                    Center(child: _OverviewRows(state: this)),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
          final Widget vertical = SingleChildScrollView(
            clipBehavior: Clip.antiAlias,
            child: canvas,
          );
          // Fixed 1280 canvas: center it on wider viewports, scroll
          // horizontally on narrower ones so nothing ever overflows.
          if (constraints.maxWidth < 1280) {
            return SingleChildScrollView(
              clipBehavior: Clip.antiAlias,
              scrollDirection: Axis.horizontal,
              child: vertical,
            );
          }
          return vertical;
        },
      ),
    );
  }

  void _showGradesOverlay() {
    String temp = _gradeKey;
    showGeneralDialog<void>(
      context: context,
      barrierColor: const Color(0x40000000),
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      transitionDuration: const Duration(milliseconds: 150),
      transitionBuilder: (
        BuildContext context,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
        Widget child,
      ) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        );
      },
      pageBuilder: (
        BuildContext context,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
      ) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setOverlayState) {
            return Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 677,
                  height: 220,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      const Text(
                        'Grades',
                        style: TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 32,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: 660,
                        height: 40,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            for (int i = 0;
                                i < GradeTheme.allGrades.length;
                                i++) ...<Widget>[
                              if (i > 0) const SizedBox(width: 4),
                              _OverlayOption(
                                label: GradeTheme.allGrades[i].title,
                                isActive: temp ==
                                    GradeTheme.allGrades[i].gradeId,
                                accent: _accent,
                                onTap: () => setOverlayState(() => temp =
                                    GradeTheme.allGrades[i].gradeId),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      _SaveButton(
                        accent: _accent,
                        onTap: () {
                          setState(() => _gradeKey = temp);
                          Navigator.of(context).pop();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showStudentTypeOverlay() {
    bool temp = _isCenter;
    showGeneralDialog<void>(
      context: context,
      barrierColor: const Color(0x40000000),
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      transitionDuration: const Duration(milliseconds: 150),
      transitionBuilder: (
        BuildContext context,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
        Widget child,
      ) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        );
      },
      pageBuilder: (
        BuildContext context,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
      ) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setOverlayState) {
            return Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 380,
                  height: 220,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      const Text(
                        'Student Type',
                        style: TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 32,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        width: 332,
                        height: 40,
                        // 332 - 2 (border) - 6 (padding) = 324 for
                        // 2 x 160 options + 4 gap.
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: const Color(0xFF979797),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            _OverlayOption(
                              label: 'Center',
                              isActive: temp,
                              accent: _accent,
                              onTap: () =>
                                  setOverlayState(() => temp = true),
                            ),
                            const SizedBox(width: 4),
                            _OverlayOption(
                              label: 'Guest',
                              isActive: !temp,
                              accent: _accent,
                              onTap: () =>
                                  setOverlayState(() => temp = false),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      _SaveButton(
                        accent: _accent,
                        onTap: () {
                          setState(() => _isCenter = temp);
                          Navigator.of(context).pop();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Memberships body entry pill (250 x 40, centered at Y 456): 1 px
/// accent ring, stadium capsule, 24 px Regular #6B7280 label. Taps open
/// the Student Type overlay.
class _StudentTypePill extends StatelessWidget {
  final Color accent;
  final VoidCallback onTap;

  const _StudentTypePill({
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 250,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(9999),
          border: Border.all(color: accent, width: 1),
        ),
        alignment: Alignment.center,
        child: const Text(
          'Student Type',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 24,
            fontWeight: FontWeight.w400,
            fontVariations: <FontVariation>[FontVariation('wght', 400)],
            color: Color(0xFF6B7280),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// Hamburger visual from the Figma header (80 x 80 at left 80 / top 24):
/// two full-width 1 px black bars, radius 9999, 10 px apart.
///
/// Static visual only — the dashboard shell overlays its functional menu
/// button on this exact spot, so taps are handled there.
class _HamburgerIcon extends StatelessWidget {
  const _HamburgerIcon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 80,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 80,
            height: 1,
            decoration: BoxDecoration(
              color: const Color(0xFF000000),
              borderRadius: BorderRadius.circular(9999),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: 80,
            height: 1,
            decoration: BoxDecoration(
              color: const Color(0xFF000000),
              borderRadius: BorderRadius.circular(9999),
            ),
          ),
        ],
      ),
    );
  }
}

/// Grade navigation bar from the Figma frame (660 x 40, border #979797,
/// radius 28): 4 tabs 160 x 32 with 4 px gaps. The active pill fills the
/// grade's own accent; labels are two-run 24 px ("Grade " Regular +
/// suffix Thin), white when active, black otherwise.
class _ProfileGradeNav extends StatelessWidget {
  final String gradeKey;
  final ValueChanged<String> onGradeSelected;

  const _ProfileGradeNav({
    required this.gradeKey,
    required this.onGradeSelected,
  });

  @override
  Widget build(BuildContext context) {
    final GradeTheme active = GradeTheme.fromKey(gradeKey);
    return Container(
      width: 660,
      height: 40,
      // 660 - 2 (1 px border each side) - 6 (3 px padding) = 652 for
      // 4 x 160 tabs + 3 x 4 gaps; height 40 - 2 - 6 = 32 for the tabs.
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF979797), width: 1),
      ),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < GradeTheme.allGrades.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 4),
            _GradeNavTab(
              grade: GradeTheme.allGrades[i],
              isActive: GradeTheme.allGrades[i].gradeId == active.gradeId,
              onTap: () {
                if (GradeTheme.allGrades[i].gradeId != active.gradeId) {
                  onGradeSelected(GradeTheme.allGrades[i].gradeId);
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _GradeNavTab extends StatelessWidget {
  final GradeTheme grade;
  final bool isActive;
  final VoidCallback onTap;

  const _GradeNavTab({
    required this.grade,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final String suffix = grade.title.startsWith('Grade ')
        ? grade.title.substring('Grade '.length)
        : grade.title;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160,
        height: 32,
        decoration: BoxDecoration(
          color: isActive ? grade.primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(28),
        ),
        alignment: Alignment.center,
        child: Text.rich(
          TextSpan(
            children: <TextSpan>[
              TextSpan(
                text: 'Grade ',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 24,
                  fontWeight: FontWeight.w400,
                  fontVariations: const <FontVariation>[
                    FontVariation('wght', 400),
                  ],
                  color: isActive ? Colors.white : Colors.black,
                ),
              ),
              TextSpan(
                text: suffix,
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 24,
                  fontWeight: FontWeight.w100,
                  fontVariations: const <FontVariation>[
                    FontVariation('wght', 100),
                  ],
                  color: isActive ? Colors.white : Colors.black,
                ),
              ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// Primary category switcher from the Figma frame (336 x 40, radius 28):
/// 2 tabs 160 x 32 with a 4 px gap. The active tab renders its 24 px
/// Regular label in the grade accent; the inactive tab stays black.
class _ProfileCategoryTabs extends StatelessWidget {
  final bool studentsActive;
  final Color accent;
  final ValueChanged<bool> onSelect;

  const _ProfileCategoryTabs({
    required this.studentsActive,
    required this.accent,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 336,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: <Widget>[
          _CategoryTab(
            label: 'Students',
            isActive: studentsActive,
            accent: accent,
            onTap: () => onSelect(true),
          ),
          const SizedBox(width: 4),
          _CategoryTab(
            label: 'Subjects',
            isActive: !studentsActive,
            accent: accent,
            onTap: () => onSelect(false),
          ),
        ],
      ),
    );
  }
}

class _CategoryTab extends StatelessWidget {
  final String label;
  final bool isActive;
  final Color accent;
  final VoidCallback onTap;

  const _CategoryTab({
    required this.label,
    required this.isActive,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160,
        height: 32,
        color: Colors.transparent,
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 24,
            fontWeight: FontWeight.w400,
            fontVariations: const <FontVariation>[
              FontVariation('wght', 400),
            ],
            color: isActive ? accent : Colors.black,
            decoration:
                isActive ? TextDecoration.underline : TextDecoration.none,
            decorationColor: accent,
            decorationThickness: 2,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// Student hero summary bar from the Figma frame (540 x 132 stadium,
/// 4 px accent border, white fill): 100 x 100 avatar at (16, 16), name
/// at (132, 24), metadata row at (132, 80) with 8 px spacing.
class _StudentHeroBar extends StatelessWidget {
  final GradeStudent student;
  final String gradeLabel;
  final Color accent;
  final String? avatarUrl;
  final String? deviceLabel;

  const _StudentHeroBar({
    required this.student,
    required this.gradeLabel,
    required this.accent,
    this.avatarUrl,
    this.deviceLabel,
  });

  @override
  Widget build(BuildContext context) {
    final String phone = student.phone ?? '—';
    final String date = student.lastSignIn;
    return Container(
      width: 540,
      height: 132,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(color: accent, width: 4),
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            left: 16,
            top: 16,
            child: _HeroAvatar(avatarUrl: avatarUrl),
          ),
          Positioned(
            left: 132,
            top: 24,
            child: SizedBox(
              width: 392,
              height: 48,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  student.name,
                  maxLines: 1,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                    fontVariations: <FontVariation>[
                      FontVariation('wght', 500),
                    ],
                    color: Color(0xFF111827),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 132,
            top: 76,
            right: 16,
            child: Row(
              children: <Widget>[
                Text(
                  phone,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    fontVariations: <FontVariation>[
                      FontVariation('wght', 400),
                    ],
                    color: Color(0xFF6B7280),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    gradeLabel,
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      fontVariations: <FontVariation>[
                        FontVariation('wght', 400),
                      ],
                      color: Color(0xFF6B7280),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  date,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    fontVariations: <FontVariation>[
                      FontVariation('wght', 400),
                    ],
                    color: Color(0xFF6B7280),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (deviceLabel != null && deviceLabel!.isNotEmpty) ...<Widget>[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      deviceLabel!,
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        fontVariations: <FontVariation>[
                          FontVariation('wght', 400),
                        ],
                        color: Color(0xFF6B7280),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Hero avatar (100 x 100 circle): clean light-neutral fill, 1 px
/// #E5E7EB ring, subtle ambient shadow, `Frame.svg` (56 x 56, #9CA3AF
/// silhouette) centered. A network image covers the circle when
/// [avatarUrl] is set, falling back to the frame graphic on error.
class _HeroAvatar extends StatelessWidget {
  final String? avatarUrl;

  const _HeroAvatar({this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    const Widget fallback = Center(
      child: _FrameIcon(),
    );
    return Container(
      width: 100,
      height: 100,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFFF3F4F6),
        border: Border.fromBorderSide(
          BorderSide(color: Color(0xFFE5E7EB), width: 1),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: avatarUrl == null || avatarUrl!.isEmpty
            ? fallback
            : Image.network(
                avatarUrl!,
                width: 100,
                height: 100,
                fit: BoxFit.cover,
                errorBuilder: (
                  BuildContext context,
                  Object error,
                  StackTrace? stackTrace,
                ) =>
                    fallback,
              ),
      ),
    );
  }
}

/// Sharp 56 x 56 user-silhouette fallback, tinted #9CA3AF.
///
/// Fail-safe by construction: while the vector asset is loading
/// ([placeholderBuilder]) or if it ever fails to load ([errorBuilder],
/// e.g. a stale web bundle that predates the asset), a Material
/// [Icons.person] glyph renders instead — the circle is never empty.
class _FrameIcon extends StatelessWidget {
  const _FrameIcon();

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/images/Frame.svg',
      width: 56,
      height: 56,
      colorFilter: const ColorFilter.mode(
        Color(0xFF9CA3AF),
        BlendMode.srcIn,
      ),
      semanticsLabel: 'Student avatar',
      placeholderBuilder: (BuildContext context) => const Icon(
        Icons.person,
        size: 56,
        color: Color(0xFF9CA3AF),
      ),
      errorBuilder: (
        BuildContext context,
        Object error,
        StackTrace? stackTrace,
      ) =>
          const Icon(
        Icons.person,
        size: 56,
        color: Color(0xFF9CA3AF),
      ),
    );
  }
}

/// Sub-navigation tabs from the Figma frame (652 x 40, border #979797,
/// radius 28): 6 tabs 104 x 32 with 4 px gaps. The active pill fills the
/// grade accent (radius 9999) with 14 px Regular white text; inactive
/// tabs render 14 px Regular #6B7280.
class _ProfileSubNav extends StatelessWidget {
  final String selected;
  final Color accent;
  final ValueChanged<String> onSelect;

  const _ProfileSubNav({
    required this.selected,
    required this.accent,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 652,
      height: 40,
      // 652 - 2 (border) - 6 (padding) = 644 for 6 x 104 tabs + 5 x 4
      // gaps; height 40 - 2 - 6 = 32 for the tabs.
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF979797), width: 1),
      ),
      child: Row(
        children: <Widget>[
          for (int i = 0;
              i < _StudentProfileOverviewScreenState.navItems.length;
              i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 4),
            _SubNavTab(
              label: _StudentProfileOverviewScreenState.navItems[i],
              isActive:
                  _StudentProfileOverviewScreenState.navItems[i] == selected,
              accent: accent,
              onTap: () => onSelect(
                _StudentProfileOverviewScreenState.navItems[i],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SubNavTab extends StatelessWidget {
  final String label;
  final bool isActive;
  final Color accent;
  final VoidCallback onTap;

  const _SubNavTab({
    required this.label,
    required this.isActive,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 104,
        height: 32,
        decoration: BoxDecoration(
          color: isActive ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(9999),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w400,
            fontVariations: const <FontVariation>[
              FontVariation('wght', 400),
            ],
            color: isActive ? Colors.white : const Color(0xFF6B7280),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// Overview data rows from the Figma frame (814 wide at left 233,
/// top 456): 4 rows x 56 with 16 px vertical gaps.
class _OverviewRows extends StatelessWidget {
  final _StudentProfileOverviewScreenState state;

  const _OverviewRows({required this.state});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 814,
      child: Column(
        children: <Widget>[
          _TextRow(
            label: 'Name',
            controller: state._nameController,
            focusNode: state._nameFocus,
            isEditing: state._isEditingName,
            state: state,
            onToggle: state.toggleNameEditing,
          ),
          const SizedBox(height: 16),
          _TextRow(
            label: 'Phone',
            controller: state._phoneController,
            focusNode: state._phoneFocus,
            isEditing: state._isEditingPhone,
            state: state,
            keyboardType: TextInputType.phone,
            onToggle: state.togglePhoneEditing,
          ),
          const SizedBox(height: 16),
          _DropdownRow(
            label: 'Grade',
            value: state._gradeLabel,
            state: state,
            onEdit: state._showGradesOverlay,
          ),
          const SizedBox(height: 16),
          _DropdownRow(
            label: 'Student type',
            value: state._typeLabel,
            state: state,
            onEdit: state._showStudentTypeOverlay,
          ),
        ],
      ),
    );
  }
}

class _TextRow extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isEditing;
  final _StudentProfileOverviewScreenState state;
  final VoidCallback onToggle;
  final TextInputType keyboardType;

  const _TextRow({
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.isEditing,
    required this.state,
    required this.onToggle,
    this.keyboardType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 814,
      height: 56,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 176,
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 28,
                fontWeight: FontWeight.w400,
                fontVariations: <FontVariation>[FontVariation('wght', 400)],
                color: Colors.black,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 40),
          _DataField(
            state: state,
            isEditing: isEditing,
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: isEditing,
              keyboardType: keyboardType,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 24,
                fontWeight: FontWeight.w400,
                fontVariations: <FontVariation>[FontVariation('wght', 400)],
                color: Color(0xFF1F2937),
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 40),
          _ActionButton(
              label: isEditing ? 'Done' : 'Edit',
              state: state,
              onTap: onToggle),
        ],
      ),
    );
  }
}

class _DropdownRow extends StatelessWidget {
  final String label;
  final String value;
  final _StudentProfileOverviewScreenState state;
  final VoidCallback onEdit;

  const _DropdownRow({
    required this.label,
    required this.value,
    required this.state,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 814,
      height: 56,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 176,
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 28,
                fontWeight: FontWeight.w400,
                fontVariations: <FontVariation>[FontVariation('wght', 400)],
                color: Colors.black,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 40),
          _DataField(
            state: state,
            child: Center(
              child: Text(
                value,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 24,
                  fontWeight: FontWeight.w400,
                  fontVariations: <FontVariation>[
                    FontVariation('wght', 400),
                  ],
                  color: Color(0xFF1F2937),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 40),
          _ActionButton(label: 'Edit', state: state, onTap: onEdit),
        ],
      ),
    );
  }
}

class _DataField extends StatelessWidget {
  final _StudentProfileOverviewScreenState state;
  final Widget child;
  final bool isEditing;

  const _DataField({
    required this.state,
    required this.child,
    this.isEditing = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 405,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isEditing ? state._accent : const Color(0xFF979797),
          width: isEditing ? 2 : 1,
        ),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final _StudentProfileOverviewScreenState state;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.state,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9999),
      child: Container(
        width: 144,
        height: 48,
        decoration: BoxDecoration(
          color: state._accent,
          borderRadius: BorderRadius.circular(9999),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 24,
            fontWeight: FontWeight.w400,
            fontVariations: <FontVariation>[FontVariation('wght', 400)],
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _OverlayOption extends StatelessWidget {
  final String label;
  final bool isActive;
  final Color accent;
  final VoidCallback onTap;

  const _OverlayOption({
    required this.label,
    required this.isActive,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        width: 160,
        height: 32,
        decoration: BoxDecoration(
          color: isActive ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(28),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 24,
            fontWeight: FontWeight.w400,
            fontVariations: const <FontVariation>[
              FontVariation('wght', 400),
            ],
            color: isActive ? Colors.white : const Color(0xFF111827),
          ),
        ),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  final Color accent;
  final VoidCallback onTap;

  const _SaveButton({required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        width: 160,
        height: 40,
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(28),
        ),
        alignment: Alignment.center,
        child: const Text(
          'Save',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 24,
            fontWeight: FontWeight.w400,
            fontVariations: <FontVariation>[FontVariation('wght', 400)],
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
