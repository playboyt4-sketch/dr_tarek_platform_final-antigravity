import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class AddAttachmentResourceOverlay extends StatefulWidget {
  final ValueChanged<Map<String, String>>? onSaveAttachment;
  final VoidCallback? onClose;

  const AddAttachmentResourceOverlay({
    super.key,
    this.onSaveAttachment,
    this.onClose,
  });

  static Future<Map<String, String>?> show(BuildContext context) {
    return showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.25),
      builder: (context) => const AddAttachmentResourceOverlay(),
    );
  }

  @override
  State<AddAttachmentResourceOverlay> createState() => _AddAttachmentResourceOverlayState();
}

class _AddAttachmentResourceOverlayState extends State<AddAttachmentResourceOverlay> {
  late final TextEditingController _nameController;
  late final TextEditingController _orderController;

  late final FocusNode _nameFocus;
  late final FocusNode _orderFocus;

  bool _isEditingName = false;
  bool _isEditingOrder = false;

  /// Native-picked attachment (file_picker v12). Bytes are loaded via
  /// readAsBytes() into [_pickedAttachmentBytes] for the web upload path.
  PlatformFile? _pickedAttachmentFile;
  Uint8List? _pickedAttachmentBytes;
  int _pickedAttachmentSize = 0;
  bool _picking = false;
  String? _fileError;

  /// In-memory bytes for the backend storage upload.
  Uint8List? get pickedAttachmentBytes => _pickedAttachmentBytes;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: '');
    _orderController = TextEditingController(text: '');

    _nameFocus = FocusNode();
    _orderFocus = FocusNode();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _orderController.dispose();

    _nameFocus.dispose();
    _orderFocus.dispose();
    super.dispose();
  }

  static String _sanitizedBaseName(String filename) {
    var base = filename.trim();
    final int dot = base.lastIndexOf('.');
    if (dot > 0) base = base.substring(0, dot);
    base = base.replaceAll(RegExp(r'[_-]+'), ' ');
    base = base.replaceAll(RegExp(r'\s+'), ' ').trim();
    return base;
  }

  static String _formatSize(int bytes) {
    if (bytes <= 0) return '0 KB';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  Future<void> _handleUploadAttachment() async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _fileError = null;
    });
    try {
      final PlatformFile? file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const <String>[
          'pdf', 'doc', 'docx', 'xls', 'xlsx',
          'ppt', 'pptx', 'zip', 'rar', 'txt',
        ],
      );
      if (!mounted) return;
      if (file == null) {
        setState(() => _picking = false);
        return;
      }
      final int byteCount = await file.length();
      final Uint8List bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _pickedAttachmentFile = file;
        _pickedAttachmentBytes = bytes;
        _pickedAttachmentSize = byteCount;
        _picking = false;
        if (_nameController.text.trim().isEmpty) {
          final String suggestion = _sanitizedBaseName(file.name);
          if (suggestion.isNotEmpty) _nameController.text = suggestion;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _picking = false;
        _fileError = 'Could not open the file picker. Please try again.';
      });
    }
  }

  void _clearPicked() {
    setState(() {
      _pickedAttachmentFile = null;
      _pickedAttachmentBytes = null;
      _pickedAttachmentSize = 0;
    });
  }

  void _handleSave() {
    if (_pickedAttachmentFile == null) {
      setState(() => _fileError = 'Please select an attachment file first');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please select an attachment file first')),
      );
      return;
    }
    final data = {
      'title': _nameController.text.trim().isEmpty ? 'Attachment Resource' : _nameController.text.trim(),
      'order': _orderController.text.trim().isEmpty ? '01' : _orderController.text.trim(),
      'file': _pickedAttachmentFile!.name,
      'type': 'Attachment',
    };
    if (widget.onSaveAttachment != null) {
      widget.onSaveAttachment!(data);
    }
    Navigator.of(context).pop(data);
  }

  @override
  Widget build(BuildContext context) {
    // 640 x 360 (was 640 x 281): third aligned row needs
    // button (~38px) + status (~28px). Save stays 24px off bottom.
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 640,
          height: 360,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x29000000),
                blurRadius: 32,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Header Title (Add New Attachment: W: 281, H: 24)
              const Positioned(
                top: 24,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    'Add New Attachment',
                    style: TextStyle(
                      fontFamily: 'Google Sans Flex',
                      fontSize: 22,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF111827),
                    ),
                  ),
                ),
              ),

              // Close Button (top-right)
              Positioned(
                top: 18,
                right: 24,
                child: IconButton(
                  icon: const Icon(Icons.close, size: 20, color: Color(0xFF4B5563)),
                  onPressed: widget.onClose ?? () => Navigator.of(context).pop(),
                ),
              ),

              // Form Rows Container (X: 40, Y: 77, W: 560)
              Positioned(
                top: 77,
                left: 40,
                child: SizedBox(
                  width: 560,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Row 1: Attachment Name (Label 176px)
                      _buildAttachmentInputRow(
                        label: 'Attachment Name',
                        controller: _nameController,
                        focusNode: _nameFocus,
                        isEditing: _isEditingName,
                        hint: 'Attachment Title',
                        onStartEdit: () {
                          setState(() => _isEditingName = true);
                          _nameFocus.requestFocus();
                          _nameController.selection = TextSelection.fromPosition(
                            TextPosition(offset: _nameController.text.length),
                          );
                        },
                        onSaveEdit: () {
                          setState(() => _isEditingName = false);
                          _nameFocus.unfocus();
                        },
                      ),
                      const SizedBox(height: 10),

                      // Row 2: Attachment Display order (Label 176px)
                      _buildAttachmentInputRow(
                        label: 'Attachment Display order',
                        controller: _orderController,
                        focusNode: _orderFocus,
                        isEditing: _isEditingOrder,
                        hint: '01',
                        onStartEdit: () {
                          setState(() => _isEditingOrder = true);
                          _orderFocus.requestFocus();
                          _orderController.selection = TextSelection.fromPosition(
                            TextPosition(offset: _orderController.text.length),
                          );
                        },
                        onSaveEdit: () {
                          setState(() => _isEditingOrder = false);
                          _orderFocus.unfocus();
                        },
                      ),
                      const SizedBox(height: 12),

                      // Row 3: aligned grid — label 176 + gap 4 + action 380.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(
                            width: 176,
                            height: 26,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Attachment File',
                                style: TextStyle(
                                  fontFamily: 'Google Sans Flex',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                  color: Color(0xFF000000),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          SizedBox(
                            width: 380,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                InkWell(
                                  onTap: _picking
                                      ? null
                                      : _handleUploadAttachment,
                                  borderRadius:
                                      BorderRadius.circular(9999),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF111827),
                                      borderRadius:
                                          BorderRadius.circular(9999),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (_picking)
                                          const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        else
                                          const Icon(Icons.upload,
                                              size: 16,
                                              color: Colors.white),
                                        const SizedBox(width: 6),
                                        Text(
                                          _pickedAttachmentFile == null
                                              ? 'Upload Attachment'
                                              : 'Replace File',
                                          style: const TextStyle(
                                            fontFamily: 'Google Sans Flex',
                                            fontSize: 14,
                                            fontWeight: FontWeight.w400,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                if (_pickedAttachmentFile == null)
                                  const Text(
                                    'No file chosen (PDF, Word, Excel, ZIP, etc.)',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'Google Sans Flex',
                                      fontSize: 12,
                                      color: Color(0xFF6B7280),
                                    ),
                                  )
                                else
                                  Container(
                                    constraints: const BoxConstraints(
                                        maxWidth: 380),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF3F4F6),
                                      borderRadius:
                                          BorderRadius.circular(9999),
                                      border: Border.all(
                                          color: Color(0xFFE2E8F0)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.attach_file,
                                            size: 16,
                                            color: Color(0xFF111827)),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            '${_pickedAttachmentFile!.name} • ${_formatSize(_pickedAttachmentSize)}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontFamily: 'Google Sans Flex',
                                              fontSize: 12,
                                              color: Color(0xFF111827),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        InkWell(
                                          onTap: _clearPicked,
                                          borderRadius:
                                              BorderRadius.circular(9999),
                                          child: const Padding(
                                            padding: EdgeInsets.all(2),
                                            child: Icon(Icons.close,
                                                size: 14,
                                                color: Color(0xFF6B7280)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (_fileError != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    _fileError!,
                                    style: const TextStyle(
                                      fontFamily: 'Google Sans Flex',
                                      fontSize: 12,
                                      color: Color(0xFFDC2626),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Bottom Save Button (centered, 24px off bottom)
              Positioned(
                top: 308,
                left: 258,
                child: InkWell(
                  onTap: _handleSave,
                  borderRadius: BorderRadius.circular(9999),
                  child: Container(
                    width: 128,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(9999),
                    ),
                    child: const Text(
                      'Save',
                      style: TextStyle(
                        fontFamily: 'Google Sans Flex',
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAttachmentInputRow({
    required String label,
    required TextEditingController controller,
    required FocusNode focusNode,
    required bool isEditing,
    required String hint,
    required VoidCallback onStartEdit,
    required VoidCallback onSaveEdit,
  }) {
    return SizedBox(
      width: 560,
      height: 26,
      child: Row(
        children: [
          // 1. Label (Exact 176 x 26 for Attachment)
          SizedBox(
            width: 176,
            height: 26,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Google Sans Flex',
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF000000),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),

          // 2. Input Capsule (296 x 26)
          Container(
            width: 296,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: isEditing ? const Color(0xFF111827) : const Color(0xFF979797),
                width: isEditing ? 1.5 : 1.0,
              ),
            ),
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              readOnly: !isEditing,
              textAlign: TextAlign.center,
              onSubmitted: (_) => onSaveEdit(),
              style: const TextStyle(
                fontFamily: 'Google Sans Flex',
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: Color(0xFF111827),
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(
                  fontFamily: 'Google Sans Flex',
                  fontSize: 14,
                  fontWeight: FontWeight.w300,
                  color: Color(0xFF9CA3AF),
                ),
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(width: 4),

          // 3. Edit / Done Capsule Button (80 x 26)
          SizedBox(
            width: 80,
            height: 26,
            child: ElevatedButton(
              onPressed: isEditing ? onSaveEdit : onStartEdit,
              style: ElevatedButton.styleFrom(
                backgroundColor: isEditing ? const Color(0xFF111827) : Colors.black,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: const StadiumBorder(),
                padding: EdgeInsets.zero,
              ),
              child: Text(
                isEditing ? 'Done' : 'Edit',
                style: const TextStyle(
                  fontFamily: 'Google Sans Flex',
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
