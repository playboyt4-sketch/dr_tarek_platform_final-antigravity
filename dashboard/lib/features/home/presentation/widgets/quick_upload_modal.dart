import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../applications/domain/grade.dart';
import '../../../applications/presentation/providers/application_decision_provider.dart';
import '../providers/home_stats_provider.dart';

/// Quick-lecture section tabs: (display label, system section key).
const List<({String key, String label})> quickUploadTabs = <({String key, String label})>[
  (key: 'online', label: 'أونلاين'),
  (key: 'center', label: 'سنتر'),
  (key: 'revision', label: 'مراجعة'),
  (key: 'final', label: 'فاينل'),
];

/// Pure validation for the quick-upload form. Returns the first user-facing
/// error, or null when the draft is submittable.
String? validateQuickUpload({
  required String? subjectId,
  required String title,
  required String bunnyVideoId,
  required String pdfPath,
}) {
  if (subjectId == null || subjectId.isEmpty) {
    return 'Please select a subject.';
  }
  if (title.trim().isEmpty) {
    return 'Lecture title is required.';
  }
  if (bunnyVideoId.trim().isEmpty && pdfPath.trim().isEmpty) {
    return 'Add a Bunny Video ID or a PDF path.';
  }
  return null;
}

/// Opens the Quick Upload modal from the "Upload Lecture" card.
Future<bool?> showQuickUploadModal(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) => Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(28)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: QuickUploadForm(),
        ),
      ),
    ),
  );
}

/// Three-step quick lecture form:
/// 1. grade → 2. subject (live per grade) → 3. lecture fields + publish.
class QuickUploadForm extends ConsumerStatefulWidget {
  const QuickUploadForm({super.key});

  @override
  ConsumerState<QuickUploadForm> createState() => _QuickUploadFormState();
}

class _QuickUploadFormState extends ConsumerState<QuickUploadForm> {
  String _gradeKey = 'grade_one';
  String? _subjectId;
  String _tabKey = 'online';
  bool _publishNow = true;
  bool _saving = false;
  String? _error;

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _bunnyController = TextEditingController();
  final TextEditingController _pdfController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _bunnyController.dispose();
    _pdfController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String? validationError = validateQuickUpload(
      subjectId: _subjectId,
      title: _titleController.text,
      bunnyVideoId: _bunnyController.text,
      pdfPath: _pdfController.text,
    );
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final FirebaseFirestore db = FirebaseFirestore.instance;
      String actorId = 'dashboard';
      try {
        actorId = FirebaseAuth.instance.currentUser?.uid ?? 'dashboard';
      } catch (_) {
        actorId = 'dashboard';
      }
      await publishQuickLecture(
        db: db,
        actorId: actorId,
        subjectId: _subjectId!,
        tabKey: _tabKey,
        title: _titleController.text.trim(),
        bunnyVideoId: _bunnyController.text.trim().isEmpty
            ? null
            : _bunnyController.text.trim(),
        pdfPath: _pdfController.text.trim().isEmpty
            ? null
            : _pdfController.text.trim(),
        publishNow: _publishNow,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lecture uploaded successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save the lecture. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<SubjectOption>> subjectsAsync =
        ref.watch(gradeSubjectsProvider(_gradeKey));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Quick Upload', style: AppTypography.gradeTitle(fontSize: 22)),
        const SizedBox(height: 4),
        Text(
          'Pick a grade and subject, then publish the lecture.',
          style: AppTypography.actionDesc(),
        ),
        const SizedBox(height: 16),
        // Step 1 — grade.
        DropdownButtonFormField<String>(
          initialValue: _gradeKey,
          decoration: const InputDecoration(labelText: 'Grade'),
          items: <DropdownMenuItem<String>>[
            for (final key in canonicalGradeKeys)
              DropdownMenuItem<String>(
                value: key,
                child: Text(gradeAnalyticsTitle(key)),
              ),
          ],
          onChanged: _saving
              ? null
              : (String? value) {
                  if (value == null) return;
                  setState(() {
                    _gradeKey = value;
                    _subjectId = null;
                  });
                },
        ),
        const SizedBox(height: 12),
        // Step 2 — subject (live per grade).
        subjectsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (Object error, StackTrace stackTrace) => Text(
            'Could not load subjects.',
            style: AppTypography.actionDesc(),
          ),
          data: (List<SubjectOption> subjects) {
            if (subjects.isEmpty) {
              return Text(
                'No subjects in this grade yet.',
                style: AppTypography.actionDesc(),
              );
            }
            return DropdownButtonFormField<String>(
              initialValue: _subjectId,
              decoration: const InputDecoration(labelText: 'Select subject'),
              items: <DropdownMenuItem<String>>[
                for (final subject in subjects)
                  DropdownMenuItem<String>(
                    value: subject.id,
                    child: Text(subject.title),
                  ),
              ],
              onChanged: _saving
                  ? null
                  : (String? value) =>
                      setState(() => _subjectId = value),
            );
          },
        ),
        const SizedBox(height: 12),
        // Step 3 — lecture fields.
        TextField(
          controller: _titleController,
          enabled: !_saving,
          decoration: const InputDecoration(labelText: 'Lecture Title'),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _tabKey,
          decoration: const InputDecoration(labelText: 'Section'),
          items: <DropdownMenuItem<String>>[
            for (final tab in quickUploadTabs)
              DropdownMenuItem<String>(
                value: tab.key,
                child: Text(tab.label),
              ),
          ],
          onChanged: _saving
              ? null
              : (String? value) {
                  if (value == null) return;
                  setState(() => _tabKey = value);
                },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _bunnyController,
          enabled: !_saving,
          decoration: const InputDecoration(labelText: 'Bunny Video ID'),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pdfController,
          enabled: !_saving,
          decoration:
              const InputDecoration(labelText: 'PDF path or link (optional)'),
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Publish immediately',
                style: AppTypography.gradeValue(fontSize: 14),
              ),
            ),
            CupertinoSwitch(
              value: _publishNow,
              onChanged: _saving
                  ? null
                  : (bool value) => setState(() => _publishNow = value),
            ),
          ],
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: const TextStyle(color: Color(0xFFB3261E), fontSize: 14),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            TextButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 160,
              height: 44,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.pillFill,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9999),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save Lecture'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Persists a quick lecture with its resources.
///
/// Reuses the mobile content-authoring wire conventions: lectures live in
/// `lectures` (draft unless [publishNow]), video stays implicitly Bunny
/// (`bunny_video_id`, no provider field), PDFs carry `storage_path` +
/// `storage_provider`. The section is resolved by ([subjectId], [tabKey]);
/// a visible custom section is created when none exists yet. Returns the
/// new lecture id.
Future<String> publishQuickLecture({
  required FirebaseFirestore db,
  required String actorId,
  required String subjectId,
  required String tabKey,
  required String title,
  String description = '',
  String? bunnyVideoId,
  String? pdfPath,
  required bool publishNow,
}) async {
  final String tabLabel = quickUploadTabs
      .firstWhere(
        (tab) => tab.key == tabKey,
        orElse: () => quickUploadTabs.first,
      )
      .label;

  // Resolve (or create) the destination section.
  final QuerySnapshot<Map<String, dynamic>> sectionsSnap = await db
      .collection('subject_sections')
      .where('subject_id', isEqualTo: subjectId)
      .where('is_deleted', isEqualTo: false)
      .get();
  String? sectionId;
  int maxSectionOrder = 0;
  for (final doc in sectionsSnap.docs) {
    final Map<String, dynamic> data = doc.data();
    final int order = (data['display_order'] as num?)?.toInt() ?? 0;
    if (order > maxSectionOrder) maxSectionOrder = order;
    if (sectionId == null && data['section_key'] == tabKey) {
      sectionId = doc.id;
    }
  }
  if (sectionId == null) {
    final DocumentReference<Map<String, dynamic>> ref =
        db.collection('subject_sections').doc();
    await ref.set(<String, dynamic>{
      'subject_id': subjectId,
      'section_key': tabKey,
      'is_system_section': false,
      'title': tabLabel,
      'display_order': maxSectionOrder + 1,
      'is_visible': true,
      'is_deleted': false,
      'created_at': FieldValue.serverTimestamp(),
      'created_by': actorId,
      'updated_at': FieldValue.serverTimestamp(),
      'updated_by': actorId,
    });
    sectionId = ref.id;
  }

  // Next lecture order inside the section.
  final QuerySnapshot<Map<String, dynamic>> lecturesSnap = await db
      .collection('lectures')
      .where('section_id', isEqualTo: sectionId)
      .where('is_deleted', isEqualTo: false)
      .get();
  int maxLectureOrder = 0;
  for (final doc in lecturesSnap.docs) {
    final int order =
        (doc.data()['display_order'] as num?)?.toInt() ?? 0;
    if (order > maxLectureOrder) maxLectureOrder = order;
  }

  final DocumentReference<Map<String, dynamic>> lectureRef =
      db.collection('lectures').doc();
  await lectureRef.set(<String, dynamic>{
    'subject_id': subjectId,
    'section_id': sectionId,
    'title': title,
    'description': description,
    'display_order': maxLectureOrder + 1,
    'publish_date': publishNow ? FieldValue.serverTimestamp() : null,
    'status': publishNow ? 'published' : 'draft',
    'is_deleted': false,
    'guest_enabled': false,
    'created_at': FieldValue.serverTimestamp(),
    'created_by': actorId,
    'updated_at': FieldValue.serverTimestamp(),
    'updated_by': actorId,
  });

  int resourceOrder = 0;
  if (bunnyVideoId != null && bunnyVideoId.isNotEmpty) {
    resourceOrder++;
    await db.collection('lecture_resources').doc().set(<String, dynamic>{
      'lecture_id': lectureRef.id,
      'resource_type': 'video',
      'title': title,
      'display_order': resourceOrder,
      'bunny_video_id': bunnyVideoId,
      'storage_path': null,
      'thumbnail': null,
      'duration': null,
      'is_visible': publishNow,
      'visibility': publishNow,
      'is_deleted': false,
      'created_at': FieldValue.serverTimestamp(),
      'created_by': actorId,
      'updated_at': FieldValue.serverTimestamp(),
      'updated_by': actorId,
    });
  }
  if (pdfPath != null && pdfPath.isNotEmpty) {
    resourceOrder++;
    await db.collection('lecture_resources').doc().set(<String, dynamic>{
      'lecture_id': lectureRef.id,
      'resource_type': 'pdf',
      'title': '$title (PDF)',
      'display_order': resourceOrder,
      'bunny_video_id': null,
      'storage_path': pdfPath,
      'storage_provider': 'firebase',
      'thumbnail': null,
      'duration': null,
      'is_visible': publishNow,
      'visibility': publishNow,
      'is_deleted': false,
      'created_at': FieldValue.serverTimestamp(),
      'created_by': actorId,
      'updated_at': FieldValue.serverTimestamp(),
      'updated_by': actorId,
    });
  }

  return lectureRef.id;
}
