const List<String> canonicalGradeKeys = <String>[
  'grade_one',
  'grade_two',
  'grade_three',
  'grade_four',
];

String? normalizeGradeKey(Object? raw) {
  if (raw is! String) return null;
  final text = raw.trim().toLowerCase();
  if (text.isEmpty) return null;
  final digit = _extractGradeDigit(text);
  if (digit != null) return 'grade_$digit';
  final folded = text
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا')
      .replaceAll('آ', 'ا')
      .replaceAll('ى', 'ي');
  if (folded.contains('اول') || folded.contains('one')) return 'grade_one';
  if (folded.contains('ثان') || folded.contains('two')) return 'grade_two';
  if (folded.contains('ثال') || folded.contains('three')) return 'grade_three';
  if (folded.contains('راب') || folded.contains('four')) return 'grade_four';
  return null;
}

int? _extractGradeDigit(String text) {
  const arabicIndicDigits = <String, int>{
    '١': 1,
    '٢': 2,
    '٣': 3,
    '٤': 4,
  };
  for (final MapEntry<String, int> entry in arabicIndicDigits.entries) {
    if (text.contains(entry.key)) return entry.value;
  }
  final RegExpMatch? match = RegExp(r'[1-4]').firstMatch(text);
  return match == null ? null : int.parse(match.group(0)!);
}

String gradeDisplayName(String? key) {
  return switch (key) {
    'grade_one' => 'الفرقة الأولى',
    'grade_two' => 'الفرقة الثانية',
    'grade_three' => 'الفرقة الثالثة',
    'grade_four' => 'الفرقة الرابعة',
    _ => 'غير محددة',
  };
}

String? studentTypeDisplayName(String? type) {
  return switch (type) {
    'center_student' => 'طالب سنتر',
    'public_student' => 'طالب عام',
    _ => null,
  };
}
