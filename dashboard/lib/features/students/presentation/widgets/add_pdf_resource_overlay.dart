import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/widgets/file_drop_upload_zone.dart';
import '../../../../core/widgets/web_file_drop.dart';

class AddPdfResourceOverlay extends StatefulWidget {
  final ValueChanged<Map<String, String>>? onSavePdf;
  final VoidCallback? onClose;

  const AddPdfResourceOverlay({
    super.key,
    this.onSavePdf,
    this.onClose,
  });

  static Future<Map<String, String>?> show(BuildContext context) {
    return showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (context) => const AddPdfResourceOverlay(),
    );
  }

  @override
  State<AddPdfResourceOverlay> createState() => _AddPdfResourceOverlayState();
}

class _AddPdfResourceOverlayState extends State<AddPdfResourceOverlay> {
  late final TextEditingController _nameController;
  late final TextEditingController _orderController;

  late final FocusNode _nameFocus;
  late final FocusNode _orderFocus;

  bool _isEditingName = false;
  bool _isEditingOrder = false;

  String? _pickedPdfName;
  Uint8List? _pickedPdfBytes;
  int _pickedPdfSize = 0;
  String? _fileError;

  /// In-memory PDF bytes for the backend storage upload.
  Uint8List? get pickedPdfBytes => _pickedPdfBytes;

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
    if (base.toLowerCase().endsWith('.pdf')) {
      base = base.substring(0, base.length - 4);
    }
    base = base.replaceAll(RegExp(r'[_-]+'), ' ');
    base = base.replaceAll(RegExp(r'\s+'), ' ').trim();
    return base;
  }

  Future<void> _acceptPdf(DroppedFileData file) async {
    setState(() {
      _pickedPdfName = file.name;
      _pickedPdfBytes = file.bytes;
      _pickedPdfSize = file.sizeBytes;
      _fileError = null;
      if (_nameController.text.trim().isEmpty) {
        final String suggestion = _sanitizedBaseName(file.name);
        if (suggestion.isNotEmpty) _nameController.text = suggestion;
      }
    });
  }

  void _clearPicked() {
    setState(() {
      _pickedPdfName = null;
      _pickedPdfBytes = null;
      _pickedPdfSize = 0;
    });
  }

  void _handleSave() {
    if (_pickedPdfName == null) {
      setState(() => _fileError = 'Please select a PDF file first');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a PDF file first')),
      );
      return;
    }
    final data = {
      'title': _nameController.text.trim().isEmpty
          ? 'PDF Resource'
          : _nameController.text.trim(),
      'order': _orderController.text.trim().isEmpty
          ? '01'
          : _orderController.text.trim(),
      'file': _pickedPdfName!,
      'type': 'PDF',
    };
    if (widget.onSavePdf != null) {
      widget.onSavePdf!(data);
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
                            'Add New PDF',
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
                    // Row 1: PDF Name
                    _buildPdfInputRow(
                      label: 'PDF Name',
                      controller: _nameController,
                      focusNode: _nameFocus,
                      isEditing: _isEditingName,
                      hint: 'PDF Title',
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
                    // Row 2: PDF Display order
                    _buildPdfInputRow(
                      label: 'PDF Display order',
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
                    // Row 3: PDF File Drag & Drop
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(
                          width: 168,
                          child: Padding(
                            padding: EdgeInsets.only(top: 10),
                            child: Text(
                              'PDF File',
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
                            allowedExtensions: kAllowedPdfExtensions,
                            maxBytes: kMaxPdfUploadBytes,
                            accentColor: const Color(0xFF111827),
                            compact: true,
                            idleTitle:
                                'اسحب وأفلت ملف الـ PDF هنا أو اضغط للاختيار',
                            dragOverTitle: 'أفلت الملف هنا للرفع',
                            subtitle: 'PDF فقط • الحد الأقصى 50MB',
                            browseLabel: _pickedPdfName == null
                                ? 'Upload PDF'
                                : 'Replace PDF',
                            selectedFileName: _pickedPdfName,
                            selectedFileSizeBytes:
                                _pickedPdfSize > 0 ? _pickedPdfSize : null,
                            onClear: _pickedPdfName == null ? null : _clearPicked,
                            externalError: _fileError,
                            onErrorChanged: (String? err) =>
                                setState(() => _fileError = err),
                            onFileAccepted: _acceptPdf,
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

  Widget _buildPdfInputRow({
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
          // 1. Label: 168 x 26
          SizedBox(
            width: 168,
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

          // 2. Input Capsule: 304 x 26
          Container(
            width: 304,
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

          // 3. Edit / Done Capsule Button: 80 x 26
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
