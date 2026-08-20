import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../authentication/domain/entities/auth_user.dart';
import '../../../authentication/presentation/providers/auth_provider.dart';
import '../../../membership/presentation/providers/membership_providers.dart';

/// TODO: replace with Figma-precise geometry when 03_UI_UX.md is Approved for these screens.
class StudentFeatureHubScreen extends StatelessWidget {
  final AuthUser user;

  const StudentFeatureHubScreen({required this.user, super.key});

  @override
  Widget build(BuildContext context) {
    final features = <_FeatureItem>[
      _FeatureItem(
        'الاختبارات القصيرة',
        Icons.quiz_outlined,
        () => _open(context, QuizzesScreen(studentId: user.id)),
      ),
      _FeatureItem(
        'الامتحانات',
        Icons.assignment_outlined,
        () => _open(context, ExamsScreen(studentId: user.id)),
      ),
      _FeatureItem(
        'ملاحظاتي',
        Icons.note_alt_outlined,
        () => _open(context, NotesScreen(studentId: user.id)),
      ),
      _FeatureItem(
        'المحفوظات',
        Icons.bookmark_border_rounded,
        () => _open(context, BookmarksScreen(studentId: user.id)),
      ),
      _FeatureItem(
        'أسئلتي للإدارة',
        Icons.help_outline_rounded,
        () => _open(context, QuestionsScreen(studentId: user.id)),
      ),
      if (user.studentType == 'center_student')
        _FeatureItem(
          'المحادثة',
          Icons.chat_bubble_outline_rounded,
          () => _open(context, ChatScreen(studentId: user.id)),
        ),
      _FeatureItem(
        'الإشعارات',
        Icons.notifications_none_rounded,
        () => _open(context, NotificationsScreen(studentId: user.id)),
      ),
      _FeatureItem(
        'الخطط والاشتراكات',
        Icons.workspace_premium_outlined,
        () => _open(context, MembershipPlansScreen(user: user)),
      ),
      _FeatureItem(
        'ملفي الشخصي',
        Icons.person_outline_rounded,
        () => _open(context, StudentProfileScreen(user: user)),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('كل الميزات')),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisExtent: 132,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: features.length,
        itemBuilder: (_, index) => _FeatureCard(item: features[index]),
      ),
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }
}

class _FeatureItem {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  const _FeatureItem(this.title, this.icon, this.onTap);
}

class _FeatureCard extends StatelessWidget {
  final _FeatureItem item;

  const _FeatureCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: item.onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(item.icon, size: 34, color: AppColors.primary),
              const SizedBox(height: 10),
              Text(item.title, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

class LectureScreen extends StatefulWidget {
  final String lectureId;
  final String title;

  const LectureScreen({
    required this.lectureId,
    required this.title,
    super.key,
  });

  @override
  State<LectureScreen> createState() => _LectureScreenState();
}

class _LectureScreenState extends State<LectureScreen> {
  late Future<List<_LectureResource>> resourcesFuture;
  _LectureResource? selectedResource;
  double progress = 0;
  String? protectedUrl;
  bool loadingUrl = false;

  @override
  void initState() {
    super.initState();
    resourcesFuture = _loadResources();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: FutureBuilder<List<_LectureResource>>(
        future: resourcesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _CenterMessage(
              'تعذر تحميل موارد المحاضرة. تحقق من الاشتراك ثم حاول مرة أخرى.',
            );
          }
          final resources = snapshot.data ?? const <_LectureResource>[];
          final selected =
              selectedResource ?? (resources.isEmpty ? null : resources.first);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _ResourcePreview(
                resource: selected,
                url: protectedUrl,
                loading: loadingUrl,
              ),
              const SizedBox(height: 12),
              if (resources.isNotEmpty)
                SizedBox(
                  height: 86,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: resources.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, index) => ChoiceChip(
                      selected: selected?.id == resources[index].id,
                      label: Text(resources[index].title),
                      onSelected: (_) => _selectResource(resources[index]),
                    ),
                  ),
                ),
              if (selected != null) ...[
                const SizedBox(height: 12),
                AppButton(
                  label: selected.isVideo
                      ? 'تشغيل الفيديو المحمي'
                      : 'فتح ملف PDF المحمي',
                  icon: selected.isVideo
                      ? Icons.play_arrow_rounded
                      : Icons.picture_as_pdf_outlined,
                  onPressed: () => _openProtectedResource(selected),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                'تقدم المحاضرة',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Slider(
                value: progress,
                onChanged: (value) => setState(() => progress = value),
                onChangeEnd: (_) => _saveProgress(),
              ),
              Text('${(progress * 100).round()}% مكتمل'),
              const SizedBox(height: 20),
              AppButton(
                label: 'حفظ في المحفوظات',
                icon: Icons.bookmark_add_outlined,
                variant: AppButtonVariant.outlined,
                onPressed: _saveBookmark,
              ),
            ],
          );
        },
      ),
    );
  }

  Future<List<_LectureResource>> _loadResources() async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('getLectureResources')
        .call({'lectureId': widget.lectureId});
    final data = Map<String, dynamic>.from(result.data as Map);
    final raw = (data['resources'] as List<dynamic>? ?? const []);
    return raw
        .map(
          (item) =>
              _LectureResource.fromMap(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  void _selectResource(_LectureResource resource) {
    setState(() {
      selectedResource = resource;
      protectedUrl = null;
    });
  }

  Future<void> _openProtectedResource(_LectureResource resource) async {
    if (resource.isVideo && resource.bunnyVideoId == null) return;
    if (!resource.isVideo && resource.id.isEmpty) return;
    setState(() => loadingUrl = true);
    try {
      final functionName = resource.isVideo
          ? 'generateBunnySignedUrl'
          : 'generateProtectedPdfUrl';
      final payload = resource.isVideo
          ? {'videoId': resource.bunnyVideoId}
          : {'resourceId': resource.id};
      final result = await FirebaseFunctions.instance
          .httpsCallable(functionName)
          .call(payload);
      final data = Map<String, dynamic>.from(result.data as Map);
      if (!mounted) return;
      setState(() => protectedUrl = data['url'] as String?);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إنشاء رابط الوصول المحمي بنجاح.')),
      );
    } on FirebaseFunctionsException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message ?? 'لا تملك صلاحية الوصول.')),
        );
      }
    } finally {
      if (mounted) setState(() => loadingUrl = false);
    }
  }

  Future<void> _saveProgress() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('lecture_progress')
        .doc('${uid}_${widget.lectureId}')
        .set({
          'student_id': uid,
          'lecture_id': widget.lectureId,
          'progress_percent': progress * 100,
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Future<void> _saveBookmark() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('bookmarks')
        .doc('${uid}_${widget.lectureId}')
        .set({
          'student_id': uid,
          'lecture_id': widget.lectureId,
          'lecture_title': widget.title,
          'created_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ المحاضرة في المحفوظات.')),
      );
    }
  }
}

class _LectureResource {
  final String id;
  final String title;
  final String resourceType;
  final String? bunnyVideoId;

  const _LectureResource({
    required this.id,
    required this.title,
    required this.resourceType,
    this.bunnyVideoId,
  });

  bool get isVideo => resourceType == 'video';

  factory _LectureResource.fromMap(Map<String, dynamic> map) =>
      _LectureResource(
        id: map['id'] as String? ?? '',
        title: map['title'] as String? ?? 'مورد تعليمي',
        resourceType: map['resourceType'] as String? ?? 'attachment',
        bunnyVideoId: map['bunnyVideoId'] as String?,
      );
}

class _ResourcePreview extends StatelessWidget {
  final _LectureResource? resource;
  final String? url;
  final bool loading;

  const _ResourcePreview({
    required this.resource,
    required this.url,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Container(
        height: 220,
        color: Colors.black87,
        alignment: Alignment.center,
        child: loading
            ? const CircularProgressIndicator(color: Colors.white)
            : resource == null
            ? const Text(
                'لا توجد موارد منشورة',
                style: TextStyle(color: Colors.white),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    resource!.isVideo
                        ? Icons.play_circle_outline
                        : Icons.picture_as_pdf_outlined,
                    color: Colors.white,
                    size: 72,
                  ),
                  if (url != null)
                    const Text(
                      'الرابط المحمي جاهز للاستخدام',
                      style: TextStyle(color: Colors.white),
                    ),
                ],
              ),
      ),
    );
  }
}

class NotesScreen extends StatefulWidget {
  final String studentId;
  const NotesScreen({required this.studentId, super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final firestore = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ملاحظاتي')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addNote,
        icon: const Icon(Icons.add),
        label: const Text('ملاحظة جديدة'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: firestore
            .collection('notes')
            .where('student_id', isEqualTo: widget.studentId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const _CenterMessage('تعذر تحميل الملاحظات.');
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const _CenterMessage('لم تضف أي ملاحظات بعد.');
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (_, index) {
              final data = docs[index].data();
              return Card(
                child: ListTile(
                  title: Text((data['title'] as String?) ?? 'ملاحظة'),
                  subtitle: Text((data['content'] as String?) ?? ''),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => docs[index].reference.delete(),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _addNote() async {
    final title = TextEditingController();
    final content = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ملاحظة جديدة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: 'العنوان'),
            ),
            TextField(
              controller: content,
              decoration: const InputDecoration(labelText: 'المحتوى'),
              maxLines: 4,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (result == true && title.text.trim().isNotEmpty) {
      await firestore.collection('notes').add({
        'student_id': widget.studentId,
        'title': title.text.trim(),
        'content': content.text.trim(),
        'created_at': FieldValue.serverTimestamp(),
      });
    }
  }
}

class BookmarksScreen extends StatelessWidget {
  final String studentId;
  const BookmarksScreen({required this.studentId, super.key});

  @override
  Widget build(BuildContext context) {
    return _FirestoreListScreen(
      title: 'المحفوظات',
      emptyMessage: 'لا توجد محاضرات محفوظة بعد.',
      query: FirebaseFirestore.instance
          .collection('bookmarks')
          .where('student_id', isEqualTo: studentId),
      titleField: 'title',
      subtitleField: 'lecture_title',
    );
  }
}

class QuestionsScreen extends StatefulWidget {
  final String studentId;
  const QuestionsScreen({required this.studentId, super.key});

  @override
  State<QuestionsScreen> createState() => _QuestionsScreenState();
}

class _QuestionsScreenState extends State<QuestionsScreen> {
  final controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('أسئلتي للإدارة')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: controller,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'اكتب سؤالك هنا'),
            ),
            const SizedBox(height: 12),
            AppButton(
              label: 'إرسال السؤال',
              icon: Icons.send_outlined,
              onPressed: _send,
            ),
            const SizedBox(height: 24),
            Expanded(
              child: _FirestoreListScreen(
                title: 'الأسئلة السابقة',
                emptyMessage: 'لم ترسل أي أسئلة بعد.',
                query: FirebaseFirestore.instance
                    .collection('questions')
                    .where('student_id', isEqualTo: widget.studentId),
                titleField: 'question',
                subtitleField: 'status',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send() async {
    if (controller.text.trim().isEmpty) return;
    await FirebaseFirestore.instance.collection('questions').add({
      'student_id': widget.studentId,
      'question': controller.text.trim(),
      'status': 'open',
      'created_at': FieldValue.serverTimestamp(),
    });
    controller.clear();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم إرسال السؤال للإدارة.')));
    }
  }
}

class ChatScreen extends StatefulWidget {
  final String studentId;

  /// When true the chat renders without its own Scaffold/AppBar so it can be
  /// embedded inside the Student Home bottom navigation.
  final bool embedded;
  const ChatScreen({required this.studentId, this.embedded = false, super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('chat_threads')
        .where('student_id', isEqualTo: widget.studentId);
    final body = Column(
      children: [
        Expanded(
          child: _FirestoreListScreen(
            title: 'المحادثات',
            emptyMessage: 'ابدأ محادثة جديدة مع الإدارة.',
            query: query,
            titleField: 'subject',
            subtitleField: 'last_message',
            embedded: widget.embedded,
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    decoration: const InputDecoration(hintText: 'اكتب رسالة'),
                  ),
                ),
                IconButton(onPressed: _send, icon: const Icon(Icons.send)),
              ],
            ),
          ),
        ),
      ],
    );
    if (widget.embedded) {
      return ColoredBox(color: Colors.white, child: body);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('المحادثة مع الإدارة')),
      body: body,
    );
  }

  Future<void> _send() async {
    if (controller.text.trim().isEmpty) return;
    await FirebaseFirestore.instance.collection('chat_threads').add({
      'student_id': widget.studentId,
      'subject': 'محادثة جديدة',
      'last_message': controller.text.trim(),
      'created_at': FieldValue.serverTimestamp(),
    });
    controller.clear();
  }
}

class NotificationsScreen extends StatelessWidget {
  final String studentId;

  /// When true the list renders without its own Scaffold/AppBar so it can be
  /// embedded inside the Student Home bottom navigation.
  final bool embedded;
  const NotificationsScreen({
    required this.studentId,
    this.embedded = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final list = _FirestoreListScreen(
      title: 'الإشعارات',
      emptyMessage: 'لا توجد إشعارات جديدة.',
      query: FirebaseFirestore.instance
          .collection('notifications')
          .where('user_id', isEqualTo: studentId),
      titleField: 'title',
      subtitleField: 'body',
      embedded: embedded,
    );
    if (embedded) {
      return ColoredBox(color: Colors.white, child: list);
    }
    return list;
  }
}

class QuizzesScreen extends StatelessWidget {
  final String studentId;
  const QuizzesScreen({required this.studentId, super.key});

  @override
  Widget build(BuildContext context) {
    return _AssessmentsScreen(
      title: 'الاختبارات القصيرة',
      collection: 'timeline_quizzes',
      attemptCollection: 'quiz_attempts',
      studentId: studentId,
      icon: Icons.quiz_outlined,
    );
  }
}

class ExamsScreen extends StatelessWidget {
  final String studentId;
  const ExamsScreen({required this.studentId, super.key});

  @override
  Widget build(BuildContext context) {
    return _AssessmentsScreen(
      title: 'الامتحانات',
      collection: 'exams',
      attemptCollection: 'exam_attempts',
      studentId: studentId,
      icon: Icons.assignment_outlined,
    );
  }
}

class _AssessmentsScreen extends StatelessWidget {
  final String title;
  final String collection;
  final String attemptCollection;
  final String studentId;
  final IconData icon;

  const _AssessmentsScreen({
    required this.title,
    required this.collection,
    required this.attemptCollection,
    required this.studentId,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection(collection)
            .where('is_published', isEqualTo: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return _CenterMessage('لا توجد اختبارات متاحة حالياً.');
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (_, index) {
              final data = docs[index].data();
              return Card(
                child: ListTile(
                  leading: Icon(icon, color: AppColors.primary),
                  title: Text(
                    (data['title'] as String?) ??
                        (data['name'] as String?) ??
                        'اختبار',
                  ),
                  subtitle: Text(
                    (data['description'] as String?) ??
                        'اختبار متاح حسب اشتراكك',
                  ),
                  trailing: const Icon(Icons.play_arrow_rounded),
                  onTap: () async {
                    await FirebaseFirestore.instance
                        .collection(attemptCollection)
                        .add({
                          'student_id': studentId,
                          'assessment_id': docs[index].id,
                          'status': 'started',
                          'started_at': FieldValue.serverTimestamp(),
                        });
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم بدء الاختبار.')),
                      );
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class MembershipPlansScreen extends ConsumerWidget {
  final AuthUser user;
  const MembershipPlansScreen({required this.user, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentType = user.studentType;
    if (
      studentType == null ||
      (studentType != 'public_student' && studentType != 'center_student')
    ) {
      return Scaffold(
        appBar: AppBar(title: const Text('الخطط والاشتراكات')),
        body: const _CenterMessage('نوع الطالب غير مُعدّ بعد.'),
      );
    }

    final plans = ref.watch(availablePlansProvider(studentType));
    return Scaffold(
      appBar: AppBar(title: const Text('الخطط والاشتراكات')),
      body: plans.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => const _CenterMessage('تعذر تحميل الخطط حالياً.'),
        data: (items) => items.isEmpty
            ? const _CenterMessage('لا توجد خطط متاحة حالياً.')
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                itemBuilder: (_, index) => Card(
                  child: ListTile(
                    leading: const Icon(
                      Icons.workspace_premium_outlined,
                      color: AppColors.primary,
                    ),
                    title: Text(items[index].planName),
                    subtitle: Text(items[index].planKey),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ),
              ),
      ),
    );
  }
}

class StudentProfileScreen extends ConsumerStatefulWidget {
  final AuthUser user;
  const StudentProfileScreen({required this.user, super.key});

  @override
  ConsumerState<StudentProfileScreen> createState() =>
      _StudentProfileScreenState();
}

class _StudentProfileScreenState extends ConsumerState<StudentProfileScreen> {
  bool uploading = false;

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    return Scaffold(
      appBar: AppBar(title: const Text('ملفي الشخصي')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  radius: 48,
                  backgroundImage: user.profilePhoto == null
                      ? null
                      : NetworkImage(user.profilePhoto!),
                  child: user.profilePhoto == null
                      ? const Icon(Icons.person, size: 48)
                      : null,
                ),
                IconButton.filled(
                  tooltip: 'تغيير الصورة',
                  onPressed: uploading ? null : _pickAndUploadPhoto,
                  icon: uploading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.camera_alt_outlined),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _ProfileRow(label: 'الاسم', value: user.fullName),
          _ProfileRow(label: 'رقم الهاتف', value: user.phoneNumber),
          _ProfileRow(label: 'الفرقة', value: user.grade ?? 'غير محددة'),
          _ProfileRow(label: 'حالة الحساب', value: user.accountStatus),
          const SizedBox(height: 24),
          AppButton(
            label: 'تسجيل الخروج',
            icon: Icons.logout,
            variant: AppButtonVariant.outlined,
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndUploadPhoto() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 85,
    );
    if (image == null) return;
    setState(() => uploading = true);
    try {
      final bytes = await image.readAsBytes();
      final ref = FirebaseStorage.instance.ref(
        'profile_photos/$uid/${DateTime.now().millisecondsSinceEpoch}_avatar.jpg',
      );
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'profile_photo': url,
        'updated_at': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تحديث صورة الملف الشخصي.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر رفع الصورة، حاول مرة أخرى.')),
        );
      }
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }
}

class _ProfileRow extends StatelessWidget {
  final String label;
  final String value;
  const _ProfileRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return ListTile(title: Text(label), trailing: Text(value));
  }
}

class _FirestoreListScreen extends StatelessWidget {
  final String title;
  final String emptyMessage;
  final Query<Map<String, dynamic>> query;
  final String titleField;
  final String subtitleField;

  /// When true the list renders without its own Scaffold/AppBar so it can be
  /// embedded inside another screen (e.g. Student Home tabs).
  final bool embedded;
  const _FirestoreListScreen({
    required this.title,
    required this.emptyMessage,
    required this.query,
    required this.titleField,
    required this.subtitleField,
    this.embedded = false,
  });
  @override
  Widget build(BuildContext context) {
    final body = StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return _CenterMessage(emptyMessage);
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) return _CenterMessage(emptyMessage);
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (_, index) {
              final data = docs[index].data();
              return Card(
                child: ListTile(
                  title: Text((data[titleField] as String?) ?? title),
                  subtitle: Text((data[subtitleField] as String?) ?? ''),
                ),
              );
            },
          );
        },
      );
    if (embedded) return body;
    return Scaffold(appBar: AppBar(title: Text(title)), body: body);
  }
}

class _CenterMessage extends StatelessWidget {
  final String message;
  const _CenterMessage(this.message);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}
