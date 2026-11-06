import 'package:flutter/material.dart';

enum LectureResourceType { video, pdf, attachment, externalLink }

class AddResourceOverlay extends StatefulWidget {
  final ValueChanged<LectureResourceType>? onSelect;
  final VoidCallback? onClose;

  const AddResourceOverlay({
    super.key,
    this.onSelect,
    this.onClose,
  });

  static Future<LectureResourceType?> show(BuildContext context) {
    return showDialog<LectureResourceType>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (context) => const AddResourceOverlay(),
    );
  }

  @override
  State<AddResourceOverlay> createState() => _AddResourceOverlayState();
}

class _AddResourceOverlayState extends State<AddResourceOverlay> {
  LectureResourceType _selectedType = LectureResourceType.video;

  final List<Map<String, dynamic>> _types = [
    {'type': LectureResourceType.video, 'label': 'Video'},
    {'type': LectureResourceType.pdf, 'label': 'PDF'},
    {'type': LectureResourceType.attachment, 'label': 'Attachment'},
    {'type': LectureResourceType.externalLink, 'label': 'External Link'},
  ];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 411,
          height: 309,
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
              // Header Title (X: 78, Y: 24, W: 255, H: 24)
              Positioned(
                top: 24,
                left: 78,
                child: SizedBox(
                  width: 255,
                  height: 24,
                  child: const Center(
                    child: Text(
                      'Add New Resource',
                      style: TextStyle(
                        fontFamily: 'Google Sans Flex',
                        fontSize: 22,
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ),
                ),
              ),

              // Close Button (X: 364, Y: 24, 24x24)
              Positioned(
                top: 24,
                left: 364,
                child: InkWell(
                  onTap: widget.onClose ?? () => Navigator.of(context).pop(),
                  child: const SizedBox(
                    width: 24,
                    height: 24,
                    child: Center(
                      child: Icon(Icons.close, size: 20, color: Color(0xFF4B5563)),
                    ),
                  ),
                ),
              ),

              // Resource Types List (Frame 135: X: 50, Y: 89, W: 228, H: 126)
              Positioned(
                top: 89,
                left: 50,
                child: SizedBox(
                  width: 228,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (int i = 0; i < _types.length; i++)
                        Padding(
                          padding: EdgeInsets.only(bottom: i < _types.length - 1 ? 10 : 0),
                          child: InkWell(
                            onTap: () {
                              setState(() => _selectedType = _types[i]['type'] as LectureResourceType);
                            },
                            child: SizedBox(
                              width: 228,
                              height: 24,
                              child: Row(
                                children: [
                                  Text(
                                    _types[i]['label'] as String,
                                    style: TextStyle(
                                      fontFamily: 'Google Sans Flex',
                                      fontSize: 20,
                                      fontWeight: _selectedType == _types[i]['type']
                                          ? FontWeight.w500
                                          : FontWeight.w400,
                                      color: _selectedType == _types[i]['type']
                                          ? const Color(0xFF111827)
                                          : const Color(0xFF4B5563),
                                    ),
                                  ),
                                  const Spacer(),
                                  if (_selectedType == _types[i]['type'])
                                    const Icon(Icons.check, size: 18, color: Color(0xFF10B981)),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Save Button (Frame 83: X: 144, Y: 257, W: 124, H: 28)
              Positioned(
                top: 257,
                left: 144,
                child: InkWell(
                  onTap: () {
                    if (widget.onSelect != null) {
                      widget.onSelect!(_selectedType);
                    }
                    Navigator.of(context).pop(_selectedType);
                  },
                  borderRadius: BorderRadius.circular(9999),
                  child: Container(
                    width: 124,
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
}
