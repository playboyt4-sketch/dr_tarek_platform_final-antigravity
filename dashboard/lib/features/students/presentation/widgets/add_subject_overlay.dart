import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/firebase_providers.dart';
import 'grade_theme.dart';

/// Figma `# add subject overlay` — literal implementation.
///
/// - 1120x316, white 100%, radius 16, No Stroke, shadow black12
///   blur 30 offset (0,8).
/// - Header: `Add New Subject` centered 20 Medium 500 #111827 + close X.
/// - 3 rows: label 160px 14px + capsule field radius 9999 gray border.
/// - Save: 130x38 pill gradeColor, white Save 16, centered bottom.
/// - No outer orange stroke, no subtitles, no toggle, button is `Save`.
class AddSubjectOverlay extends ConsumerStatefulWidget {
  final String gradeKey;
  final Color gradeColor;
  final int nextDisplayOrder;

  const AddSubjectOverlay({
    super.key,
    required this.gradeKey,
    required this.gradeColor,
    required this.nextDisplayOrder,
  });

  static Future<void> show(
    BuildContext context, {
    required String gradeKey,
    required Color gradeColor,
    required int nextDisplayOrder,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (BuildContext context) => AddSubjectOverlay(
        gradeKey: gradeKey,
        gradeColor: gradeColor,
        nextDisplayOrder: nextDisplayOrder,
      ),
    );
  }

  @override
  ConsumerState<AddSubjectOverlay> createState() => _AddSubjectOverlayState();
}

class _AddSubjectOverlayState extends ConsumerState<AddSubjectOverlay> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
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
      final FirebaseFirestore db = ref.read(firebaseFirestoreProvider);
      await db.collection('subjects').add(<String, Object?>{
        'title': name,
        'grade': _selectedGradeKey,
        'cover_url': _urlController.text.trim(),
        'is_active': true,
        'is_visible': true,
        'is_deleted': false,
        'display_order': widget.nextDisplayOrder,
        'created_at': FieldValue.serverTimestamp(),
      });
      if (mounted) Navigator.of(context).pop();
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.code == 'permission-denied'
              ? 'No permission (rules block subjects write). Deploy updated firestore.rules.'
              : 'Save failed (${e.code}). Try again.';
          _saving = false;
        });
      }
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
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
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
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Color(0xFF6B7280)),
                ),
              ),
              Column(
                children: [
                  const Text(
                    'Add New Subject',
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
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(9999),
                        border: Border.all(color: const Color(0xFFD1D5DB)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedGradeKey,
                          isExpanded: true,
                          icon: const Icon(
                            Icons.keyboard_arrow_down,
                            size: 18,
                            color: Color(0xFF6B7280),
                          ),
                          style: const TextStyle(
                            fontFamily: 'Google Sans Flex',
                            fontSize: 14,
                            color: Color(0xFF111827),
                          ),
                          items: GradeTheme.allGrades
                              .map(
                                (GradeTheme g) => DropdownMenuItem<String>(
                                  value: g.gradeId,
                                  child: Text(g.title),
                                ),
                              )
                              .toList(),
                          onChanged: (String? v) {
                            if (v != null) {
                              setState(() => _selectedGradeKey = v);
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
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(9999),
                            borderSide: const BorderSide(
                              color: Color(0xFFD1D5DB),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(9999),
                            borderSide: const BorderSide(
                              color: Color(0xFFD1D5DB),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(9999),
                            borderSide: BorderSide(color: widget.gradeColor),
                          ),
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
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(9999),
                            borderSide: const BorderSide(
                              color: Color(0xFFD1D5DB),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(9999),
                            borderSide: const BorderSide(
                              color: Color(0xFFD1D5DB),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(9999),
                            borderSide: BorderSide(color: widget.gradeColor),
                          ),
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
                            _selectedGradeKey,
                          ).primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9999),
                          ),
                          elevation: 0,
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Save',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontFamily: 'Google Sans Flex',
                                  fontSize: 16,
                                ),
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
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Google Sans Flex',
              fontSize: 14,
              color: Color(0xFF374151),
            ),
          ),
        ),
        SizedBox(width: 340, child: field),
      ],
    );
  }
}

/// Width of the trailing close-control slot in [SubjectDetailsDialog].
///
/// The header title must stay mathematically centered as one group, so the
/// leading side mirrors this trailing 48px Material slot instead of nudging
/// the title with padding/offsets (same convention as the subject header
/// card's full-bleed centered title). Pure symmetric flex — no hardcoded
/// visual offsets, fully constraint-based on every viewport.
const double _kDetailsCloseSlotWidth = 48;

/// Subject details transition — Figma
/// `# Grade- Grade one - subjects - details` (interim dialog).
class SubjectDetailsDialog extends StatelessWidget {
  final String title;
  final bool isActive;
  final Color gradeColor;

  const SubjectDetailsDialog({
    super.key,
    required this.title,
    required this.isActive,
    required this.gradeColor,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    required bool isActive,
    required Color gradeColor,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (BuildContext context) => SubjectDetailsDialog(
        title: title,
        isActive: isActive,
        gradeColor: gradeColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 520,
          padding: const EdgeInsets.fromLTRB(32, 28, 32, 28),
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Leading slot mirrors the trailing close control so the
                  // title stays centered as one group; the status dot keeps
                  // its exact leading position (see [_kDetailsCloseSlotWidth]).
                  SizedBox(
                    width: _kDetailsCloseSlotWidth,
                    child: Row(
                      children: [
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isActive
                                ? const Color(0xFF34C759)
                                : const Color(0xFFEF4444),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Google Sans Flex',
                        fontSize: 26,
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Color(0xFF6B7280)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 38,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: gradeColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9999),
                    ),
                    elevation: 0,
                  ),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
