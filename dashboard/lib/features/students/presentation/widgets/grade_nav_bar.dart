import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';
import 'grade_theme.dart';

/// Reusable grade navigation — one implementation for all four grades.
///
/// Adapts across viewport widths: expands up to 720px on tablet/desktop and
/// scrolls horizontally with touch-friendly pill widths on mobile.
class GradeNavBar extends StatelessWidget {
  final String gradeKey;
  final ValueChanged<String> onGradeSelected;

  const GradeNavBar({
    super.key,
    required this.gradeKey,
    required this.onGradeSelected,
  });

  @override
  Widget build(BuildContext context) {
    final GradeTheme active = GradeTheme.fromKey(gradeKey);
    void selectGrade(String key) {
      if (key != active.gradeId) onGradeSelected(key);
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 660;
        final bool compact = maxWidth < 540;

        if (compact) {
          return Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Container(
                height: 44,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(9999),
                  border: Border.all(
                    color: const Color(0x33000000),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (final GradeTheme grade in GradeTheme.allGrades)
                      GestureDetector(
                        onTap: () => selectGrade(grade.gradeId),
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 108),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: grade.gradeId == active.gradeId
                                ? grade.primaryColor
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(9999),
                          ),
                          child: Text(
                            grade.title,
                            style: TextStyle(
                              fontFamily: AppTypography.fontFamily,
                              fontSize: 14,
                              fontWeight: grade.gradeId == active.gradeId
                                  ? FontWeight.w500
                                  : FontWeight.w400,
                              color: grade.gradeId == active.gradeId
                                  ? Colors.white
                                  : const Color(0xFF6B7280),
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

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Container(
              height: 42,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(9999),
                border: Border.all(color: const Color(0x33000000), width: 1.0),
              ),
              child: Row(
                children: <Widget>[
                  for (final GradeTheme grade in GradeTheme.allGrades)
                    Expanded(
                      child: GestureDetector(
                        onTap: () => selectGrade(grade.gradeId),
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: grade.gradeId == active.gradeId
                                ? grade.primaryColor
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(9999),
                          ),
                          child: Text(
                            grade.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: AppTypography.fontFamily,
                              fontSize: 15,
                              fontWeight: grade.gradeId == active.gradeId
                                  ? FontWeight.w500
                                  : FontWeight.w400,
                              color: grade.gradeId == active.gradeId
                                  ? Colors.white
                                  : const Color(0xFF6B7280),
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
      },
    );
  }
}

/// Reusable Students / Subjects tab pair.
class StudentsSubjectsTabs extends StatelessWidget {
  final bool studentsActive;
  final Color accent;
  final VoidCallback? onStudentsTap;
  final VoidCallback? onSubjectsTap;

  const StudentsSubjectsTabs({
    super.key,
    required this.studentsActive,
    required this.accent,
    this.onStudentsTap,
    this.onSubjectsTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        _tab('Students', studentsActive, onStudentsTap),
        const SizedBox(width: 48),
        _tab('Subjects', !studentsActive, onSubjectsTap),
      ],
    );
  }

  Widget _tab(String label, bool active, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 16,
                fontWeight: active ? FontWeight.w500 : FontWeight.w400,
                color: active ? accent : const Color(0xFF111827),
              ),
            ),
            Container(
              margin: const EdgeInsets.only(top: 4),
              width: 58,
              height: 2,
              color: active ? accent : Colors.transparent,
            ),
          ],
        ),
      ),
    );
  }
}
