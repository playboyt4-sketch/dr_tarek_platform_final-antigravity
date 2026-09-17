import 'package:flutter/material.dart';

class AddExternalLinkResourceOverlay extends StatefulWidget {
  final ValueChanged<Map<String, String>>? onSaveLink;
  final VoidCallback? onClose;

  const AddExternalLinkResourceOverlay({
    super.key,
    this.onSaveLink,
    this.onClose,
  });

  static Future<Map<String, String>?> show(BuildContext context) {
    return showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.25),
      builder: (context) => const AddExternalLinkResourceOverlay(),
    );
  }

  @override
  State<AddExternalLinkResourceOverlay> createState() => _AddExternalLinkResourceOverlayState();
}

class _AddExternalLinkResourceOverlayState extends State<AddExternalLinkResourceOverlay> {
  late final TextEditingController _nameController;
  late final TextEditingController _orderController;
  late final TextEditingController _urlController;

  late final FocusNode _nameFocus;
  late final FocusNode _orderFocus;
  late final FocusNode _urlFocus;

  bool _isEditingName = false;
  bool _isEditingOrder = false;
  bool _isEditingUrl = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: '');
    _orderController = TextEditingController(text: '');
    _urlController = TextEditingController(text: '');

    _nameFocus = FocusNode();
    _orderFocus = FocusNode();
    _urlFocus = FocusNode();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _orderController.dispose();
    _urlController.dispose();

    _nameFocus.dispose();
    _orderFocus.dispose();
    _urlFocus.dispose();
    super.dispose();
  }

  void _handleSave() {
    final data = {
      'title': _nameController.text.trim().isEmpty ? 'External Link' : _nameController.text.trim(),
      'order': _orderController.text.trim().isEmpty ? '01' : _orderController.text.trim(),
      'url': _urlController.text.trim(),
      'type': 'External Link',
    };
    if (widget.onSaveLink != null) {
      widget.onSaveLink!(data);
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
              // Header Title (Add New External Link: W: 299, H: 24)
              Positioned(
                top: 24,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    'Add New External Link',
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

              // Form Rows Container (Frame 586px Centered at X: 27, Y: 77)
              Positioned(
                top: 77,
                left: 27,
                child: SizedBox(
                  width: 586,
                  child: Column(
                    children: [
                      // Row 1: External Link Name
                      _buildLinkInputRow(
                        label: 'External Link Name',
                        controller: _nameController,
                        focusNode: _nameFocus,
                        isEditing: _isEditingName,
                        hint: 'Link Name',
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

                      // Row 2: External Link Display order
                      _buildLinkInputRow(
                        label: 'External Link Display order',
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

                      // Row 3: External Link URL
                      _buildLinkInputRow(
                        label: 'External Link URL',
                        controller: _urlController,
                        focusNode: _urlFocus,
                        isEditing: _isEditingUrl,
                        hint: 'https://...',
                        onStartEdit: () {
                          setState(() => _isEditingUrl = true);
                          _urlFocus.requestFocus();
                          _urlController.selection = TextSelection.fromPosition(
                            TextPosition(offset: _urlController.text.length),
                          );
                        },
                        onSaveEdit: () {
                          setState(() => _isEditingUrl = false);
                          _urlFocus.unfocus();
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

  Widget _buildLinkInputRow({
    required String label,
    required TextEditingController controller,
    required FocusNode focusNode,
    required bool isEditing,
    required String hint,
    required VoidCallback onStartEdit,
    required VoidCallback onSaveEdit,
  }) {
    return SizedBox(
      width: 586,
      height: 26,
      child: Row(
        children: [
          // 1. Label: Exact 180 x 26
          SizedBox(
            width: 180,
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
          const SizedBox(width: 6),

          // 2. Input Capsule: 316 x 26
          Container(
            width: 316,
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
