/// FINAL_DECISIONS §13 helpers: canonical grade keys, ranks and the
/// prior-grade computation used by both grant entry points (registration
/// approval and the student profile screen). Pure and unit-testable.
///
/// Two spellings exist historically in the codebase — the registration
/// wizard stores `grade_one..grade_four` while some admin screens display
/// `grade_1..grade_4`. Everything here canonicalizes to `grade_*_one`
/// form, mirroring normalizeGradeKey() in functions/src/index.ts.
library;

const List<String> kCanonicalGradeKeys = [
  'grade_one',
  'grade_two',
  'grade_three',
  'grade_four',
];

const Map<String, String> kGradeLabels = {
  'grade_one': 'الفرقة الأولى',
  'grade_two': 'الفرقة الثانية',
  'grade_three': 'الفرقة الثالثة',
  'grade_four': 'الفرقة الرابعة',
};

String gradeLabel(String key) => kGradeLabels[key] ?? key;

/// Canonicalizes any known spelling into `grade_*`; null when unparseable.
String? normalizeAdminGradeKey(Object? raw) {
  if (raw is! String) return null;
  final normalized = raw.trim().toLowerCase();
  if (kCanonicalGradeKeys.contains(normalized)) return normalized;
  // Both historical spellings (bare digit and grade_N) map to the
  // canonical form, mirroring normalizeGradeKey() in functions/src/index.ts.
  const aliases = <String, String>{
    '1': 'grade_one',
    'grade_1': 'grade_one',
    'grade 1': 'grade_one',
    '2': 'grade_two',
    'grade_2': 'grade_two',
    'grade 2': 'grade_two',
    '3': 'grade_three',
    'grade_3': 'grade_three',
    'grade 3': 'grade_three',
    '4': 'grade_four',
    'grade_4': 'grade_four',
    'grade 4': 'grade_four',
  };
  return aliases[normalized];
}

/// 1..4 rank of a grade key; null when unparseable.
int? adminGradeRank(String? key) {
  final normalized = normalizeAdminGradeKey(key);
  if (normalized == null) return null;
  return kCanonicalGradeKeys.indexOf(normalized) + 1;
}

/// FINAL_DECISIONS §13: canonical grades strictly BELOW the student's own
/// grade. Grade 1 (or an unknown/unset grade) has no prior grades — the
/// caller must not render any prior-term UI in that case.
List<String> priorGradeKeysFor(String? studentGrade) {
  final rank = adminGradeRank(studentGrade);
  if (rank == null || rank <= 1) return const [];
  return kCanonicalGradeKeys.take(rank - 1).toList(growable: false);
}

/// Builds the `subjectAccess` payload expected by `approveStudent`:
/// [{subjectId, enabled}] with NO duplicate subject ids. Prior-term picks
/// merge over the primary selection (primary wins on conflicts).
List<Map<String, dynamic>> buildSubjectAccessPayload({
  required Iterable<String> primarySubjectIds,
  Iterable<String> priorGradeSubjectIds = const [],
}) {
  final payload = <Map<String, dynamic>>[];
  final seen = <String>{};
  for (final id in primarySubjectIds) {
    if (id.isEmpty || !seen.add(id)) continue;
    payload.add({'subjectId': id, 'enabled': true});
  }
  for (final id in priorGradeSubjectIds) {
    if (id.isEmpty || !seen.add(id)) continue;
    payload.add({'subjectId': id, 'enabled': true});
  }
  return payload;
}
