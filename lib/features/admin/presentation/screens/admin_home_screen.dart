import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/friendly_error_message.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../authentication/domain/entities/auth_user.dart';
import '../../../authentication/presentation/providers/auth_provider.dart';
import 'admin_notifications_composer_screen.dart';
import 'admins_management_screen.dart';
import 'custom_groups_screen.dart';
import '../../../content_authoring/presentation/screens/admin_subject_picker_screen.dart';
import 'plan_quality_matrix_screen.dart';
import 'platform_features_screen.dart';
import 'students_management_screen.dart';
import 'subjects_management_screen.dart';
import '../../../academic_periods/presentation/screens/academic_periods_screen.dart';

class AdminHomeScreen extends ConsumerWidget {
  final AuthUser user;

  const AdminHomeScreen({required this.user, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة الإدارة'),
        actions: [
          IconButton(
            tooltip: 'تسجيل الخروج',
            onPressed: () => ref.read(authProvider.notifier).logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'مرحباً ${user.fullName}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(
            user.role == 'teacher' ? 'المعلم المسؤول عن المنصة' : 'مدير المنصة',
          ),
          const SizedBox(height: 20),
          _AdminStatsGrid(),
          const SizedBox(height: 20),
          Text('إجراءات سريعة', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          AppButton(
            label: 'اعتماد الطلاب وتحديد المواد',
            icon: Icons.how_to_reg_outlined,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const _PendingStudentsScreen()),
            ),
          ),
          const SizedBox(height: 10),
          AppButton(
            label: 'إدارة الطلاب',
            icon: Icons.people_alt_outlined,
            variant: AppButtonVariant.outlined,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const StudentsManagementScreen()),
            ),
          ),
          const SizedBox(height: 10),
          AppButton(
            label: 'إدارة المواد',
            icon: Icons.menu_book_outlined,
            variant: AppButtonVariant.outlined,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SubjectsManagementScreen()),
            ),
          ),
          const SizedBox(height: 10),
          AppButton(
            label: 'إدارة الأقسام والمحاضرات',
            icon: Icons.collections_bookmark_outlined,
            variant: AppButtonVariant.outlined,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const AdminSubjectPickerScreen()),
            ),
          ),
          const SizedBox(height: 10),
          AppButton(
            label: 'المجموعات المخصصة',
            icon: Icons.groups_outlined,
            variant: AppButtonVariant.outlined,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CustomGroupsScreen()),
            ),
          ),
          const SizedBox(height: 10),
          AppButton(
            label: 'إدارة جودات الفيديو',
            icon: Icons.high_quality_outlined,
            variant: AppButtonVariant.outlined,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const PlanQualityMatrixScreen(),
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (user.role == 'teacher')
            AppButton(
              label: 'الفترات الدراسية',
              icon: Icons.calendar_month_outlined,
              variant: AppButtonVariant.outlined,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AcademicPeriodsScreen(user: user),
                ),
              ),
            ),
          if (user.role == 'teacher') const SizedBox(height: 10),
          if (user.role == 'teacher')
            AppButton(
              label: 'إدارة الأدمنز',
              icon: Icons.admin_panel_settings_outlined,
              variant: AppButtonVariant.outlined,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AdminsManagementScreen(user: user),
                ),
              ),
            ),
          if (user.role == 'teacher') const SizedBox(height: 10),
          if (user.role == 'teacher')
            AppButton(
              label: 'ميزات المنصة',
              icon: Icons.toggle_on_outlined,
              variant: AppButtonVariant.outlined,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PlatformFeaturesScreen(user: user),
                ),
              ),
            ),
          if (user.role == 'teacher') const SizedBox(height: 10),
          AppButton(
            label: 'إنشاء وإرسال إشعار جديد',
            icon: Icons.campaign_outlined,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const AdminNotificationsComposerScreen(),
              ),
            ),
          ),
          const SizedBox(height: 10),
          AppButton(
            label: 'الإشعارات المرسلة',
            icon: Icons.notifications_none_rounded,
            variant: AppButtonVariant.outlined,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _AdminCollectionScreen(
                  title: 'الإشعارات',
                  collection: 'notifications',
                  emptyMessage: 'لا توجد إشعارات حالياً.',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminStatsGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // `registration_requests` is NOT a real collection (05 Database has no
    // such schema; registration lives on users.approval_status == 'pending').
    // The pending tile therefore counts pending new_student users, which the
    // users rule permits staff to list.
    Query<Map<String, dynamic>> pendingRegistrationsQuery() =>
        FirebaseFirestore.instance
            .collection('users')
            .where('role', isEqualTo: 'new_student')
            .where('approval_status', isEqualTo: 'pending');

    final stats =
        <({String title, String collection, IconData icon, Query<Map<String, dynamic>> Function()? query})>[
      (title: 'الطلاب', collection: 'users', icon: Icons.people_outline, query: null),
      (title: 'المواد', collection: 'subjects', icon: Icons.menu_book_outlined, query: null),
      (
        title: 'طلبات التسجيل',
        collection: 'users',
        icon: Icons.pending_actions_outlined,
        query: pendingRegistrationsQuery,
      ),
      (title: 'الإشعارات', collection: 'notifications', icon: Icons.notifications_none_outlined, query: null),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: stats.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 112,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemBuilder: (_, index) {
        final stat = stats[index];
        return Card(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: (stat.query?.call() ??
                    FirebaseFirestore.instance.collection(stat.collection))
                .limit(100)
                .snapshots(),
            builder: (_, snapshot) => Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(stat.icon, color: AppColors.primary),
                  const Spacer(),
                  Text(
                    '${snapshot.data?.size ?? 0}',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(stat.title),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AdminCollectionScreen extends StatelessWidget {
  final String title;
  final String collection;
  final String emptyMessage;

  const _AdminCollectionScreen({
    required this.title,
    required this.collection,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection(collection)
            .limit(100)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('تعذر تحميل البيانات.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.docs.isEmpty) {
            return Center(child: Text(emptyMessage));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: snapshot.data!.docs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, index) {
              final data = snapshot.data!.docs[index].data();
              return Card(
                child: ListTile(
                  title: Text(
                    (data['full_name'] ??
                            data['title'] ??
                            data['question'] ??
                            'سجل')
                        as String,
                  ),
                  subtitle: Text(
                    (data['status'] ??
                            data['body'] ??
                            data['phone_number'] ??
                            '')
                        as String,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _PendingStudentsScreen extends StatelessWidget {
  const _PendingStudentsScreen();

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'new_student')
        .where('approval_status', isEqualTo: 'pending');
    return Scaffold(
      appBar: AppBar(title: const Text('طلبات اعتماد الطلاب')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('تعذر تحميل طلبات الاعتماد.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('لا توجد طلبات اعتماد حالياً.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.person_add_alt_1_outlined),
                  title: Text((data['full_name'] as String?) ?? 'طالب جديد'),
                  subtitle: Text(
                    '${(data['phone_number'] as String?) ?? ''}\n'
                    'الفرقة: ${(data['grade'] as String?) ?? 'غير محددة'}',
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openApproval(context, doc.id),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _openApproval(BuildContext context, String studentId) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (_) => _StudentApprovalDialog(studentId: studentId),
    );
    if (approved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم اعتماد الطالب وتسجيل صلاحيات المواد.'),
        ),
      );
    }
  }
}

class _StudentApprovalDialog extends StatefulWidget {
  final String studentId;

  const _StudentApprovalDialog({required this.studentId});

  @override
  State<_StudentApprovalDialog> createState() => _StudentApprovalDialogState();
}

class _StudentApprovalDialogState extends State<_StudentApprovalDialog> {
  String studentType = 'public_student';
  bool loadingSubjects = true;
  bool submitting = false;
  String? errorMessage;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> subjects = const [];
  final Map<String, bool> enabledBySubject = {};

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  Future<void> _loadSubjects() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('subjects')
          .where('is_deleted', isEqualTo: false)
          .orderBy('display_order')
          .get();
      if (!mounted) return;
      setState(() {
        subjects = snapshot.docs;
        for (final subject in subjects) {
          enabledBySubject[subject.id] = false;
        }
        loadingSubjects = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        errorMessage = 'تعذر تحميل المواد: $error';
        loadingSubjects = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('اعتماد الطالب'),
      content: SizedBox(
        width: 520,
        child: loadingSubjects
            ? const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator()),
              )
            : errorMessage != null
            ? Text(errorMessage!)
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: studentType,
                      decoration: const InputDecoration(
                        labelText: 'نوع الطالب',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'public_student',
                          child: Text('Public Student'),
                        ),
                        DropdownMenuItem(
                          value: 'center_student',
                          child: Text('Center Student'),
                        ),
                      ],
                      onChanged: submitting
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => studentType = value);
                              }
                            },
                    ),
                    const SizedBox(height: 16),
                    const Text('صلاحية الوصول لكل مادة'),
                    const SizedBox(height: 8),
                    if (subjects.isEmpty)
                      const Text('لا توجد مواد فعالة.')
                    else
                      ...subjects.map(
                        (subject) => ListTile(
                          dense: true,
                          title: Text(
                            (subject.data()['name'] as String?) ??
                                (subject.data()['title'] as String?) ??
                                subject.id,
                          ),
                          trailing: CupertinoSwitch(
                            value: enabledBySubject[subject.id] ?? false,
                            activeTrackColor: AppColors.success,
                            onChanged: submitting
                                ? null
                                : (value) => setState(
                                    () => enabledBySubject[subject.id] = value,
                                  ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: loadingSubjects || submitting || errorMessage != null
              ? null
              : _approve,
          child: submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('اعتماد'),
        ),
      ],
    );
  }

  Future<void> _approve() async {
    setState(() {
      submitting = true;
      errorMessage = null;
    });
    try {
      final subjectAccess = subjects
          .map(
            (subject) => {
              'subjectId': subject.id,
              'enabled': enabledBySubject[subject.id] ?? false,
            },
          )
          .toList(growable: false);
      await FirebaseFunctions.instance.httpsCallable('approveStudent').call({
        'studentId': widget.studentId,
        'studentType': studentType,
        'subjectAccess': subjectAccess,
      });
      if (mounted) Navigator.of(context).pop(true);
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(() {
        submitting = false;
        errorMessage = friendlyFunctionErrorMessage(error, 'تعذر اعتماد الطالب.');
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        submitting = false;
        errorMessage = 'تعذر اعتماد الطالب: $error';
      });
    }
  }
}

