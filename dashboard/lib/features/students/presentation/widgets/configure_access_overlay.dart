import 'package:flutter/material.dart';

class StudentAccessItem {
  final String id;
  final String name;
  final String studentCode;
  bool hasAccess;

  StudentAccessItem({
    required this.id,
    required this.name,
    required this.studentCode,
    this.hasAccess = true,
  });
}

class ConfigureAccessOverlay extends StatefulWidget {
  final String gradeKey;
  final List<String>? initialAllowedStudentIds;
  final ValueChanged<List<String>>? onSaveAccess;
  final VoidCallback? onClose;

  const ConfigureAccessOverlay({
    super.key,
    required this.gradeKey,
    this.initialAllowedStudentIds,
    this.onSaveAccess,
    this.onClose,
  });

  static Future<List<String>?> show(
    BuildContext context, {
    required String gradeKey,
    List<String>? initialAllowedStudentIds,
  }) {
    return showDialog<List<String>>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (context) => ConfigureAccessOverlay(
        gradeKey: gradeKey,
        initialAllowedStudentIds: initialAllowedStudentIds,
      ),
    );
  }

  @override
  State<ConfigureAccessOverlay> createState() => _ConfigureAccessOverlayState();
}

class _ConfigureAccessOverlayState extends State<ConfigureAccessOverlay> {
  late final TextEditingController _searchController;
  String _searchQuery = '';

  // Sample mock students list for the grade (replaces with provider data if available)
  late List<StudentAccessItem> _students;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();

    _students = [
      StudentAccessItem(id: 'std_1', name: 'أحمد محمد علي', studentCode: '20260101'),
      StudentAccessItem(id: 'std_2', name: 'محمود إبراهيم حسن', studentCode: '20260102'),
      StudentAccessItem(id: 'std_3', name: 'سارة عبد الله يوسف', studentCode: '20260103'),
      StudentAccessItem(id: 'std_4', name: 'عمر خالد المنشاوي', studentCode: '20260104'),
      StudentAccessItem(id: 'std_5', name: 'فاطمة طارق العربي', studentCode: '20260105'),
      StudentAccessItem(id: 'std_6', name: 'يوسف أحمد سعيد', studentCode: '20260106'),
    ];

    if (widget.initialAllowedStudentIds != null) {
      for (var s in _students) {
        s.hasAccess = widget.initialAllowedStudentIds!.contains(s.id);
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _allSelected => _students.every((s) => s.hasAccess);

  void _toggleAll(bool value) {
    setState(() {
      for (var s in _students) {
        s.hasAccess = value;
      }
    });
  }

  void _handleSave() {
    final allowedIds = _students.where((s) => s.hasAccess).map((s) => s.id).toList();
    if (widget.onSaveAccess != null) {
      widget.onSaveAccess!(allowedIds);
    }
    Navigator.of(context).pop(allowedIds);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _students.where((s) {
      if (_searchQuery.isEmpty) return true;
      return s.name.contains(_searchQuery) || s.studentCode.contains(_searchQuery);
    }).toList();

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 640,
          height: 520,
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
          child: Column(
            children: [
              // Top Header
              Padding(
                padding: const EdgeInsets.only(left: 36, right: 24, top: 20, bottom: 12),
                child: Row(
                  children: [
                    const Spacer(),
                    const Text(
                      'Configure Access',
                      style: TextStyle(
                        fontFamily: 'Google Sans Flex',
                        fontSize: 22,
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20, color: Color(0xFF4B5563)),
                      onPressed: widget.onClose ?? () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Search & Select All Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Row(
                  children: [
                    // Search box
                    Expanded(
                      child: Container(
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: const Color(0xFFD1D5DB), width: 1.0),
                        ),
                        child: TextField(
                          controller: _searchController,
                          onChanged: (val) => setState(() => _searchQuery = val.trim()),
                          style: const TextStyle(fontFamily: 'Google Sans Flex', fontSize: 13),
                          decoration: const InputDecoration(
                            hintText: 'بحث باسم الطالب أو الكود...',
                            hintStyle: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 6),
                            border: InputBorder.none,
                            prefixIcon: Icon(Icons.search, size: 16, color: Color(0xFF9CA3AF)),
                            prefixIconConstraints: BoxConstraints(minWidth: 24, maxHeight: 16),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Select All Toggle
                    Row(
                      children: [
                        const Text(
                          'منح الكل',
                          style: TextStyle(fontFamily: 'Google Sans Flex', fontSize: 13, color: Color(0xFF374151)),
                        ),
                        const SizedBox(width: 8),
                        _buildStudentToggle(
                          value: _allSelected,
                          onChanged: _toggleAll,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),

              // Students List
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 8),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFFF3F4F6)),
                  itemBuilder: (context, index) {
                    final student = filtered[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: const Color(0xFFF3F4F6),
                            child: Text(
                              student.name.isNotEmpty ? student.name[0] : 'S',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF374151)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                student.name,
                                style: const TextStyle(
                                  fontFamily: 'Google Sans Flex',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                  color: Color(0xFF111827),
                                ),
                              ),
                              Text(
                                'كود: ${student.studentCode}',
                                style: const TextStyle(
                                  fontFamily: 'Google Sans Flex',
                                  fontSize: 11,
                                  color: Color(0xFF9CA3AF),
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          // Toggle Switch for this student
                          _buildStudentToggle(
                            value: student.hasAccess,
                            onChanged: (val) {
                              setState(() => student.hasAccess = val);
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              const SizedBox(height: 12),

              // Bottom Save Button (124 x 28)
              Center(
                child: SizedBox(
                  width: 124,
                  height: 28,
                  child: ElevatedButton(
                    onPressed: _handleSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: const StadiumBorder(),
                      padding: EdgeInsets.zero,
                    ),
                    child: const Text(
                      'Save',
                      style: TextStyle(
                        fontFamily: 'Google Sans Flex',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStudentToggle({required bool value, required ValueChanged<bool> onChanged}) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        width: 48,
        height: 24,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: value ? const Color(0xFF10B981) : const Color(0xFFE5E7EB),
          borderRadius: BorderRadius.circular(100),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 150),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}
