import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../applications/domain/grade.dart';
import '../../../applications/presentation/providers/application_decision_provider.dart';
import '../providers/grade_pending_requests_provider.dart';
import 'grade_students_screen.dart' show gradeAccent;

const List<({String key, String label})> _grades =
    <({String key, String label})>[
  (key: 'grade_one', label: 'Grade One'),
  (key: 'grade_two', label: 'Grade Two'),
  (key: 'grade_three', label: 'Grade Three'),
  (key: 'grade_four', label: 'Grade Four'),
];

String _gradeLabel(String? gradeKey) {
  return switch (gradeKey) {
    'grade_two' => 'Grade Two',
    'grade_three' => 'Grade Three',
    'grade_four' => 'Grade Four',
    _ => 'Grade One',
  };
}

/// Fallback subjects per grade (Arabic accounting set from the Figma
/// frame) used only when the live `subjects` collection is unreachable.
List<SubjectOption> _fallbackSubjects(String gradeKey) {
  if (gradeKey != 'grade_one') return const <SubjectOption>[];
  const List<String> titles = <String>[
    'مالية متقدمة',
    'محاسبة حكومية',
    'مشاكل محاسبية',
    'محاسبة إدارية',
    'محاسبة دولية',
    'محاسبة ضريبية',
  ];
  return <SubjectOption>[
    for (int i = 0; i < titles.length; i++)
      SubjectOption(
        id: 'fallback-$gradeKey-$i',
        title: titles[i],
        gradeKey: gradeKey,
      ),
  ];
}

/// Review screen for one pending request
/// (`# Grade- Grade one pending requests view`): fixed 1280 x 800 canvas.
///
/// - header: brand 540 x 80 at (370, 24); the unified shell draws the
///   single fixed menu button at (80, 24, 80 x 80);
/// - grades nav 660 x 40 at (310, 132) + tabs 336 x 40 at (472, 190);
/// - student capsule 540 x 132 at (370, 240): 100 x 100 avatar, 24 Bold
///   name, 13 px metadata row (phone • grade • date • device);
/// - stepper bar at (80, 392), 1120 wide, 40 px gaps, 250 x 60 capsules
///   with a #F59E0B frame: 3 buttons for Center students
///   ([Student Type] [Student Subjects] [Other Subjects]), 2 centered
///   buttons for Guest ([Student Type] [Student Subjects]);
/// - decision bar centered at Y 710 (gap 24): 160 x 48 Approve (filled)
///   + 160 x 48 Reject (outlined) wired to `approveStudent` /
///   `rejectStudent` with snackbar + back navigation.
class GradePendingRequestsViewScreen extends ConsumerStatefulWidget {
  final PendingRequestRow row;
  final VoidCallback? onMenuPressed;
  final ValueChanged<String>? onStudentsTab;
  final ValueChanged<String>? onSubjectsTab;
  final VoidCallback? onBack;

  const GradePendingRequestsViewScreen({
    super.key,
    required this.row,
    this.onMenuPressed,
    this.onStudentsTab,
    this.onSubjectsTab,
    this.onBack,
  });

  @override
  ConsumerState<GradePendingRequestsViewScreen> createState() =>
      _GradePendingRequestsViewScreenState();
}

class _GradePendingRequestsViewScreenState
    extends ConsumerState<GradePendingRequestsViewScreen> {
  // Legacy 'public_student' values (pre-migration requests) count as
  // Guest, never as Center.
  late bool _isCenter = widget.row.application.studentType != 'guest' &&
      widget.row.application.studentType != 'public_student';
  Map<String, bool> _gradeToggles = <String, bool>{};
  Map<String, String> _gradePlans = <String, String>{};
  Map<String, bool> _otherToggles = <String, bool>{};
  Map<String, String> _otherPlans = <String, String>{};
  bool _busy = false;
  String? _error;

  String get _gradeKey =>
      widget.row.application.gradeKey ?? 'grade_one';
  Color get _accent => gradeAccent(_gradeKey);

  String get _typeLabel => _isCenter ? 'Center' : 'Guest';

  /// Grades before the student's own grade (oldest first). Grade One has
  /// no previous grades, so its Other-Subjects overlay is an empty state.
  List<String> _previousGradeKeys() {
    final int index = canonicalGradeKeys.indexOf(_gradeKey);
    if (index <= 0) return const <String>[];
    return canonicalGradeKeys.sublist(0, index);
  }

  /// Synchronous subject snapshot for dialogs and the approve payload:
  /// live provider value when loaded and non-empty, otherwise the same
  /// Figma fallback the dialogs display. Never suspends, so overlay
  /// opening and approve can never hang on a pending future.
  List<SubjectOption> _gradeSubjectsSync() {
    final List<SubjectOption>? live =
        ref.read(gradeSubjectsProvider(_gradeKey)).maybeWhen(
              data: (List<SubjectOption> subjects) => subjects,
              orElse: () => null,
            );
    if (live != null && live.isNotEmpty) return live;
    return _fallbackSubjects(_gradeKey);
  }

  List<SubjectOption> _otherSubjectsSync() {
    final List<SubjectOption> all = <SubjectOption>[];
    for (final String key in _previousGradeKeys()) {
      final List<SubjectOption>? live =
          ref.read(gradeSubjectsProvider(key)).maybeWhen(
                data: (List<SubjectOption> subjects) => subjects,
                orElse: () => null,
              );
      if (live != null && live.isNotEmpty) {
        all.addAll(live);
      } else {
        all.addAll(_fallbackSubjects(key));
      }
    }
    return all;
  }

  Map<String, List<SubjectOption>> _otherSubjectGroups() {
    final Map<String, List<SubjectOption>> groups =
        <String, List<SubjectOption>>{};
    for (final String key in _previousGradeKeys()) {
      final List<SubjectOption>? live =
          ref.read(gradeSubjectsProvider(key)).maybeWhen(
                data: (List<SubjectOption> subjects) => subjects,
                orElse: () => null,
              );
      final List<SubjectOption> list =
          (live != null && live.isNotEmpty) ? live : _fallbackSubjects(key);
      if (list.isNotEmpty) groups[key] = list;
    }
    return groups;
  }

  Future<void> _pickType() async {
    final bool? selected = await showStudentTypeDialog(
      context,
      isCenter: _isCenter,
      accent: _accent,
    );
    if (selected == null || !mounted) return;
    setState(() {
      _isCenter = selected;
    });
  }

  Future<void> _pickGradeSubjects() async {
    final GradeSubjectsResult? updated = await showGradeSubjectsDialog(
      context,
      gradeLabel: _gradeLabel(_gradeKey),
      subjects: _gradeSubjectsSync(),
      initialToggles: _gradeToggles,
      initialPlans: _gradePlans,
    );
    if (updated == null || !mounted) return;
    setState(() {
      _gradeToggles = updated.toggles;
      _gradePlans = updated.plans;
    });
  }

  Future<void> _pickOtherSubjects() async {
    final GradeSubjectsResult? updated = await showOtherSubjectsDialog(
      context,
      gradeKey: _gradeKey,
      previousGrades: _previousGradeKeys(),
      groups: _otherSubjectGroups(),
      initialToggles: _otherToggles,
      initialPlans: _otherPlans,
    );
    if (updated == null || !mounted) return;
    setState(() {
      _otherToggles = updated.toggles;
      _otherPlans = updated.plans;
    });
  }

  List<Map<String, Object>> _subjectAccess(
    List<SubjectOption> gradeSubjects,
    List<SubjectOption> otherSubjects,
  ) {
    return <Map<String, Object>>[
      for (final SubjectOption subject in gradeSubjects)
        <String, Object>{
          'subjectId': subject.id,
          'enabled': _gradeToggles[subject.id] ?? true,
          'plan': _gradePlans[subject.id] ?? 'free',
        },
      for (final SubjectOption subject in otherSubjects)
        <String, Object>{
          'subjectId': subject.id,
          'enabled': _otherToggles[subject.id] ?? true,
          'plan': _otherPlans[subject.id] ?? 'free',
        },
    ];
  }

  Future<void> _approve() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final List<SubjectOption> gradeSubjects = _gradeSubjectsSync();
      final List<SubjectOption> otherSubjects =
          _isCenter ? _otherSubjectsSync() : const <SubjectOption>[];
      final List<Map<String, Object>> access =
          _subjectAccess(gradeSubjects, otherSubjects);
      final ApprovalResult result = await ref
          .read(applicationDecisionControllerProvider)
          .approve(
            studentId: widget.row.application.id,
            studentType: _isCenter ? 'center_student' : 'guest',
            planKey: _isCenter ? 'free' : 'guest',
            subjectAccess: access,
          );
      if (!mounted) return;
      ref.invalidate(gradePendingRequestsProvider(_gradeKey));
      final bool hasPaidPlan = access.any(
        (Map<String, Object> item) =>
            item['enabled'] == true && (item['plan'] ?? 'free') != 'free',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            hasPaidPlan
                ? 'تم اعتماد الطالب بنجاح — تفعيل الباقات المدفوعة '
                    'يتم عبر تسجيل دفعة.'
                : result.activationFailures.isNotEmpty
                    ? 'تم الاعتماد وتفعيل ${result.activatedCount} مادة — '
                        'تعذّر تفعيل ${result.activationFailures.length}.'
                    : 'تم اعتماد الطالب وتفعيل '
                        '${result.activatedCount} مادة بنجاح.',
          ),
        ),
      );
      widget.onBack?.call();
    } on DecisionFailure catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'تعذّر تنفيذ القرار. حاول مرة أخرى.';
        });
      }
    }
  }

  Future<void> _reject() async {
    if (_busy) return;
    final String? reason = await showRejectReasonDialog(
      context,
      accent: _accent,
    );
    if (reason == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(applicationDecisionControllerProvider).reject(
            studentId: widget.row.application.id,
            reason: reason,
          );
      if (!mounted) return;
      ref.invalidate(gradePendingRequestsProvider(_gradeKey));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم رفض طلب الانضمام.')),
      );
      widget.onBack?.call();
    } on DecisionFailure catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'تعذّر تنفيذ القرار. حاول مرة أخرى.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Prime every grade's subjects stream up front so the stepper
    // overlays and the approve payload always read loaded values;
    // offline they resolve to errors and the Figma fallbacks apply.
    for (final String key in canonicalGradeKeys) {
      ref.watch(gradeSubjectsProvider(key));
    }
    final List<({String label, String value, VoidCallback onTap})> steps =
        <({String label, String value, VoidCallback onTap})>[
      (
        label: 'Student Type',
        value: _typeLabel,
        onTap: _pickType,
      ),
      (
        label: 'Student Subjects',
        value: 'Manage',
        onTap: _pickGradeSubjects,
      ),
      if (_isCenter)
        (
          label: 'Other Subjects',
          value: 'Manage',
          onTap: _pickOtherSubjects,
        ),
    ];
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
                  child: IgnorePointer(child: _BrandLockup()),
                ),
                Positioned(
                  left: 310,
                  top: 132,
                  width: 660,
                  height: 40,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: const Color(0xFF979797),
                        width: 1,
                        strokeAlign: BorderSide.strokeAlignInside,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        for (int i = 0; i < _grades.length; i++)
                          ...<Widget>[
                          if (i > 0) const SizedBox(width: 4),
                          _GradePill(
                            label: _grades[i].label,
                            active: _grades[i].key == _gradeKey,
                            accent: gradeAccent(_grades[i].key),
                            onTap: () {},
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 472,
                  top: 190,
                  width: 336,
                  height: 40,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      _SectionTab(
                        label: 'Students',
                        active: true,
                        accent: _accent,
                        onTap: () =>
                            widget.onStudentsTab?.call(_gradeKey),
                      ),
                      const SizedBox(width: 4),
                      _SectionTab(
                        label: 'Subjects',
                        active: false,
                        accent: _accent,
                        onTap: () =>
                            widget.onSubjectsTab?.call(_gradeKey),
                      ),
                    ],
                  ),
                ),
                _StudentInfoCard(
                  row: widget.row,
                  gradeLabel: _gradeLabel(_gradeKey),
                ),
                // Review stepper bar (80, 392, 1120 wide, gap 40).
                Positioned(
                  left: 80,
                  top: 392,
                  width: 1120,
                  height: 60,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      for (int i = 0; i < steps.length; i++) ...<Widget>[
                        if (i > 0) const SizedBox(width: 40),
                        _StepButton(
                          label: steps[i].label,
                          value: steps[i].value,
                          onTap: _busy ? null : steps[i].onTap,
                        ),
                      ],
                    ],
                  ),
                ),
                if (_error != null)
                  Positioned(
                    left: 240,
                    top: 664,
                    width: 800,
                    height: 40,
                    child: Center(
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 14,
                          color: Color(0xFFB3261E),
                        ),
                      ),
                    ),
                  ),
                // Decision bar centered at Y 710 (gap 24).
                Positioned(
                  left: 468,
                  top: 710,
                  width: 344,
                  height: 48,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      _DecisionButton(
                        label: 'Approve',
                        filled: true,
                        accent: _accent,
                        busy: _busy,
                        onTap: _approve,
                      ),
                      const SizedBox(width: 24),
                      _DecisionButton(
                        label: 'Reject',
                        filled: false,
                        accent: _accent,
                        busy: _busy,
                        onTap: _reject,
                      ),
                    ],
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
              style: AppTypography.homeBrandLight(fontSize: 48).copyWith(
                color: AppColors.ink,
              ),
            ),
          ],
        ),
        maxLines: 1,
      ),
    );
  }
}

class _GradePill extends StatelessWidget {
  final String label;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  const _GradePill({
    required this.label,
    required this.active,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      height: 32,
      child: Material(
        color: active ? accent : Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: active
                    ? const Color(0xFFFFFFFF)
                    : const Color(0xFF374151),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTab extends StatelessWidget {
  final String label;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  const _SectionTab({
    required this.label,
    required this.active,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      height: 32,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 14,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: active ? accent : const Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              height: 2,
              width: 64,
              color: active ? accent : Colors.transparent,
            ),
          ],
        ),
      ),
    );
  }
}

/// Student capsule 540 x 132 at (370, 240): 100 x 100 avatar, 24 Bold
/// name, 13 px metadata row (phone • grade • date • device).
class _StudentInfoCard extends StatelessWidget {
  final PendingRequestRow row;
  final String gradeLabel;

  const _StudentInfoCard({
    required this.row,
    required this.gradeLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 370,
      top: 240,
      width: 540,
      height: 132,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(9999),
          border: Border.all(
            color: const Color(0xFFF59E0B),
            width: 1.5,
          ),
        ),
        child: Stack(
          children: <Widget>[
            const Positioned(
              left: 16,
              top: 16,
              width: 100,
              height: 100,
              child: _StudentAvatar(),
            ),
            Positioned(
              left: 132,
              top: 24,
              width: 392,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    row.application.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: <Widget>[
                      _MetaChip(text: row.application.phone),
                      _MetaChip(text: gradeLabel),
                      _MetaChip(text: row.requestDate),
                      _MetaChip(text: row.deviceLabel),
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

class _StudentAvatar extends StatelessWidget {
  const _StudentAvatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFFF3F4F6),
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.person,
        size: 56,
        color: Color(0xFF9CA3AF),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String text;

  const _MetaChip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: AppTypography.fontFamily,
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: Color(0xFF6B7280),
      ),
    );
  }
}

/// Stepper capsule 250 x 60 with a #F59E0B frame: 18 Medium label +
/// current-value subtitle.
class _StepButton extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _StepButton({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 250,
      height: 60,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9999),
          side: const BorderSide(color: Color(0xFFF59E0B), width: 1.5),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9999),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 18,
                  height: 1.1,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF374151),
                ),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 13,
                  height: 1.1,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DecisionButton extends StatelessWidget {
  final String label;
  final bool filled;
  final Color accent;
  final bool busy;
  final VoidCallback onTap;

  const _DecisionButton({
    required this.label,
    required this.filled,
    required this.accent,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Widget child = busy && filled
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
        : Text(
            label,
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: filled ? Colors.white : accent,
            ),
          );
    if (filled) {
      return SizedBox(
        width: 160,
        height: 48,
        child: ElevatedButton(
          onPressed: busy ? null : onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
            disabledBackgroundColor: accent.withValues(alpha: 0.6),
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9999),
            ),
            elevation: 0,
          ),
          child: child,
        ),
      );
    }
    return SizedBox(
      width: 160,
      height: 48,
      child: OutlinedButton(
        onPressed: busy ? null : onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          padding: EdgeInsets.zero,
          side: BorderSide(color: accent, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9999),
          ),
        ),
        child: child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The overlays.
// ---------------------------------------------------------------------------

/// Saved per-subject selection: enable toggles + plan per subject id
/// (`free` is the default plan when absent).
typedef GradeSubjectsResult = ({Map<String, bool> toggles, Map<String, String> plans});

const List<String> _subjectPlans = <String>['free', 'pro', 'max'];

String _planDisplay(String plan) {
  return switch (plan) {
    'pro' => 'PRO',
    'max' => 'MAX',
    _ => 'FREE',
  };
}

Widget _overlayShell({
  required double width,
  required double height,
  required String title,
  required List<Widget> children,
  double borderRadius = 20,
  double titleFontSize = 20,
}) {
  return Dialog(
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(borderRadius),
    ),
    clipBehavior: Clip.antiAlias,
    child: SizedBox(
      width: width,
      height: height,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: titleFontSize,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    ),
  );
}

Widget _saveButton({
  required Color accent,
  required VoidCallback? onTap,
}) {
  return SizedBox(
    width: 160,
    height: 32,
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
      child: const Text(
        'Save',
        style: TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: Color(0xFFFFFFFF),
        ),
      ),
    ),
  );
}

/// Overlay 1 — Student Type (380 x 220): Center | Guest switch + Save.
/// Returns the selected `isCenter`, or null when dismissed.
Future<bool?> showStudentTypeDialog(
  BuildContext context, {
  required bool isCenter,
  required Color accent,
}) {
  bool selected = isCenter;
  return showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          return _overlayShell(
            width: 380,
            height: 220,
            title: 'Student Type',
            children: <Widget>[
              Container(
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9999),
                  border: Border.all(
                    color: const Color(0xFFE5E7EB),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    for (final ({String label, bool value}) option in const <
                        ({String label, bool value})>[
                      (label: 'Center', value: true),
                      (label: 'Guest', value: false),
                    ])
                      Expanded(
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => selected = option.value),
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: selected == option.value
                                  ? accent
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(9999),
                            ),
                            child: Text(
                              option.label,
                              style: TextStyle(
                                fontFamily: AppTypography.fontFamily,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: selected == option.value
                                    ? Colors.white
                                    : const Color(0xFF374151),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Spacer(),
              Center(
                child: _saveButton(
                  accent: accent,
                  onTap: () => Navigator.of(context).pop(selected),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

/// Per-subject [ FREE | PRO | MAX ] capsule. The selected option fills
/// orange (#F59E0B) with white text; the whole capsule is untappable
/// while the subject switch is off.
class _PlanCapsule extends StatelessWidget {
  final String selected;
  final bool enabled;
  final ValueChanged<String> onSelected;

  const _PlanCapsule({
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !enabled,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.4,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9999),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          padding: const EdgeInsets.all(2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final String plan in _subjectPlans)
                GestureDetector(
                  onTap: () => onSelected(plan),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: selected == plan
                          ? const Color(0xFFF59E0B)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(9999),
                    ),
                    child: Text(
                      _planDisplay(plan),
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: selected == plan
                            ? Colors.white
                            : const Color(0xFF374151),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _subjectRow({
  required String title,
  required bool enabled,
  required ValueChanged<bool> onChanged,
  required String plan,
  required ValueChanged<String> onPlanChanged,
}) {
  // Figma order (left → right): name, green switch, plan capsule —
  // centered as one compact group (no spaceBetween).
  return SizedBox(
    height: 56,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        // 1. Subject name, fixed width, right-aligned.
        SizedBox(
          width: 180,
          child: Text(
            title,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'GoogleSansFlex',
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Color(0xFF111827),
            ),
          ),
        ),
        const SizedBox(width: 36),
        // 2. Green enable switch.
        CupertinoSwitch(
          value: enabled,
          onChanged: onChanged,
          activeTrackColor: const Color(0xFF10B981),
        ),
        const SizedBox(width: 24),
        // 3. Triple plan capsule.
        _PlanCapsule(
          selected: plan,
          enabled: enabled,
          onSelected: onPlanChanged,
        ),
      ],
    ),
  );
}

/// Overlay — Grade Subjects (930 x 416, radius 24): per-subject emerald
/// switches (default ON) with a per-subject [ FREE | PRO | MAX ] capsule
/// (default FREE, untappable while the switch is off). The orange Save
/// persists toggles + plans and closes the overlay.
Future<GradeSubjectsResult?> showGradeSubjectsDialog(
  BuildContext context, {
  required String gradeLabel,
  required List<SubjectOption> subjects,
  required Map<String, bool> initialToggles,
  required Map<String, String> initialPlans,
}) {
  final Map<String, bool> toggles = Map<String, bool>.from(initialToggles);
  final Map<String, String> plans = Map<String, String>.from(initialPlans);
  return showDialog<GradeSubjectsResult>(
    context: context,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          return _overlayShell(
            width: 930,
            height: 416,
            borderRadius: 24,
            titleFontSize: 28,
            title: '$gradeLabel Subjects',
            children: <Widget>[
              Expanded(
                child: subjects.isEmpty
                    ? const Center(
                        child: Text(
                          'No subjects in this grade yet.',
                          style: TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontSize: 14,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      )
                    : ListView(
                        padding: EdgeInsets.zero,
                        children: <Widget>[
                          for (final SubjectOption subject in subjects)
                            _subjectRow(
                              title: subject.title,
                              enabled: toggles[subject.id] ?? true,
                              onChanged: (bool value) => setState(
                                () => toggles[subject.id] = value,
                              ),
                              plan: plans[subject.id] ?? 'free',
                              onPlanChanged: (String plan) => setState(
                                () => plans[subject.id] = plan,
                              ),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 8),
              Center(
                child: _saveButton(
                  accent: const Color(0xFFF59E0B),
                  onTap: () => Navigator.of(context).pop(
                    (toggles: toggles, plans: plans),
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

/// Overlay — Other Subjects (930 wide, vertical scroll): previous-grade
/// sections with switches + per-subject plans. Grade One students have
/// no previous grades, so a clean empty state is shown. The fixed
/// orange Save persists the makeup selection and closes the overlay.
Future<GradeSubjectsResult?> showOtherSubjectsDialog(
  BuildContext context, {
  required String gradeKey,
  required List<String> previousGrades,
  required Map<String, List<SubjectOption>> groups,
  required Map<String, bool> initialToggles,
  required Map<String, String> initialPlans,
}) {
  final Map<String, bool> toggles = Map<String, bool>.from(initialToggles);
  final Map<String, String> plans = Map<String, String>.from(initialPlans);
  final List<String> orderedKeys = <String>[
    for (final String key in previousGrades)
      if ((groups[key] ?? const <SubjectOption>[]).isNotEmpty) key,
  ];
  return showDialog<GradeSubjectsResult>(
    context: context,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          Widget body;
          if (previousGrades.isEmpty) {
            body = const Center(
              child: Text(
                'لا توجد فرق دراسية سابقة لطلاب الفرقة الأولى',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 16,
                  color: Color(0xFF6B7280),
                ),
              ),
            );
          } else if (orderedKeys.isEmpty) {
            body = const Center(
              child: Text(
                'No previous subjects yet.',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 14,
                  color: Color(0xFF6B7280),
                ),
              ),
            );
          } else {
            body = SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (int g = 0; g < orderedKeys.length; g++) ...<Widget>[
                    if (g > 0) const SizedBox(height: 12),
                    Text(
                      '${_gradeLabel(orderedKeys[g])} Subjects',
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF374151),
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (final SubjectOption subject
                        in groups[orderedKeys[g]]!)
                      _subjectRow(
                        title: subject.title,
                        enabled: toggles[subject.id] ?? true,
                        onChanged: (bool value) => setState(
                          () => toggles[subject.id] = value,
                        ),
                        plan: plans[subject.id] ?? 'free',
                        onPlanChanged: (String plan) => setState(
                          () => plans[subject.id] = plan,
                        ),
                      ),
                  ],
                ],
              ),
            );
          }
          return _overlayShell(
            width: 930,
            height: 520,
            borderRadius: 24,
            titleFontSize: 28,
            title: 'Other Subjects',
            children: <Widget>[
              Expanded(child: body),
              const SizedBox(height: 8),
              Center(
                child: _saveButton(
                  accent: const Color(0xFFF59E0B),
                  onTap: () => Navigator.of(context).pop(
                    (toggles: toggles, plans: plans),
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

/// Reject-reason dialog: requires ≥ 3 characters, then returns the reason.
Future<String?> showRejectReasonDialog(
  BuildContext context, {
  required Color accent,
}) {
  final TextEditingController controller = TextEditingController();
  String? error;
  return showDialog<String>(
    context: context,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          return _overlayShell(
            width: 380,
            height: 300,
            title: 'Reject Request',
            children: <Widget>[
              TextField(
                controller: controller,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'سبب الرفض',
                  border: OutlineInputBorder(),
                ),
              ),
              if (error != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  error!,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 13,
                    color: Color(0xFFB3261E),
                  ),
                ),
              ],
              const Spacer(),
              Center(
                child: _saveButton(
                  accent: accent,
                  onTap: () {
                    if (controller.text.trim().length < 3) {
                      setState(
                        () => error =
                            'اكتب سبب الرفض (3 أحرف على الأقل).',
                      );
                      return;
                    }
                    Navigator.of(context).pop(controller.text.trim());
                  },
                ),
              ),
            ],
          );
        },
      );
    },
  );
}
