import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';

/// Semantic Grade Colors — single source of truth for the 4 grades.
///
/// Structure is 100% unified; only [primaryColor] (`gradeColor`) varies:
/// - Grade One   → #F59E0B (Amber)
/// - Grade Two   → #1D4ED8 (Royal Blue)
/// - Grade Three → #15803D (Forest Green)
/// - Grade Four  → #DC2626 (Ruby Red)
/// Status dots are constant: active #34C759, inactive #EF4444.
class GradeTheme {
  final String gradeId;
  final String title;
  final Color primaryColor;

  const GradeTheme({
    required this.gradeId,
    required this.title,
    required this.primaryColor,
  });

  static const List<GradeTheme> allGrades = [
    GradeTheme(
        gradeId: 'grade_one',
        title: 'Grade One',
        primaryColor: Color(0xFFF59E0B)),
    GradeTheme(
        gradeId: 'grade_two',
        title: 'Grade Two',
        primaryColor: Color(0xFF1D4ED8)),
    GradeTheme(
        gradeId: 'grade_three',
        title: 'Grade Three',
        primaryColor: Color(0xFF15803D)),
    GradeTheme(
        gradeId: 'grade_four',
        title: 'Grade Four',
        primaryColor: Color(0xFFDC2626)),
  ];

  /// Canonical lookup — accepts `grade_one` and legacy `grade_1` spellings.
  static GradeTheme fromKey(String gradeKey) {
    final String normalized = gradeKey.trim().toLowerCase();
    final String canonical = switch (normalized) {
      'grade_1' || 'grade1' || '1' => 'grade_one',
      'grade_2' || 'grade2' || '2' => 'grade_two',
      'grade_3' || 'grade3' || '3' => 'grade_three',
      'grade_4' || 'grade4' || '4' => 'grade_four',
      _ => normalized,
    };
    return allGrades.firstWhere(
      (GradeTheme g) => g.gradeId == canonical,
      orElse: () => allGrades.first,
    );
  }

  /// Bridge to the legacy [AppColors] accents (same hex values).
  static Color accentFor(String gradeKey) {
    return switch (GradeTheme.fromKey(gradeKey).gradeId) {
      'grade_two' => AppColors.gradeTwo,
      'grade_three' => AppColors.gradeThree,
      'grade_four' => AppColors.gradeFour,
      _ => AppColors.gradeOne,
    };
  }

  /// Display label for a subject row's OWN grade (`Grade One` …),
  /// shared by the Subjects / Memberships / Payments / Device tabs so all
  /// four render identically. Resolves only known catalog ids; unknown or
  /// missing grades render as `—` instead of invented data. (Unlike
  /// [fromKey], which falls back to Grade One — correct for navigation,
  /// wrong for data display.)
  static String subjectGradeLabel(String? gradeKey) {
    final String key = (gradeKey ?? '').trim();
    if (key.isEmpty) return '—';
    for (final GradeTheme grade in allGrades) {
      if (grade.gradeId == key) return grade.title;
    }
    return '—';
  }
}
