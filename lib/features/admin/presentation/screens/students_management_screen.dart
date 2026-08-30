import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../core/errors/friendly_error_message.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/admin_grades.dart';
import '../widgets/payment_receipt_dialog.dart';

/// Students management screen.
///
/// Wired to the existing Cloud Functions only: approveStudent,
/// convertStudentType, setSubscriptionDisciplinaryStatus,
/// setSubjectAccess, onPasswordResetApproved, onPaymentLogged.
/// Every binary decision uses a [CupertinoSwitch].
class StudentsManagementScreen extends StatelessWidget {
  const StudentsManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('users')
        .where('role', whereIn: const ['student', 'new_student']);

    return Scaffold(
      appBar: AppBar(title: const Text('إدارة الطلاب')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('تعذر تحميل قائمة الطلاب.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('لا يوجد طلاب مسجلون بعد.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              final name = (data['full_name'] as String?) ?? 'طالب';
              final phone = (data['phone_number'] as String?) ?? '';
              final role = (data['role'] as String?) ?? '';
              final approval = (data['approval_status'] as String?) ?? '';
              final studentType = (data['student_type'] as String?) ?? '';
              final grade = (data['grade'] as String?) ?? '';

              return Card(
                child: ListTile(
                  leading: Icon(
                    approval == 'approved'
                        ? Icons.verified_user_outlined
                        : Icons.pending_actions_outlined,
                    color: approval == 'approved'
                        ? AppColors.success
                        : AppColors.warning,
                  ),
                  title: Text(name),
                  subtitle: Text(
                    '$phone • ${_gradeLabel(grade)}\n'
                    '${_roleLabel(role, approval)}'
                    '${studentType.isEmpty ? '' : ' • ${_studentTypeLabel(studentType)}'}',
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => StudentDetailScreen(
                        studentId: doc.id,
                        studentName: name,
                        studentType: studentType,
                        isApproved: approval == 'approved' && role == 'student',
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  static String _gradeLabel(String grade) {
    return switch (grade) {
      'grade_1' => 'الفرقة الأولى',
      'grade_2' => 'الفرقة الثانية',
      'grade_3' => 'الفرقة الثالثة',
      'grade_4' => 'الفرقة الرابعة',
      _ => grade.isEmpty ? 'غير محدد' : grade,
    };
  }

  static String _roleLabel(String role, String approval) {
    if (role == 'new_student' || approval == 'pending') return 'بانتظار الاعتماد';
    if (approval == 'rejected') return 'مرفوض';
    return 'طالب حالي';
  }

  static String _studentTypeLabel(String studentType) {
    return switch (studentType) {
      'center_student' => 'طالب سنتر',
      'public_student' => 'طالب عام',
      _ => studentType,
    };
  }
}

class StudentDetailScreen extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String studentType;
  final bool isApproved;

  const StudentDetailScreen({
    required this.studentId,
    required this.studentName,
    required this.studentType,
    required this.isApproved,
    super.key,
  });

  @override
  State<StudentDetailScreen> createState() => _StudentDetailScreenState();
}

class _StudentDetailScreenState extends State<StudentDetailScreen> {
  final _functions = FirebaseFunctions.instance;
  final _busy = <String>{};

  Future<void> _call(
    String key,
    String functionName,
    Map<String, dynamic> payload,
    String successMessage,
  ) async {
    setState(() => _busy.add(key));
    try {
      await _functions.httpsCallable(functionName).call(payload);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } on FirebaseFunctionsException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              friendlyFunctionErrorMessage(error, 'فشلت العملية.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  void _showStaffPasswordResetDialog() {
    final passwordController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إعادة تعيين كلمة مرور الطالب'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'أدخل كلمة مرور مؤقتة جديدة للطالب (على الأقل 8 أحرف، حرف كبير، حرف صغير، رقم، ورمز خاص). سيُطلب من الطالب تغييرها فور تسجيل الدخول.',
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(
                labelText: 'كلمة المرور المؤقتة الجديدة',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              final newPass = passwordController.text.trim();
              if (newPass.length < 8) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('كلمة المرور يجب أن تكون 8 أحرف على الأقل.')),
                );
                return;
              }
              Navigator.of(ctx).pop();

              // Create or find pending reset request ID or invoke password reset
              final pendingSnap = await FirebaseFirestore.instance
                  .collection('password_reset_requests')
                  .where('student_id', isEqualTo: widget.studentId)
                  .where('status', isEqualTo: 'pending')
                  .limit(1)
                  .get();

              String requestId;
              if (pendingSnap.docs.isNotEmpty) {
                requestId = pendingSnap.docs.first.id;
              } else {
                final reqRef = FirebaseFirestore.instance.collection('password_reset_requests').doc();
                await reqRef.set({
                  'student_id': widget.studentId,
                  'status': 'pending',
                  'created_at': FieldValue.serverTimestamp(),
                });
                requestId = reqRef.id;
              }

              await _call(
                'password_reset',
                'onPasswordResetApproved',
                {'requestId': requestId, 'newPassword': newPass},
                'تمت إعادة تعيين كلمة المرور بنجاح وتسجيل الإجراء بالأرشيف الأمني.',
              );
            },
            child: const Text('تأكيد وإعادة التعيين'),
          ),
        ],
      ),
    );
  }

  void _showLogPaymentDialog() {
    final amountController = TextEditingController();
    final notesController = TextEditingController();
    String? selectedSubjectId;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('تسجيل دفعة جديدة للطالب'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance.collection('subjects').where('is_deleted', isEqualTo: false).snapshots(),
                builder: (context, snapshot) {
                  final subjects = snapshot.data?.docs ?? [];
                  return DropdownButtonFormField<String>(
                    initialValue: selectedSubjectId,
                    decoration: const InputDecoration(
                      labelText: 'المادة',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final s in subjects)
                        DropdownMenuItem(
                          value: s.id,
                          child: Text((s.data()['title'] ?? s.data()['name'] ?? s.id).toString()),
                        ),
                    ],
                    onChanged: (val) => setDialogState(() => selectedSubjectId = val),
                  );
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'المبلغ المدفوع (ج.م)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات (اختياري)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                final amount = double.tryParse(amountController.text.trim());
                if (selectedSubjectId == null || amount == null || amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('يرجى اختيار المادة وتحديد المبلغ.')),
                  );
                  return;
                }
                Navigator.of(ctx).pop();
                // Contract of onPaymentLogged: studentId, subjectId,
                // amount, receiptNumber (+ optional notes). The receipt
                // number is generated here for the manual external payment.
                final receiptNumber =
                    'R-${DateTime.now().millisecondsSinceEpoch}';
                await _call(
                  'log_payment',
                  'onPaymentLogged',
                  {
                    'studentId': widget.studentId,
                    'subjectId': selectedSubjectId,
                    'amount': amount,
                    'receiptNumber': receiptNumber,
                    if (notesController.text.trim().isNotEmpty)
                      'notes': notesController.text.trim(),
                  },
                  'تم تسجيل الدفعة وتوليد الفاتورة بنجاح.',
                );
              },
              child: const Text('تسجيل الدفعة'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.studentName),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock_reset_outlined),
            tooltip: 'إعادة تعيين كلمة المرور',
            onPressed: _showStaffPasswordResetDialog,
          ),
          IconButton(
            icon: const Icon(Icons.payment_outlined),
            tooltip: 'تسجيل دفعة',
            onPressed: _showLogPaymentDialog,
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').doc(widget.studentId).snapshots(),
        builder: (context, userSnap) {
          final userData = userSnap.data?.data() ?? {};
          final fullName = (userData['full_name'] as String?) ?? widget.studentName;
          final phone = (userData['phone_number'] as String?) ?? '';
          final displayHandle = (userData['display_handle'] as String?) ?? '';
          final grade = (userData['grade'] as String?) ?? '';
          final groupId = (userData['group_id'] as String?) ?? '';
          final studentType = (userData['student_type'] as String?) ?? widget.studentType;
          final approval = (userData['approval_status'] as String?) ?? '';
          final boundDeviceId = (userData['device_id'] as String?) ?? '';

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            children: [
              // 1. Profile Summary Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                            child: Text(
                              fullName.isNotEmpty ? fullName[0] : 'ط',
                              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.primary),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                if (displayHandle.isNotEmpty)
                                  Text('@$displayHandle', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                                Text(phone, style: const TextStyle(fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('الفرقة المقيد بها: ${StudentsManagementScreen._gradeLabel(grade)}', style: const TextStyle(fontSize: 13)),
                          if (groupId.isNotEmpty)
                            Text('المجموعة: $groupId', style: const TextStyle(fontSize: 13, color: AppColors.primary)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // 2. Approval Action (if pending)
              if (approval == 'pending') ...[
                _StudentApprovalCard(
                  studentId: widget.studentId,
                  studentGrade: grade,
                  busy: _busy.contains('approve'),
                  onApprove: (type, subjects, priorSubjects, selectedGroup) =>
                      _call(
                    'approve',
                    'approveStudent',
                    {
                      'studentId': widget.studentId,
                      'studentType': type,
                      // Contract of approveStudent: subjectAccess is a list
                      // of {subjectId, enabled} — includes the §13
                      // prior-grade picks merged with the primary selection.
                      'subjectAccess': buildSubjectAccessPayload(
                        primarySubjectIds: subjects,
                        priorGradeSubjectIds: priorSubjects,
                      ),
                      ...?selectedGroup == null ? null : {'groupId': selectedGroup},
                    },
                    'تم اعتماد الطالب بنجاح.',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              // 3. Student Type Converter (if approved)
              if (widget.isApproved || approval == 'approved') ...[
                Text('نوع الطالب', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                _StudentTypeConverter(
                  currentType: studentType,
                  busy: _busy.contains('convert'),
                  onConvert: (target) => _call(
                    'convert',
                    'convertStudentType',
                    {'studentId': widget.studentId, 'targetStudentType': target},
                    'تم تحويل نوع الطالب.',
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],

              // 4. Bound Device Info Card (Read-Only with Staff Reset)
              Text('بيانات الجهاز المرتبط', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              _StudentDeviceCard(
                studentId: widget.studentId,
                boundDeviceId: boundDeviceId,
                busy: _busy.contains('reset_device'),
                onResetDevice: () => _call(
                  'reset_device',
                  'onDeviceChangeRequest',
                  {
                    'studentId': widget.studentId,
                    'action': 'force_reset',
                  },
                  'تمت إعادة تعيين جهاز الطالب بنجاح.',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // 5. Subjects and Subscriptions
              Text('المواد والاشتراكات', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              _StudentSubjectsCard(
                studentId: widget.studentId,
                busy: _busy,
                onCall: _call,
              ),
              const SizedBox(height: AppSpacing.lg),

              // 5b. FINAL_DECISIONS §13: prior-grade subject grants.
              // Rendered ONLY when the student's grade has prior grades —
              // grade_one students never see this section at all (not even
              // disabled).
              if (priorGradeKeysFor(grade).isNotEmpty) ...[
                Text('منح وصول لمواد فرق سابقة',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                _PriorGradeSubjectsCard(
                  studentId: widget.studentId,
                  studentGrade: grade,
                  priorGrades: priorGradeKeysFor(grade),
                  busy: _busy,
                  onCall: _call,
                ),
                const SizedBox(height: AppSpacing.lg),
              ],

              // 6. Payment Logs and Receipts
              Text('سجل المدفوعات والفواتير', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              _StudentPaymentHistoryCard(
                studentId: widget.studentId,
                studentName: fullName,
                studentPhone: phone,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StudentApprovalCard extends StatefulWidget {
  final String studentId;

  /// Canonical student grade from the users doc — drives the §13
  /// prior-grade grant section (absent entirely for grade_one/unknown).
  final String studentGrade;
  final bool busy;
  final Function(
    String type,
    List<String> subjects,
    List<String> priorGradeSubjects,
    String? group,
  ) onApprove;

  const _StudentApprovalCard({
    required this.studentId,
    required this.studentGrade,
    required this.busy,
    required this.onApprove,
  });

  @override
  State<_StudentApprovalCard> createState() => _StudentApprovalCardState();
}

class _StudentApprovalCardState extends State<_StudentApprovalCard> {
  String _selectedType = 'center_student';
  final Set<String> _selectedSubjectIds = {};
  final Set<String> _selectedPriorSubjectIds = {};
  String? _selectedGroup;

  @override
  void initState() {
    super.initState();
    // §13 applies to center students only; default the type accordingly so
    // the prior-grade section is immediately meaningful where applicable.
    _selectedType = 'center_student';
  }

  @override
  Widget build(BuildContext context) {
    // FINAL_DECISIONS §13: only grades ABOVE grade_one have prior grades.
    final priorGrades = priorGradeKeysFor(widget.studentGrade);
    return Card(
      color: AppColors.warning.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.warning),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.pending_actions_outlined, color: AppColors.warning),
                SizedBox(width: AppSpacing.sm),
                Text('مراجعة طلب التسجيل', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              initialValue: _selectedType,
              decoration: const InputDecoration(labelText: 'نوع الطالب المعتمد', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'center_student', child: Text('طالب سنتر (Center Student)')),
                DropdownMenuItem(value: 'public_student', child: Text('طالب عام (Public Student)')),
              ],
              onChanged: (val) => setState(() => _selectedType = val ?? 'center_student'),
            ),
            const SizedBox(height: AppSpacing.sm),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('subjects').where('is_deleted', isEqualTo: false).snapshots(),
              builder: (context, snapshot) {
                final allSubjects = snapshot.data?.docs ?? [];
                // Primary selection stays ALL subjects; the §13 section
                // lists ONLY subjects tagged with a prior grade of THIS
                // student. Untagged legacy subjects stay primary-only.
                final priorSubjects = priorGrades.isEmpty
                    ? <QueryDocumentSnapshot<Map<String, dynamic>>>[]
                    : allSubjects
                        .where((s) => priorGrades
                            .contains(normalizeAdminGradeKey(s.data()['grade'])))
                        .toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('تخصيص المواد الأولية:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final s in allSubjects)
                          FilterChip(
                            label: Text((s.data()['title'] ?? s.data()['name'] ?? s.id).toString()),
                            selected: _selectedSubjectIds.contains(s.id),
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  _selectedSubjectIds.add(s.id);
                                } else {
                                  _selectedSubjectIds.remove(s.id);
                                }
                              });
                            },
                          ),
                      ],
                    ),
                    // FINAL_DECISIONS §13 entry point (a): optional
                    // prior-grade grants at approval time. Absent entirely
                    // for grade_one / unknown-grade students, and hidden
                    // when nothing is tagged yet.
                    if (_selectedType == 'center_student' &&
                        priorSubjects.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'منح وصول لمواد فرق سابقة (اختياري — الفرقة ${gradeLabel(widget.studentGrade)}):',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final s in priorSubjects)
                            FilterChip(
                              avatar: const Icon(Icons.history_edu,
                                  size: 16, color: AppColors.primary),
                              label: Text(
                                '${(s.data()['title'] ?? s.id)} '
                                '(${gradeLabel(normalizeAdminGradeKey(s.data()['grade'])!)})',
                                style: const TextStyle(fontSize: 12),
                              ),
                              selected: _selectedPriorSubjectIds.contains(s.id),
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    _selectedPriorSubjectIds.add(s.id);
                                  } else {
                                    _selectedPriorSubjectIds.remove(s.id);
                                  }
                                });
                              },
                            ),
                        ],
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),
            widget.busy
                ? const Center(child: CircularProgressIndicator())
                : FilledButton.icon(
                    onPressed: () => widget.onApprove(
                      _selectedType,
                      _selectedSubjectIds.toList(),
                      _selectedType == 'center_student'
                          ? _selectedPriorSubjectIds.toList()
                          : const <String>[],
                      _selectedGroup,
                    ),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('اعتماد التسجيل وتفعيل المواد'),
                  ),
          ],
        ),
      ),
    );
  }
}

class _StudentTypeConverter extends StatelessWidget {
  final String currentType;
  final bool busy;
  final ValueChanged<String> onConvert;

  const _StudentTypeConverter({
    required this.currentType,
    required this.busy,
    required this.onConvert,
  });

  @override
  Widget build(BuildContext context) {
    final target = currentType == 'center_student' ? 'public_student' : 'center_student';
    final targetLabel = target == 'center_student' ? 'طالب سنتر' : 'طالب عام';
    return Card(
      child: ListTile(
        leading: const Icon(Icons.swap_horiz_rounded),
        title: Text('النوع الحالي: ${currentType == 'center_student' ? 'طالب سنتر' : 'طالب عام'}'),
        subtitle: Text('تحويل إلى: $targetLabel'),
        trailing: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : FilledButton(
                onPressed: () => onConvert(target),
                child: const Text('تحويل'),
              ),
      ),
    );
  }
}

class _StudentDeviceCard extends StatelessWidget {
  final String studentId;
  final String boundDeviceId;
  final bool busy;
  final VoidCallback onResetDevice;

  const _StudentDeviceCard({
    required this.studentId,
    required this.boundDeviceId,
    required this.busy,
    required this.onResetDevice,
  });

  @override
  Widget build(BuildContext context) {
    if (boundDeviceId.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: Text('لا يوجد جهاز مرتبط بهذا الحساب حالياً.', style: TextStyle(color: AppColors.muted)),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('devices').doc(boundDeviceId).snapshots(),
      builder: (context, snapshot) {
        final device = snapshot.data?.data() ?? {};
        final model = (device['device_model'] as String?) ?? (device['model'] as String?) ?? boundDeviceId;
        final os = (device['os_version'] as String?) ?? (device['platform'] as String?) ?? 'غير معروف';

        return Card(
          child: ListTile(
            leading: const Icon(Icons.devices_outlined, color: AppColors.primary),
            title: Text('الجهاز: $model'),
            subtitle: Text('نظام التشغيل: $os\nالمعرف: $boundDeviceId'),
            isThreeLine: true,
            trailing: busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : OutlinedButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('تأكيد إعادة تعيين الجهاز'),
                          content: const Text(
                            'هل أنت متأكد من فك ارتباط الجهاز الحالي؟ سيتيح هذا للطالب تسجيل الدخول من جهاز جديد وفق الصلاحيات المخولة لك.',
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('إلغاء')),
                            FilledButton(
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                onResetDevice();
                              },
                              child: const Text('تأكيد الفك'),
                            ),
                          ],
                        ),
                      );
                    },
                    child: const Text('إعادة تعيين'),
                  ),
          ),
        );
      },
    );
  }
}

class _StudentSubjectsCard extends StatelessWidget {
  final String studentId;
  final Set<String> busy;
  final Future<void> Function(
    String key,
    String functionName,
    Map<String, dynamic> payload,
    String successMessage,
  ) onCall;

  const _StudentSubjectsCard({
    required this.studentId,
    required this.busy,
    required this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    final assignments = FirebaseFirestore.instance
        .collection('subject_access_assignments')
        .where('student_id', isEqualTo: studentId)
        .where('is_deleted', isEqualTo: false)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: assignments,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Text('تعذر تحميل مواد الطالب.'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Text('لا توجد صلاحيات مواد مسجلة لهذا الطالب بعد.'),
            ),
          );
        }
        return Column(
          children: [
            for (final doc in docs)
              _StudentSubjectTile(
                studentId: studentId,
                assignment: doc.data(),
                busy: busy,
                onCall: onCall,
              ),
          ],
        );
      },
    );
  }
}

/// FINAL_DECISIONS §13 entry point (b): grant/revoke prior-grade subject
/// access from the student's profile at ANY time. Every mutation goes
/// through the existing audited `setSubjectAccess` callable — no new write
/// path, no Rules bypass (requireStudentAccessManager +
/// assertAdminGradeAccessForStudent still apply server-side).
class _PriorGradeSubjectsCard extends StatelessWidget {
  final String studentId;

  /// Canonical student grade; only grades with priors reach this widget.
  final String studentGrade;
  final List<String> priorGrades;
  final Set<String> busy;
  final Future<void> Function(
    String key,
    String functionName,
    Map<String, dynamic> payload,
    String successMessage,
  ) onCall;

  const _PriorGradeSubjectsCard({
    required this.studentId,
    required this.studentGrade,
    required this.priorGrades,
    required this.busy,
    required this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    final subjectsStream = FirebaseFirestore.instance
        .collection('subjects')
        .where('is_deleted', isEqualTo: false)
        .snapshots();
    final assignmentsStream = FirebaseFirestore.instance
        .collection('subject_access_assignments')
        .where('student_id', isEqualTo: studentId)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: subjectsStream,
      builder: (context, subjectsSnap) {
        if (!subjectsSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final priorSubjects = subjectsSnap.data!.docs
            .where((s) =>
                priorGrades.contains(normalizeAdminGradeKey(s.data()['grade'])))
            .toList()
          ..sort((a, b) {
            final rankA =
                adminGradeRank(a.data()['grade'] as String?) ?? 0;
            final rankB =
                adminGradeRank(b.data()['grade'] as String?) ?? 0;
            final byRank = rankA.compareTo(rankB);
            if (byRank != 0) return byRank;
            return a.id.compareTo(b.id);
          });
        if (priorSubjects.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(
                'لا توجد مواد معلَّمة بفرق سابقة (فرقة ${priorGrades.map(gradeLabel).join('، ')}) بعد. علِّم الفرقة من شاشة إدارة المواد أولاً.',
                style: const TextStyle(color: AppColors.muted),
              ),
            ),
          );
        }
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: assignmentsStream,
          builder: (context, assignmentsSnap) {
            // Current assignment state per prior-grade subject: enabled
            // when an assignment exists AND is enabled AND not deleted.
            final enabledBySubject = <String, bool>{};
            for (final doc in assignmentsSnap.data?.docs ?? const []) {
              final data = doc.data();
              final subjectId = data['subject_id'] as String?;
              if (subjectId == null) continue;
              enabledBySubject[subjectId] =
                  data['is_deleted'] != true && data['enabled'] == true;
            }
            return Column(
              children: [
                for (final subject in priorSubjects)
                  _PriorGradeSubjectTile(
                    studentId: studentId,
                    subjectId: subject.id,
                    subjectName: (subject.data()['title'] ??
                            subject.data()['name'] ??
                            subject.id)
                        .toString(),
                    subjectGrade:
                        normalizeAdminGradeKey(subject.data()['grade'])!,
                    enabled: enabledBySubject[subject.id] ?? false,
                    busy: busy,
                    onCall: onCall,
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _PriorGradeSubjectTile extends StatelessWidget {
  final String studentId;
  final String subjectId;
  final String subjectName;
  final String subjectGrade;
  final bool enabled;
  final Set<String> busy;
  final Future<void> Function(
    String key,
    String functionName,
    Map<String, dynamic> payload,
    String successMessage,
  ) onCall;

  const _PriorGradeSubjectTile({
    required this.studentId,
    required this.subjectId,
    required this.subjectName,
    required this.subjectGrade,
    required this.enabled,
    required this.busy,
    required this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        dense: true,
        title: Text(
          '$subjectName (${gradeLabel(subjectGrade)})',
          style: const TextStyle(fontSize: 14),
        ),
        subtitle: Text(
          enabled ? 'الوصول مُفعّل' : 'غير مُفعّل',
          style: TextStyle(
            fontSize: 12,
            color: enabled ? AppColors.success : AppColors.muted,
          ),
        ),
        trailing: busy.contains('prior_access_$subjectId')
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : CupertinoSwitch(
                value: enabled,
                activeTrackColor: AppColors.success,
                onChanged: (value) => onCall(
                  'prior_access_$subjectId',
                  'setSubjectAccess',
                  {
                    'studentId': studentId,
                    'subjectId': subjectId,
                    'enabled': value,
                  },
                  value
                      ? 'تم منح وصول المادة (فرقة سابقة).'
                      : 'تم سحب وصول المادة (فرقة سابقة).',
                ),
              ),
      ),
    );
  }
}

class _StudentSubjectTile extends StatelessWidget {
  final String studentId;
  final Map<String, dynamic> assignment;
  final Set<String> busy;
  final Future<void> Function(
    String key,
    String functionName,
    Map<String, dynamic> payload,
    String successMessage,
  ) onCall;

  const _StudentSubjectTile({
    required this.studentId,
    required this.assignment,
    required this.busy,
    required this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    final subjectId = (assignment['subject_id'] as String?) ?? '';
    final enabled = assignment['enabled'] == true;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: _SubjectName(subjectId: subjectId),
                ),
                const Text('وصول المادة'),
                const SizedBox(width: AppSpacing.sm),
                busy.contains('access_$subjectId')
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : CupertinoSwitch(
                        value: enabled,
                        activeTrackColor: AppColors.success,
                        onChanged: (value) => onCall(
                          'access_$subjectId',
                          'setSubjectAccess',
                          {
                            'studentId': studentId,
                            'subjectId': subjectId,
                            'enabled': value,
                          },
                          value ? 'تم تفعيل وصول المادة.' : 'تم تعطيل وصول المادة.',
                        ),
                      ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _SubscriptionDisciplinaryRow(
              studentId: studentId,
              subjectId: subjectId,
              busy: busy,
              onCall: onCall,
            ),
          ],
        ),
      ),
    );
  }
}

class _SubjectName extends StatelessWidget {
  final String subjectId;

  const _SubjectName({required this.subjectId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('subjects').doc(subjectId).get(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final name = (data?['title'] ?? data?['name'] ?? subjectId).toString();
        final grade = (data?['grade'] as String?) ?? '';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            if (grade.isNotEmpty)
              Text(
                'الفرقة الأصلية للمادة: ${StudentsManagementScreen._gradeLabel(grade)}',
                style: const TextStyle(color: AppColors.muted, fontSize: 11),
              ),
          ],
        );
      },
    );
  }
}

class _SubscriptionDisciplinaryRow extends StatelessWidget {
  final String studentId;
  final String subjectId;
  final Set<String> busy;
  final Future<void> Function(
    String key,
    String functionName,
    Map<String, dynamic> payload,
    String successMessage,
  ) onCall;

  const _SubscriptionDisciplinaryRow({
    required this.studentId,
    required this.subjectId,
    required this.busy,
    required this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    final subscriptions = FirebaseFirestore.instance
        .collection('subscriptions')
        .where('student_id', isEqualTo: studentId)
        .where('subject_id', isEqualTo: subjectId)
        .limit(3)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: subscriptions,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Text(
            'لا يوجد اشتراك مسجل لهذه المادة.',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          );
        }
        final doc = snapshot.data!.docs.firstWhere(
          (item) => item.data()['is_deleted'] != true,
          orElse: () => snapshot.data!.docs.first,
        );
        final data = doc.data();
        final disabled = data['manually_disabled'] == true;
        final status = (data['status'] as String?) ?? '';
        final planId = (data['plan_id'] as String?) ?? '';

        return Row(
          children: [
            Expanded(
              child: Text(
                'الاشتراك: $status (${_planLabel(planId)})${disabled ? ' • موقوف تأديبياً' : ''}',
                style: TextStyle(
                  fontSize: 12,
                  color: disabled ? AppColors.error : AppColors.muted,
                ),
              ),
            ),
            const Text('إيقاف تأديبي', style: TextStyle(fontSize: 12)),
            const SizedBox(width: AppSpacing.sm),
            busy.contains('discipline_${doc.id}')
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : CupertinoSwitch(
                    value: disabled,
                    activeTrackColor: AppColors.error,
                    onChanged: (value) => onCall(
                      'discipline_${doc.id}',
                      'setSubscriptionDisciplinaryStatus',
                      {
                        'subscriptionId': doc.id,
                        'disabled': value,
                        if (value) 'reason': 'إيقاف تأديبي من الداشبورد',
                      },
                      value
                          ? 'تم الإيقاف التأديبي للاشتراك.'
                          : 'تم رفع الإيقاف التأديبي.',
                    ),
                  ),
          ],
        );
      },
    );
  }

  static String _planLabel(String planId) {
    return switch (planId) {
      'center_max' => 'Max',
      'center_pro' => 'Pro',
      'center_free' || 'public_free' => 'Free',
      _ => planId,
    };
  }
}

class _StudentPaymentHistoryCard extends StatelessWidget {
  final String studentId;
  final String studentName;
  final String studentPhone;

  const _StudentPaymentHistoryCard({
    required this.studentId,
    required this.studentName,
    required this.studentPhone,
  });

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('payment_logs')
        .where('student_id', isEqualTo: studentId)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Text('لا توجد مدفوعات مسجلة لهذا الطالب بعد.', style: TextStyle(color: AppColors.muted)),
            ),
          );
        }
        final docs = snapshot.data!.docs;
        return Column(
          children: [
            for (final doc in docs) ...[
              Builder(builder: (ctx) {
                final p = doc.data();
                // onPaymentLogged persists the amount under `amount`.
                final amount = (p['amount'] as num?) ?? (p['amount_paid'] as num?) ?? 0;
                final subjectId = (p['subject_id'] as String?) ?? '';
                final timestamp = (p['created_at'] as Timestamp?)?.toDate();
                final dateStr = timestamp != null
                    ? '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}'
                    : 'اليوم';

                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.receipt_outlined, color: AppColors.success),
                    title: Text('$amount ج.م - $subjectId'),
                    subtitle: Text('التاريخ: $dateStr'),
                    trailing: IconButton(
                      icon: const Icon(Icons.open_in_new_rounded),
                      tooltip: 'عرض الفاتورة / مشاركة',
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (_) => PaymentReceiptDialog(
                            receiptId: doc.id,
                            studentName: studentName,
                            studentPhone: studentPhone,
                            subjectTitle: subjectId,
                            amountPaid: amount,
                            paymentDate: dateStr,
                          ),
                        );
                      },
                    ),
                  ),
                );
              }),
            ],
          ],
        );
      },
    );
  }
}
