import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../archive/presentation/providers/archive_provider.dart';
import '../../../archive/presentation/widgets/archive_confirm_dialog.dart';
import '../providers/grade_students_provider.dart';
import '../providers/student_profile_grade_provider.dart';
import 'grade_students_screen.dart' show gradeAccent;
import 'student_profile_memberships_tab.dart';
import 'student_profile_payments_tab.dart';
import 'student_profile_device_tab.dart';
import 'student_profile_security_tab.dart';
import 'student_profile_subjects_tab.dart';
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
/// barrier black 25%). `Overview`, `Subjects`, `Memberships`, `Payments`,
/// `Device` and `Security` have destinations; the remaining sub-nav pills
/// stay static until their screens land.
///
/// The passed [student] pre-fills the hero (name/phone/grade/date) and the
/// Name, Phone, Grade and Student Type rows.
class StudentProfileOverviewScreen extends ConsumerStatefulWidget {
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
  /// `Memberships`, `Payments`, `Device` and `Security` have destinations;
  /// any other value falls back to `Overview`.
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
  ConsumerState<StudentProfileOverviewScreen> createState() =>
      _StudentProfileOverviewScreenState();
}

class _StudentProfileOverviewScreenState
    extends ConsumerState<StudentProfileOverviewScreen> {
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

  /// Guards the Name/Phone persist round-trip (Done) against double taps.
  bool _savingProfile = false;

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
            widget.initialNav == 'Device' ||
            widget.initialNav == 'Security'
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
  /// `Subjects`, `Memberships`, `Payments`, `Device` and `Security` have
  /// destinations; the remaining pills stay static until their screens
  /// land.
  void selectNav(String nav) {
    if (nav != 'Overview' &&
        nav != 'Subjects' &&
        nav != 'Memberships' &&
        nav != 'Payments' &&
        nav != 'Device' &&
        nav != 'Security') {
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

  /// Maps a callable failure to a dashboard-facing message. The
  /// `convertStudentType` incompatibility arrives as `failed-precondition`
  /// carrying a JSON body with `code: INCOMPATIBLE_SUBSCRIPTIONS`.
  static String _functionsErrorMessage(FirebaseFunctionsException error) {
    if (error.code == 'already-exists') {
      return 'رقم الهاتف مسجل لحساب آخر.';
    }
    final String details = error.message ?? '';
    if (details.contains('INCOMPATIBLE_SUBSCRIPTIONS')) {
      return 'لا يمكن التحويل: توجد اشتراكات نشطة غير متوافقة مع النوع الجديد.';
    }
    if (error.code == 'invalid-argument' && details.isNotEmpty) {
      String friendly = details;
      try {
        final Object? decoded = jsonDecode(details);
        if (decoded is Map && decoded['message'] is String) {
          friendly = decoded['message'] as String;
        }
      } catch (_) {}
      return friendly;
    }
    if (details.isNotEmpty) return details;
    return 'تعذّر تنفيذ الإجراء. حاول مرة أخرى.';
  }

  /// Persists one profile field through the audited
  /// `updateStudentProfileByStaff` callable (staff cannot write
  /// `users/{userId}` directly per `firestore.rules`). Returns true when
  /// the value is stored server-side.
  Future<bool> _persistProfileField(String field, String value) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await FirebaseFunctions.instance
          .httpsCallable('updateStudentProfileByStaff')
          .call(<String, dynamic>{
        'studentId': widget.student.id,
        if (field == 'name') 'fullName': value,
        if (field == 'phone') 'phoneNumber': value,
      });
    } on FirebaseFunctionsException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(_functionsErrorMessage(error))),
      );
      return false;
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذّر تنفيذ الإجراء. حاول مرة أخرى.')),
      );
      return false;
    }
    ref.invalidate(gradeStudentsProvider);
    return true;
  }

  void toggleNameEditing() async {
    // Done → persist the edited name before leaving edit mode.
    if (_isEditingName && !_savingProfile) {
      final String next = _nameController.text.trim();
      if (next == widget.student.name.trim()) {
        setState(() => _isEditingName = false);
        _nameFocus.unfocus();
        return;
      }
      if (next.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('الاسم لا يمكن أن يكون فارغًا.')),
        );
        return;
      }
      _savingProfile = true;
      final bool saved = await _persistProfileField('name', next);
      _savingProfile = false;
      if (!mounted) return;
      if (!saved) return;
      setState(() => _isEditingName = false);
      _nameFocus.unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث اسم الطالب بنجاح.')),
      );
      return;
    }
    setState(() => _isEditingName = !_isEditingName);
    if (_isEditingName) {
      _nameFocus.requestFocus();
    } else {
      _nameFocus.unfocus();
    }
  }

  void togglePhoneEditing() async {
    // Done → persist the edited phone before leaving edit mode.
    if (_isEditingPhone && !_savingProfile) {
      final String next = _phoneController.text.trim();
      if (next == (widget.student.phone ?? '').trim()) {
        setState(() => _isEditingPhone = false);
        _phoneFocus.unfocus();
        return;
      }
      if (next.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('رقم الهاتف لا يمكن أن يكون فارغًا.')),
        );
        return;
      }
      _savingProfile = true;
      final bool saved = await _persistProfileField('phone', next);
      _savingProfile = false;
      if (!mounted) return;
      if (!saved) return;
      setState(() => _isEditingPhone = false);
      _phoneFocus.unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث رقم هاتف الطالب بنجاح.')),
      );
      return;
    }
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
          final DashboardBreakpoint breakpoint =
              breakpointForWidth(constraints.maxWidth);
          final bool isMobile = breakpoint == DashboardBreakpoint.mobile;
          final double horizontalPadding = switch (breakpoint) {
            DashboardBreakpoint.mobile => 16,
            DashboardBreakpoint.tablet => 28,
            DashboardBreakpoint.desktop => 48,
          };

          return SingleChildScrollView(
            clipBehavior: Clip.antiAlias,
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              isMobile ? 12 : 20,
              horizontalPadding,
              32,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const ResponsiveScreenHeader(),
                SizedBox(height: isMobile ? 8 : 20),
                Center(
                  child: _ProfileGradeNav(
                    gradeKey: _gradeKey,
                    onGradeSelected: selectGrade,
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: _ProfileCategoryTabs(
                    studentsActive: _studentsActive,
                    accent: _accent,
                    onSelect: _selectCategory,
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: _StudentHeroBar(
                    student: widget.student,
                    gradeLabel: _gradeLabel,
                    accent: _accent,
                    avatarUrl: widget.avatarUrl,
                    deviceLabel: widget.deviceLabel,
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: _ProfileSubNav(
                    selected: _nav,
                    accent: _accent,
                    onSelect: selectNav,
                  ),
                ),
                const SizedBox(height: 20),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 960),
                    child: _buildActiveTabBody(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildActiveTabBody() {
    if (_nav == 'Subjects') {
      return StudentProfileSubjectsTab(
        student: widget.student,
        gradeKey: _gradeKey,
      );
    }
    if (_nav == 'Memberships') {
      return Column(
        children: <Widget>[
          Center(
            child: _StudentTypePill(
              accent: _accent,
              onTap: _showStudentTypeOverlay,
            ),
          ),
          const SizedBox(height: 18),
          StudentProfileMembershipsTab(
            student: widget.student,
            gradeKey: _gradeKey,
          ),
        ],
      );
    }
    if (_nav == 'Payments') {
      return StudentProfilePaymentsTab(
        student: widget.student,
        gradeKey: _gradeKey,
      );
    }
    if (_nav == 'Device') {
      return StudentProfileDeviceTab(
        student: widget.student,
        gradeKey: _gradeKey,
      );
    }
    if (_nav == 'Security') {
      return StudentProfileSecurityTab(
        student: widget.student,
        gradeKey: _gradeKey,
      );
    }
    return _OverviewRows(state: this);
  }

  Future<void> _archiveStudent() async {
    final bool confirmed = await showArchiveConfirmDialog(
      context: context,
      entityLabel: 'Student',
      itemTitle: widget.student.name,
      extraNote:
          'While archived, the student account is temporarily disabled and cannot sign in.',
    );
    if (!confirmed || !mounted) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(archiveControllerProvider)
          .archiveStudent(widget.student.id);
      if (!mounted) return;
      invalidateArchiveDependents(ref);
      messenger.showSnackBar(
        SnackBar(content: Text('${widget.student.name} moved to Archive.')),
      );
      widget.onBack?.call();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFDC2626),
          content: Text(_failureMessage(e)),
        ),
      );
    }
  }

  void _showGradesOverlay() {
    String temp = _gradeKey;
    bool saving = false;
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
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Material(
                  color: Colors.transparent,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 677),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 24,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          const Text(
                            'Grades',
                            style: TextStyle(
                              fontFamily: AppTypography.fontFamily,
                              fontSize: 28,
                              fontWeight: FontWeight.w400,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 20),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
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
                                    onTap: saving
                                        ? () {}
                                        : () => setOverlayState(() => temp =
                                            GradeTheme.allGrades[i].gradeId),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                      _SaveButton(
                        accent: _accent,
                        isLoading: saving,
                        onTap: saving
                            ? () {}
                            : () async {
                                // Capture navigator + messenger before any
                                // async gap (lint:
                                // use_build_context_synchronously).
                                final navigator = Navigator.of(context);
                                final messenger = ScaffoldMessenger.of(
                                  this.context,
                                );
                                if (temp == _gradeKey) {
                                  // No-op: matches the backend (no write,
                                  // no audit event for an unchanged grade).
                                  navigator.pop();
                                  return;
                                }
                                setOverlayState(() => saving = true);
                                try {
                                  await ref
                                      .read(
                                        studentProfileGradeControllerProvider,
                                      )
                                      .updateGrade(
                                        studentId: widget.student.id,
                                        grade: temp,
                                      );
                                } catch (e) {
                                  // Never pretend success: surface the
                                  // backend/permission failure and keep the
                                  // displayed grade unchanged.
                                  setOverlayState(() => saving = false);
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(_failureMessage(e)),
                                    ),
                                  );
                                  return;
                                }
                                if (!mounted) return;
                                // The write succeeded server-side: reflect
                                // the persisted grade locally, close, then
                                // refresh every grade tab's student list so
                                // the student moves tabs without a reload.
                                setState(() => _gradeKey = temp);
                                navigator.pop();
                                ref.invalidate(gradeStudentsProvider);
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content:
                                        Text('تم تحديث فرقة الطالب بنجاح.'),
                                  ),
                                );
                              },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ),
            );
          },
        );
      },
    );
  }

  static String _failureMessage(Object error) {
    final String text = error.toString();
    const String prefix = 'DecisionFailure: ';
    if (text.startsWith(prefix)) return text.substring(prefix.length);
    return 'تعذّر تنفيذ الإجراء. حاول مرة أخرى.';
  }

  void _showStudentTypeOverlay() {
    bool temp = _isCenter;
    bool saving = false;
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
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Material(
                  color: Colors.transparent,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 24,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          const Text(
                            'Student Type',
                            style: TextStyle(
                              fontFamily: AppTypography.fontFamily,
                              fontSize: 28,
                              fontWeight: FontWeight.w400,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Container(
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
                              children: <Widget>[
                                Expanded(
                                  child: _OverlayOption(
                                    label: 'Center',
                                    isActive: temp,
                                    accent: _accent,
                                    onTap: saving
                                        ? () {}
                                        : () =>
                                            setOverlayState(() => temp = true),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: _OverlayOption(
                                    label: 'Guest',
                                    isActive: !temp,
                                    accent: _accent,
                                    onTap: saving
                                        ? () {}
                                        : () =>
                                            setOverlayState(() => temp = false),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                      _SaveButton(
                        accent: _accent,
                        isLoading: saving,
                        onTap: saving
                            ? () {}
                            : () async {
                                // Capture navigator + messenger before any
                                // async gap (lint:
                                // use_build_context_synchronously).
                                final navigator = Navigator.of(context);
                                final messenger = ScaffoldMessenger.of(
                                  this.context,
                                );
                                if (temp == _isCenter) {
                                  // No-op: matches the backend (no write,
                                  // no audit event for an unchanged type).
                                  navigator.pop();
                                  return;
                                }
                                setOverlayState(() => saving = true);
                                try {
                                  await FirebaseFunctions.instance
                                      .httpsCallable('convertStudentType')
                                      .call(<String, dynamic>{
                                    'studentId': widget.student.id,
                                    'targetStudentType': temp
                                        ? 'center_student'
                                        : 'guest',
                                  });
                                } on FirebaseFunctionsException catch (e) {
                                  // Never pretend success: surface the
                                  // backend failure (including
                                  // INCOMPATIBLE_SUBSCRIPTIONS conflicts)
                                  // and keep the displayed type unchanged.
                                  setOverlayState(() => saving = false);
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        _functionsErrorMessage(e),
                                      ),
                                    ),
                                  );
                                  return;
                                } catch (_) {
                                  setOverlayState(() => saving = false);
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'تعذّر تنفيذ الإجراء. حاول مرة أخرى.',
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                if (!mounted) return;
                                // The write succeeded server-side: reflect
                                // the persisted type locally, close, then
                                // refresh every grade tab's student list.
                                setState(() => _isCenter = temp);
                                navigator.pop();
                                ref.invalidate(gradeStudentsProvider);
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'تم تحديث نوع الطالب بنجاح.',
                                    ),
                                  ),
                                );
                              },
                      ),
                    ],
                  ),
                ),
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

/// Grade navigation bar: scrollable on mobile, expanding capsule on desktop.
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        height: 42,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFF979797), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
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
    final bool compact = context.isMobileViewport;
    final double fontSize = compact ? 16 : 22;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(minWidth: compact ? 104 : 150),
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
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
                  fontSize: fontSize,
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
                  fontSize: fontSize,
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

/// Primary category switcher: Students / Subjects.
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
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 336),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: _CategoryTab(
              label: 'Students',
              isActive: studentsActive,
              accent: accent,
              onTap: () => onSelect(true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _CategoryTab(
              label: 'Subjects',
              isActive: !studentsActive,
              accent: accent,
              onTap: () => onSelect(false),
            ),
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
        height: 36,
        color: Colors.transparent,
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: context.isMobileViewport ? 20 : 24,
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

/// Student hero summary bar: responsive Row layout up to 580px wide.
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
    final bool compact = context.isMobileViewport;
    final double avatarSize = compact ? 68 : 96;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 580),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(compact ? 14 : 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(compact ? 32 : 9999),
          border: Border.all(color: accent, width: compact ? 2.5 : 4),
        ),
        child: Row(
          children: <Widget>[
            _HeroAvatar(avatarUrl: avatarUrl, size: avatarSize),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    student.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: compact ? 18 : 24,
                      fontWeight: FontWeight.w500,
                      fontVariations: const <FontVariation>[
                        FontVariation('wght', 500),
                      ],
                      color: const Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    children: <Widget>[
                      Text(
                        phone,
                        style: const TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                      Text(
                        gradeLabel,
                        style: const TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 13,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                      Text(
                        date,
                        style: const TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 13,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                      if (deviceLabel != null && deviceLabel!.isNotEmpty)
                        Text(
                          deviceLabel!,
                          style: const TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontSize: 13,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                    ],
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

/// Hero avatar circle.
class _HeroAvatar extends StatelessWidget {
  final String? avatarUrl;
  final double size;

  const _HeroAvatar({this.avatarUrl, this.size = 96});

  @override
  Widget build(BuildContext context) {
    final Widget fallback = Center(
      child: _FrameIcon(size: size * 0.56),
    );
    return Container(
      width: size,
      height: size,
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
                width: size,
                height: size,
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

class _FrameIcon extends StatelessWidget {
  final double size;

  const _FrameIcon({this.size = 56});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/images/Frame.svg',
      width: size,
      height: size,
      colorFilter: const ColorFilter.mode(
        Color(0xFF9CA3AF),
        BlendMode.srcIn,
      ),
      semanticsLabel: 'Student avatar',
      placeholderBuilder: (BuildContext context) => Icon(
        Icons.person,
        size: size,
        color: const Color(0xFF9CA3AF),
      ),
      errorBuilder: (
        BuildContext context,
        Object error,
        StackTrace? stackTrace,
      ) =>
          Icon(
        Icons.person,
        size: size,
        color: const Color(0xFF9CA3AF),
      ),
    );
  }
}

/// Sub-navigation tabs: horizontally scrollable on mobile, compact row on desktop.
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        height: 42,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFF979797), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
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
        constraints: const BoxConstraints(minWidth: 100),
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
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

/// Overview data rows: stacked on mobile, horizontal flexible rows on tablet/desktop.
class _OverviewRows extends StatelessWidget {
  final _StudentProfileOverviewScreenState state;

  const _OverviewRows({required this.state});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 814),
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
          const SizedBox(height: 28),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: state._archiveStudent,
              icon: const Icon(Icons.archive_outlined, size: 18),
              label: const Text('Archive Student'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFDC2626),
                side: const BorderSide(color: Color(0xFFFCA5A5)),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9999),
                ),
              ),
            ),
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
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compact = constraints.maxWidth < AppBreakpoints.mobileMax;
        final Widget field = _DataField(
          state: state,
          isEditing: isEditing,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: isEditing,
            keyboardType: keyboardType,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: compact ? 18 : 22,
              fontWeight: FontWeight.w400,
              fontVariations: const <FontVariation>[FontVariation('wght', 400)],
              color: const Color(0xFF1F2937),
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
        );
        final Widget action = _ActionButton(
          label: isEditing ? 'Done' : 'Edit',
          state: state,
          compact: compact,
          onTap: onToggle,
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                label,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF374151),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(child: field),
                  const SizedBox(width: 10),
                  action,
                ],
              ),
            ],
          );
        }

        return SizedBox(
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
                    fontSize: 24,
                    fontWeight: FontWeight.w400,
                    fontVariations: <FontVariation>[FontVariation('wght', 400)],
                    color: Colors.black,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 24),
              Expanded(child: field),
              const SizedBox(width: 24),
              action,
            ],
          ),
        );
      },
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
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compact = constraints.maxWidth < AppBreakpoints.mobileMax;
        final Widget field = _DataField(
          state: state,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                value,
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: compact ? 18 : 22,
                  fontWeight: FontWeight.w400,
                  fontVariations: const <FontVariation>[
                    FontVariation('wght', 400),
                  ],
                  color: const Color(0xFF1F2937),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        );
        final Widget action = _ActionButton(
          label: 'Edit',
          state: state,
          compact: compact,
          onTap: onEdit,
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                label,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF374151),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(child: field),
                  const SizedBox(width: 10),
                  action,
                ],
              ),
            ],
          );
        }

        return SizedBox(
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
                    fontSize: 24,
                    fontWeight: FontWeight.w400,
                    fontVariations: <FontVariation>[FontVariation('wght', 400)],
                    color: Colors.black,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 24),
              Expanded(child: field),
              const SizedBox(width: 24),
              action,
            ],
          ),
        );
      },
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
  final bool compact;

  const _ActionButton({
    required this.label,
    required this.state,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9999),
      child: Container(
        width: compact ? 88 : 132,
        height: 48,
        decoration: BoxDecoration(
          color: state._accent,
          borderRadius: BorderRadius.circular(9999),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: compact ? 16 : 22,
            fontWeight: FontWeight.w400,
            fontVariations: const <FontVariation>[FontVariation('wght', 400)],
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
        constraints: const BoxConstraints(minWidth: 112),
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: isActive ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(28),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 18,
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
  final bool isLoading;

  const _SaveButton({
    required this.accent,
    required this.onTap,
    this.isLoading = false,
  });

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
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Text(
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
