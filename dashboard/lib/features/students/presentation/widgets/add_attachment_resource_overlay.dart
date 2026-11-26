import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/widgets/file_drop_upload_zone.dart';
import '../../../../core/widgets/web_file_drop.dart';

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
      barrierColor: Colors.black.withValues(alpha: 0.25),
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

  String? _pickedAttachmentName;
  Uint8List? _pickedAttachmentBytes;
  int _pickedAttachmentSize = 0;
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

  Future<void> _acceptAttachment(DroppedFileData file) async {
    setState(() {
      _pickedAttachmentName = file.name;
      _pickedAttachmentBytes = file.bytes;
      _pickedAttachmentSize = file.sizeBytes;
      _fileError = null;
      if (_nameController.text.trim().isEmpty) {
        final String suggestion = _sanitizedBaseName(file.name);
        if (suggestion.isNotEmpty) _nameController.text = suggestion;
      }
    });
  }

  void _clearPicked() {
    setState(() {
      _pickedAttachmentName = null;
      _pickedAttachmentBytes = null;
      _pickedAttachmentSize = 0;
    });
  }

  void _handleSave() {
    if (_pickedAttachmentName == null) {
      setState(() => _fileError = 'Please select an attachment file first');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please select an attachment file first')),
      );
      return;
    }
    final data = {
      'title': _nameController.text.trim().isEmpty
          ? 'Attachment Resource'
          : _nameController.text.trim(),
      'order': _orderController.text.trim().isEmpty
          ? '01'
          : _orderController.text.trim(),
      'file': _pickedAttachmentName!,
      'type': 'Attachment',
    };
    if (widget.onSaveAttachment != null) {
      widget.onSaveAttachment!(data);
    }
    Navigator.of(context).pop(data);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 22),
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
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        const Center(
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
                        Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            icon: const Icon(Icons.close,
                                size: 20, color: Color(0xFF4B5563)),
                            onPressed: widget.onClose ??
                                () => Navigator.of(context).pop(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
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
                    // Row 3: Attachment File Drag & Drop
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(
                          width: 176,
                          child: Padding(
                            padding: EdgeInsets.only(top: 10),
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
                        Expanded(
                          child: FileDropUploadZone(
                            allowedExtensions: kAllowedAttachmentExtensions,
                            maxBytes: kMaxAttachmentUploadBytes,
                            accentColor: const Color(0xFF111827),
                            compact: true,
                            idleTitle:
                                'اسحب وأفلت المرفق هنا أو اضغط للاختيار',
                            dragOverTitle: 'أفلت الملف هنا للرفع',
                            subtitle:
                                'PDF, Word, Excel, PowerPoint, ZIP, صور • الحد الأقصى 50MB',
                            browseLabel: _pickedAttachmentName == null
                                ? 'Upload Attachment'
                                : 'Replace File',
                            selectedFileName: _pickedAttachmentName,
                            selectedFileSizeBytes: _pickedAttachmentSize > 0
                                ? _pickedAttachmentSize
                                : null,
                            onClear: _pickedAttachmentName == null
                                ? null
                                : _clearPicked,
                            externalError: _fileError,
                            onErrorChanged: (String? err) =>
                                setState(() => _fileError = err),
                            onFileAccepted: _acceptAttachment,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    InkWell(
                      onTap: _handleSave,
                      borderRadius: BorderRadius.circular(9999),
                      child: Container(
                        width: 128,
                        height: 34,
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
                  ],
                ),
              ),
            ),
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
