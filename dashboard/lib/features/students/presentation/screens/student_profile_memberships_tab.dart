import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_typography.dart';
import '../providers/grade_students_provider.dart' show GradeStudent;
import '../providers/student_profile_subjects_provider.dart';
import '../screens/grade_students_screen.dart' show gradeAccent;
import '../widgets/grade_theme.dart';

/// Student Profile → Memberships tab content.
///
/// Renders below the persistent profile header (inside the 830-wide
/// dynamic body): the same subject registrations as the Subjects tab,
/// but with a per-row membership Status badge (Active/Inactive) and a
/// Change Plan action that opens the Student Plan overlay
/// ([showStudentPlanDialog]). Plan changes go through the audited
/// `activateFreePlan` → `upgrade` callable sequence
/// ([StudentProfileSubjectsController.changePlan]).
class StudentProfileMembershipsTab extends ConsumerStatefulWidget {
  final GradeStudent student;
  final String gradeKey;

  const StudentProfileMembershipsTab({
    super.key,
    required this.student,
    required this.gradeKey,
  });

  @override
  ConsumerState<StudentProfileMembershipsTab> createState() =>
      _StudentProfileMembershipsTabState();
}

class _StudentProfileMembershipsTabState
    extends ConsumerState<StudentProfileMembershipsTab> {
  String get _gradeKey => GradeTheme.fromKey(widget.gradeKey).gradeId;
  Color get _accent => gradeAccent(_gradeKey);

  Future<void> _changePlan(StudentSubjectRegistration row) async {
    final String? updated = await showStudentPlanDialog(
      context,
      accent: _accent,
      currentPlan: row.planLabel,
    );
    if (updated == null || !mounted) return;
    try {
      await ref.read(studentProfileSubjectsControllerProvider).changePlan(
            studentId: widget.student.id,
            isCenter: widget.student.isCenter,
            subjectId: row.subjectId,
            plan: updated,
          );
      ref.invalidate(studentProfileSubjectsProvider(widget.student.id));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plan updated.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_failureMessage(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<StudentSubjectRegistration>> rowsAsync =
        ref.watch(studentProfileSubjectsProvider(widget.student.id));

    return SizedBox(
      width: 830,
      child: rowsAsync.when(
        loading: () => const SizedBox(
          height: 200,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => SizedBox(
          height: 200,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text(
                  'تعذّر تحميل مواد الطالب.',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 14,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => ref.invalidate(
                    studentProfileSubjectsProvider(widget.student.id),
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (rows) => _MembershipsTable(state: this, rows: rows),
      ),
    );
  }

  static String _failureMessage(Object error) {
    final String text = error.toString();
    const String prefix = 'DecisionFailure: ';
    if (text.startsWith(prefix)) return text.substring(prefix.length);
    return 'تعذّر تنفيذ الإجراء. حاول مرة أخرى.';
  }
}

/// Memberships table (Figma Dev Mode: 830 wide): white card, 1 px
/// #E5E7EB border, radius 16, black-25% shadow (blur 4, offset 0/4).
/// Header 830 with 8 px padding — No. 56 | Subjects 306 | plan 116 |
/// Status 116 | Action 156 — 1 px divider, then dynamic ~52 px data
/// rows with 10 px padding. Row numbers are presentation-only.
class _MembershipsTable extends StatelessWidget {
  final _StudentProfileMembershipsTabState state;
  final List<StudentSubjectRegistration> rows;

  const _MembershipsTable({
    required this.state,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 830,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x3F000000),
            blurRadius: 4,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.all(8),
            child: Row(
              children: <Widget>[
                SizedBox(width: 56, child: _MembershipHeaderLabel('No.')),
                SizedBox(width: 306, child: _MembershipHeaderLabel('Subjects')),
                SizedBox(width: 116, child: _MembershipHeaderLabel('plan')),
                SizedBox(width: 116, child: _MembershipHeaderLabel('Status')),
                SizedBox(width: 156, child: _MembershipHeaderLabel('Action')),
              ],
            ),
          ),
          Container(height: 1, color: const Color(0xFFE5E7EB)),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'لا توجد مواد مسجلة لهذا الطالب بعد.',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 14,
                  color: Color(0xFF6B7280),
                ),
              ),
            )
          else
            for (int i = 0; i < rows.length; i++)
              _MembershipDataRow(
                state: state,
                index: i,
                row: rows[i],
              ),
        ],
      ),
    );
  }
}

class _MembershipHeaderLabel extends StatelessWidget {
  final String text;

  const _MembershipHeaderLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontFamily: AppTypography.fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        fontVariations: <FontVariation>[FontVariation('wght', 400)],
        color: Color(0xFF6B7280),
      ),
    );
  }
}

class _MembershipDataRow extends StatelessWidget {
  final _StudentProfileMembershipsTabState state;
  final int index;
  final StudentSubjectRegistration row;

  const _MembershipDataRow({
    required this.state,
    required this.index,
    required this.row,
  });

  @override
  Widget build(BuildContext context) {
    final String number = (index + 1).toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 56,
            child: Text(
              '$number.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 24,
                fontWeight: FontWeight.w400,
                fontVariations: <FontVariation>[FontVariation('wght', 400)],
                color: Colors.black,
              ),
            ),
          ),
          SizedBox(
            width: 306,
            child: Text(
              row.title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 24,
                fontWeight: FontWeight.w400,
                fontVariations: <FontVariation>[FontVariation('wght', 400)],
                color: Colors.black,
              ),
            ),
          ),
          SizedBox(
            width: 116,
            child: Text(
              row.planLabel.isEmpty ? '—' : row.planLabel,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 24,
                fontWeight: FontWeight.w400,
                fontVariations: <FontVariation>[FontVariation('wght', 400)],
                color: Colors.black,
              ),
            ),
          ),
          SizedBox(
            width: 116,
            child: Center(
              child: _StatusBadge(active: row.enabled),
            ),
          ),
          SizedBox(
            width: 156,
            child: Center(
              child: SizedBox(
                width: 88,
                height: 28,
                child: ElevatedButton(
                  onPressed: () => state._changePlan(row),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: state._accent,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9999),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Change Plan',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      fontVariations: <FontVariation>[
                        FontVariation('wght', 400),
                      ],
                      color: Color(0xFFFFFFFF),
                    ),
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

/// Membership status badge: soft-emerald pill for Active, soft-red for
/// Inactive (hug contents with 10/4 padding, radius 9999, 14 px label).
class _StatusBadge extends StatelessWidget {
  final bool active;

  const _StatusBadge({required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: active
            ? const Color(0xFFECFDF5)
            : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(9999),
      ),
      child: Text(
        active ? 'Active' : 'Inactive',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w400,
          fontVariations: const <FontVariation>[FontVariation('wght', 400)],
          color: active
              ? const Color(0xFF059669)
              : const Color(0xFFDC2626),
        ),
      ),
    );
  }
}

/// Overlay 2 — Student Plan (328 x 220): FREE | PRO | MAX switch with
/// the current plan preselected + Save. Returns the chosen plan key
/// (lowercase) on save, null on dismiss.
Future<String?> showStudentPlanDialog(
  BuildContext context, {
  required Color accent,
  required String currentPlan,
}) {
  const List<String> plans = <String>['FREE', 'PRO', 'MAX'];
  String temp = plans.contains(currentPlan.toUpperCase())
      ? currentPlan.toUpperCase()
      : 'FREE';
  return showGeneralDialog<String>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.25),
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
                width: 328,
                height: 220,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const Text(
                      'Student Plan',
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 32,
                        fontWeight: FontWeight.w400,
                        fontVariations: <FontVariation>[
                          FontVariation('wght', 400),
                        ],
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      width: 280,
                      height: 40,
                      // 280 - 2 (border) - 6 (padding) = 272 for
                      // 3 x 88 options + 2 x 4 gaps.
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
                          for (int i = 0; i < plans.length; i++) ...<Widget>[
                            if (i > 0) const SizedBox(width: 4),
                            _PlanOption(
                              label: plans[i],
                              isActive: temp == plans[i],
                              accent: accent,
                              onTap: () =>
                                  setOverlayState(() => temp = plans[i]),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    InkWell(
                      onTap: () => Navigator.of(context).pop(temp.toLowerCase()),
                      borderRadius: BorderRadius.circular(9999),
                      child: Container(
                        width: 160,
                        height: 40,
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(9999),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'Save',
                          style: TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontSize: 24,
                            fontWeight: FontWeight.w400,
                            fontVariations: <FontVariation>[
                              FontVariation('wght', 400),
                            ],
                            color: Colors.white,
                          ),
                        ),
                      ),
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

class _PlanOption extends StatelessWidget {
  final String label;
  final bool isActive;
  final Color accent;
  final VoidCallback onTap;

  const _PlanOption({
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
        width: 88,
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
            color: isActive ? Colors.white : Colors.black,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
