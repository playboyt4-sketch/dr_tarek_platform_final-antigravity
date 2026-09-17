import 'package:flutter/material.dart';

/// Subject Card Widget — Figma `# Grade- Grade one - subjects`.
///
/// Fixed geometry: 540 x 128, radius 28, 1.5px [gradeColor] border.
/// Title: 48px Regular 400 #6B7280 centered. Status dot Frame 22x22
/// radius 11 with inner Ellipse 14x14: active #34C759 / inactive #EF4444
/// at Top:14 Right:18. Divider Line 17 1px rgba(0,0,0,0.08).
/// Bottom strip 40px: Lectures / Revisions / Final / Online,
/// Thin 100 14px black. Hover: Smart animate 150ms Ease out.
class SubjectCardItem extends StatefulWidget {
  final String title;
  final bool isActive;
  final int lecturesCount;
  final int revisionsCount;
  final int finalCount;
  final int onlineCount;
  final Color gradeColor;
  final VoidCallback onTap;

  const SubjectCardItem({
    super.key,
    required this.title,
    required this.isActive,
    required this.lecturesCount,
    required this.revisionsCount,
    required this.finalCount,
    required this.onlineCount,
    required this.gradeColor,
    required this.onTap,
  });

  @override
  State<SubjectCardItem> createState() => _SubjectCardItemState();
}

class _SubjectCardItemState extends State<SubjectCardItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          width: 540,
          height: 128,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: widget.gradeColor,
              width: 1.5,
            ),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: widget.gradeColor.withValues(alpha: 0.18),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : [],
          ),
          child: Column(
            children: [
              // Top Section: Title & Status
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Subject Name
                    Center(
                      child: Text(
                        widget.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Google Sans Flex',
                          fontWeight: FontWeight.w400,
                          fontSize: 48,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ),
                    // Status Dot Indicator (Top Right)
                    Positioned(
                      top: 14,
                      right: 18,
                      child: Container(
                        width: 22,
                        height: 22,
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.transparent,
                        ),
                        child: Center(
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: widget.isActive
                                  ? const Color(0xFF34C759)
                                  : const Color(0xFFEF4444),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Thin Divider
              Container(
                height: 1,
                color: Colors.black.withValues(alpha: 0.08),
              ),
              // Bottom Section: Statistics Details
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatItem('Lectures (${widget.lecturesCount})'),
                    _buildStatItem('Revisions (${widget.revisionsCount})'),
                    _buildStatItem('Final (${widget.finalCount})'),
                    _buildStatItem('Online (${widget.onlineCount})'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(String label) {
    return Flexible(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          maxLines: 1,
          style: const TextStyle(
            fontFamily: 'Google Sans Flex',
            fontWeight: FontWeight.w100,
            fontSize: 14,
            color: Color(0xFF000000),
          ),
        ),
      ),
    );
  }
}

/// + Add Subject card — always last in grid. 540x128, radius 28,
/// 1.5px gradeColor border, white. Center: filled gradeColor pill
/// (radius 9999) with + icon + Add Subject white text.
class AddSubjectCard extends StatefulWidget {
  final Color gradeColor;
  final VoidCallback onTap;

  const AddSubjectCard({
    super.key,
    required this.gradeColor,
    required this.onTap,
  });

  @override
  State<AddSubjectCard> createState() => _AddSubjectCardState();
}

class _AddSubjectCardState extends State<AddSubjectCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          width: 540,
          height: 128,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: widget.gradeColor, width: 1.5),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: widget.gradeColor.withValues(alpha: 0.18),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : [],
          ),
          alignment: Alignment.center,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: widget.gradeColor,
              borderRadius: BorderRadius.circular(9999),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_circle_outline,
                    color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text(
                  'Add Subject',
                  style: TextStyle(
                    fontFamily: 'Google Sans Flex',
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
