import 'package:flutter/material.dart';

import '../../../../core/utils/storage_upload_helper.dart';
import '../../../../core/widgets/file_drop_upload_zone.dart';
import '../../../../core/widgets/web_file_drop.dart';

/// Capsule URL text field paired with a Drag & Drop + Click-to-Browse upload
/// zone for subject covers (`jpg`, `jpeg`, `png`, `webp`, max 10 MB) stored
/// under `subjects/covers/...` in Firebase Storage. Manual URL entry/pasting
/// remains supported alongside direct upload.
class SubjectCoverUrlField extends StatefulWidget {
  final TextEditingController controller;
  final Color accentColor;
  final VoidCallback? onSubmitted;
  final ValueChanged<bool>? onUploadingChanged;
  final ValueChanged<String?>? onErrorChanged;

  const SubjectCoverUrlField({
    super.key,
    required this.controller,
    required this.accentColor,
    this.onSubmitted,
    this.onUploadingChanged,
    this.onErrorChanged,
  });

  @override
  State<SubjectCoverUrlField> createState() => _SubjectCoverUrlFieldState();
}

class _SubjectCoverUrlFieldState extends State<SubjectCoverUrlField> {
  bool _uploading = false;
  String? _selectedFileName;
  int? _selectedFileSize;

  Future<void> _handleAcceptedImage(DroppedFileData file) async {
    widget.onErrorChanged?.call(null);
    setState(() => _uploading = true);
    widget.onUploadingChanged?.call(true);

    try {
      final String downloadUrl = await uploadDashboardFileToStorage(
        folder: 'subjects/covers',
        file: file,
      );
      if (!mounted) return;

      widget.controller.text = downloadUrl;
      setState(() {
        _selectedFileName = file.name;
        _selectedFileSize = file.sizeBytes;
      });
      widget.onErrorChanged?.call(null);
    } catch (_) {
      if (!mounted) return;
      widget.onErrorChanged?.call(
        'Could not upload subject cover image. Please try again.',
      );
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
      widget.onUploadingChanged?.call(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 36,
          child: TextField(
            controller: widget.controller,
            textInputAction: TextInputAction.done,
            onSubmitted:
                widget.onSubmitted != null ? (_) => widget.onSubmitted!() : null,
            decoration: InputDecoration(
              hintText: 'https://... or drag & drop image below',
              hintStyle: const TextStyle(
                fontFamily: 'Google Sans Flex',
                fontSize: 13,
                color: Color(0xFF9CA3AF),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9999),
                borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9999),
                borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9999),
                borderSide: BorderSide(color: widget.accentColor),
              ),
            ),
            style: const TextStyle(
              fontFamily: 'Google Sans Flex',
              fontSize: 14,
              color: Color(0xFF111827),
            ),
          ),
        ),
        const SizedBox(height: 8),
        FileDropUploadZone(
          allowedExtensions: kAllowedImageExtensions,
          maxBytes: kMaxImageUploadBytes,
          accentColor: widget.accentColor,
          compact: true,
          isUploading: _uploading,
          idleTitle: 'اسحب وأفلت صورة البوستر هنا أو اضغط للاختيار',
          dragOverTitle: 'أفلت الملف هنا للرفع',
          subtitle: 'JPG, JPEG, PNG, WEBP • الحد الأقصى 10MB',
          browseLabel: 'Upload Image',
          browseButtonKey: const Key('upload-subject-cover-button'),
          selectedFileName: _selectedFileName,
          selectedFileSizeBytes: _selectedFileSize,
          onClear: _selectedFileName == null
              ? null
              : () => setState(() {
                    _selectedFileName = null;
                    _selectedFileSize = null;
                  }),
          onFileAccepted: _handleAcceptedImage,
          onErrorChanged: widget.onErrorChanged,
        ),
      ],
    );
  }
}
