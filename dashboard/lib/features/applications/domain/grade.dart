const List<String> canonicalGradeKeys = <String>[
  'grade_one',
  'grade_two',
  'grade_three',
  'grade_four',
];

/// Normalizes any known grade spelling to its canonical key
/// (`canonicalGradeKeys`): `grade_one` … `grade_four`.
///
/// Digit spellings (`grade_2`, `2`, `Grade 3`, Arabic-Indic digits) and
/// word spellings (English/Arabic labels) all fold to the same canonical
/// key, so grade-filtered lists match regardless of which spelling a
/// document carries. Returns null when unparseable.
String? normalizeGradeKey(Object? raw) {
  if (raw is! String) return null;
  final text = raw.trim().toLowerCase();
  if (text.isEmpty) return null;
  final digit = _extractGradeDigit(text);
  if (digit != null) return canonicalGradeKeys[digit - 1];
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
    'guest' => 'ضيف',
    // Pre-migration stored value; display-only continuity until the data
    // migration covers all requests.
    'public_student' => 'ضيف',
    _ => null,
  };
}
