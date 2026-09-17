import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../applications/presentation/providers/application_decision_provider.dart';
import '../providers/grade_students_provider.dart';
import '../widgets/add_subject_overlay.dart';
import '../widgets/dashboard_brand_lockup.dart';
import '../widgets/grade_nav_bar.dart';
import '../widgets/grade_theme.dart';
import '../widgets/scoped_search_bar.dart';
import '../widgets/subject_card_item.dart';

/// Grade accent per canonical grade key.
Color gradeAccent(String gradeKey) {
  return switch (gradeKey) {
    'grade_two' => AppColors.gradeTwo,
    'grade_three' => AppColors.gradeThree,
    'grade_four' => AppColors.gradeFour,
    _ => AppColors.gradeOne,
  };
}

StudentSearchScope _toDataScope(SearchScope scope) {
  return switch (scope) {
    SearchScope.name => StudentSearchScope.name,
    SearchScope.type => StudentSearchScope.type,
    SearchScope.plan => StudentSearchScope.plan,
    SearchScope.status => StudentSearchScope.status,
  };
}

/// Grade students screen (`# Grade- Grade one - students`):
/// fixed 1280 x 800 canvas, pure white.
///
/// - header: brand 540 x 80 at (370, 24); the unified shell draws the
///   single fixed menu button at (80, 24, 80 x 80);
/// - grades nav 660 x 40 at (310, 136), pills 160 x 32 (gap 4);
/// - sub tabs 336 x 40 at (472, 190), Students active / Subjects;
/// - stats row at Y 250: total capsule (80, 250, 250 x 124),
///   plan breakdown (370, 250, 250 x 128), pending CTA
///   (660, 250, 540 x 124);
/// - [ScopedSearchBar] at (430, 427), 420 x 44, live filtering;
/// - students table (80, 522, 1120 x 260): 40 px sticky header +
///   48 px scrollable rows, status capsules + 88 x 32 View buttons.
class GradeStudentsScreen extends ConsumerStatefulWidget {
  final String initialGradeKey;

  /// When true the screen opens on the Subjects tab instead of Students.
  final bool initialSubjectsTab;
  final VoidCallback? onMenuPressed;
  final ValueChanged<String>? onReviewPending;

  /// Table "View" destination. When set, tapping View navigates to the
  /// full Student Profile Overview for (student, current gradeKey)
  /// instead of opening the legacy details dialog.
  final void Function(GradeStudent student, String gradeKey)? onStudentTap;

  /// Subject card tap destination. When null, the interim
  /// [SubjectDetailsDialog] is shown (legacy behavior).
  final ValueChanged<SubjectOption>? onSubjectTap;

  const GradeStudentsScreen({
    super.key,
    this.initialGradeKey = 'grade_one',
    this.initialSubjectsTab = false,
    this.onMenuPressed,
    this.onReviewPending,
    this.onStudentTap,
    this.onSubjectTap,
  });

  @override
  ConsumerState<GradeStudentsScreen> createState() =>
      _GradeStudentsScreenState();
}

class _GradeStudentsScreenState extends ConsumerState<GradeStudentsScreen> {
  late String _gradeKey = widget.initialGradeKey;
  late bool _studentsTab = !widget.initialSubjectsTab;
  SearchScope _scope = SearchScope.name;
  String _query = '';

  Color get _accent => gradeAccent(_gradeKey);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFFFFF),
      child: SingleChildScrollView(
        clipBehavior: Clip.antiAlias,
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 1280,
            height: 800,
            child: Stack(
              children: <Widget>[
                const Positioned(
                  left: 370,
                  top: 24,
                  width: 540,
                  height: 80,
                  child:
                      IgnorePointer(child: DashboardBrandLockup()),
                ),
                Positioned(
                  left: 310,
                  top: 136,
                  width: 660,
                  height: 40,
                  child: GradeNavBar(
                    gradeKey: _gradeKey,
                    onGradeSelected: (String key) => setState(() {
                      _gradeKey = key;
                      _query = '';
                    }),
                  ),
                ),
                Positioned(
                  left: 474,
                  top: 190,
                  width: 332,
                  height: 40,
                  child: StudentsSubjectsTabs(
                    studentsActive: _studentsTab,
                    accent: _accent,
                    onStudentsTap: () =>
                        setState(() => _studentsTab = true),
                    onSubjectsTap: () =>
                        setState(() => _studentsTab = false),
                  ),
                ),
                if (_studentsTab) ...<Widget>[
                  _StatsRow(
                    gradeKey: _gradeKey,
                    accent: _accent,
                    onReviewPending: () =>
                        widget.onReviewPending?.call(_gradeKey),
                  ),
                  Positioned(
                    left: 430,
                    top: 427,
                    width: 420,
                    height: 44,
                    child: ScopedSearchBar(
                      onScopeChanged: (SearchScope scope) =>
                          setState(() => _scope = scope),
                      onSearchChanged: (String value) =>
                          setState(() => _query = value),
                    ),
                  ),
                  _StudentsTable(
                    gradeKey: _gradeKey,
                    accent: _accent,
                    scope: _toDataScope(_scope),
                    query: _query,
                    onStudentTap: widget.onStudentTap,
                  ),
                ] else
                  _SubjectsPane(
                    gradeKey: _gradeKey,
                    accent: _accent,
                    onSubjectTap: widget.onSubjectTap,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Stats row at Y 250: total capsule + plan breakdown + pending CTA.
class _StatsRow extends ConsumerWidget {
  final String gradeKey;
  final Color accent;
  final VoidCallback onReviewPending;

  const _StatsRow({
    required this.gradeKey,
    required this.accent,
    required this.onReviewPending,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<GradeStudentsData> dataAsync =
        ref.watch(gradeStudentsProvider(gradeKey));
    return dataAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (Object error, StackTrace stackTrace) =>
          const SizedBox.shrink(),
      data: (GradeStudentsData data) {
        return Stack(
          children: <Widget>[
            // Total students capsule (80, 250, 250 x 124).
            Positioned(
              left: 80,
              top: 250,
              width: 250,
              height: 124,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(9999),
                  border: Border.all(color: accent, width: 1.5),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const Text(
                      'Total Students',
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${data.total}',
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Frame 39 plan breakdown (370, 250, 250 x 128).
            Positioned(
              left: 370,
              top: 250,
              width: 250,
              height: 128,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (int i = 0; i < data.breakdown.length; i++) ...<Widget>[
                    if (i > 0) const SizedBox(height: 6),
                    Text(
                      '${data.breakdown[i].label}: '
                      '${data.breakdown[i].count} '
                      '(${data.breakdown[i].share}%)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 13,
                        height: 1.3,
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF374151),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Pending CTA capsule (660, 250, 540 x 124).
            Positioned(
              left: 660,
              top: 250,
              width: 540,
              height: 124,
              child: Material(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9999),
                  side: BorderSide(color: accent, width: 2),
                ),
                child: InkWell(
                  onTap: onReviewPending,
                  borderRadius: BorderRadius.circular(9999),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      const Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Review Pending Requests',
                            maxLines: 1,
                            style: TextStyle(
                              fontFamily: AppTypography.fontFamily,
                              fontSize: 22,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF374151),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(9999),
                        ),
                        child: Text(
                          '${data.pendingCount}',
                          style: const TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFFFFFFF),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Text(
                        '>',
                        style: TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF111827),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Students table (80, 522, 1120 x 260): 40 px header + scrollable rows.
class _StudentsTable extends ConsumerWidget {
  final String gradeKey;
  final Color accent;
  final StudentSearchScope scope;
  final String query;
  final void Function(GradeStudent student, String gradeKey)? onStudentTap;

  const _StudentsTable({
    required this.gradeKey,
    required this.accent,
    required this.scope,
    required this.query,
    this.onStudentTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<GradeStudentsData> dataAsync =
        ref.watch(gradeStudentsProvider(gradeKey));
    return Positioned(
      left: 80,
      top: 522,
      width: 1120,
      height: 260,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x0D000000),
                blurRadius: 20,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: dataAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (Object error, StackTrace stackTrace) => const Center(
              child: Text(
                'Could not load students.',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 14,
                  color: Color(0xFF6B7280),
                ),
              ),
            ),
            data: (GradeStudentsData data) {
              final List<GradeStudent> rows =
                  filterStudents(data.students, scope, query);
              return Column(
                children: <Widget>[
                  const _TableHeader(),
                  Container(height: 1, color: const Color(0xFFE5E7EB)),
                  Expanded(
                    child: rows.isEmpty
                        ? const Center(
                            child: Text(
                              'No students found.',
                              style: TextStyle(
                                fontFamily: AppTypography.fontFamily,
                                fontSize: 14,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: EdgeInsets.zero,
                            itemCount: rows.length,
                            separatorBuilder:
                                (BuildContext context, int index) =>
                                    Container(
                              height: 1,
                              color: const Color(0xFFF3F4F6),
                            ),
                            itemBuilder:
                                (BuildContext context, int index) {
                              final GradeStudent student = rows[index];
                              final void Function(GradeStudent, String)?
                                  openProfile = onStudentTap;
                              return _StudentRow(
                                number: index + 1,
                                student: student,
                                accent: accent,
                                onViewPressed: openProfile == null
                                    ? () => showStudentDetailsDialog(
                                        context, student)
                                    : () =>
                                        openProfile(student, gradeKey),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

const List<({String label, int flex})> _columns =
    <({String label, int flex})>[
  (label: 'No.', flex: 1),
  (label: 'Student Name', flex: 4),
  (label: 'Type', flex: 2),
  (label: 'Plan', flex: 2),
  (label: 'Status', flex: 2),
  (label: 'Last Sign in', flex: 2),
  (label: 'Action', flex: 2),
];

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: <Widget>[
            for (final column in _columns)
              Expanded(
                flex: column.flex,
                child: Text(
                  column.label,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StudentRow extends StatelessWidget {
  final int number;
  final GradeStudent student;
  final Color accent;
  final VoidCallback onViewPressed;

  const _StudentRow({
    required this.number,
    required this.student,
    required this.accent,
    required this.onViewPressed,
  });

  @override
  Widget build(BuildContext context) {
    final bool active = student.isActive;
    return SizedBox(
      height: 48,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: <Widget>[
            Expanded(
              flex: 1,
              child: Text(
                '${number.toString().padLeft(2, '0')}.',
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 14,
                  color: Color(0xFF6B7280),
                ),
              ),
            ),
            Expanded(
              flex: 4,
              child: Text(
                student.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 14,
                  color: Color(0xFF111827),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(9999),
                  ),
                  child: Text(
                    student.typeLabel,
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF374151),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                student.plan,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111827),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(0xFFECFDF5)
                        : const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(9999),
                  ),
                  child: Text(
                    student.statusLabel,
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: active
                          ? const Color(0xFF059669)
                          : const Color(0xFFDC2626),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                student.lastSignIn,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 14,
                  color: Color(0xFF111827),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 88,
                  height: 32,
                  child: ElevatedButton(
                    onPressed: onViewPressed,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9999),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'View',
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFFFFFFFF),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Legacy details dialog — only used when [GradeStudentsScreen.onStudentTap]
/// is null (e.g. in widget tests). Production shells always wire
/// [GradeStudentsScreen.onStudentTap], so View navigates to the full
/// Student Profile Overview screen instead.
void showStudentDetailsDialog(BuildContext context, GradeStudent student) {
  showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          student.name,
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _DetailLine(label: 'Type', value: student.typeLabel),
            _DetailLine(label: 'Plan', value: student.plan),
            _DetailLine(label: 'Status', value: student.statusLabel),
            _DetailLine(label: 'Last Sign in', value: student.lastSignIn),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

class _DetailLine extends StatelessWidget {
  final String label;
  final String value;

  const _DetailLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 14,
          color: Color(0xFF374151),
        ),
      ),
    );
  }
}

/// Subjects pane (80, 276, 1120 wide): destination of the Subjects tab.
///
/// Figma `# Grade- Grade one - subjects`:
/// - scrollable body [Y:276], margins 80, W:1120, AlwaysScrollableScrollPhysics
/// - 2-column grid, gap 40h / 24v, card 540x128 + Add card always last
/// - card tap → details dialog; Add tap → add-subject overlay.
class _SubjectsPane extends ConsumerWidget {
  final String gradeKey;
  final Color accent;
  final ValueChanged<SubjectOption>? onSubjectTap;

  const _SubjectsPane({
    required this.gradeKey,
    required this.accent,
    this.onSubjectTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<SubjectOption>> subjectsAsync =
        ref.watch(gradeSubjectsProvider(gradeKey));
    final Color gradeColor = GradeTheme.fromKey(gradeKey).primaryColor;
    return Positioned(
      left: 80,
      top: 276,
      width: 1120,
      height: 506,
      child: subjectsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) => const Center(
          child: Text(
            'Could not load subjects.',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 14,
              color: Color(0xFF6B7280),
            ),
          ),
        ),
        data: (List<SubjectOption> subjects) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Wrap(
              spacing: 40,
              runSpacing: 24,
              children: <Widget>[
                for (final SubjectOption subject in subjects)
                  SubjectCardItem(
                    title: subject.title,
                    // SubjectOption carries no counters yet — live
                    // lecture/revision breakdown lands with the details
                    // screen; cards show Figma zeros meanwhile.
                    isActive: subject.isVisible,
                    lecturesCount: 0,
                    revisionsCount: 0,
                    finalCount: 0,
                    onlineCount: 0,
                    gradeColor: gradeColor,
                    onTap: () {
                      final ValueChanged<SubjectOption>? open =
                          onSubjectTap;
                      if (open != null) {
                        open(subject);
                      } else {
                        SubjectDetailsDialog.show(
                          context,
                          title: subject.title,
                          isActive: subject.isVisible,
                          gradeColor: gradeColor,
                        );
                      }
                    },
                  ),
                AddSubjectCard(
                  gradeColor: gradeColor,
                  onTap: () => AddSubjectOverlay.show(
                    context,
                    gradeKey: gradeKey,
                    gradeColor: gradeColor,
                    nextDisplayOrder: subjects.length,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Shared live subject list for one grade (also used by the shell).
class GradeSubjectsList extends ConsumerWidget {
  final String gradeKey;

  const GradeSubjectsList({super.key, required this.gradeKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<SubjectOption>> subjectsAsync =
        ref.watch(gradeSubjectsProvider(gradeKey));
    return subjectsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace stackTrace) => Text(
        'Could not load subjects.',
        style: AppTypography.statLabel(fontSize: 20),
      ),
      data: (List<SubjectOption> subjects) {
        if (subjects.isEmpty) {
          return Text(
            'No subjects in this grade yet.',
            style: AppTypography.statLabel(fontSize: 20),
          );
        }
        return Column(
          children: <Widget>[
            for (final SubjectOption subject in subjects)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border:
                      Border.all(color: AppColors.inputStroke, width: 1),
                ),
                child: Text(
                  subject.title,
                  style: AppTypography.statValue(fontSize: 24),
                ),
              ),
          ],
        );
      },
    );
  }
}
