import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/responsive/responsive.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/animated_menu_button.dart';
import '../../features/applications/presentation/providers/application_decision_provider.dart';
import '../../features/archive/presentation/screens/archive_screen.dart';
import '../../features/authentication/presentation/providers/auth_providers.dart';
import '../../features/authentication/presentation/providers/sign_out_action.dart';
import '../../features/home/presentation/screens/dashboard_home_screen.dart';
import '../../features/students/presentation/providers/grade_pending_requests_provider.dart';
import '../../features/students/presentation/providers/grade_students_provider.dart';
import '../../features/students/presentation/screens/grade_pending_requests_screen.dart';
import '../../features/students/presentation/screens/grade_pending_requests_view_screen.dart';
import '../../features/students/presentation/screens/grade_students_screen.dart';
import '../../features/students/presentation/screens/student_profile_overview_screen.dart';
import '../../features/students/presentation/screens/subject_details_screen.dart';
import '../../features/students/presentation/widgets/grade_theme.dart';
import '../../features/subscription/presentation/screens/subscription_screen.dart';
import 'dashboard_full_menu.dart';

/// Dashboard sections. Home + four grades + grade pending requests +
/// management suite.
enum DashboardSection {
  home,
  gradeOne,
  gradeTwo,
  gradeThree,
  gradeFour,
  studentProfile,
  subjectDetails,
  pendingRequests,
  pendingRequestView,
  subscription,
  admins,
  announcements,
  auditLogs,
  payments,
  systemSettings,
  archive,
}

/// Fully responsive Dashboard shell using [LayoutBuilder]:
/// - Mobile (`< 768px`): `AppBar` + slide-out `Drawer` navigation, full-width
///   scrollable content without scaling or rigid dimensions.
/// - Tablet (`768px – 1100px`) & Desktop (`> 1100px`): full-viewport layout
///   expanding to fill 100% of available space with top-left [TheMenuButton]
///   toggling [DashboardFullMenu].
class DashboardShell extends ConsumerStatefulWidget {
  const DashboardShell({super.key});

  @override
  ConsumerState<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends ConsumerState<DashboardShell> {
  final GlobalKey<ScaffoldState> _mobileScaffoldKey =
      GlobalKey<ScaffoldState>();

  DashboardSection activeSection = DashboardSection.home;
  bool _menuOpen = false;
  String _pendingGrade = 'grade_one';
  String _gradeTabGrade = 'grade_one';
  bool _gradeSubjectsTab = false;
  PendingRequestRow? _viewRow;
  String _detailsGrade = 'grade_one';
  String _detailsSubjectId = '';
  GradeStudent? _profileStudent;
  String _profileGrade = 'grade_one';

  /// Unified open state consumed by the fixed top-layer [TheMenuButton].
  bool get isMenuOpen => _menuOpen;

  /// Single toggle for the fixed top-layer button — opens and closes
  /// the full-menu overlay on tablet/desktop.
  void toggleMenu() => setState(() => _menuOpen = !_menuOpen);

  void _openMenu() => setState(() => _menuOpen = true);
  void _closeMenu() => setState(() => _menuOpen = false);

  /// "Review Pending Requests" CTA → dedicated pending-requests screen.
  void _openPendingRequests(String gradeKey) => setState(() {
        activeSection = DashboardSection.pendingRequests;
        _pendingGrade = gradeKey;
      });

  /// Table View → full review screen for the selected request.
  void _openRequestView(PendingRequestRow row) => setState(() {
        _viewRow = row;
        _pendingGrade = row.application.gradeKey ?? _pendingGrade;
        activeSection = DashboardSection.pendingRequestView;
      });

  /// Back from the review screen → pending-requests table.
  void _closeRequestView() => setState(() {
        activeSection = DashboardSection.pendingRequests;
      });

  /// Table View → full Student Profile Overview for the tapped row.
  /// The screen's current grade tab is passed through so the profile
  /// opens in the same grade context (Grade One ⇒ yellow theme).
  void _openStudentProfile(GradeStudent student, String gradeKey) =>
      setState(() {
        _profileStudent = student;
        _profileGrade = gradeKey;
        _gradeTabGrade = gradeKey;
        activeSection = DashboardSection.studentProfile;
      });

  /// Back from the profile → students table of the same grade.
  void _closeStudentProfile() => setState(() {
        activeSection = _sectionForGrade(_profileGrade);
      });

  /// Grade students screen for [gradeKey], optionally on Subjects tab.
  void _openGradeStudents(String gradeKey, {bool subjectsTab = false}) =>
      setState(() {
        activeSection = _sectionForGrade(gradeKey);
        _gradeTabGrade = gradeKey;
        _gradeSubjectsTab = subjectsTab;
        _profileStudent = null;
      });

  /// Subject Details page for one subject inside its grade context.
  void _openSubjectDetailsForSubject(SubjectOption subject) => setState(() {
        final String resolved = GradeTheme.fromKey(
          subject.gradeKey ?? _gradeTabGrade,
        ).gradeId;
        activeSection = DashboardSection.subjectDetails;
        _detailsGrade = resolved;
        _detailsSubjectId = subject.id;
        _gradeTabGrade = resolved;
      });

  static DashboardSection _sectionForGrade(String gradeKey) {
    return switch (gradeKey) {
      'grade_two' => DashboardSection.gradeTwo,
      'grade_three' => DashboardSection.gradeThree,
      'grade_four' => DashboardSection.gradeFour,
      _ => DashboardSection.gradeOne,
    };
  }

  void _navigate(String route) {
    setState(() {
      activeSection = _sectionFor(route);
      _menuOpen = false;
      _profileStudent = null;
      final String? gradeKey = _gradeKeyForRoute(route);
      if (gradeKey != null) {
        _gradeTabGrade = gradeKey;
        _gradeSubjectsTab = false;
      }
    });
  }

  static String? _gradeKeyForRoute(String route) {
    return switch (route) {
      DashboardMenuRoutes.gradeOne => 'grade_one',
      DashboardMenuRoutes.gradeTwo => 'grade_two',
      DashboardMenuRoutes.gradeThree => 'grade_three',
      DashboardMenuRoutes.gradeFour => 'grade_four',
      _ => null,
    };
  }

  static DashboardSection _sectionFor(String route) {
    switch (route) {
      case DashboardMenuRoutes.gradeOne:
        return DashboardSection.gradeOne;
      case DashboardMenuRoutes.gradeTwo:
        return DashboardSection.gradeTwo;
      case DashboardMenuRoutes.gradeThree:
        return DashboardSection.gradeThree;
      case DashboardMenuRoutes.gradeFour:
        return DashboardSection.gradeFour;
      case DashboardMenuRoutes.subscription:
        return DashboardSection.subscription;
      case DashboardMenuRoutes.admins:
        return DashboardSection.admins;
      case DashboardMenuRoutes.announcements:
        return DashboardSection.announcements;
      case DashboardMenuRoutes.auditLogs:
        return DashboardSection.auditLogs;
      case DashboardMenuRoutes.payments:
        return DashboardSection.payments;
      case DashboardMenuRoutes.systemSettings:
        return DashboardSection.systemSettings;
      case DashboardMenuRoutes.archive:
        return DashboardSection.archive;
      case DashboardMenuRoutes.home:
      default:
        return DashboardSection.home;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final DashboardBreakpoint breakpoint =
            breakpointForWidth(constraints.maxWidth);

        if (breakpoint == DashboardBreakpoint.mobile) {
          return Scaffold(
            key: _mobileScaffoldKey,
            backgroundColor: AppColors.background,
            appBar: AppBar(
              toolbarHeight: 60,
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              elevation: 0,
              scrolledUnderElevation: 0,
              iconTheme: const IconThemeData(color: Color(0xFF111827)),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Container(height: 1, color: const Color(0xFFE5E7EB)),
              ),
              title: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text.rich(
                  TextSpan(
                    children: <TextSpan>[
                      TextSpan(
                        text: 'Tarek el araby ',
                        style: AppTypography.homeBrandHeavy(fontSize: 22),
                      ),
                      TextSpan(
                        text: 'Platform',
                        style: AppTypography.homeBrandLight(fontSize: 22),
                      ),
                    ],
                  ),
                  maxLines: 1,
                ),
              ),
            ),
            drawer: _MobileDashboardDrawer(
              activeSection: activeSection,
              onSelectRoute: (String route) {
                Navigator.of(context).pop();
                _navigate(route);
              },
              onSignOut: () {
                Navigator.of(context).pop();
                confirmAndSignOut(context, ref);
              },
            ),
            body: SafeArea(
              top: false,
              child: SizedBox.expand(
                child: _contentFor(activeSection),
              ),
            ),
          );
        }

        final bool isDesktop = breakpoint == DashboardBreakpoint.desktop;
        return Scaffold(
          backgroundColor: AppColors.background,
          body: SizedBox.expand(
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Positioned.fill(
                  child: _contentFor(activeSection),
                ),
                if (isMenuOpen)
                  Positioned.fill(
                    child: DashboardFullMenu(
                      onClose: _closeMenu,
                      onNavigate: _navigate,
                      onSignOut: () => confirmAndSignOut(context, ref),
                    ),
                  ),
                Positioned(
                  left: isDesktop ? 48 : 20,
                  top: isDesktop ? 20 : 16,
                  width: 80,
                  height: 80,
                  child: TheMenuButton(
                    isOpen: isMenuOpen,
                    onTap: toggleMenu,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _contentFor(DashboardSection section) {
    switch (section) {
      case DashboardSection.home:
        return DashboardHomeScreen(
          onMenuPressed: _openMenu,
          onNavigate: _openGradeStudents,
        );
      case DashboardSection.gradeOne:
      case DashboardSection.gradeTwo:
      case DashboardSection.gradeThree:
      case DashboardSection.gradeFour:
        return GradeStudentsScreen(
          key: ValueKey<String>(
            'grade-$_gradeTabGrade-subjects-$_gradeSubjectsTab',
          ),
          initialGradeKey: _gradeTabGrade,
          initialSubjectsTab: _gradeSubjectsTab,
          onMenuPressed: _openMenu,
          onReviewPending: _openPendingRequests,
          onStudentTap: _openStudentProfile,
          onSubjectTap: (subject) => _openSubjectDetailsForSubject(subject),
        );
      case DashboardSection.studentProfile:
        final GradeStudent? profileStudent = _profileStudent;
        if (profileStudent == null) {
          return GradeStudentsScreen(
            key: ValueKey<String>(
              'grade-$_gradeTabGrade-subjects-$_gradeSubjectsTab',
            ),
            initialGradeKey: _gradeTabGrade,
            initialSubjectsTab: _gradeSubjectsTab,
            onMenuPressed: _openMenu,
            onReviewPending: _openPendingRequests,
            onStudentTap: _openStudentProfile,
          );
        }
        return StudentProfileOverviewScreen(
          key: ValueKey<String>(
              'student-profile-${profileStudent.id}-$_profileGrade'),
          student: profileStudent,
          gradeKey: _profileGrade,
          avatarUrl: profileStudent.photoUrl,
          onBack: _closeStudentProfile,
          onGradeSelected: _openGradeStudents,
          onStudentsTab: () => _openGradeStudents(_profileGrade),
          onSubjectsTab: () =>
              _openGradeStudents(_profileGrade, subjectsTab: true),
        );
      case DashboardSection.subjectDetails:
        return SubjectDetailsScreen(
          key: ValueKey<String>(
              'subject-details-$_detailsGrade-$_detailsSubjectId'),
          gradeKey: _detailsGrade,
          subjectId: _detailsSubjectId,
          onGradeSelected: (String gradeKey) =>
              _openGradeStudents(gradeKey, subjectsTab: true),
          onStudentsTab: () => _openGradeStudents(_detailsGrade),
          onSubjectsTab: () =>
              _openGradeStudents(_detailsGrade, subjectsTab: true),
          onSubjectDeleted: () =>
              _openGradeStudents(_detailsGrade, subjectsTab: true),
          onSubjectGradeChanged: (String gradeKey) => setState(() {
            _detailsGrade = gradeKey;
          }),
        );
      case DashboardSection.pendingRequests:
        return GradePendingRequestsScreen(
          key: ValueKey<String>('pending-$_pendingGrade'),
          initialGradeKey: _pendingGrade,
          onMenuPressed: _openMenu,
          onStudentsTab: (String gradeKey) => _openGradeStudents(gradeKey),
          onSubjectsTab: (String gradeKey) =>
              _openGradeStudents(gradeKey, subjectsTab: true),
          onViewRequest: _openRequestView,
        );
      case DashboardSection.pendingRequestView:
        final PendingRequestRow? row = _viewRow;
        if (row == null) {
          return GradePendingRequestsScreen(
            key: ValueKey<String>('pending-$_pendingGrade'),
            initialGradeKey: _pendingGrade,
            onMenuPressed: _openMenu,
            onStudentsTab: (String gradeKey) => _openGradeStudents(gradeKey),
            onSubjectsTab: (String gradeKey) =>
                _openGradeStudents(gradeKey, subjectsTab: true),
            onViewRequest: _openRequestView,
          );
        }
        return GradePendingRequestsViewScreen(
          key: ValueKey<String>('pending-view-${row.application.id}'),
          row: row,
          onMenuPressed: _openMenu,
          onStudentsTab: (String gradeKey) => _openGradeStudents(gradeKey),
          onSubjectsTab: (String gradeKey) =>
              _openGradeStudents(gradeKey, subjectsTab: true),
          onBack: _closeRequestView,
        );
      case DashboardSection.subscription:
        return Consumer(
          builder: (BuildContext context, WidgetRef ref, _) {
            final bool isDoctor = ref.watch(sessionProvider).maybeWhen(
                  data: (session) => session?.role == 'doctor',
                  orElse: () => false,
                );
            return SubscriptionScreen(isDoctor: isDoctor);
          },
        );
      case DashboardSection.admins:
        return const _SectionFrame(
          title: 'Admins',
          child: _ComingNext(),
        );
      case DashboardSection.announcements:
        return const _SectionFrame(
          title: 'Announcements',
          child: _ComingNext(),
        );
      case DashboardSection.auditLogs:
        return const _SectionFrame(
          title: 'Audit Logs',
          child: _ComingNext(),
        );
      case DashboardSection.payments:
        return const _SectionFrame(
          title: 'Payments',
          child: _ComingNext(),
        );
      case DashboardSection.systemSettings:
        return const _SectionFrame(
          title: 'System Settings',
          child: _ComingNext(),
        );
      case DashboardSection.archive:
        return const ArchiveScreen();
    }
  }
}

class _MobileDashboardDrawer extends StatelessWidget {
  final DashboardSection activeSection;
  final ValueChanged<String> onSelectRoute;
  final VoidCallback? onSignOut;

  const _MobileDashboardDrawer({
    required this.activeSection,
    required this.onSelectRoute,
    this.onSignOut,
  });

  static DashboardSection _sectionForRoute(String route) {
    return switch (route) {
      DashboardMenuRoutes.gradeOne => DashboardSection.gradeOne,
      DashboardMenuRoutes.gradeTwo => DashboardSection.gradeTwo,
      DashboardMenuRoutes.gradeThree => DashboardSection.gradeThree,
      DashboardMenuRoutes.gradeFour => DashboardSection.gradeFour,
      DashboardMenuRoutes.subscription => DashboardSection.subscription,
      DashboardMenuRoutes.admins => DashboardSection.admins,
      DashboardMenuRoutes.announcements => DashboardSection.announcements,
      DashboardMenuRoutes.auditLogs => DashboardSection.auditLogs,
      DashboardMenuRoutes.payments => DashboardSection.payments,
      DashboardMenuRoutes.systemSettings => DashboardSection.systemSettings,
      DashboardMenuRoutes.archive => DashboardSection.archive,
      _ => DashboardSection.home,
    };
  }

  static Color? _dotColorForRoute(String route) {
    return switch (route) {
      DashboardMenuRoutes.gradeOne => AppColors.gradeOne,
      DashboardMenuRoutes.gradeTwo => AppColors.gradeTwo,
      DashboardMenuRoutes.gradeThree => AppColors.gradeThree,
      DashboardMenuRoutes.gradeFour => AppColors.gradeFour,
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text.rich(
                        TextSpan(
                          children: <TextSpan>[
                            TextSpan(
                              text: 'Tarek el araby ',
                              style: AppTypography.homeBrandHeavy(fontSize: 22),
                            ),
                            TextSpan(
                              text: 'Platform',
                              style: AppTypography.homeBrandLight(fontSize: 22),
                            ),
                          ],
                        ),
                        maxLines: 1,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close menu',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE5E7EB)),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                children: <Widget>[
                  _DrawerEntry(
                    label: 'Home',
                    icon: Icons.home_outlined,
                    selected: activeSection == DashboardSection.home,
                    onTap: () => onSelectRoute(DashboardMenuRoutes.home),
                  ),
                  const SizedBox(height: 16),
                  const _DrawerGroupLabel('Grades'),
                  const SizedBox(height: 4),
                  for (final item in DashboardMenuData.grades)
                    _DrawerEntry(
                      label: item.label,
                      dotColor: _dotColorForRoute(item.route),
                      selected: activeSection == _sectionForRoute(item.route),
                      onTap: () => onSelectRoute(item.route),
                    ),
                  const SizedBox(height: 16),
                  const _DrawerGroupLabel('Management'),
                  const SizedBox(height: 4),
                  for (final item in DashboardMenuData.management)
                    _DrawerEntry(
                      label: item.label,
                      icon: item.route == DashboardMenuRoutes.archive
                          ? Icons.archive_outlined
                          : Icons.tune_rounded,
                      selected: activeSection == _sectionForRoute(item.route),
                      onTap: () => onSelectRoute(item.route),
                    ),
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: Color(0xFFE5E7EB)),
                  const SizedBox(height: 8),
                  ListTile(
                    dense: true,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    leading: const Icon(
                      Icons.logout_rounded,
                      size: 20,
                      color: Color(0xFFDC2626),
                    ),
                    title: const Text(
                      'Sign Out',
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                    onTap: onSignOut,
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

class _DrawerGroupLabel extends StatelessWidget {
  final String text;

  const _DrawerGroupLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFF6B7280),
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _DrawerEntry extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? dotColor;
  final bool selected;
  final VoidCallback onTap;

  const _DrawerEntry({
    required this.label,
    this.icon,
    this.dotColor,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? const Color(0xFFF3F4F6) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: <Widget>[
                if (dotColor != null)
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(left: 4, right: 14),
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                  )
                else if (icon != null) ...<Widget>[
                  Icon(
                    icon,
                    size: 20,
                    color: selected
                        ? const Color(0xFF111827)
                        : const Color(0xFF6B7280),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 16,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected
                          ? const Color(0xFF111827)
                          : const Color(0xFF374151),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Framed inner section: responsive header + title + content.
class _SectionFrame extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionFrame({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double horizontalPadding =
            breakpointForWidth(constraints.maxWidth) ==
                    DashboardBreakpoint.mobile
                ? 16
                : breakpointForWidth(constraints.maxWidth) ==
                        DashboardBreakpoint.tablet
                    ? 28
                    : 48;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            20,
            horizontalPadding,
            40,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const ResponsiveScreenHeader(),
              const SizedBox(height: 24),
              Text(
                title,
                style: AppTypography.sectionHeading(
                  fontSize: constraints.maxWidth < AppBreakpoints.mobileMax
                      ? 24
                      : 32,
                ),
              ),
              const SizedBox(height: 24),
              child,
            ],
          ),
        );
      },
    );
  }
}

class _ComingNext extends StatelessWidget {
  const _ComingNext();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'This section is coming next.',
        style: AppTypography.statLabel(fontSize: 20),
        textAlign: TextAlign.center,
      ),
    );
  }
}
