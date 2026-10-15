import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/dashboard_filter_dropdown.dart';
import '../../../../core/widgets/glass_text_field.dart';
import '../../../../core/widgets/primary_action_button.dart';
import '../../domain/entities/join_application.dart';
import '../../domain/grade.dart';
import '../providers/application_decision_provider.dart';

/// Result message of a completed decision, shown by the caller as a
/// SnackBar. `null` means the dialog was dismissed without a decision.
Future<String?> showApplicationDecisionDialog(
  BuildContext context,
  JoinApplication application,
) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) =>
        _ApplicationDecisionDialog(application: application),
  );
}

enum _DecisionTab { approve, reject }

class _ApplicationDecisionDialog extends ConsumerStatefulWidget {
  const _ApplicationDecisionDialog({required this.application});

  final JoinApplication application;

  @override
  ConsumerState<_ApplicationDecisionDialog> createState() =>
      _ApplicationDecisionDialogState();
}

class _ApplicationDecisionDialogState
    extends ConsumerState<_ApplicationDecisionDialog> {
  static const Map<String, String> _studentTypes = <String, String>{
    'center_student': 'طالب سنتر',
    'guest': 'ضيف',
  };

  static const Map<String, String> _plans = <String, String>{
    'free': 'free — المجانية',
    'guest': 'guest — المجانية (ضيف)',
    'pro': 'pro — مدفوعة',
    'max': 'max — مدفوعة',
  };

  _DecisionTab _tab = _DecisionTab.approve;
  late String _studentType;
  late String _planKey;
  Map<String, bool> _subjectToggles = <String, bool>{};
  bool _togglesSeeded = false;
  bool _busy = false;
  String? _error;
  String? _reasonError;
  final TextEditingController _reasonController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final String? requested = widget.application.studentType;
    // Pre-migration stored value maps to the Guest type so legacy pending
    // requests are not silently defaulted to center.
    final String requestedType =
        requested == 'public_student' ? 'guest' : requested ?? 'center_student';
    _studentType = _studentTypes.containsKey(requestedType)
        ? requestedType
        : 'center_student';
    _planKey = _defaultPlanFor(_studentType);
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  static String _defaultPlanFor(String studentType) =>
      studentType == 'guest' ? 'guest' : 'free';

  void _selectStudentType(String? value) {
    if (value == null || value == _studentType) return;
    setState(() {
      _studentType = value;
      _planKey = _defaultPlanFor(value);
      _error = null;
    });
  }

  Future<void> _confirmApprove(List<SubjectOption> subjects) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    // Only explicit ON enters the payload: OFF / untouched rows produce
    // NO write, so no clutter disabled assignment rows are created in
    // the Subjects tab (same discipline as the review-screen flow).
    final List<Map<String, Object>> subjectAccess = <Map<String, Object>>[
      for (final SubjectOption subject in subjects)
        if (_subjectToggles[subject.id] ?? true)
          <String, Object>{
            'subjectId': subject.id,
            'enabled': true,
          },
    ];
    try {
      final ApprovalResult result = await ref
          .read(applicationDecisionControllerProvider)
          .approve(
            studentId: widget.application.id,
            studentType: _studentType,
            planKey: _planKey,
            subjectAccess: subjectAccess,
          );
      if (!mounted) return;
      final bool isPaidPlan =
          !ApplicationDecisionController.freePlanKeys.contains(_planKey);
      final String message;
      if (isPaidPlan) {
        message = 'تم اعتماد الطالب بنجاح — تفعيل الباقة المدفوعة '
            '($_planKey) يتم عبر تسجيل دفعة.';
      } else if (result.activationFailures.isNotEmpty) {
        message = 'تم الاعتماد وتفعيل ${result.activatedCount} مادة — '
            'تعذّر تفعيل ${result.activationFailures.length}.';
      } else {
        message =
            'تم اعتماد الطالب وتفعيل ${result.activatedCount} مادة بنجاح.';
      }
      Navigator.of(context).pop(message);
    } on DecisionFailure catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  Future<void> _confirmReject() async {
    if (_busy) return;
    final String reason = _reasonController.text.trim();
    if (reason.length < 3) {
      setState(() => _reasonError = 'اكتب سبب الرفض (3 أحرف على الأقل).');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _reasonError = null;
    });
    try {
      await ref.read(applicationDecisionControllerProvider).reject(
            studentId: widget.application.id,
            reason: reason,
          );
      if (!mounted) return;
      Navigator.of(context).pop('تم رفض طلب الانضمام.');
    } on DecisionFailure catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    final JoinApplication application = widget.application;
    final AsyncValue<List<SubjectOption>> subjectsAsync =
        ref.watch(gradeSubjectsProvider(application.gradeKey));

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: rs(24), vertical: rs(24)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 680),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.inputStroke, width: 1.5),
          borderRadius: BorderRadius.circular(28),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: rs(36),
            vertical: rs(32),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          application.fullName,
                          style: AppTypography.statValue(fontSize: rs(30)),
                        ),
                        SizedBox(height: rs(8)),
                        Text(
                          application.phone,
                          style: AppTypography.statLabel(fontSize: rs(22)),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      IconButton(
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                        color: AppColors.ink,
                        tooltip: 'إغلاق',
                      ),
                      _GradeChip(label: gradeDisplayName(application.gradeKey)),
                    ],
                  ),
                ],
              ),
              SizedBox(height: rs(24)),
              _SegmentedTabs(
                tab: _tab,
                onChanged: _busy
                    ? null
                    : (tab) => setState(() {
                          _tab = tab;
                          _error = null;
                        }),
              ),
              SizedBox(height: rs(24)),
              if (_tab == _DecisionTab.approve) ...<Widget>[
                _FieldLabel(text: 'نوع الطالب'),
                SizedBox(height: rs(10)),
                DashboardFilterDropdown<String>(
                  width: 600,
                  value: _studentType,
                  items: _studentTypes,
                  onChanged: _busy ? (_) {} : _selectStudentType,
                ),
                SizedBox(height: rs(20)),
                _FieldLabel(text: 'باقة الاشتراك'),
                SizedBox(height: rs(10)),
                DashboardFilterDropdown<String>(
                  width: 600,
                  value: _planKey,
                  items: _plans,
                  onChanged: _busy
                      ? (_) {}
                      : (String? value) => setState(() {
                            if (value != null) _planKey = value;
                          }),
                ),
                SizedBox(height: rs(20)),
                _FieldLabel(text: 'المواد المصرح بها'),
                SizedBox(height: rs(10)),
                subjectsAsync.when(
                  loading: () => Padding(
                    padding: EdgeInsets.symmetric(vertical: rs(24)),
                    child: const Center(
                      child: CircularProgressIndicator(color: AppColors.ink),
                    ),
                  ),
                  error: (Object error, StackTrace _) => Text(
                    'تعذّر تحميل المواد. أعد فتح النافذة.',
                    style: AppTypography.statLabel(fontSize: rs(22)),
                  ),
                  data: (List<SubjectOption> subjects) {
                    if (subjects.isEmpty) {
                      return Text(
                        'لا توجد مواد نشطة لهذه الفرقة — سيُعتمد الطالب بدون مواد.',
                        style: AppTypography.statLabel(fontSize: rs(22)),
                      );
                    }
                    if (!_togglesSeeded) {
                      _subjectToggles = <String, bool>{
                        for (final SubjectOption s in subjects) s.id: true,
                      };
                      _togglesSeeded = true;
                    }
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        for (final SubjectOption subject in subjects)
                          _SubjectToggleRow(
                            title: subject.title,
                            value: _subjectToggles[subject.id] ?? true,
                            onChanged: _busy
                                ? null
                                : (bool value) => setState(
                                      () => _subjectToggles[subject.id] = value,
                                    ),
                          ),
                      ],
                    );
                  },
                ),
                if (_error != null) ...<Widget>[
                  SizedBox(height: rs(16)),
                  Text(
                    _error!,
                    style: AppTypography.statLabel(fontSize: rs(22)).copyWith(
                      color: const Color(0xFFB3261E),
                    ),
                  ),
                ],
                SizedBox(height: rs(24)),
                PrimaryActionButton(
                  label: 'تأكيد القبول',
                  isLoading: _busy,
                  onPressed: _busy
                      ? null
                      : () {
                          final List<SubjectOption> subjects =
                              subjectsAsync.maybeWhen(
                            data: (List<SubjectOption> value) => value,
                            orElse: () => <SubjectOption>[],
                          );
                          _confirmApprove(subjects);
                        },
                ),
              ] else ...<Widget>[
                _FieldLabel(text: 'سبب الرفض'),
                SizedBox(height: rs(10)),
                GlassTextField(
                  controller: _reasonController,
                  placeholder: 'اكتب سبب الرفض...',
                  errorText: _reasonError,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _confirmReject(),
                ),
                if (_error != null) ...<Widget>[
                  SizedBox(height: rs(16)),
                  Text(
                    _error!,
                    style: AppTypography.statLabel(fontSize: rs(22)).copyWith(
                      color: const Color(0xFFB3261E),
                    ),
                  ),
                ],
                SizedBox(height: rs(24)),
                PrimaryActionButton(
                  label: 'تأكيد الرفض',
                  isLoading: _busy,
                  onPressed: _busy ? null : _confirmReject,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    return Text(text, style: AppTypography.sectionHeading(fontSize: rs(24)));
  }
}

class _GradeChip extends StatelessWidget {
  const _GradeChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: rs(18), vertical: rs(8)),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(rs(100)),
      ),
      child: Text(label, style: AppTypography.buttonLabel(fontSize: rs(20))),
    );
  }
}

class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs({required this.tab, required this.onChanged});

  final _DecisionTab tab;
  final ValueChanged<_DecisionTab>? onChanged;

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    return Row(
      children: <Widget>[
        Expanded(
          child: _TabButton(
            label: 'قبول الطلب',
            selected: tab == _DecisionTab.approve,
            onTap:
                onChanged == null ? null : () => onChanged!(_DecisionTab.approve),
          ),
        ),
        SizedBox(width: rs(12)),
        Expanded(
          child: _TabButton(
            label: 'رفض الطلب',
            selected: tab == _DecisionTab.reject,
            onTap:
                onChanged == null ? null : () => onChanged!(_DecisionTab.reject),
          ),
        ),
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(rs(100)),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: rs(14)),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.ink : Colors.white,
          border: Border.all(color: AppColors.inputStroke, width: 1.5),
          borderRadius: BorderRadius.circular(rs(100)),
        ),
        child: Text(
          label,
          style: AppTypography.buttonLabel(fontSize: rs(22)).copyWith(
            color: selected ? Colors.white : AppColors.ink,
          ),
        ),
      ),
    );
  }
}

class _SubjectToggleRow extends StatelessWidget {
  const _SubjectToggleRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    return Container(
      margin: EdgeInsets.only(bottom: rs(10)),
      padding: EdgeInsets.symmetric(horizontal: rs(20), vertical: rs(6)),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.inputStroke, width: 1.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: AppTypography.statLabel(fontSize: rs(22)),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.ink,
          ),
        ],
      ),
    );
  }
}
