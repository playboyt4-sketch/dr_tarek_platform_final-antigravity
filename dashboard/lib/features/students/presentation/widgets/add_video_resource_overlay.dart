import 'package:flutter/material.dart';

/// VIDEO-ID-ONLY: bare Bunny GUID only — URLs are rejected.
bool isValidBunnyVideoId(String raw) {
  return RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(raw.trim());
}

class AddVideoResourceOverlay extends StatefulWidget {
  final ValueChanged<Map<String, String>>? onSaveVideo;
  final VoidCallback? onClose;

  const AddVideoResourceOverlay({
    super.key,
    this.onSaveVideo,
    this.onClose,
  });

  static Future<Map<String, String>?> show(BuildContext context) {
    return showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.25),
      builder: (context) => const AddVideoResourceOverlay(),
    );
  }

  @override
  State<AddVideoResourceOverlay> createState() => _AddVideoResourceOverlayState();
}

class _AddVideoResourceOverlayState extends State<AddVideoResourceOverlay> {
  late final TextEditingController _nameController;
  late final TextEditingController _orderController;
  late final TextEditingController _idController;

  late final FocusNode _nameFocus;
  late final FocusNode _orderFocus;
  late final FocusNode _idFocus;

  bool _isEditingName = false;
  bool _isEditingOrder = false;
  bool _isEditingId = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: '');
    _orderController = TextEditingController(text: '');
    _idController = TextEditingController(text: '');

    _nameFocus = FocusNode();
    _orderFocus = FocusNode();
    _idFocus = FocusNode();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _orderController.dispose();
    _idController.dispose();

    _nameFocus.dispose();
    _orderFocus.dispose();
    _idFocus.dispose();
    super.dispose();
  }

  void _handleSave() {
    final String vid = _idController.text.trim();
    if (vid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Video ID is required.')),
      );
      return;
    }
    if (!isValidBunnyVideoId(vid)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('الصق الـ Video ID فقط (GUID) — الروابط غير مقبولة.')),
      );
      return;
    }
    final data = {
      'title': _nameController.text.trim().isEmpty ? 'Video' : _nameController.text.trim(),
      'order': _orderController.text.trim().isEmpty ? '01' : _orderController.text.trim(),
      'id': vid,
      'type': 'Video',
    };
    if (widget.onSaveVideo != null) {
      widget.onSaveVideo!(data);
    }
    Navigator.of(context).pop(data);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 640,
          height: 281,
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
              // Header Title (X: 200, Y: 24, W: 240, H: 24)
              Positioned(
                top: 24,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    'Add New Video',
                    style: const TextStyle(
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

              // Form Rows Container (Frame 'Video details': X: 40, Y: 77, W: 560)
              Positioned(
                top: 77,
                left: 40,
                child: SizedBox(
                  width: 560,
                  child: Column(
                    children: [
                      // Row 1: Video Name
                      _buildVideoInputRow(
                        label: 'Video Name',
                        controller: _nameController,
                        focusNode: _nameFocus,
                        isEditing: _isEditingName,
                        hint: 'Video Title',
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

                      // Row 2: Video Display order
                      _buildVideoInputRow(
                        label: 'Video Display order',
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
                      const SizedBox(height: 10),

                      // Row 3: Video ID
                      _buildVideoInputRow(
                        label: 'Video ID',
                        controller: _idController,
                        focusNode: _idFocus,
                        isEditing: _isEditingId,
                        hint: 'bunny-video-id',
                        onStartEdit: () {
                          setState(() => _isEditingId = true);
                          _idFocus.requestFocus();
                          _idController.selection = TextSelection.fromPosition(
                            TextPosition(offset: _idController.text.length),
                          );
                        },
                        onSaveEdit: () {
                          setState(() => _isEditingId = false);
                          _idFocus.unfocus();
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // Bottom Save Button (X: 258, Y: 229, W: 128, H: 28)
              Positioned(
                top: 229,
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

  Widget _buildVideoInputRow({
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
