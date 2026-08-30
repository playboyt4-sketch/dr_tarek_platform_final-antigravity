import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/errors/friendly_error_message.dart'
    show mapFunctionErrorCode;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_input.dart';
import '../../../lecture/domain/entities/lecture_resource.dart'
    show LectureResourceType;
import '../providers/admin_content_providers.dart';

/// FINAL_DECISIONS §15 / Part E: the Teacher-configured platform default
/// pre-selects the upload provider; the Admin can override per file.
final defaultStorageProviderProvider = FutureProvider<String>((ref) async {
  return await ref.watch(systemSettingsDataSourceProvider).defaultStorageProvider() ??
      'firebase';
});

/// Resource management per Feature 04 "Lecture Structure":
///  - video   -> Bunny video id ONLY (06 §6.4) + explicit sequence number
///               + optional thumbnail upload;
///  - pdf     -> dual-provider upload with live progress to
///               /lecture_resources/{lectureId}/{resourceId}/{file}
///               (11 Assets §4.2) — the file lands under the REAL resource
///               document id;
///  - attachment -> same upload pattern; zip/doc/xls/ppt/txt PLUS
///               jpg/jpeg/png image attachments (approved);
///  - external_link -> URL + display label, validated before saving.
/// Plus reorder (atomic batch), visibility toggle, soft-archive.
class AdminResourcesScreen extends ConsumerWidget {
  final String lectureId;
  final String lectureTitle;

  const AdminResourcesScreen({
    super.key,
    required this.lectureId,
    required this.lectureTitle,
  });

  Future<void> _mutate(
    BuildContext context,
    Future<void> Function() action, {
    required String fallback,
    String? successMessage,
  }) async {
    try {
      await action();
      if (successMessage != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(successMessage)));
      }
    } on Failure catch (failure) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(mapFunctionErrorCode(
                'invalid-argument', failure.debugDetail, fallback))));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(fallback)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resources = ref.watch(adminResourcesProvider(lectureId));

    return Scaffold(
      appBar: AppBar(title: Text('الموارد — $lectureTitle')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add),
        onPressed: () => _addResourceSheet(context, ref),
      ),
      body: resources.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('تعذر تحميل الموارد.'),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () =>
                  ref.invalidate(adminResourcesProvider(lectureId)),
              child: const Text('إعادة المحاولة'),
            ),
          ]),
        ),
        data: (list) {
          if (list.isEmpty) return const Center(child: Text('لا توجد موارد بعد.'));
          return ReorderableListView.builder(
            itemCount: list.length,
            onReorderItem: (oldIndex, newIndex) {
              final items = [...list];
              items.insert(newIndex, items.removeAt(oldIndex));
              _mutate(
                context,
                () =>
                    ref.read(reorderResourcesUseCaseProvider).execute(items),
                fallback: 'تعذر إعادة الترتيب.',
              );
            },
            itemBuilder: (_, i) {
              final r = list[i];
              return Card(
                key: ValueKey(r.id),
                margin:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  leading:
                      Icon(_iconFor(r.resourceType), color: AppColors.primary),
                  title: Text(r.title.isEmpty ? 'مورد بدون عنوان' : r.title),
                  subtitle: Text(
                    '${_labelFor(r.resourceType)}'
                    '${r.bunnyVideoId != null ? " • Bunny: ${r.bunnyVideoId}" : ""}'
                    '${r.storagePath != null ? " • ملف مرفوع" : ""}'
                    ' • ترتيب ${r.displayOrder}'
                    ' • ${r.isVisible ? "ظاهر" : "مخفي"}',
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) {
                      switch (v) {
                        case 'toggle':
                          _mutate(
                            context,
                            () => ref
                                .read(setResourceVisibilityUseCaseProvider)
                                .execute(
                                    resourceId: r.id, visible: !r.isVisible),
                            fallback: 'تعذر تغيير إظهار المورد.',
                          );
                        case 'thumbnail':
                          _pickThumbnail(context, ref, r.id);
                        case 'archive':
                          _mutate(
                            context,
                            () => ref
                                .read(archiveResourceUseCaseProvider)
                                .execute(r.id),
                            fallback: 'تعذر أرشفة المورد.',
                            successMessage: 'تمت أرشفة المورد.',
                          );
                      }
                    },
                    itemBuilder: (_) => [
                      if (r.resourceType == LectureResourceType.video)
                        const PopupMenuItem(
                            value: 'thumbnail', child: Text('تغيير الصورة المصغرة')),
                      const PopupMenuItem(
                          value: 'toggle', child: Text('تبديل الإظهار')),
                      const PopupMenuItem(
                          value: 'archive', child: Text('أرشفة المورد')),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  IconData _iconFor(LectureResourceType type) => switch (type) {
        LectureResourceType.video => Icons.play_circle_outline,
        LectureResourceType.pdf => Icons.picture_as_pdf_outlined,
        LectureResourceType.attachment => Icons.attach_file,
        LectureResourceType.externalLink => Icons.link,
      };

  String _labelFor(LectureResourceType type) => switch (type) {
        LectureResourceType.video => 'فيديو',
        LectureResourceType.pdf => 'PDF',
        LectureResourceType.attachment => 'مرفق',
        LectureResourceType.externalLink => 'رابط خارجي',
      };

  int _nextOrder(WidgetRef ref) =>
      (ref.read(adminResourcesProvider(lectureId)).value?.length ?? 0) + 1;

  void _addResourceSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.play_circle_outline),
            title: const Text('فيديو Bunny (جزء من المحاضرة)'),
            onTap: () {
              Navigator.pop(context);
              _videoDialog(context, ref);
            },
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('ملف PDF'),
            onTap: () {
              Navigator.pop(context);
              _pickAndUpload(context, ref,
                  isPdf: true, extensions: ['pdf']);
            },
          ),
          ListTile(
            leading: const Icon(Icons.attach_file),
            title: const Text('مرفق (ZIP/DOC/XLS/PPT/JPG/PNG…)'),
            onTap: () {
              Navigator.pop(context);
              _pickAndUpload(context, ref,
                  isPdf: false,
                  extensions: [
                    'zip', 'doc', 'docx', 'xls', 'xlsx',
                    'ppt', 'pptx', 'txt', 'jpg', 'jpeg', 'png',
                  ]);
            },
          ),
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('رابط خارجي'),
            onTap: () {
              Navigator.pop(context);
              _linkDialog(context, ref);
            },
          ),
        ]),
      ),
    );
  }

  /// Video part: Bunny video_id + explicit sequence number (Feature 04
  /// "Multiple Videos"), optional thumbnail picked right after creation.
  Future<void> _videoDialog(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController();
    final bunnyId = TextEditingController();
    int sequence = _nextOrder(ref);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('فيديو جديد'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            AppInput(controller: title, hint: 'عنوان الجزء'),
            const SizedBox(height: 8),
            AppInput(controller: bunnyId, hint: 'Bunny Video ID فقط — لا روابط'),
            const SizedBox(height: 8),
            Row(children: [
              const Text('رقم التسلسل:'),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () =>
                    setState(() => sequence = sequence > 1 ? sequence - 1 : 1),
              ),
              Text('$sequence'),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => setState(() => sequence += 1),
              ),
            ]),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('إضافة')),
          ],
        ),
      ),
    );
    if (saved != true || !context.mounted) return;
    if (bunnyId.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bunny Video ID مطلوب.')));
      return;
    }
    await _mutate(
      context,
      () => ref.read(addVideoResourceUseCaseProvider).execute(
            lectureId: lectureId,
            title: title.text.trim(),
            sequenceNumber: sequence,
            bunnyVideoId: bunnyId.text.trim(),
          ),
      fallback: 'تعذر إضافة الفيديو.',
      successMessage:
          'أُضيف الفيديو. يمكنك إضافة صورة مصغرة من قائمة المورد.',
    );
  }

  Future<void> _linkDialog(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController();
    final url = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('رابط خارجي'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          AppInput(controller: title, hint: 'العنوان الظاهر'),
          const SizedBox(height: 8),
          AppInput(controller: url, hint: 'https://…'),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('إضافة')),
        ],
      ),
    );
    if (saved != true || !context.mounted) return;

    // Validate BEFORE saving — well-formed http(s) URL only.
    final parsed = Uri.tryParse(url.text.trim());
    final isValid = parsed != null &&
        parsed.hasScheme &&
        (parsed.scheme == 'http' || parsed.scheme == 'https') &&
        parsed.host.isNotEmpty;
    if (!isValid) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('الرابط غير صالح — يجب أن يبدأ بـ https:// ويتضمن نطاقًا.')));
      return;
    }
    await _mutate(
      context,
      () => ref.read(addExternalLinkResourceUseCaseProvider).execute(
            lectureId: lectureId,
            title: title.text.trim(),
            displayOrder: _nextOrder(ref),
            externalUrl: parsed,
          ),
      fallback: 'تعذر إضافة الرابط.',
    );
  }

  /// PDF / attachment flow: pick file -> dialog with provider selector
  /// (FINAL_DECISIONS §15: pre-selected from the platform default,
  /// overridable per file) + live upload progress. The repository creates
  /// the doc id FIRST and uploads bytes under it, so storage_path always
  /// matches 11 Assets §4.2 exactly.
  Future<void> _pickAndUpload(
    BuildContext context,
    WidgetRef ref, {
    required bool isPdf,
    required List<String> extensions,
  }) async {
    final platformFile = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: extensions,
    );
    final path = platformFile?.path;
    if (platformFile == null || path == null || !context.mounted) return;
    final file = File(path);

    final titleController = TextEditingController(text: platformFile.name);
    final defaultProvider =
        await ref.read(defaultStorageProviderProvider.future);
    String selectedProvider = defaultProvider; // platform default pre-selected
    double progress = 0;
    bool started = false;

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
        Future<void> start() async {
          started = true;
          try {
            if (isPdf) {
              await ref.read(addPdfResourceUseCaseProvider).execute(
                    lectureId: lectureId,
                    title: titleController.text.trim(),
                    file: file,
                    storageProvider: selectedProvider,
                    onProgress: (p) => setState(() => progress = p),
                  );
            } else {
              await ref.read(addAttachmentResourceUseCaseProvider).execute(
                    lectureId: lectureId,
                    title: titleController.text.trim(),
                    file: file,
                    storageProvider: selectedProvider,
                    onProgress: (p) => setState(() => progress = p),
                  );
            }
            if (ctx.mounted) Navigator.pop(ctx);
          } catch (e) {
            if (ctx.mounted) Navigator.pop(ctx);
            if (context.mounted) {
              final message = e is Failure && e.code == FailureCode.validation
                  ? 'الملف أكبر من الحد المسموح (حد مبدئي 50MB — بانتظار التأكيد).'
                  : 'فشل رفع الملف.';
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(message)));
            }
          }
        }

        if (!started) {
          started = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => start());
        }
        return AlertDialog(
          title: Text(isPdf ? 'رفع PDF' : 'رفع مرفق'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'عنوان المورد'),
              ),
              const SizedBox(height: 12),
              // Dual-provider selector (FINAL_DECISIONS §15): defaults to the
              // Teacher-configured platform default, overridable per file.
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment<String>(value: 'firebase', label: Text('Firebase')),
                  ButtonSegment<String>(value: 'bunny', label: Text('Bunny')),
                ],
                selected: {selectedProvider},
                onSelectionChanged: (selection) =>
                    setState(() => selectedProvider = selection.first),
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(value: progress == 0 ? null : progress),
              const SizedBox(height: 8),
              Text(progress == 0
                  ? 'جارٍ البدء…'
                  : '${(progress * 100).toStringAsFixed(0)}%'),
            ]),
          ),
        );
      }),
    );
  }

  /// Optional video thumbnail: uploaded under the resource's own path
  /// prefix through the selected provider (FINAL_DECISIONS §15); its
  /// storage path + provider are written to lecture_resources.
  Future<void> _pickThumbnail(
      BuildContext context, WidgetRef ref, String resourceId) async {
    final platformFile = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
    );
    final path = platformFile?.path;
    if (path == null || !context.mounted) return;

    final defaultProvider =
        await ref.read(defaultStorageProviderProvider.future);
    String selectedProvider = defaultProvider;
    double progress = 0;
    bool started = false;
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
        Future<void> start() async {
          started = true;
          try {
            await ref.read(setResourceThumbnailUseCaseProvider).execute(
                  lectureId: lectureId,
                  resourceId: resourceId,
                  file: File(path),
                  storageProvider: selectedProvider,
                  onProgress: (p) => setState(() => progress = p),
                );
            if (ctx.mounted) Navigator.pop(ctx);
          } catch (e) {
            if (ctx.mounted) Navigator.pop(ctx);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text(
                      'فشل رفع الصورة المصغرة (الحد المبدئي 5MB، jpg/png/webp فقط).')));
            }
          }
        }

        if (!started) {
          started = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => start());
        }
        return AlertDialog(
          title: const Text('رفع صورة مصغرة'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(value: 'firebase', label: Text('Firebase')),
                ButtonSegment<String>(value: 'bunny', label: Text('Bunny')),
              ],
              selected: {selectedProvider},
              onSelectionChanged: (selection) =>
                  setState(() => selectedProvider = selection.first),
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: progress == 0 ? null : progress),
            const SizedBox(height: 8),
            Text(progress == 0
                ? 'جارٍ البدء…'
                : '${(progress * 100).toStringAsFixed(0)}%'),
          ]),
        );
      }),
    );
  }
}
