import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../applications/domain/grade.dart';
import '../../../applications/presentation/providers/application_decision_provider.dart';
import '../../../students/data/bunny_association_gateway.dart';
import '../../../students/domain/bunny_library_association.dart';
import '../../../students/domain/bunny_library_catalog.dart';
import '../../../students/domain/repositories/bunny_library_catalog_repository.dart';
import '../../../students/presentation/providers/bunny_library_catalog_provider.dart';
import '../../../students/presentation/providers/subject_details_provider.dart';
import '../providers/home_stats_provider.dart';

/// Quick-lecture section tabs: (display label, system section key).
const List<({String key, String label})> quickUploadTabs = <({String key, String label})>[
  (key: 'online', label: 'أونلاين'),
  (key: 'center', label: 'سنتر'),
  (key: 'revision', label: 'مراجعة'),
  (key: 'final', label: 'فاينل'),
];

/// VIDEO-ID-ONLY: bare Bunny GUID only — URLs are rejected.
bool isValidBunnyVideoId(String raw) {
  return RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(raw.trim());
}

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
  if (bunnyVideoId.trim().isNotEmpty &&
      !isValidBunnyVideoId(bunnyVideoId)) {
    return 'الصق الـ Video ID فقط (GUID) — الروابط غير مقبولة.';
  }
  return null;
}

/// Opens the Quick Upload modal from the "Quick Upload" card.
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
  String? _selectedLibraryId;
  bool _isDiscovering = false;
  BunnyDiscoveryResult? _discoveryResult;
  String _lastDiscoveredVideoId = '';

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

  Future<void> _onVideoIdChanged(String raw) async {
    final String vid = raw.trim();
    if (!isValidBunnyVideoId(vid)) {
      if (_discoveryResult != null || _selectedLibraryId != null) {
        setState(() {
          _discoveryResult = null;
          _selectedLibraryId = null;
          _lastDiscoveredVideoId = '';
        });
      }
      return;
    }
    if (vid == _lastDiscoveredVideoId) return;
    _lastDiscoveredVideoId = vid;
    setState(() {
      _isDiscovering = true;
      _discoveryResult = null;
      _selectedLibraryId = null;
    });
    try {
      final repo = ref.read(bunnyLibraryCatalogRepositoryProvider);
      final result = await repo.discoverVideoLibrary(vid);
      if (!mounted) return;
      setState(() {
        _isDiscovering = false;
        _discoveryResult = result;
        if (result.isFound) {
          _selectedLibraryId = result.libraryId;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDiscovering = false;
        _discoveryResult = BunnyDiscoveryResult(
          status: BunnyDiscoveryStatus.error,
          errorMessage: e.toString(),
        );
      });
    }
  }

  bool _uploadingPdf = false;

  Future<void> _uploadPdfFile() async {
    if (_uploadingPdf || _saving) return;
    try {
      final PlatformFile? file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      if (file == null) return;
      setState(() => _uploadingPdf = true);

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تعذر قراءة ملف الـ PDF المختار.')),
          );
        }
        return;
      }

      final safeName = file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final storagePath = 'lectures/pdfs/${DateTime.now().millisecondsSinceEpoch}_$safeName';
      final storageRef = FirebaseStorage.instance.ref().child(storagePath);

      await storageRef.putData(
        bytes,
        SettableMetadata(contentType: 'application/pdf'),
      );
      final downloadUrl = await storageRef.getDownloadURL();

      if (mounted) {
        setState(() {
          _pdfController.text = downloadUrl;
          if (_titleController.text.trim().isEmpty) {
            _titleController.text = file.name.replaceAll('.pdf', '').replaceAll('_', ' ');
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم رفع ملف الـ PDF بنجاح وملء الرابط تلقائياً.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل رفع ملف الـ PDF: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _uploadingPdf = false);
      }
    }
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
    final String vid = _bunnyController.text.trim();
    if (vid.isNotEmpty && (_selectedLibraryId == null || _selectedLibraryId!.isEmpty)) {
      setState(() => _error = 'Please select a Bunny library for this video.');
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
        bunnyVideoId: vid.isEmpty ? null : vid,
        selectedLibraryId: _selectedLibraryId,
        pdfPath: _pdfController.text.trim().isEmpty
            ? null
            : _pdfController.text.trim(),
        publishNow: _publishNow,
        associationGateway:
            CallableBunnyAssociationGateway(FirebaseFunctions.instance),
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
          decoration: const InputDecoration(
            labelText: 'Bunny Video ID',
            hintText: 'e.g. 11111111-2222-3333-4444-555555555555',
          ),
          textInputAction: TextInputAction.next,
          onChanged: _onVideoIdChanged,
        ),
        if (_isDiscovering) ...<Widget>[
          const SizedBox(height: 6),
          const Row(
            children: <Widget>[
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 8),
              Text(
                'جارٍ فحص المكتبة تلقائياً...',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ] else if (_discoveryResult?.isFound == true) ...<Widget>[
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              const Icon(Icons.check_circle, size: 16, color: Colors.green),
              const SizedBox(width: 6),
              Text(
                'تم التعرف على المكتبة تلقائياً: ${_discoveryResult!.libraryId}',
                style: const TextStyle(fontSize: 12, color: Colors.green),
              ),
            ],
          ),
        ] else if (_bunnyController.text.trim().isNotEmpty &&
            isValidBunnyVideoId(_bunnyController.text.trim())) ...<Widget>[
          const SizedBox(height: 8),
          ref.watch(eligibleBunnyLibrariesProvider).when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                error: (Object err, _) => Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        'تعذر تحميل قائمة المكتبات.',
                        style: TextStyle(fontSize: 12, color: Colors.red),
                      ),
                    ),
                    TextButton(
                      onPressed: () => ref
                          .read(eligibleBunnyLibrariesProvider.notifier)
                          .retry(),
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
                data: (List<BunnyLibraryOption> libraries) {
                  if (libraries.isEmpty) {
                    return const Text(
                      'لا توجد مكتبات فيديو مسجلة.',
                      style: TextStyle(fontSize: 12, color: Colors.orange),
                    );
                  }
                  return DropdownButtonFormField<String>(
                    initialValue: _selectedLibraryId,
                    decoration: const InputDecoration(
                      labelText: 'اختر مكتبة الفيديو',
                      isDense: true,
                    ),
                    items: <DropdownMenuItem<String>>[
                      for (final lib in libraries)
                        DropdownMenuItem<String>(
                          value: lib.id,
                          child: Text('${lib.displayName} (${lib.id})'),
                        ),
                    ],
                    onChanged: _saving
                        ? null
                        : (String? val) =>
                            setState(() => _selectedLibraryId = val),
                  );
                },
              ),
        ],
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _pdfController,
                enabled: !_saving && !_uploadingPdf,
                decoration: const InputDecoration(
                  labelText: 'رابط ملف الـ PDF (أو ارفعه من الزر)',
                  hintText: 'https://... أو مسار الملف',
                ),
                textInputAction: TextInputAction.done,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _saving || _uploadingPdf ? null : _uploadPdfFile,
                icon: _uploadingPdf
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file),
                label: Text(_uploadingPdf ? 'جارٍ الرفع...' : 'رفع ملف PDF'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
              ),
            ),
          ],
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
  String? selectedLibraryId,
  String? pdfPath,
  required bool publishNow,
  BunnyAssociationGateway? associationGateway,
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
  String? videoResourceId;
  if (bunnyVideoId != null && bunnyVideoId.isNotEmpty) {
    resourceOrder++;
    final DocumentReference<Map<String, dynamic>> videoRef =
        db.collection('lecture_resources').doc();
    videoResourceId = videoRef.id;
    await videoRef.set(<String, dynamic>{
      'lecture_id': lectureRef.id,
      'subject_id': subjectId,
      'resource_type': 'video',
      'title': title,
      'display_order': resourceOrder,
      // ADR-010: the Video ID is only a pointer on an unverified row. The
      // library association is SERVER-OWNED (Rules deny a client write) and is
      // persisted by `associateBunnyVideoToLibrary` after verification below.
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
      'subject_id': subjectId,
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

  // First-video sync (same sequential flow): at most one video exists here;
  // the canonical selector decides (draft lectures stay null via
  // publishNow-gated visibility).
  final FirstVideoCandidate? quickWinner = videoResourceId == null
      ? null
      : selectFirstVideoCandidate(<FirstVideoCandidate>[
          FirstVideoCandidate(
            id: videoResourceId,
            type: 'video',
            title: title,
            isVisible: publishNow,
            isDeleted: false,
            bunnyVideoId: bunnyVideoId,
            displayOrder: 1,
          ),
        ]);
  await lectureRef.update(<String, dynamic>{
    'first_video':
        quickWinner == null ? null : firstVideoFields(quickWinner),
  });

  // ADR-010: verify + persist the association through the server AFTER the
  // pointer write, so the callable's trusted recomputation of `first_video`
  // (which carries the verified library) wins. A failure leaves the video row
  // pending — and therefore unplayable — never a legacy default-library row.
  if (videoResourceId != null &&
      bunnyVideoId != null &&
      bunnyVideoId.isNotEmpty &&
      associationGateway != null) {
    final String? libId = normalizeBunnyLibraryId(selectedLibraryId) ??
        bunnyLibraryIdForCreate(resourceType: 'video');
    if (libId != null && libId.isNotEmpty) {
      await associationGateway.associate(
        resourceId: videoResourceId,
        lectureId: lectureRef.id,
        libraryId: libId,
        videoId: bunnyVideoId,
      );
    }
  }

  return lectureRef.id;
}
