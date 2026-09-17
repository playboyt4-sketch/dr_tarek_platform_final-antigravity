import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'grade_theme.dart';

/// Figma `edit subject overlay` — same chrome as `AddSubjectOverlay`.
///
/// - 1120x316, white 100%, radius 16, No Stroke, shadow black12
///   blur 30 offset (0,8).
/// - Header: `Edit Subject` centered 20 Medium 500 #111827 + close X.
/// - 3 rows in order: Grade (dropdown, current grade pre-selected,
///   values from [GradeTheme]) / Subject Name (prefilled, editable) /
///   Subject Cover URL (prefilled from the existing `cover_url` field).
/// - Save: 130x38 pill gradeColor, white Save 16, centered bottom.
///
/// Pure presentation: persistence arrives via [onSave] (the screen wires
/// it to [SubjectDetailsController.updateSubject]), so this widget never
/// touches Firestore. Validation is limited to the approved minimum:
/// non-empty trimmed name; grade comes from the dropdown so it is always
/// a canonical grade. There is no project URL-validation convention for
/// cover URLs (the add overlay accepts any string), so none is invented.
class EditSubjectOverlay extends ConsumerStatefulWidget {
  final String gradeKey;
  final String initialTitle;
  final String initialCoverUrl;
  final Color gradeColor;
  final Future<void> Function({
    required String gradeKey,
    required String title,
    required String coverUrl,
  }) onSave;

  const EditSubjectOverlay({
    super.key,
    required this.gradeKey,
    required this.initialTitle,
    required this.initialCoverUrl,
    required this.gradeColor,
    required this.onSave,
  });

  /// Opens the overlay centered with a black 25% backdrop; closes on
  /// outside tap or the X control. Returns true when the save succeeded.
  static Future<bool?> show(
    BuildContext context, {
    required String gradeKey,
    required String initialTitle,
    required String initialCoverUrl,
    required Color gradeColor,
    required Future<void> Function({
      required String gradeKey,
      required String title,
      required String coverUrl,
    }) onSave,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (BuildContext context) => EditSubjectOverlay(
        gradeKey: gradeKey,
        initialTitle: initialTitle,
        initialCoverUrl: initialCoverUrl,
        gradeColor: gradeColor,
        onSave: onSave,
      ),
    );
  }

  @override
  ConsumerState<EditSubjectOverlay> createState() =>
      _EditSubjectOverlayState();
}

class _EditSubjectOverlayState extends ConsumerState<EditSubjectOverlay> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.initialTitle);
  late final TextEditingController _urlController =
      TextEditingController(text: widget.initialCoverUrl);
  late String _selectedGradeKey = widget.gradeKey;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter the subject name.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        gradeKey: _selectedGradeKey,
        title: name,
        coverUrl: _urlController.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not save. Try again.';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 1120,
          height: 316,
          padding:
              const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 30,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: 0,
                top: 0,
                child: IconButton(
                  onPressed: _saving
                      ? null
                      : () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close,
                      color: Color(0xFF6B7280)),
                ),
              ),
              Column(
                children: [
                  const Text(
                    'Edit Subject',
                    style: TextStyle(
                      fontFamily: 'Google Sans Flex',
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildRow(
                    'Grade',
                    Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16),
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(9999),
                        border: Border.all(
                            color: const Color(0xFFD1D5DB)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedGradeKey,
                          isExpanded: true,
                          icon: const Icon(
                              Icons.keyboard_arrow_down,
                              size: 18,
                              color: Color(0xFF6B7280)),
                          style: const TextStyle(
                            fontFamily: 'Google Sans Flex',
                            fontSize: 14,
                            color: Color(0xFF111827),
                          ),
                          items: GradeTheme.allGrades
                              .map((GradeTheme g) =>
                                  DropdownMenuItem<String>(
                                    value: g.gradeId,
                                    child: Text(g.title),
                                  ))
                              .toList(),
                          onChanged: _saving
                              ? null
                              : (String? v) {
                                  if (v != null) {
                                    setState(
                                        () => _selectedGradeKey = v);
                                  }
                                },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildRow(
                    'Subject Name',
                    SizedBox(
                      height: 36,
                      child: TextField(
                        controller: _nameController,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          contentPadding:
                              const EdgeInsets.symmetric(
                                  horizontal: 16),
                          border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(9999),
                              borderSide: const BorderSide(
                                  color:
                                      Color(0xFFD1D5DB))),
                          enabledBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(9999),
                              borderSide: const BorderSide(
                                  color:
                                      Color(0xFFD1D5DB))),
                          focusedBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(9999),
                              borderSide: BorderSide(
                                  color: widget.gradeColor)),
                        ),
                        style: const TextStyle(
                          fontFamily: 'Google Sans Flex',
                          fontSize: 14,
                          color: Color(0xFF111827),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildRow(
                    'Subject Cover URL',
                    SizedBox(
                      height: 36,
                      child: TextField(
                        controller: _urlController,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _save(),
                        decoration: InputDecoration(
                          contentPadding:
                              const EdgeInsets.symmetric(
                                  horizontal: 16),
                          border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(9999),
                              borderSide: const BorderSide(
                                  color:
                                      Color(0xFFD1D5DB))),
                          enabledBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(9999),
                              borderSide: const BorderSide(
                                  color:
                                      Color(0xFFD1D5DB))),
                          focusedBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(9999),
                              borderSide: BorderSide(
                                  color: widget.gradeColor)),
                        ),
                        style: const TextStyle(
                          fontFamily: 'Google Sans Flex',
                          fontSize: 14,
                          color: Color(0xFF111827),
                        ),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _error!,
                      style: const TextStyle(
                        fontFamily: 'Google Sans Flex',
                        fontSize: 12,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Center(
                    child: SizedBox(
                      width: 130,
                      height: 38,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: GradeTheme.fromKey(
                                  _selectedGradeKey)
                              .primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(
                                      9999)),
                          elevation: 0,
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Save',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontFamily:
                                        'Google Sans Flex',
                                    fontSize: 16),
                              ),
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

  Widget _buildRow(String label, Widget field) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 160,
          child: Text(label,
              style: const TextStyle(
                  fontFamily: 'Google Sans Flex',
                  fontSize: 14,
                  color: Color(0xFF374151))),
        ),
        SizedBox(
          width: 340,
          child: field,
        ),
      ],
    );
  }
}
