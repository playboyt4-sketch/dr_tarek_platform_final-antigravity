import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'web_file_drop.dart';

/// Standard size & extension limits for dashboard file uploads.
const int kMaxPdfUploadBytes = 50 * 1024 * 1024;
const int kMaxImageUploadBytes = 10 * 1024 * 1024;
const int kMaxAttachmentUploadBytes = 50 * 1024 * 1024;

const List<String> kAllowedPdfExtensions = <String>['pdf'];
const List<String> kAllowedImageExtensions = <String>[
  'jpg',
  'jpeg',
  'png',
  'webp',
];
const List<String> kAllowedAttachmentExtensions = <String>[
  'pdf',
  'doc',
  'docx',
  'xls',
  'xlsx',
  'ppt',
  'pptx',
  'zip',
  'rar',
  'txt',
  'jpg',
  'jpeg',
  'png',
  'webp',
];

class FileValidationResult {
  final bool isValid;
  final String? errorMessage;
  final String extension;

  const FileValidationResult.valid(this.extension)
      : isValid = true,
        errorMessage = null;

  const FileValidationResult.invalid(this.errorMessage, {this.extension = ''})
      : isValid = false;
}

/// Validates a dropped or picked file against allowed extensions and max size.
FileValidationResult validateUploadFile({
  required String fileName,
  required int byteCount,
  required List<String> allowedExtensions,
  required int maxBytes,
}) {
  final String trimmed = fileName.trim();
  final int dotIndex = trimmed.lastIndexOf('.');
  final String ext =
      dotIndex >= 0 ? trimmed.substring(dotIndex + 1).toLowerCase() : '';
  final List<String> normalizedAllowed =
      allowedExtensions.map((String e) => e.toLowerCase()).toList();

  if (ext.isEmpty || !normalizedAllowed.contains(ext)) {
    final String expected =
        normalizedAllowed.map((String e) => e.toUpperCase()).join(', ');
    return FileValidationResult.invalid(
      'صيغة الملف غير مدعومة ($expected فقط).',
      extension: ext,
    );
  }

  if (byteCount <= 0) {
    return FileValidationResult.invalid(
      'الملف المختار فارغ ولا يمكن رفعه.',
      extension: ext,
    );
  }

  if (byteCount > maxBytes) {
    final int maxMb = (maxBytes / (1024 * 1024)).round();
    return FileValidationResult.invalid(
      'حجم الملف يتجاوز الحد الأقصى المسموح ($maxMb MB).',
      extension: ext,
    );
  }

  return FileValidationResult.valid(ext);
}

/// Formats file sizes concisely (KB / MB).
String formatUploadByteSize(int bytes) {
  if (bytes <= 0) return '0 KB';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}

/// Reusable Drag & Drop + Click-to-Browse upload zone with a dashed border
/// and live drag-hover visual feedback.
class FileDropUploadZone extends StatefulWidget {
  final List<String> allowedExtensions;
  final int maxBytes;
  final Future<void> Function(DroppedFileData file) onFileAccepted;
  final ValueChanged<String?>? onErrorChanged;
  final Color accentColor;
  final String idleTitle;
  final String dragOverTitle;
  final String? subtitle;
  final String browseLabel;
  final String? selectedFileName;
  final int? selectedFileSizeBytes;
  final VoidCallback? onClear;
  final bool isUploading;
  final bool enabled;
  final bool compact;
  final String? externalError;
  final Key? browseButtonKey;

  const FileDropUploadZone({
    super.key,
    required this.allowedExtensions,
    required this.maxBytes,
    required this.onFileAccepted,
    this.onErrorChanged,
    this.accentColor = const Color(0xFF111827),
    this.idleTitle = 'اسحب وأفلت الملف هنا أو اضغط للاختيار',
    this.dragOverTitle = 'أفلت الملف هنا للرفع',
    this.subtitle,
    this.browseLabel = 'اختر ملفاً',
    this.selectedFileName,
    this.selectedFileSizeBytes,
    this.onClear,
    this.isUploading = false,
    this.enabled = true,
    this.compact = false,
    this.externalError,
    this.browseButtonKey,
  });

  @override
  State<FileDropUploadZone> createState() => FileDropUploadZoneState();
}

class FileDropUploadZoneState extends State<FileDropUploadZone> {
  final GlobalKey _zoneKey = GlobalKey();
  WebDropRegistration? _dropRegistration;
  bool _isDraggingOver = false;
  bool _busyLocal = false;
  String? _localError;

  bool get isDraggingOver => _isDraggingOver;

  bool get _isBusy => widget.isUploading || _busyLocal;

  @override
  void initState() {
    super.initState();
    _dropRegistration = registerWebFileDropTarget(
      hitTest: _containsPoint,
      onDragOverChanged: setDraggingOver,
      onDrop: handleDroppedFile,
    );
  }

  @override
  void dispose() {
    _dropRegistration?.dispose();
    _dropRegistration = null;
    super.dispose();
  }

  bool _containsPoint(double clientX, double clientY) {
    if (!mounted || !widget.enabled) return false;
    final RenderBox? box =
        _zoneKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) return false;
    final Offset topLeft = box.localToGlobal(Offset.zero);
    final Rect bounds = topLeft & box.size;
    return bounds.contains(Offset(clientX, clientY));
  }

  /// Updates the visual drag-hover state (public for widget testing).
  void setDraggingOver(bool over) {
    if (!mounted) return;
    if (!widget.enabled || _isBusy) {
      if (_isDraggingOver) {
        setState(() => _isDraggingOver = false);
      }
      return;
    }
    if (_isDraggingOver == over) return;
    setState(() => _isDraggingOver = over);
  }

  void _reportError(String? message) {
    if (mounted) {
      setState(() => _localError = message);
    }
    widget.onErrorChanged?.call(message);
  }

  /// Validates and forwards a dropped file (public for widget testing).
  Future<void> handleDroppedFile(DroppedFileData file) async {
    if (!mounted || !widget.enabled || _isBusy) return;

    final FileValidationResult validation = validateUploadFile(
      fileName: file.name,
      byteCount: file.sizeBytes,
      allowedExtensions: widget.allowedExtensions,
      maxBytes: widget.maxBytes,
    );

    if (!validation.isValid) {
      _reportError(validation.errorMessage);
      return;
    }

    _reportError(null);
    setState(() => _busyLocal = true);
    try {
      await widget.onFileAccepted(file);
    } finally {
      if (mounted) {
        setState(() => _busyLocal = false);
      }
    }
  }

  Future<void> _pickFileManually() async {
    if (!widget.enabled || _isBusy) return;
    _reportError(null);
    setState(() => _busyLocal = true);
    try {
      final PlatformFile? file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: widget.allowedExtensions,
      );
      if (!mounted || file == null) return;

      final int byteCount = await file.length();
      if (!mounted) return;
      final FileValidationResult prelim = validateUploadFile(
        fileName: file.name,
        byteCount: byteCount,
        allowedExtensions: widget.allowedExtensions,
        maxBytes: widget.maxBytes,
      );
      if (!prelim.isValid) {
        _reportError(prelim.errorMessage);
        return;
      }

      final Uint8List bytes = await file.readAsBytes();
      if (!mounted) return;
      await widget.onFileAccepted(
        DroppedFileData(
          name: file.name,
          sizeBytes: bytes.length,
          bytes: bytes,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      _reportError('تعذر فتح نافذة اختيار الملف. حاول مرة أخرى.');
    } finally {
      if (mounted) {
        setState(() => _busyLocal = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? effectiveError = widget.externalError ?? _localError;
    final Color borderColor = _isDraggingOver
        ? widget.accentColor
        : effectiveError != null
            ? const Color(0xFFDC2626)
            : const Color(0xFFD1D5DB);
    final Color fillColor = _isDraggingOver
        ? widget.accentColor.withValues(alpha: 0.08)
        : const Color(0xFFF9FAFB);

    final bool hasSelected =
        widget.selectedFileName != null && widget.selectedFileName!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Semantics(
          button: true,
          label: widget.browseLabel,
          child: InkWell(
            key: const Key('file-drop-zone-surface'),
            onTap: (widget.enabled && !_isBusy) ? _pickFileManually : null,
            borderRadius: BorderRadius.circular(12),
            child: CustomPaint(
              key: _zoneKey,
              painter: _DashedRRectPainter(
                color: borderColor,
                strokeWidth: _isDraggingOver ? 2.0 : 1.4,
                radius: 12,
                dashLength: 6,
                gapLength: 4,
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding: EdgeInsets.symmetric(
                  horizontal: widget.compact ? 12 : 16,
                  vertical: widget.compact ? 10 : 14,
                ),
                decoration: BoxDecoration(
                  color: fillColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: widget.compact
                    ? _buildCompactBody(context)
                    : _buildRegularBody(context),
              ),
            ),
          ),
        ),
        if (hasSelected) ...<Widget>[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(9999),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.insert_drive_file_outlined,
                  size: 16,
                  color: widget.accentColor,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    widget.selectedFileSizeBytes != null &&
                            widget.selectedFileSizeBytes! > 0
                        ? '${widget.selectedFileName!} • ${formatUploadByteSize(widget.selectedFileSizeBytes!)}'
                        : widget.selectedFileName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Google Sans Flex',
                      fontSize: 12,
                      color: Color(0xFF111827),
                    ),
                  ),
                ),
                if (widget.onClear != null && !_isBusy) ...<Widget>[
                  const SizedBox(width: 4),
                  InkWell(
                    key: const Key('file-drop-zone-clear'),
                    onTap: widget.onClear,
                    borderRadius: BorderRadius.circular(9999),
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(
                        Icons.close,
                        size: 14,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (effectiveError != null && effectiveError.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            effectiveError,
            key: const Key('file-drop-zone-error'),
            style: const TextStyle(
              fontFamily: 'Google Sans Flex',
              fontSize: 12,
              color: Color(0xFFDC2626),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRegularBody(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (_isBusy)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: widget.accentColor,
                ),
              )
            else
              Icon(
                _isDraggingOver
                    ? Icons.file_download_outlined
                    : Icons.cloud_upload_outlined,
                size: 22,
                color: _isDraggingOver
                    ? widget.accentColor
                    : const Color(0xFF4B5563),
              ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _isBusy
                    ? 'جارٍ المعالجة والرفع...'
                    : _isDraggingOver
                        ? widget.dragOverTitle
                        : widget.idleTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Google Sans Flex',
                  fontSize: 13,
                  fontWeight:
                      _isDraggingOver ? FontWeight.w600 : FontWeight.w500,
                  color: _isDraggingOver
                      ? widget.accentColor
                      : const Color(0xFF111827),
                ),
              ),
            ),
          ],
        ),
        if (widget.subtitle != null && !_isDraggingOver) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            widget.subtitle!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Google Sans Flex',
              fontSize: 11.5,
              color: Color(0xFF6B7280),
            ),
          ),
        ],
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: widget.browseButtonKey ??
              const Key('file-drop-zone-browse-button'),
          onPressed: (widget.enabled && !_isBusy) ? _pickFileManually : null,
          icon: Icon(
            Icons.upload_file_outlined,
            size: 16,
            color: widget.accentColor,
          ),
          label: Text(
            widget.browseLabel,
            style: TextStyle(
              fontFamily: 'Google Sans Flex',
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: widget.accentColor,
            ),
          ),
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            side: BorderSide(color: widget.accentColor),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9999),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactBody(BuildContext context) {
    return Row(
      children: <Widget>[
        if (_isBusy)
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: widget.accentColor,
            ),
          )
        else
          Icon(
            _isDraggingOver
                ? Icons.file_download_outlined
                : Icons.cloud_upload_outlined,
            size: 20,
            color: _isDraggingOver
                ? widget.accentColor
                : const Color(0xFF4B5563),
          ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                _isBusy
                    ? 'جارٍ الرفع...'
                    : _isDraggingOver
                        ? widget.dragOverTitle
                        : widget.idleTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Google Sans Flex',
                  fontSize: 12.5,
                  fontWeight:
                      _isDraggingOver ? FontWeight.w600 : FontWeight.w500,
                  color: _isDraggingOver
                      ? widget.accentColor
                      : const Color(0xFF111827),
                ),
              ),
              if (widget.subtitle != null && !_isDraggingOver)
                Text(
                  widget.subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Google Sans Flex',
                    fontSize: 11,
                    color: Color(0xFF6B7280),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          key: widget.browseButtonKey ??
              const Key('file-drop-zone-browse-button'),
          onPressed: (widget.enabled && !_isBusy) ? _pickFileManually : null,
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            side: BorderSide(color: widget.accentColor),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9999),
            ),
          ),
          child: Text(
            widget.browseLabel,
            style: TextStyle(
              fontFamily: 'Google Sans Flex',
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: widget.accentColor,
            ),
          ),
        ),
      ],
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double radius;
  final double dashLength;
  final double gapLength;

  const _DashedRRectPainter({
    required this.color,
    required this.strokeWidth,
    required this.radius,
    required this.dashLength,
    required this.gapLength,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final RRect rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final Path source = Path()..addRRect(rrect);
    final Path dashed = Path();

    for (final metric in source.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final double next = math.min(distance + dashLength, metric.length);
        dashed.addPath(metric.extractPath(distance, next), Offset.zero);
        distance += dashLength + gapLength;
      }
    }

    canvas.drawPath(dashed, paint);
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.radius != radius;
  }
}
