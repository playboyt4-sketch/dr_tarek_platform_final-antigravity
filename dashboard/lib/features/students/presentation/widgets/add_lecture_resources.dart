import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Staged resources for the Add New Lecture form.
///
/// Resources are staged locally inside the form and persisted together
/// with the lecture on Save (the lecture id does not exist before that).
/// Supported types for this task only: Video / PDF / Attachment /
/// External Link — no Timeline Quiz.
///
/// Behavior mirrors the approved resource implementation:
/// - Video: Bunny video id only (uploaded separately to Bunny; the
///   teacher enters the id — never a playback URL).
/// - PDF / Attachment: file picked from the device; bytes upload through
///   Firebase Storage on save (approved path convention).
/// - External Link: display name + validated http(s) URL.
/// Rows stay independently editable/deletable; order is an editable
/// numeric field and the list renders sorted by it.

enum StagedResourceKind { video, pdf, attachment, externalLink }

String stagedResourceLabel(StagedResourceKind kind) => switch (kind) {
      StagedResourceKind.video => 'Video',
      StagedResourceKind.pdf => 'PDF',
      StagedResourceKind.attachment => 'Attachment',
      StagedResourceKind.externalLink => 'External Link',
    };

/// Existing project URL rule (same as the approved resource flow):
/// well-formed http(s) URL with a host.
bool isValidHttpUrl(String value) {
  final Uri? parsed = Uri.tryParse(value.trim());
  return parsed != null &&
      parsed.hasScheme &&
      (parsed.scheme == 'http' || parsed.scheme == 'https') &&
      parsed.host.isNotEmpty;
}

class StagedResource {
  String name;
  int displayOrder;
  final StagedResourceKind kind;
  String bunnyVideoId;
  String externalUrl;
  Uint8List? fileBytes;
  String? fileName;
  String? contentType;

  StagedResource({
    required this.name,
    required this.displayOrder,
    required this.kind,
    this.bunnyVideoId = '',
    this.externalUrl = '',
    this.fileBytes,
    this.fileName,
    this.contentType,
  });
}

/// Ordered staged-resource list with Edit / Delete per row.
class StagedResourceList extends StatelessWidget {
  final List<StagedResource> resources;
  final ValueChanged<int> onEdit;
  final ValueChanged<int> onDelete;

  const StagedResourceList({
    super.key,
    required this.resources,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (resources.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 2),
        child: Text(
          'No resources yet.',
          style: TextStyle(
            fontFamily: 'Google Sans Flex',
            fontSize: 12,
            color: Color(0xFF6B7280),
          ),
        ),
      );
    }
    final List<int> order = List<int>.generate(resources.length, (i) => i)
      ..sort((int a, int b) => resources[a]
          .displayOrder
          .compareTo(resources[b].displayOrder));
    // Figma `Frame 134` list: items `414.5 x 24`, vertical gap 7.
    return Center(
      child: SizedBox(
        width: 414.5,
        child: Column(
          children: [
            for (int position = 0; position < order.length; position++)
              Builder(builder: (BuildContext context) {
                final int i = order[position];
                final StagedResource resource = resources[i];
                final String name = resource.name.trim().isEmpty
                    ? 'Untitled ${stagedResourceLabel(resource.kind)}'
                    : resource.name.trim();
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3.5),
                  child: SizedBox(
                    width: 414.5,
                    height: 24,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 36,
                          child: Text(
                            '${(position + 1).toString().padLeft(2, '0')}.',
                            style: const TextStyle(
                              fontFamily: 'Google Sans Flex',
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF111827),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${stagedResourceLabel(resource.kind)} - $name',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Google Sans Flex',
                              fontSize: 14,
                              color: Color(0xFF111827),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        SizedBox(
                          width: 97,
                          height: 24,
                          child: ElevatedButton(
                            onPressed: () => onEdit(i),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              minimumSize: const Size(97, 24),
                              padding: EdgeInsets.zero,
                              tapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              shape: const StadiumBorder(),
                            ),
                            child: const Text(
                              'Edit',
                              style: TextStyle(
                                fontFamily: 'Google Sans Flex',
                                fontSize: 13,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                                width: 24, height: 24),
                            onPressed: () => onDelete(i),
                            icon: const Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: Color(0xFF4B5563),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

/// Add-resource sheet: the four approved choices only. Returns the
/// created staged resource, or null when canceled at any step.
Future<StagedResource?> showAddResourceSheet(
  BuildContext context, {
  required int nextOrder,
  required Color gradeColor,
}) async {
  final StagedResourceKind? kind =
      await showModalBottomSheet<StagedResourceKind>(
    context: context,
    builder: (BuildContext context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Add New Resource',
              style: TextStyle(
                fontFamily: 'Google Sans Flex',
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          for (final StagedResourceKind option in StagedResourceKind.values)
            ListTile(
              leading: Icon(_iconFor(option)),
              title: Text(stagedResourceLabel(option)),
              onTap: () => Navigator.pop(context, option),
            ),
        ],
      ),
    ),
  );
  if (kind == null) return null;
  if (!context.mounted) return null;
  // ignore: use_build_context_synchronously — [context] is the caller's;
  // only the sheet (already dismissed) used a child context.
  return showResourceDialog(context,
      kind: kind, nextOrder: nextOrder, gradeColor: gradeColor);
}

IconData _iconFor(StagedResourceKind kind) => switch (kind) {
      StagedResourceKind.video => Icons.play_circle_outline,
      StagedResourceKind.pdf => Icons.picture_as_pdf_outlined,
      StagedResourceKind.attachment => Icons.attach_file,
      StagedResourceKind.externalLink => Icons.link,
    };

/// Add/Edit resource dialog per type. Returns the staged resource, or
/// null when canceled. Add flows pick sensible defaults; edit flows are
/// prefilled from [existing].
Future<StagedResource?> showResourceDialog(
  BuildContext context, {
  required StagedResourceKind kind,
  required int nextOrder,
  required Color gradeColor,
  StagedResource? existing,
}) {
  switch (kind) {
    case StagedResourceKind.video:
      return _videoDialog(context,
          nextOrder: nextOrder, gradeColor: gradeColor, existing: existing);
    case StagedResourceKind.pdf:
    case StagedResourceKind.attachment:
      return _fileDialog(context,
          kind: kind, nextOrder: nextOrder, gradeColor: gradeColor, existing: existing);
    case StagedResourceKind.externalLink:
      return _linkDialog(context,
          nextOrder: nextOrder, gradeColor: gradeColor, existing: existing);
  }
}

Future<StagedResource?> _videoDialog(
  BuildContext context, {
  required int nextOrder,
  required Color gradeColor,
  StagedResource? existing,
}) async {
  final TextEditingController name =
      TextEditingController(text: existing?.name ?? '');
  final TextEditingController bunnyId =
      TextEditingController(text: existing?.bunnyVideoId ?? '');
  final TextEditingController order = TextEditingController(
      text: '${existing?.displayOrder ?? nextOrder}');
  final bool? saved = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.25),
    builder: (BuildContext context) => _ResourceFormShell(gradeColor: gradeColor,
      title: existing == null ? 'Add New Video' : 'Edit Video',
      onSave: () => Navigator.of(context).pop(true),
      children: [
        _field(controller: name, hint: 'Video Name'),
        const SizedBox(height: 8),
        _field(
          controller: bunnyId,
          hint: 'Video ID (Bunny Video ID only)',
          helper:
              'Upload the video to Bunny CDN first, then paste its Video ID here.',
        ),
        const SizedBox(height: 8),
        _field(
          controller: order,
          hint: 'Video Display Order',
          numeric: true,
        ),
      ],
    ),
  );
  if (saved != true || !context.mounted) return null;
  if (bunnyId.text.trim().isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bunny Video ID is required.')));
    return null;
  }
  return StagedResource(
    name: name.text.trim(),
    displayOrder: int.tryParse(order.text.trim()) ?? nextOrder,
    kind: StagedResourceKind.video,
    bunnyVideoId: bunnyId.text.trim(),
  );
}

Future<StagedResource?> _fileDialog(
  BuildContext context, {
  required StagedResourceKind kind,
  required int nextOrder,
  required Color gradeColor,
  StagedResource? existing,
}) async {
  final bool isPdf = kind == StagedResourceKind.pdf;
  final TextEditingController name =
      TextEditingController(text: existing?.name ?? '');
  final TextEditingController order = TextEditingController(
      text: '${existing?.displayOrder ?? nextOrder}');
  Uint8List? bytes = existing?.fileBytes;
  String? fileName = existing?.fileName;
  String? pickedLabel = fileName;

  final bool? saved = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.25),
    builder: (BuildContext context) => StatefulBuilder(
      builder: (BuildContext context, StateSetter setState) =>
          _ResourceFormShell(
        gradeColor: gradeColor,
        title: existing == null
            ? (isPdf ? 'Add New PDF' : 'Add New Attachment')
            : (isPdf ? 'Edit PDF' : 'Edit Attachment'),
        onSave: () => Navigator.of(context).pop(true),
        children: [
          _field(
              controller: name,
              hint: isPdf ? 'PDF Name' : 'Attachment Name'),
          const SizedBox(height: 8),
          _field(
            controller: order,
            hint: 'Display Order',
            numeric: true,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.upload_file_outlined),
            label: Text(pickedLabel ??
                (isPdf ? 'Upload PDF' : 'Upload Attachment')),
            onPressed: () async {
              final List<PlatformFile> picked =
                  await FilePicker.pickFiles(
                type: FileType.custom,
                allowedExtensions: isPdf
                    ? const ['pdf']
                    : const [
                        'zip', 'doc', 'docx', 'xls', 'xlsx',
                        'ppt', 'pptx', 'txt', 'jpg', 'jpeg', 'png',
                      ],
              );
              if (picked.isEmpty) return;
              final PlatformFile file = picked.first;
              Uint8List? data;
              try {
                data = await file.readAsBytes();
              } catch (_) {
                data = null;
              }
              if (data == null) return;
              setState(() {
                bytes = data;
                fileName = file.name;
                pickedLabel = fileName;
                if (name.text.trim().isEmpty && fileName != null) {
                  name.text = fileName!;
                }
              });
            },
          ),
        ],
      ),
    ),
  );
  if (saved != true || !context.mounted) return null;
  if (bytes == null) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose a file first.')));
    return null;
  }
  return StagedResource(
    name: name.text.trim(),
    displayOrder: int.tryParse(order.text.trim()) ?? nextOrder,
    kind: kind,
    fileBytes: bytes,
    fileName: fileName,
    contentType: isPdf ? 'application/pdf' : null,
  );
}

Future<StagedResource?> _linkDialog(
  BuildContext context, {
  required int nextOrder,
  required Color gradeColor,
  StagedResource? existing,
}) async {
  final TextEditingController name =
      TextEditingController(text: existing?.name ?? '');
  final TextEditingController url =
      TextEditingController(text: existing?.externalUrl ?? '');
  final TextEditingController order = TextEditingController(
      text: '${existing?.displayOrder ?? nextOrder}');
  final bool? saved = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.25),
    builder: (BuildContext context) => _ResourceFormShell(gradeColor: gradeColor,
      title:
          existing == null ? 'Add New External Link' : 'Edit External Link',
      onSave: () => Navigator.of(context).pop(true),
      children: [
        _field(controller: name, hint: 'External Link Name'),
        const SizedBox(height: 8),
        _field(controller: url, hint: 'External Link URL (https://…)'),
        const SizedBox(height: 8),
        _field(
          controller: order,
          hint: 'Display Order',
          numeric: true,
        ),
      ],
    ),
  );
  if (saved != true || !context.mounted) return null;
  if (!isValidHttpUrl(url.text)) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Invalid URL — it must start with https:// and include a domain.')));
    return null;
  }
  return StagedResource(
    name: name.text.trim(),
    displayOrder: int.tryParse(order.text.trim()) ?? nextOrder,
    kind: StagedResourceKind.externalLink,
    externalUrl: url.text.trim(),
  );
}

Widget _field({
  required TextEditingController controller,
  required String hint,
  String? helper,
  bool numeric = false,
}) {
  return TextField(
    controller: controller,
    keyboardType: numeric ? TextInputType.number : TextInputType.text,
    decoration: InputDecoration(
      hintText: hint,
      helperText: helper,
      helperMaxLines: 2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9999),
          borderSide: const BorderSide(color: Color(0xFFD1D5DB))),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9999),
          borderSide: const BorderSide(color: Color(0xFFD1D5DB))),
    ),
    style: const TextStyle(
      fontFamily: 'Google Sans Flex',
      fontSize: 14,
      color: Color(0xFF111827),
    ),
  );
}

class _ResourceFormShell extends StatelessWidget {
  final String title;
  final VoidCallback onSave;
  final List<Widget> children;
  final Color gradeColor;

  const _ResourceFormShell({
    required this.title,
    required this.onSave,
    required this.children,
    required this.gradeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 440,
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Google Sans Flex',
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 12),
              ...children,
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 38,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9999),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 38,
                      child: ElevatedButton(
                        key: const Key('resourceDialogSave'),
                        onPressed: onSave,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: gradeColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9999),
                          ),
                        ),
                        child: const Text('Save'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
