import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Admin notifications composer screen.
/// Supports 3-tier targeting:
/// 1. All students
/// 2. Specific grade or custom group
/// 3. Specific student
///
/// Supports Text, Image+Text, and Short Video+Text notifications.
class AdminNotificationsComposerScreen extends StatefulWidget {
  const AdminNotificationsComposerScreen({super.key});

  @override
  State<AdminNotificationsComposerScreen> createState() =>
      _AdminNotificationsComposerScreenState();
}

class _AdminNotificationsComposerScreenState
    extends State<AdminNotificationsComposerScreen> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _mediaUrlController = TextEditingController();
  final _studentPhoneController = TextEditingController();

  String _notificationType = 'Announcements'; // Announcements, Lecture, System
  String _mediaType = 'none'; // none, image, video
  String _targetScope = 'all'; // all, group, student
  String? _selectedGrade;
  String? _selectedGroupId;
  bool _isCritical = false;
  bool _submitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _mediaUrlController.dispose();
    _studentPhoneController.dispose();
    super.dispose();
  }

  void _applyScheduledLectureTemplate() {
    setState(() {
      _notificationType = 'Lecture';
      _titleController.text = 'تنبيه: محاضرة جديدة مجدولة';
      _bodyController.text = 'غداً في تمام الساعة 5:00 مساءً تبدأ محاضرة المراجعة والتحليل. يرجى التواجد.';
    });
  }

  Future<void> _sendNotification() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();

    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى كتابة عنوان ونص الإشعار.')),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? 'staff';
      final firestore = FirebaseFirestore.instance;

      List<String> targetUserIds = [];

      if (_targetScope == 'all') {
        final query = await firestore
            .collection('users')
            .where('role', isEqualTo: 'student')
            .where('approval_status', isEqualTo: 'approved')
            .get();
        targetUserIds = query.docs.map((doc) => doc.id).toList();
      } else if (_targetScope == 'group') {
        Query<Map<String, dynamic>> query = firestore
            .collection('users')
            .where('role', isEqualTo: 'student')
            .where('approval_status', isEqualTo: 'approved');

        if (_selectedGrade != null) {
          query = query.where('grade', isEqualTo: _selectedGrade);
        }
        if (_selectedGroupId != null) {
          query = query.where('group_id', isEqualTo: _selectedGroupId);
        }
        final snap = await query.get();
        targetUserIds = snap.docs.map((doc) => doc.id).toList();
      } else if (_targetScope == 'student') {
        final phone = _studentPhoneController.text.trim();
        if (phone.isEmpty) {
          throw Exception('يرجى إدخال رقم هاتف الطالب المستهدف.');
        }
        final snap = await firestore
            .collection('users')
            .where('phone_number', isEqualTo: phone)
            .limit(1)
            .get();
        if (snap.docs.isEmpty) {
          throw Exception('لم يتم العثور على طالب بهذا الرقم.');
        }
        targetUserIds = [snap.docs.first.id];
      }

      if (targetUserIds.isEmpty) {
        throw Exception('لم يتم العثور على أي طالب يطابق معايير الاستهداف.');
      }

      final batch = firestore.batch();
      for (final uid in targetUserIds) {
        final notifRef = firestore.collection('notifications').doc();
        batch.set(notifRef, {
          'user_id': uid,
          'title': title,
          'body': body,
          'type': _notificationType,
          'notification_type': _notificationType,
          'status': 'queued',
          'priority': _isCritical ? 'critical' : 'normal',
          'media_type': _mediaType,
          if (_mediaType != 'none' && _mediaUrlController.text.isNotEmpty)
            'media_url': _mediaUrlController.text.trim(),
          'created_at': FieldValue.serverTimestamp(),
          'created_by': currentUserId,
        });
      }

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم إرسال الإشعار بنجاح إلى ${targetUserIds.length} طالب.')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل إرسال الإشعار: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('محرر الإشعارات'),
        actions: [
          TextButton.icon(
            onPressed: _applyScheduledLectureTemplate,
            icon: const Icon(Icons.schedule_rounded),
            label: const Text('قالب محاضرة'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('1. نطاق الاستهداف', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'all', label: Text('الكل')),
                      ButtonSegment(value: 'group', label: Text('فرقة / مجموعة')),
                      ButtonSegment(value: 'student', label: Text('طالب محدد')),
                    ],
                    selected: {_targetScope},
                    onSelectionChanged: (set) => setState(() => _targetScope = set.first),
                  ),
                  if (_targetScope == 'group') ...[
                    const SizedBox(height: AppSpacing.md),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedGrade,
                      decoration: const InputDecoration(
                        labelText: 'الفرقة الدراسية',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'grade_1', child: Text('الفرقة الأولى')),
                        DropdownMenuItem(value: 'grade_2', child: Text('الفرقة الثانية')),
                        DropdownMenuItem(value: 'grade_3', child: Text('الفرقة الثالثة')),
                        DropdownMenuItem(value: 'grade_4', child: Text('الفرقة الرابعة')),
                      ],
                      onChanged: (val) => setState(() => _selectedGrade = val),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance.collection('custom_groups').snapshots(),
                      builder: (context, snapshot) {
                        final groups = snapshot.data?.docs ?? [];
                        return DropdownButtonFormField<String>(
                          initialValue: _selectedGroupId,
                          decoration: const InputDecoration(
                            labelText: 'المجموعة المخصصة (اختياري)',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem(value: null, child: Text('كل المجموعات')),
                            for (final g in groups)
                              DropdownMenuItem(
                                value: g.id,
                                child: Text((g.data()['name'] as String?) ?? g.id),
                              ),
                          ],
                          onChanged: (val) => setState(() => _selectedGroupId = val),
                        );
                      },
                    ),
                  ],
                  if (_targetScope == 'student') ...[
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: _studentPhoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'رقم هاتف الطالب المستهدف',
                        hintText: '01xxxxxxxxx',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('2. محتوى الإشعار', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'عنوان الإشعار',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _bodyController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'نص الإشعار',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<String>(
                    initialValue: _mediaType,
                    decoration: const InputDecoration(
                      labelText: 'نوع الوسائط المرفقة',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'none', child: Text('نص فقط')),
                      DropdownMenuItem(value: 'image', child: Text('صورة + نص')),
                      DropdownMenuItem(value: 'video', child: Text('فيديو قصير + نص')),
                    ],
                    onChanged: (val) => setState(() => _mediaType = val ?? 'none'),
                  ),
                  if (_mediaType != 'none') ...[
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: _mediaUrlController,
                      decoration: InputDecoration(
                        labelText: _mediaType == 'image' ? 'رابط الصورة' : 'رابط الفيديو',
                        hintText: 'https://...',
                        border: const OutlineInputBorder(),
                        prefixIcon: Icon(_mediaType == 'image' ? Icons.image_outlined : Icons.videocam_outlined),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'إشعار ذو أولوية قصوى (تنبيه فوري)',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      CupertinoSwitch(
                        value: _isCritical,
                        activeTrackColor: AppColors.primary,
                        onChanged: (val) => setState(() => _isCritical = val),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _submitting
              ? const Center(child: CircularProgressIndicator())
              : FilledButton.icon(
                  onPressed: _sendNotification,
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('إرسال الإشعار الآن'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
        ],
      ),
    );
  }
}
