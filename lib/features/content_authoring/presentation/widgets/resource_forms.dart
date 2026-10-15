import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/errors/friendly_error_message.dart'
    show mapFunctionErrorCode;
import '../../../../core/widgets/app_input.dart';
import '../../../lecture/domain/entities/lecture_resource.dart'
    show LectureResourceType;
import '../../domain/entities/admin_content_entities.dart';
import '../../domain/use_cases/resource_use_cases.dart'
    show isValidBunnyVideoId;
import '../providers/admin_content_providers.dart';

/// Shared Add/Edit resource forms for the approved Lecture Creation flow.
///
/// Used both by [AdminResourcesScreen] and by the Add New Lecture dialog,
/// so the Teacher gets identical behavior in both places.
///
/// Covers ONLY Video / PDF / Attachment / External Link.
/// Timeline Quiz is deliberately excluded (handled separately after its
/// data model and UX are finalized).

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String resourceTypeLabel(LectureResourceType type) => switch (type) {
      LectureResourceType.video => 'Video',
      LectureResourceType.pdf => 'PDF',
      LectureResourceType.attachment => 'Attachment',
      LectureResourceType.externalLink => 'External Link',
    };

IconData resourceTypeIcon(LectureResourceType type) => switch (type) {
      LectureResourceType.video => Icons.play_circle_outline,
      LectureResourceType.pdf => Icons.picture_as_pdf_outlined,
      LectureResourceType.attachment => Icons.attach_file,
      LectureResourceType.externalLink => Icons.link,
    };

/// Existing project URL rule: well-formed http(s) URL with a host.
bool isValidHttpUrl(String value) {
  final parsed = Uri.tryParse(value.trim());
  return parsed != null &&
      parsed.hasScheme &&
      (parsed.scheme == 'http' || parsed.scheme == 'https') &&
      parsed.host.isNotEmpty;
}

int _nextOrderFor(WidgetRef ref, String lectureId) =>
    (ref.read(adminResourcesProvider(lectureId)).value?.length ?? 0) + 1;

int _parseOrder(String text, int fallback) {
  final parsed = int.tryParse(text.trim());
  if (parsed == null || parsed < 1) return fallback;
  return parsed;
}

Future<void> _mutateResource(
  BuildContext context,
  Future<void> Function() action, {
  required String fallback,
  String? successMessage,
}) async {
  try {
    await action();
    if (successMessage != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(successMessage)));
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

// ---------------------------------------------------------------------------
// Add New Resource sheet
// ---------------------------------------------------------------------------

/// Opens the `Add New Resource` option sheet (Video / PDF / Attachment /
/// External Link only — no Timeline Quiz).
void showAddResourceSheet(
    BuildContext context, WidgetRef ref, String lectureId) {
  showModalBottomSheet<void>(
    context: context,
    builder: (_) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'Add New Resource',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.play_circle_outline),
          title: const Text('Video'),
          onTap: () {
            Navigator.pop(context);
            showVideoResourceDialog(context, ref, lectureId);
          },
        ),
        ListTile(
          leading: const Icon(Icons.picture_as_pdf_outlined),
          title: const Text('PDF'),
          onTap: () {
            Navigator.pop(context);
            showPdfResourceFlow(context, ref, lectureId);
          },
        ),
        ListTile(
          leading: const Icon(Icons.attach_file),
          title: const Text('Attachment'),
          onTap: () {
            Navigator.pop(context);
            showAttachmentResourceFlow(context, ref, lectureId);
          },
        ),
        ListTile(
          leading: const Icon(Icons.link),
          title: const Text('External Link'),
          onTap: () {
            Navigator.pop(context);
            showExternalLinkDialog(context, ref, lectureId);
          },
        ),
      ]),
    ),
  );
}

// ---------------------------------------------------------------------------
// Video
// ---------------------------------------------------------------------------

/// `Add New Video` (or `Edit Video`). Approved workflow: the video is
/// uploaded separately to Bunny CDN; the Teacher enters the Bunny Video
/// ID here only. Playback URLs are never accepted as authoring input.
Future<void> showVideoResourceDialog(
  BuildContext context,
  WidgetRef ref,
  String lectureId, {
  AdminLectureResource? existing,
}) async {
  final title = TextEditingController(text: existing?.title ?? '');
  final bunnyId = TextEditingController(text: existing?.bunnyVideoId ?? '');
  int order = existing?.displayOrder ?? _nextOrderFor(ref, lectureId);
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(existing == null ? 'Add New Video' : 'Edit Video'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          AppInput(controller: title, hint: 'Video Name'),
          const SizedBox(height: 8),
          AppInput(
            controller: bunnyId,
            hint: 'Video ID (Bunny Video ID only)',
            helperText:
                'Upload the video to Bunny CDN first, then paste its Video ID here.',
          ),
          const SizedBox(height: 8),
          Row(children: [
            const Text('Video Display Order:'),
            const SizedBox(width: 12),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: () =>
                  setState(() => order = order > 1 ? order - 1 : 1),
            ),
            Text('$order'),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => setState(() => order += 1),
            ),
          ]),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(existing == null ? 'Save' : 'Update')),
        ],
      ),
    ),
  );
  if (saved != true || !context.mounted) return;
  if (bunnyId.text.trim().isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bunny Video ID is required.')));
    return;
  }
  if (!isValidBunnyVideoId(bunnyId.text)) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('الصق الـ Video ID فقط (GUID) — الروابط غير مقبولة.')));
    return;
  }
  if (existing == null) {
    await _mutateResource(
      context,
      () => ref.read(addVideoResourceUseCaseProvider).execute(
            lectureId: lectureId,
            title: title.text.trim(),
            sequenceNumber: order,
            bunnyVideoId: bunnyId.text.trim(),
          ),
      fallback: 'Could not add the video.',
      successMessage:
          'Video added. A thumbnail can be set from the resource Edit action.',
    );
  } else {
    final updated = existing.copyWith(
      title: title.text.trim(),
      displayOrder: order,
      bunnyVideoId: bunnyId.text.trim(),
    );
    await _mutateResource(
      context,
      () => ref.read(updateResourceUseCaseProvider).execute(updated),
      fallback: 'Could not save the video.',
      successMessage: 'Video saved.',
    );
  }
}

// ---------------------------------------------------------------------------
// PDF / Attachment upload flows
// ---------------------------------------------------------------------------

const _pdfExtensions = ['pdf'];
const _attachmentExtensions = [
  'zip',
  'doc',
  'docx',
  'xls',
  'xlsx',
  'ppt',
  'pptx',
  'txt',
  'jpg',
  'jpeg',
  'png',
];

/// `Add New PDF`: PDF Name + PDF Display Order + Upload PDF. The file is
/// picked from the device and uploaded through the existing dual-provider
/// storage architecture — the Teacher never types a storage path.
Future<void> showPdfResourceFlow(
    BuildContext context, WidgetRef ref, String lectureId) {
  return _fileResourceFlow(
    context,
    ref,
    lectureId,
    isPdf: true,
    dialogTitle: 'Add New PDF',
    nameHint: 'PDF Name',
    uploadLabel: 'Upload PDF',
    extensions: _pdfExtensions,
  );
}

/// `Add New Attachment`: Attachment Name + Display Order + Upload
/// Attachment, through the same storage architecture.
Future<void> showAttachmentResourceFlow(
    BuildContext context, WidgetRef ref, String lectureId) {
  return _fileResourceFlow(
    context,
    ref,
    lectureId,
    isPdf: false,
    dialogTitle: 'Add New Attachment',
    nameHint: 'Attachment Name',
    uploadLabel: 'Upload Attachment',
    extensions: _attachmentExtensions,
  );
}

Future<void> _fileResourceFlow(
  BuildContext context,
  WidgetRef ref,
  String lectureId, {
  required bool isPdf,
  required String dialogTitle,
  required String nameHint,
  required String uploadLabel,
  required List<String> extensions,
}) async {
  final titleController = TextEditingController();
  final orderController = TextEditingController(
      text: '${_nextOrderFor(ref, lectureId)}');
  final defaultProvider =
      await ref.read(defaultStorageProviderProvider.future);
  String selectedProvider = defaultProvider;
  File? picked;

  if (!context.mounted) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      return AlertDialog(
        title: Text(dialogTitle),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          AppInput(controller: titleController, hint: nameHint),
          const SizedBox(height: 8),
          TextField(
            controller: orderController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Display Order'),
          ),
          const SizedBox(height: 12),
          // Dual-provider selector (FINAL_DECISIONS §15): platform
          // default pre-selected, overridable per file.
          SegmentedButton<String>(
            segments: const [
              ButtonSegment<String>(value: 'firebase', label: Text('Firebase')),
              ButtonSegment<String>(value: 'bunny', label: Text('Bunny')),
            ],
            selected: {selectedProvider},
            onSelectionChanged: (selection) =>
                setState(() => selectedProvider = selection.first),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.upload_file_outlined),
            label: Text(picked == null ? uploadLabel : picked!.path.split(Platform.pathSeparator).last),
            onPressed: () async {
              final platformFile = await FilePicker.pickFile(
                type: FileType.custom,
                allowedExtensions: extensions,
              );
              final path = platformFile?.path;
              if (path == null) return;
              setState(() {
                picked = File(path);
                if (titleController.text.trim().isEmpty) {
                  titleController.text = platformFile?.name ?? '';
                }
              });
            },
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      );
    }),
  );
  if (confirmed != true || !context.mounted) return;
  final file = picked;
  if (file == null) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose a file first.')));
    return;
  }
  final order =
      _parseOrder(orderController.text, _nextOrderFor(ref, lectureId));
  double progress = 0;

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      Future<void> start() async {
        try {
          if (isPdf) {
            await ref.read(addPdfResourceUseCaseProvider).execute(
                  lectureId: lectureId,
                  title: titleController.text.trim(),
                  file: file,
                  displayOrder: order,
                  storageProvider: selectedProvider,
                  onProgress: (p) => setState(() => progress = p),
                );
          } else {
            await ref.read(addAttachmentResourceUseCaseProvider).execute(
                  lectureId: lectureId,
                  title: titleController.text.trim(),
                  file: file,
                  displayOrder: order,
                  storageProvider: selectedProvider,
                  onProgress: (p) => setState(() => progress = p),
                );
          }
          if (ctx.mounted) Navigator.pop(ctx);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('File uploaded.')));
          }
        } catch (e) {
          if (ctx.mounted) Navigator.pop(ctx);
          if (context.mounted) {
            final message = e is Failure && e.code == FailureCode.validation
                ? 'The file is larger than the allowed limit (50MB).'
                : 'File upload failed.';
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(message)));
          }
        }
      }

      WidgetsBinding.instance.addPostFrameCallback((_) => start());
      return AlertDialog(
        title: Text(uploadLabel),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          LinearProgressIndicator(value: progress == 0 ? null : progress),
          const SizedBox(height: 8),
          Text(progress == 0
              ? 'Starting…'
              : '${(progress * 100).toStringAsFixed(0)}%'),
        ]),
      );
    }),
  );
}

// ---------------------------------------------------------------------------
// External Link
// ---------------------------------------------------------------------------

/// `Add New External Link` (or `Edit External Link`): name + http(s) URL
/// + display order, saved through the repository/use-case layer.
Future<void> showExternalLinkDialog(
  BuildContext context,
  WidgetRef ref,
  String lectureId, {
  AdminLectureResource? existing,
}) async {
  final title = TextEditingController(text: existing?.title ?? '');
  final url = TextEditingController(text: existing?.externalUrl ?? '');
  final order = TextEditingController(
      text: '${existing?.displayOrder ?? _nextOrderFor(ref, lectureId)}');
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
          existing == null ? 'Add New External Link' : 'Edit External Link'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        AppInput(controller: title, hint: 'External Link Name'),
        const SizedBox(height: 8),
        AppInput(controller: url, hint: 'External Link URL (https://…)'),
        const SizedBox(height: 8),
        TextField(
          controller: order,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Display Order'),
        ),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(existing == null ? 'Save' : 'Update')),
      ],
    ),
  );
  if (saved != true || !context.mounted) return;
  if (!isValidHttpUrl(url.text)) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Invalid URL — it must start with https:// and include a domain.')));
    return;
  }
  final displayOrder =
      _parseOrder(order.text, _nextOrderFor(ref, lectureId));
  if (existing == null) {
    await _mutateResource(
      context,
      () => ref.read(addExternalLinkResourceUseCaseProvider).execute(
            lectureId: lectureId,
            title: title.text.trim(),
            displayOrder: displayOrder,
            externalUrl: Uri.parse(url.text.trim()),
          ),
      fallback: 'Could not add the link.',
    );
  } else {
    final updated = AdminLectureResource(
      id: existing.id,
      lectureId: existing.lectureId,
      resourceType: existing.resourceType,
      title: title.text.trim(),
      displayOrder: displayOrder,
      bunnyVideoId: existing.bunnyVideoId,
      storagePath: existing.storagePath,
      storageProvider: existing.storageProvider,
      thumbnailProvider: existing.thumbnailProvider,
      externalUrl: url.text.trim(),
      thumbnail: existing.thumbnail,
      duration: existing.duration,
      isVisible: existing.isVisible,
      isDeleted: existing.isDeleted,
      deletedAt: existing.deletedAt,
      deletedBy: existing.deletedBy,
    );
    await _mutateResource(
      context,
      () => ref.read(updateResourceUseCaseProvider).execute(updated),
      fallback: 'Could not save the link.',
      successMessage: 'Link saved.',
    );
  }
}

// ---------------------------------------------------------------------------
// Video thumbnail
// ---------------------------------------------------------------------------

/// Optional video thumbnail upload (FINAL_DECISIONS §15: provider
/// selector with platform default + progress). Reached from Edit flows.
Future<void> showThumbnailFlow(
    BuildContext context, WidgetRef ref, AdminLectureResource resource) async {
  final platformFile = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
  );
  final path = platformFile?.path;
  if (path == null || !context.mounted) return;

  final defaultProvider =
      await ref.read(defaultStorageProviderProvider.future);
  String selectedProvider = defaultProvider;
  double progress = 0;
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      Future<void> start() async {
        try {
          await ref.read(setResourceThumbnailUseCaseProvider).execute(
                lectureId: resource.lectureId,
                resourceId: resource.id,
                file: File(path),
                storageProvider: selectedProvider,
                onProgress: (p) => setState(() => progress = p),
              );
          if (ctx.mounted) Navigator.pop(ctx);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Thumbnail uploaded.')));
          }
        } catch (e) {
          if (ctx.mounted) Navigator.pop(ctx);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content:
                    Text('Thumbnail upload failed (5MB max, jpg/png/webp).')));
          }
        }
      }

      WidgetsBinding.instance.addPostFrameCallback((_) => start());
      return AlertDialog(
        title: const Text('Upload Thumbnail'),
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
              ? 'Starting…'
              : '${(progress * 100).toStringAsFixed(0)}%'),
        ]),
      );
    }),
  );
}

// ---------------------------------------------------------------------------
// Visibility toggle
// ---------------------------------------------------------------------------

/// Flips resource visibility with feedback.
Future<void> toggleResourceVisibilityWithFeedback(
    BuildContext context, WidgetRef ref, AdminLectureResource resource) {
  return _mutateResource(
    context,
    () => ref.read(setResourceVisibilityUseCaseProvider).execute(
        resourceId: resource.id, visible: !resource.isVisible),
    fallback: 'Could not change resource visibility.',
  );
}

// ---------------------------------------------------------------------------
// Edit dispatch + delete + row widget
// ---------------------------------------------------------------------------

/// Opens the right edit form for [resource] (title/order for files,
/// full forms for video/link).
Future<void> showEditResourceDialog(
    BuildContext context, WidgetRef ref, AdminLectureResource resource) {
  return switch (resource.resourceType) {
    LectureResourceType.video => showVideoResourceDialog(
        context, ref, resource.lectureId,
        existing: resource),
    LectureResourceType.externalLink => showExternalLinkDialog(
        context, ref, resource.lectureId,
        existing: resource),
    LectureResourceType.pdf || LectureResourceType.attachment =>
      _editFileResourceDialog(context, ref, resource),
  };
}

Future<void> _editFileResourceDialog(
    BuildContext context, WidgetRef ref, AdminLectureResource resource) async {
  final title = TextEditingController(text: resource.title);
  final order =
      TextEditingController(text: '${resource.displayOrder}');
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(resource.resourceType == LectureResourceType.pdf
          ? 'Edit PDF'
          : 'Edit Attachment'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        AppInput(
            controller: title,
            hint: resource.resourceType == LectureResourceType.pdf
                ? 'PDF Name'
                : 'Attachment Name'),
        const SizedBox(height: 8),
        TextField(
          controller: order,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Display Order'),
        ),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Update')),
      ],
    ),
  );
  if (saved != true || !context.mounted) return;
  final updated = resource.copyWith(
    title: title.text.trim(),
    displayOrder: _parseOrder(order.text, resource.displayOrder),
  );
  await _mutateResource(
    context,
    () => ref.read(updateResourceUseCaseProvider).execute(updated),
    fallback: 'Could not save the resource.',
    successMessage: 'Resource saved.',
  );
}

/// Deletes (soft-archives) a resource with feedback.
Future<void> deleteResourceWithFeedback(
    BuildContext context, WidgetRef ref, AdminLectureResource resource) {
  return _mutateResource(
    context,
    () => ref.read(archiveResourceUseCaseProvider).execute(resource.id),
    fallback: 'Could not delete the resource.',
    successMessage: 'Resource deleted.',
  );
}

/// Approved resource row: `01. Video - Part 01   Edit   Delete`.
/// Ordering itself is handled by the enclosing ReorderableListView.
/// The overflow menu keeps the pre-existing visibility toggle and
/// video-thumbnail actions.
class LectureResourceRow extends StatelessWidget {
  final int index;
  final AdminLectureResource resource;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final Widget? trailingExtra;

  const LectureResourceRow({
    super.key,
    required this.index,
    required this.resource,
    required this.onEdit,
    required this.onDelete,
    this.trailingExtra,
  });

  @override
  Widget build(BuildContext context) {
    final label = resourceTypeLabel(resource.resourceType);
    final name =
        resource.title.isEmpty ? 'Untitled $label' : resource.title;
    return ListTile(
      leading: Icon(resourceTypeIcon(resource.resourceType)),
      title: Text(
          '${(index + 1).toString().padLeft(2, '0')}. $label - $name'),
      subtitle: Text(
        'Order ${resource.displayOrder}'
        '${resource.bunnyVideoId != null ? " • Bunny: ${resource.bunnyVideoId}" : ""}'
        '${resource.storagePath != null ? " • File uploaded" : ""}'
        ' • ${resource.isVisible ? "Visible" : "Hidden"}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(onPressed: onEdit, child: const Text('Edit')),
          TextButton(onPressed: onDelete, child: const Text('Delete')),
          ?trailingExtra,
        ],
      ),
    );
  }
}

/// Manageable resource list shared by [AdminResourcesScreen] and the
/// Add New Lecture dialog: drag-to-reorder + Edit/Delete rows + the
/// overflow menu (visibility toggle, video thumbnail).
class LectureResourceList extends ConsumerWidget {
  final String lectureId;
  final bool shrinkWrap;

  const LectureResourceList({
    super.key,
    required this.lectureId,
    this.shrinkWrap = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resources = ref.watch(adminResourcesProvider(lectureId));
    return resources.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Could not load resources.'),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () =>
                ref.invalidate(adminResourcesProvider(lectureId)),
            child: const Text('Retry'),
          ),
        ]),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const Center(child: Text('No resources yet.'));
        }
        return ReorderableListView.builder(
          shrinkWrap: shrinkWrap,
          physics: shrinkWrap
              ? const NeverScrollableScrollPhysics()
              : null,
          itemCount: list.length,
          onReorderItem: (oldIndex, newIndex) {
            final items = [...list];
            items.insert(newIndex, items.removeAt(oldIndex));
            ref
                .read(reorderResourcesUseCaseProvider)
                .execute(items)
                .catchError((_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Could not reorder resources.')));
              }
            });
          },
          itemBuilder: (_, i) {
            final r = list[i];
            return Card(
              key: ValueKey(r.id),
              margin:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: LectureResourceRow(
                index: i,
                resource: r,
                onEdit: () => showEditResourceDialog(context, ref, r),
                onDelete: () =>
                    deleteResourceWithFeedback(context, ref, r),
                trailingExtra: PopupMenuButton<String>(
                  onSelected: (v) {
                    switch (v) {
                      case 'toggle':
                        toggleResourceVisibilityWithFeedback(
                            context, ref, r);
                      case 'thumbnail':
                        showThumbnailFlow(context, ref, r);
                    }
                  },
                  itemBuilder: (_) => [
                    if (r.resourceType == LectureResourceType.video)
                      const PopupMenuItem(
                          value: 'thumbnail',
                          child: Text('Change Thumbnail')),
                    const PopupMenuItem(
                        value: 'toggle',
                        child: Text('Toggle Visibility')),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
