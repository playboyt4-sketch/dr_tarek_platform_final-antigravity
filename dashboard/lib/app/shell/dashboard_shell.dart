import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_typography.dart';
import '../../core/widgets/animated_menu_button.dart';
import '../../features/authentication/presentation/providers/auth_providers.dart';
import '../../features/home/presentation/screens/dashboard_home_screen.dart';
import '../../features/students/presentation/providers/grade_pending_requests_provider.dart';
import '../../features/students/presentation/providers/grade_students_provider.dart';
import '../../features/students/presentation/screens/grade_pending_requests_screen.dart';
import '../../features/students/presentation/screens/grade_pending_requests_view_screen.dart';
import '../../features/students/presentation/screens/grade_students_screen.dart';
import '../../features/students/presentation/screens/student_profile_overview_screen.dart';
import '../../features/students/presentation/screens/subject_details_screen.dart';
import '../../features/applications/presentation/providers/application_decision_provider.dart';
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
}

/// App shell for the 1280 x 800 dashboard with a geometrically-locked
/// centered canvas: every page renders inside a fixed 1280 x 800 canvas
/// that stays centered in the browser window ([Center] + [FittedBox]
/// scaleDown), so grade screens never stick to the left. A unified top
/// [Stack] layer keeps [TheMenuButton] at the exact canvas pixel
/// (80, 24, 80 x 80) on every screen, so opening the
/// [DashboardFullMenu] overlay never shifts the button by a single pixel.
class DashboardShell extends StatefulWidget {
  const DashboardShell({super.key});

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
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
  /// the full-menu overlay without moving a single pixel.
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
  ///
  /// Dashboard-level grade navigation always leaves any detail state:
  /// the selected student profile is cleared so a grade tap from inside
  /// a profile returns to that grade's Students list instead of
  /// re-contextualizing the open profile.
  void _openGradeStudents(String gradeKey, {bool subjectsTab = false}) =>
      setState(() {
        activeSection = _sectionForGrade(gradeKey);
        _gradeTabGrade = gradeKey;
        _gradeSubjectsTab = subjectsTab;
        _profileStudent = null;
      });

  /// Subject Details page for one subject inside its grade context.
  ///
  /// The [SubjectOption.gradeKey] carried from Firestore is the single
  /// source of truth for the grade context: the shell's cached
  /// [_gradeTabGrade] can be stale when the grade was switched inside
  /// [GradeStudentsScreen] (its internal nav owns a local `_gradeKey`
  /// that never notifies the shell). Deriving [_detailsGrade] from the
  /// subject itself keeps selected grade → [GradeTheme] → active nav
  /// pill → Subject Details on the same grade. A null/missing subject
  /// grade falls back to the shell's current tab grade; both paths are
  /// canonicalized through [GradeTheme.fromKey] so legacy spellings
  /// (`grade_1`, `1`, …) resolve to the same `grade_*` id.
  /// Canonical entry point for subject-card navigation.
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
      case DashboardMenuRoutes.home:
      default:
        return DashboardSection.home;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: SizedBox(
            width: 1280,
            height: 800,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // محتوى الصفحة (يبدأ محتواه الداخلي عند X: 80px)
                _contentFor(activeSection),

                // القائمة الكاملة
                if (isMenuOpen)
                  DashboardFullMenu(
                    onClose: _closeMenu,
                    onNavigate: (String section) {
                      _navigate(section);
                    },
                  ),

                // زر المنيو داخل الـ 1280 الموسط:
                // يبدأ عند left: 80px بالمللي ليستقر فوق كارت الدائرة والجدول تماماً:
                Positioned(
                  left: 80,
                  top: 24,
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
        ),
      ),
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
          onSubjectTap: (subject) =>
              _openSubjectDetailsForSubject(subject),
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
          // Dashboard-level controls: grade tabs exit the profile to
          // that grade's Students list, Students returns to the current
          // grade's list, Subjects opens the grade's Subjects view.
          // Each clears the selected student; none edits users.grade.
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
          onStudentsTab: () =>
              _openGradeStudents(_detailsGrade),
          onSubjectsTab: () =>
              _openGradeStudents(_detailsGrade, subjectsTab: true),
          onSubjectDeleted: () =>
              _openGradeStudents(_detailsGrade, subjectsTab: true),
          onSubjectGradeChanged: (String gradeKey) => setState(() {
            // Stay on the details page; the new key remounts it in the
            // subject's new grade context.
            _detailsGrade = gradeKey;
          }),
        );
      case DashboardSection.pendingRequests:
        return GradePendingRequestsScreen(
          key: ValueKey<String>('pending-$_pendingGrade'),
          initialGradeKey: _pendingGrade,
          onMenuPressed: _openMenu,
          onStudentsTab: (String gradeKey) =>
              _openGradeStudents(gradeKey),
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
            onStudentsTab: (String gradeKey) =>
                _openGradeStudents(gradeKey),
            onSubjectsTab: (String gradeKey) =>
                _openGradeStudents(gradeKey, subjectsTab: true),
            onViewRequest: _openRequestView,
          );
        }
        return GradePendingRequestsViewScreen(
          key: ValueKey<String>('pending-view-${row.application.id}'),
          row: row,
          onMenuPressed: _openMenu,
          onStudentsTab: (String gradeKey) =>
              _openGradeStudents(gradeKey),
          onSubjectsTab: (String gradeKey) =>
              _openGradeStudents(gradeKey, subjectsTab: true),
          onBack: _closeRequestView,
        );
      case DashboardSection.subscription:
        // Role-aware gating: delegated Admins see the rolling-window rows
        // locked (Doctor only); the backend re-enforces this server-side.
        // Unknown/loading sessions fail closed (locked).
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
    }
  }
}

/// Framed inner section: header brand + title + content.
///
/// The unified shell now owns the fixed top-layer [TheMenuButton] at
/// (80, 24, 80 x 80), so this frame only reserves the 290 px spacer
/// (80 button + 210 gap) to keep the brand locked at (370, 24).
class _SectionFrame extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionFrame({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 24, 0, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // Spacer matching the shell's fixed button (80) + gap
                    // (210) so the brand stays at X 370.
                    const SizedBox(width: 290, height: 80),
                    SizedBox(
                      width: 540,
                      height: 80,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text.rich(
                          TextSpan(
                            children: <TextSpan>[
                              TextSpan(
                                text: 'Tarek el araby ',
                                style: AppTypography.homeBrandHeavy(
                                    fontSize: 48),
                              ),
                              TextSpan(
                                text: 'Platform',
                                style: AppTypography.homeBrandLight(
                                    fontSize: 48),
                              ),
                            ],
                          ),
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Text(title,
                    style: AppTypography.sectionHeading(fontSize: 32)),
                const SizedBox(height: 24),
                child,
              ],
            ),
          ),
        ),
      ),
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
        style: AppTypography.statLabel(fontSize: 24),
        textAlign: TextAlign.center,
      ),
    );
  }
}
