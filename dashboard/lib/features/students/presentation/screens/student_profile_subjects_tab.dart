import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../applications/domain/grade.dart';
import '../../../applications/presentation/providers/application_decision_provider.dart'
    show SubjectOption, gradeSubjectsProvider;
import '../../domain/repositories/subject_access_repository.dart'
    show SubjectGrantOutcome;
import '../providers/grade_students_provider.dart'
    show GradeStudent, gradeStudentsProvider;
import '../providers/student_profile_subjects_provider.dart';
import '../screens/grade_pending_requests_view_screen.dart'
    show GradeSubjectsResult, showGradeSubjectsDialog, showOtherSubjectsDialog;
import '../screens/grade_students_screen.dart' show gradeAccent;
import '../widgets/grade_theme.dart';

/// Student Profile → Subjects tab content.
///
/// Renders inside the existing Student Profile shell: the shell owns the
/// brand header, the grade navigation, and the sidebar — this widget is
/// the main content column (814 wide) shown when the Subjects pill is
/// active.
///
/// - The table lists ONLY subjects registered for this student
///   (non-deleted `subject_access_assignments`), with the subject-scoped
///   plan per row (FREE / PRO / MAX from the active `subscriptions`
///   document — never a global student plan).
/// - Access toggles apply immediately via `setSubjectAccess` (no Save).
/// - Delete soft-deletes the assignment after confirmation (the platform
///   Subject document is untouched).
/// - Add buttons open the existing subject-selection overlays; their Save
///   commits the additions. Grade One shows only Add Subject; grades
///   Two–Four additionally show Add Other Subject (previous grades).
class StudentProfileSubjectsTab extends ConsumerStatefulWidget {
  final GradeStudent student;
  final String gradeKey;

  const StudentProfileSubjectsTab({
    super.key,
    required this.student,
    required this.gradeKey,
  });

  @override
  ConsumerState<StudentProfileSubjectsTab> createState() =>
      _StudentProfileSubjectsTabState();
}

class _StudentProfileSubjectsTabState
    extends ConsumerState<StudentProfileSubjectsTab> {
  String get _gradeKey => GradeTheme.fromKey(widget.gradeKey).gradeId;
  Color get _accent => gradeAccent(_gradeKey);

  /// Guest students have no plans at all — they only get guest access.
  /// All plan UI (capsule, plan column values, repair) is hidden for them.
  bool get _isGuest => !widget.student.isCenter;

  /// Grade ids before the student's own grade (oldest first). Grade One
  /// has no previous grades, so no Add Other Subject button is rendered.
  List<String> get _previousGradeKeys {
    final int index = canonicalGradeKeys.indexOf(_gradeKey);
    if (index <= 0) return const <String>[];
    return canonicalGradeKeys.sublist(0, index);
  }

  Future<void> _setAccess(
    StudentSubjectRegistration row,
    bool enabled,
  ) async {
    // Enabling an assignment that has no active subscription would immediately
    // leave the row in the broken "بدون خطة نشطة" state; require/attach the
    // subscription atomically via grantSubjectAccessWithPlan in the same action.
    if (enabled && row.planLabel.isEmpty) {
      await _repairRow(row);
      return;
    }
    try {
      await ref
          .read(studentProfileSubjectsControllerProvider)
          .setAccess(
            studentId: widget.student.id,
            subjectId: row.subjectId,
            enabled: enabled,
          );
      ref.invalidate(gradeStudentsProvider(_gradeKey));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_failureMessage(e))),
      );
    }
  }

  Future<void> _confirmDelete(StudentSubjectRegistration row) async {
    final bool? confirmed = await showRemoveSubjectDialog(
      context,
      subjectTitle: row.title,
      accent: _accent,
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(studentProfileSubjectsControllerProvider)
          .removeSubject(
            studentId: widget.student.id,
            subjectId: row.subjectId,
            enabled: row.enabled,
          );
      ref.invalidate(studentProfileSubjectsProvider(widget.student.id));
      ref.invalidate(gradeStudentsProvider(_gradeKey));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت إزالة المادة من ملف الطالب.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_failureMessage(e))),
      );
    }
  }

  /// Synchronous subject snapshot for the add overlays: live provider
  /// values when loaded and non-empty, otherwise an empty list (the
  /// overlays render their own empty state — no invented subjects).
  List<SubjectOption> _subjectsSync(String gradeKey) {
    return ref.read(gradeSubjectsProvider(gradeKey)).maybeWhen(
          data: (subjects) => subjects,
          orElse: () => const <SubjectOption>[],
        );
  }

  Map<String, List<SubjectOption>> _otherSubjectGroups() {
    final Map<String, List<SubjectOption>> groups =
        <String, List<SubjectOption>>{};
    for (final String key in _previousGradeKeys) {
      final List<SubjectOption> list = _subjectsSync(key);
      if (list.isNotEmpty) groups[key] = list;
    }
    return groups;
  }

  List<SubjectOption> _otherSubjectsFlat() {
    final Map<String, List<SubjectOption>> groups = _otherSubjectGroups();
    return <SubjectOption>[
      for (final String key in _previousGradeKeys)
        ...groups[key] ?? const <SubjectOption>[],
    ];
  }

  /// Fresh FREE-gate read for every plan dialog open.
  ///
  /// `freePlanAvailabilityProvider` is a one-shot auto-dispose fetch, so a
  /// Firestore change made outside the app (e.g. a Teacher-side settings
  /// edit) would otherwise stay stale until a full reload. Refreshing here
  /// makes each opened dialog reflect the current server value without a
  /// reload. Fail-open client-side: while the refresh fails FREE stays
  /// selectable and the server gate decides.
  Future<bool> _freshFreePlanEnabled() async {
    try {
      return await ref.refresh(freePlanAvailabilityProvider.future);
    } catch (_) {
      return ref.read(freePlanAvailabilityProvider).maybeWhen(
            data: (enabled) => enabled,
            orElse: () => true,
          );
    }
  }

  Future<void> _pickGradeSubjects(
    List<StudentSubjectRegistration> existingRows,
    Set<String> alreadyRegistered,
    Map<String, bool> persistedToggles,
    Map<String, String> persistedPlans,
  ) async {
    final List<SubjectOption> scope = _subjectsSync(_gradeKey);
    // Guest: no plan gate needed — no plan capsule is shown at all.
    final bool freeEnabled =
        _isGuest ? true : await _freshFreePlanEnabled();
    if (!mounted) return;
    final GradeSubjectsResult? updated = await showGradeSubjectsDialog(
      context,
      gradeLabel: GradeTheme.fromKey(_gradeKey).title,
      subjects: scope,
      // Persisted relationships only: unassigned subjects open OFF.
      initialToggles: persistedToggles,
      initialPlans: persistedPlans,
      freePlanEnabled: freeEnabled,
      hidePlans: _isGuest,
    );
    if (updated == null || !mounted) return;
    await _commitAdditions(
      updated,
      alreadyRegistered,
      scope,
      existingRows: existingRows,
      freePlanEnabled: freeEnabled,
    );
  }

  Future<void> _pickOtherSubjects(
    List<StudentSubjectRegistration> existingRows,
    Set<String> alreadyRegistered,
    Map<String, bool> persistedToggles,
    Map<String, String> persistedPlans,
  ) async {
    final List<SubjectOption> scope = _otherSubjectsFlat();
    // Guest: no plan gate needed — no plan capsule is shown at all.
    final bool freeEnabled =
        _isGuest ? true : await _freshFreePlanEnabled();
    if (!mounted) return;
    final GradeSubjectsResult? updated = await showOtherSubjectsDialog(
      context,
      gradeKey: _gradeKey,
      previousGrades: _previousGradeKeys,
      groups: _otherSubjectGroups(),
      // Persisted relationships only: unassigned subjects open OFF.
      initialToggles: persistedToggles,
      initialPlans: persistedPlans,
      freePlanEnabled: freeEnabled,
      hidePlans: _isGuest,
    );
    if (updated == null || !mounted) return;
    await _commitAdditions(
      updated,
      alreadyRegistered,
      scope,
      existingRows: existingRows,
      freePlanEnabled: freeEnabled,
    );
  }

  Future<void> _commitAdditions(
    GradeSubjectsResult updated,
    Set<String> alreadyRegistered,
    List<SubjectOption> scope, {
    List<StudentSubjectRegistration> existingRows =
        const <StudentSubjectRegistration>[],
    bool freePlanEnabled = true,
  }) async {
    final String defaultPlan =
        _isGuest ? 'free' : (freePlanEnabled ? 'free' : 'pro');
    final Map<String, String> effectivePlans = _isGuest
        ? <String, String>{
            for (final String id in updated.toggles.keys) id: 'free',
          }
        : updated.plans;
    final List<NewStudentSubject> picked = buildNewStudentSubjects(
      scope: scope,
      toggles: updated.toggles,
      plans: effectivePlans,
      alreadyRegistered: alreadyRegistered,
      defaultPlan: defaultPlan,
    );

    // Also handle already-registered subjects modified inside the overlay
    // (e.g. re-enabled from OFF -> ON, repaired from missing plan, or plan tier changed).
    final Map<String, StudentSubjectRegistration> existingById =
        <String, StudentSubjectRegistration>{
      for (final r in existingRows) r.subjectId: r,
    };
    final List<({String subjectId, String title, bool enable, String plan})>
        existingChanges =
        <({String subjectId, String title, bool enable, String plan})>[];
    for (final SubjectOption s in scope) {
      if (!alreadyRegistered.contains(s.id)) continue;
      final StudentSubjectRegistration? prev = existingById[s.id];
      if (prev == null) continue;
      final bool nextEnabled = updated.toggles[s.id] ?? prev.enabled;
      final String chosenPlan =
          (effectivePlans[s.id] ??
                  (prev.planLabel.isNotEmpty
                      ? prev.planLabel.toLowerCase()
                      : defaultPlan))
              .toLowerCase();
      final bool planChanged = !_isGuest &&
          nextEnabled &&
          (prev.planLabel.isEmpty ||
              prev.planLabel.toLowerCase() != chosenPlan);
      final bool toggleChanged = nextEnabled != prev.enabled;
      if (toggleChanged || planChanged) {
        existingChanges.add((
          subjectId: s.id,
          title: s.title,
          enable: nextEnabled,
          plan: chosenPlan,
        ));
      }
    }

    if (picked.isEmpty && existingChanges.isEmpty) return;
    if (!mounted) return;
    final Map<String, String> titles = <String, String>{
      for (final SubjectOption s in scope) s.id: s.title,
    };
    // Guest summary shows "GUEST" instead of a plan tier.
    final Map<String, String> pickedPlans = <String, String>{
      for (final NewStudentSubject p in picked)
        p.subjectId: _isGuest ? 'guest' : p.plan,
      for (final c in existingChanges)
        c.subjectId: _isGuest ? 'guest' : (c.enable ? c.plan : 'off'),
    };
    final List<SubjectGrantOutcome> outcomes = <SubjectGrantOutcome>[];
    final controller = ref.read(studentProfileSubjectsControllerProvider);
    try {
      if (picked.isNotEmpty) {
        outcomes.addAll(
          await controller.addSubjects(
            studentId: widget.student.id,
            isCenter: widget.student.isCenter,
            subjects: picked,
            alreadyRegistered: alreadyRegistered,
            subjectTitles: titles,
          ),
        );
      }
      for (final change in existingChanges) {
        try {
          if (change.enable) {
            await controller.changePlan(
              studentId: widget.student.id,
              isCenter: widget.student.isCenter,
              subjectId: change.subjectId,
              plan: change.plan,
            );
          } else {
            await controller.setAccess(
              studentId: widget.student.id,
              subjectId: change.subjectId,
              enabled: false,
            );
          }
          outcomes.add(SubjectGrantOutcome(
            subjectId: change.subjectId,
            subjectName: change.title,
            success: true,
          ));
        } catch (e) {
          outcomes.add(SubjectGrantOutcome(
            subjectId: change.subjectId,
            subjectName: change.title,
            success: false,
            errorMessage: _failureMessage(e),
          ));
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_failureMessage(e))),
      );
      return;
    }
    // Refresh immediately so succeeded rows render without reopening
    // the profile; failures keep their honest per-row messages below.
    // Also refresh the grade list so its `N subjects` stays identical.
    ref.invalidate(studentProfileSubjectsProvider(widget.student.id));
    ref.invalidate(gradeStudentsProvider(_gradeKey));
    if (!mounted) return;
    await showSubjectGrantSummary(
      context,
      outcomes: outcomes,
      plans: pickedPlans,
    );
  }

  /// Re-triggers the atomic grant for ONE broken row (or edits an existing
  /// row's plan) via [showRepairPlanDialog], updating `subject_access_assignments`
  /// and `subscriptions` together in one server transaction.
  Future<void> _repairRow(StudentSubjectRegistration row) async {
    if (_isGuest) {
      try {
        await ref.read(studentProfileSubjectsControllerProvider).changePlan(
              studentId: widget.student.id,
              isCenter: widget.student.isCenter,
              subjectId: row.subjectId,
              plan: 'free',
            );
        ref.invalidate(studentProfileSubjectsProvider(widget.student.id));
        ref.invalidate(gradeStudentsProvider(_gradeKey));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم إصلاح "${row.title}" (Guest).')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_failureMessage(e))),
        );
      }
      return;
    }
    final bool isEdit = row.planLabel.isNotEmpty;
    final bool freeEnabled = await _freshFreePlanEnabled();
    if (!mounted) return;
    final String? plan = await showRepairPlanDialog(
      context,
      accent: _accent,
      subjectTitle: row.title,
      freePlanEnabled: freeEnabled,
      initialPlan: isEdit ? row.planLabel : null,
      isEdit: isEdit,
    );
    if (plan == null || !mounted) return;
    try {
      await ref.read(studentProfileSubjectsControllerProvider).changePlan(
            studentId: widget.student.id,
            isCenter: widget.student.isCenter,
            subjectId: row.subjectId,
            plan: plan,
          );
      ref.invalidate(studentProfileSubjectsProvider(widget.student.id));
      ref.invalidate(gradeStudentsProvider(_gradeKey));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEdit
                ? 'تم تحديث خطة "${row.title}" (${plan.toUpperCase()}).'
                : 'تم إصلاح "${row.title}" (${plan.toUpperCase()}).',
          ),
        ),
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
    // Prime every grade's subjects stream so the add overlays and the
    // table joins always read loaded values.
    for (final String key in canonicalGradeKeys) {
      ref.watch(gradeSubjectsProvider(key));
    }
    final AsyncValue<List<StudentSubjectRegistration>> rowsAsync =
        ref.watch(studentProfileSubjectsProvider(widget.student.id));

    return SizedBox(
      width: double.infinity,
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
            data: (rows) =>
                _SubjectsTableBlock(state: this, rows: rows),
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

/// Table + add-buttons block: the table was intentionally sized to leave
/// room below it for the subject-addition actions.
class _SubjectsTableBlock extends StatelessWidget {
  final _StudentProfileSubjectsTabState state;
  final List<StudentSubjectRegistration> rows;

  const _SubjectsTableBlock({
    required this.state,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    final Set<String> registered = <String>{
      for (final row in rows) row.subjectId,
    };
    // Persisted assignment state pre-fills the add overlays: registered
    // subjects reopen with their stored toggle/plan, everything else
    // opens OFF / FREE. Test/design students have no assignments, so
    // every toggle opens OFF / gray for them.
    final Map<String, bool> persistedToggles = <String, bool>{
      for (final row in rows) row.subjectId: row.enabled,
    };
    final Map<String, String> persistedPlans = <String, String>{
      for (final row in rows)
        if (row.planLabel.isNotEmpty)
          row.subjectId: row.planLabel.toLowerCase(),
    };
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          _SubjectsTable(state: state, rows: rows),
          const SizedBox(height: 24),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: <Widget>[
              _AddButton(
                label: 'Add Subject',
                accent: state._accent,
                onTap: () => state._pickGradeSubjects(
                  rows,
                  registered,
                  persistedToggles,
                  persistedPlans,
                ),
              ),
              if (state._previousGradeKeys.isNotEmpty)
                _AddButton(
                  label: 'Add Other Subject',
                  accent: state._accent,
                  onTap: () => state._pickOtherSubjects(
                    rows,
                    registered,
                    persistedToggles,
                    persistedPlans,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Registered-subjects table (Figma Dev Mode: 830 wide at left 225,
/// top 456): white card, 1 px #E5E7EB border, radius 16, black-25%
/// shadow (blur 4, offset 0/4). Header 830 with 8 px padding —
/// No. 56 | Subjects 216 | Grade 146 | plan 116 | Access 116 |
/// Action 156 (= 806, inside the 808 content width: 830 card minus
/// 1 px borders and 10 px padding) — 1 px divider, then dynamic ~52 px
/// data rows with 10 px padding. The Grade column shows each subject's OWN catalog grade
/// (which may differ from the student's current grade). Row numbers are
/// presentation-only.
class _SubjectsTable extends StatelessWidget {
  final _StudentProfileSubjectsTabState state;
  final List<StudentSubjectRegistration> rows;

  const _SubjectsTable({
    required this.state,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
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
      child: ResponsiveHorizontalTable(
        minTableWidth: 830,
        child: Column(
          children: <Widget>[
            const _SubjectsHeaderRow(),
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
                _SubjectDataRow(
                  state: state,
                  index: i,
                  row: rows[i],
                ),
          ],
        ),
      ),
    );
  }
}

class _SubjectsHeaderRow extends StatelessWidget {
  const _SubjectsHeaderRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(8),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 56,
            child: _HeaderLabel('No.'),
          ),
          SizedBox(width: 216, child: _HeaderLabel('Subjects')),
          SizedBox(width: 146, child: _HeaderLabel('Grade')),
          SizedBox(width: 116, child: _HeaderLabel('plan')),
          SizedBox(width: 116, child: _HeaderLabel('Access')),
          SizedBox(width: 156, child: _HeaderLabel('Action')),
        ],
      ),
    );
  }
}

class _HeaderLabel extends StatelessWidget {
  final String text;

  const _HeaderLabel(this.text);

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

class _SubjectDataRow extends StatelessWidget {
  final _StudentProfileSubjectsTabState state;
  final int index;
  final StudentSubjectRegistration row;

  const _SubjectDataRow({
    required this.state,
    required this.index,
    required this.row,
  });

  @override
  Widget build(BuildContext context) {
    final String number =
        (index + 1).toString().padLeft(2, '0');
    // Guest students have no plans: the plan cell always shows "ضيف"
    // and never the broken-row warning. Center broken-but-visible state:
    // access is enabled yet no active subscription backs the row
    // (e.g. a pre-fix partial save). Rendered as an explicit warning —
    // never the neutral "—" — so an Admin scanning the table notices
    // the anomaly immediately.
    final bool isGuest = state._isGuest;
    final bool missingPlan = !isGuest && row.enabled && row.planLabel.isEmpty;
    final bool guestNeedsRepair =
        isGuest && row.enabled && row.planLabel.isEmpty;
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
                fontSize: 16,
                fontWeight: FontWeight.w400,
                fontVariations: <FontVariation>[FontVariation('wght', 400)],
                color: Colors.black,
              ),
            ),
          ),
          SizedBox(
            width: 216,
            child: Text(
              row.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 16,
                fontWeight: FontWeight.w400,
                fontVariations: <FontVariation>[FontVariation('wght', 400)],
                color: Colors.black,
              ),
            ),
          ),
          SizedBox(
            width: 146,
            child: Text(
              GradeTheme.subjectGradeLabel(row.gradeKey),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 16,
                fontWeight: FontWeight.w400,
                fontVariations: <FontVariation>[FontVariation('wght', 400)],
                color: Colors.black,
              ),
            ),
          ),
          SizedBox(
            width: 116,
            child: isGuest
                ? const Text(
                    'Guest',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF6B7280),
                    ),
                  )
                : missingPlan
                    ? InkWell(
                        onTap: () => state._repairRow(row),
                        borderRadius: BorderRadius.circular(8),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            'بدون خطة نشطة',
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: AppTypography.fontFamily,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFDC2626),
                            ),
                          ),
                        ),
                      )
                    : Center(
                        child: InkWell(
                          onTap: () => state._repairRow(row),
                          borderRadius: BorderRadius.circular(9999),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF9FAFB),
                              borderRadius: BorderRadius.circular(9999),
                              border: Border.all(
                                color: const Color(0xFFE5E7EB),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  row.planLabel.isEmpty ? '—' : row.planLabel,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontFamily: AppTypography.fontFamily,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.black,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.edit_outlined,
                                  size: 13,
                                  color: state._accent,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
          ),
          SizedBox(
            width: 116,
            child: Center(
              child: _AccessSwitch(
                value: row.enabled,
                onChanged: (value) => state._setAccess(row, value),
              ),
            ),
          ),
          SizedBox(
            width: 156,
            child: Center(
              child: (missingPlan || guestNeedsRepair)
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        SizedBox(
                          width: 70,
                          height: 28,
                          child: OutlinedButton(
                            onPressed: () => state._repairRow(row),
                            style: OutlinedButton.styleFrom(
                              foregroundColor:
                                  const Color(0xFFDC2626),
                              padding: EdgeInsets.zero,
                              side: const BorderSide(
                                color: Color(0xFFDC2626),
                                width: 1.5,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(9999),
                              ),
                            ),
                            child: const Text(
                              'Repair',
                              style: TextStyle(
                                fontFamily:
                                    AppTypography.fontFamily,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 70,
                          height: 28,
                          child: ElevatedButton(
                            onPressed: () =>
                                state._confirmDelete(row),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: state._accent,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(9999),
                              ),
                              elevation: 0,
                            ),
                            child: const Text(
                              'Delete',
                              style: TextStyle(
                                fontFamily:
                                    AppTypography.fontFamily,
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
                      ],
                    )
                  : SizedBox(
                      width: 88,
                      height: 28,
                      child: ElevatedButton(
                        onPressed: () => state._confirmDelete(row),
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
                          'Delete',
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

/// Access switch (Figma Dev Mode: 64 x 28 track, radius 100, green
/// #34C759 when ON / gray when OFF; white 38 x 24 thumb, radius 100).
/// Immediate — no Save.
class _AccessSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _AccessSwitch({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        width: 64,
        height: 28,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: value
              ? const Color(0xFF34C759)
              : const Color(0xFFD1D5DB),
          borderRadius: BorderRadius.circular(100),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 150),
          alignment:
              value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 38,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(100),
            ),
          ),
        ),
      ),
    );
  }
}

/// Grade-accent capsule below the table (250 x 40), 24 px white label.
class _AddButton extends StatelessWidget {
  final String label;
  final Color accent;
  final VoidCallback onTap;

  const _AddButton({
    required this.label,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 250,
      height: 40,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9999),
          ),
          elevation: 0,
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 20,
            fontWeight: FontWeight.w400,
            fontVariations: <FontVariation>[FontVariation('wght', 400)],
            color: Color(0xFFFFFFFF),
          ),
        ),
      ),
    );
  }
}

/// Delete confirmation: removes the subject from THIS student's profile
/// (archives the student-subject relationship). The platform Subject
/// itself is never deleted. Figma prototype behavior: centered, outside
/// tap dismisses, black 25% barrier, 150 ms ease-out dissolve.
Future<bool?> showRemoveSubjectDialog(
  BuildContext context, {
  required String subjectTitle,
  required Color accent,
}) {
  return showGeneralDialog<bool>(
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
      return Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 380,
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text(
                  'Remove Subject',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Remove "$subjectTitle" from this student\'s profile? '
                  'The subject stays on the platform and keeps working '
                  'for other students.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 14,
                    color: Color(0xFF374151),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    SizedBox(
                      width: 120,
                      height: 36,
                      child: OutlinedButton(
                        onPressed: () =>
                            Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: accent,
                          padding: EdgeInsets.zero,
                          side: BorderSide(color: accent, width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9999),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 120,
                      height: 36,
                      child: ElevatedButton(
                        onPressed: () =>
                            Navigator.of(context).pop(true),
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
                          'Delete',
                          style: TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFFFFFFFF),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Per-subject save summary (Fix 3): one dialog listing EVERY subject's
/// outcome after a multi-subject Save — successes with their saved plan,
/// failures with the backend message — instead of a single ambiguous
/// snackbar. The table behind it is already refreshed by the caller.
Future<void> showSubjectGrantSummary(
  BuildContext context, {
    required List<SubjectGrantOutcome> outcomes,
    required Map<String, String> plans,
  }) {
  final int failed =
      outcomes.where((o) => !o.success).length;
  return showGeneralDialog<void>(
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
      return Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 460,
            constraints: const BoxConstraints(maxHeight: 520),
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  failed == 0 ? 'تم حفظ المواد' : 'نتيجة حفظ المواد',
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        for (final SubjectGrantOutcome outcome
                            in outcomes)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 4,
                            ),
                            child: Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: <Widget>[
                                Icon(
                                  outcome.success
                                      ? Icons.check_circle
                                      : Icons.error,
                                  size: 18,
                                  color: outcome.success
                                      ? const Color(0xFF059669)
                                      : const Color(0xFFDC2626),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    outcome.success
                                        ? '${outcome.subjectName}: تم الحفظ (${(plans[outcome.subjectId] ?? '').toUpperCase()})'
                                        : '${outcome.subjectName}: فشل — ${outcome.errorMessage ?? 'تعذّر التنفيذ'}',
                                    style: const TextStyle(
                                      fontFamily:
                                          AppTypography.fontFamily,
                                      fontSize: 14,
                                      color: Color(0xFF374151),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: 120,
                  height: 36,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9999),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'حسناً',
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
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
}

/// Plan picker for repairing a broken row OR changing an existing row's plan
/// (`FREE` / `PRO` / `MAX`). Honors [freePlanEnabled] and never auto-assigns
/// without user confirmation.
Future<String?> showRepairPlanDialog(
  BuildContext context, {
    required Color accent,
    required String subjectTitle,
    bool freePlanEnabled = true,
    String? initialPlan,
    bool isEdit = false,
  }) {
  final List<String> plans = freePlanEnabled
      ? const <String>['FREE', 'PRO', 'MAX']
      : const <String>['PRO', 'MAX'];
  final String normalizedInitial = (initialPlan ?? '').trim().toUpperCase();
  String temp = plans.contains(normalizedInitial) ? normalizedInitial : 'PRO';
  return showGeneralDialog<String>(
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
                padding:
                    const EdgeInsets.fromLTRB(24, 24, 24, 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      isEdit ? 'تعديل الخطة' : 'إصلاح الخطة',
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isEdit
                          ? 'اختر الخطة الجديدة لمادة "$subjectTitle".'
                          : 'اختر خطة "$subjectTitle" لتفعيل الاشتراك وحل المشكلة.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 14,
                        color: Color(0xFF374151),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        for (int i = 0; i < plans.length; i++) ...<Widget>[
                          if (i > 0) const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => setOverlayState(
                              () => temp = plans[i],
                            ),
                            child: Container(
                              width: 88,
                              height: 36,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: temp == plans[i]
                                    ? accent
                                    : Colors.transparent,
                                borderRadius:
                                    BorderRadius.circular(9999),
                                border: Border.all(
                                  color: temp == plans[i]
                                      ? accent
                                      : const Color(0xFFE5E7EB),
                                ),
                              ),
                              child: Text(
                                plans[i],
                                style: TextStyle(
                                  fontFamily:
                                      AppTypography.fontFamily,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: temp == plans[i]
                                      ? Colors.white
                                      : const Color(0xFF374151),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: 160,
                      height: 40,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(
                          temp.toLowerCase(),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(9999),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Save',
                          style: TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontSize: 20,
                            fontWeight: FontWeight.w400,
                            color: Color(0xFFFFFFFF),
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
