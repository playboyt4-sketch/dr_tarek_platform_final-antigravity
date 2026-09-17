import '../presentation/providers/grade_students_provider.dart';

/// Visual-verification switch. When true, [gradeStudentsProvider] serves
/// [mockGradeStudentsData] instead of hitting Firestore, so the "Total
/// Students" capsule and the students table render immediately with
/// realistic rows. Set to false to restore the live Firestore query.
const bool kUseMockGradeStudents = false;

/// Minimal mock mirroring the main-app `Student` entity
/// (`lib/features/profile/domain/entities/student.dart`):
/// id / name / phone / grade / studentType('Center' | 'Guest').
/// `plan`, `status` and `lastSignIn` have no entity field yet, so the
/// mapper below fills in stable dummy values per student.
class MockStudent {
  final String id;
  final String name;
  final String phone;
  final String gradeKey;
  final bool isCenter;

  const MockStudent({
    required this.id,
    required this.name,
    required this.phone,
    required this.gradeKey,
    required this.isCenter,
  });
}

/// At least one student per grade + both types, so every grade tab and
/// the Center/Guest pill show real rows.
const List<MockStudent> mockStudents = <MockStudent>[
  MockStudent(
    id: 'stu_001',
    name: 'ahmed mohamed gamal',
    phone: '01115800180',
    gradeKey: 'grade_one',
    isCenter: true,
  ),
  MockStudent(
    id: 'stu_002',
    name: 'omar khaled abdelrahman',
    phone: '01023456789',
    gradeKey: 'grade_two',
    isCenter: false,
  ),
  MockStudent(
    id: 'stu_003',
    name: 'youssef mostafa ibrahim',
    phone: '01234567890',
    gradeKey: 'grade_three',
    isCenter: true,
  ),
  MockStudent(
    id: 'stu_004',
    name: 'mariam ahmed el sayed',
    phone: '01512345678',
    gradeKey: 'grade_four',
    isCenter: false,
  ),
  MockStudent(
    id: 'stu_005',
    name: 'fatma hussein ali',
    phone: '01198765432',
    gradeKey: 'grade_one',
    isCenter: false,
  ),
  MockStudent(
    id: 'stu_006',
    name: 'karim tarek fouad',
    phone: '01011223344',
    gradeKey: 'grade_two',
    isCenter: true,
  ),
];

/// Dummy per-student extras keyed by id (entity has no plan/status/
/// last-sign-in fields yet).
const Map<String, ({String plan, bool isActive, String lastSignIn})>
    _mockExtras = <String, ({String plan, bool isActive, String lastSignIn})>{
  'stu_001': (plan: 'PRO', isActive: true, lastSignIn: '12/8/2026'),
  'stu_002': (plan: 'FREE', isActive: true, lastSignIn: '11/8/2026'),
  'stu_003': (plan: 'MAX', isActive: true, lastSignIn: '10/8/2026'),
  'stu_004': (plan: 'FREE', isActive: false, lastSignIn: '9/8/2026'),
  'stu_005': (plan: 'FREE', isActive: true, lastSignIn: '8/8/2026'),
  'stu_006': (plan: 'PRO', isActive: false, lastSignIn: '7/8/2026'),
};

/// Builds the exact snapshot the grade screen consumes:
/// - rows filtered to [gradeKey] only (Grade One tab ⇒ grade_one rows),
/// - `Student Name` ← [MockStudent.name],
///   `Type` ← Center/Guest derived from [MockStudent.isCenter],
/// - `Total Students` counter == filtered rows length via [GradeStudentsData.total].
GradeStudentsData mockGradeStudentsData(String gradeKey) {
  final List<GradeStudent> rows = <GradeStudent>[
    for (final MockStudent student in mockStudents)
      if (student.gradeKey == gradeKey)
        GradeStudent(
          id: student.id,
          name: student.name,
          isCenter: student.isCenter,
          plan: _mockExtras[student.id]?.plan ?? 'FREE',
          isActive: _mockExtras[student.id]?.isActive ?? true,
          lastSignIn: _mockExtras[student.id]?.lastSignIn ?? '—',
          phone: student.phone,
        ),
  ];
  return GradeStudentsData(
    gradeKey: gradeKey,
    students: rows,
    pendingCount: 2,
    breakdown: _mockBreakdown(rows),
    isFallback: false,
  );
}

List<PlanBreakdownRow> _mockBreakdown(List<GradeStudent> students) {
  int freeCount = 0, pro = 0, max = 0, guestCount = 0;
  for (final GradeStudent student in students) {
    if (student.plan == 'PRO') {
      pro++;
    } else if (student.plan == 'MAX') {
      max++;
    } else if (student.isCenter) {
      freeCount++;
    } else {
      guestCount++;
    }
  }
  int share(int count) =>
      students.isEmpty ? 0 : ((count * 100) / students.length).round();
  return <PlanBreakdownRow>[
    PlanBreakdownRow(label: 'Free', count: freeCount, share: share(freeCount)),
    PlanBreakdownRow(label: 'PRO', count: pro, share: share(pro)),
    PlanBreakdownRow(label: 'MAX', count: max, share: share(max)),
    PlanBreakdownRow(
        label: 'Guest', count: guestCount, share: share(guestCount)),
  ];
}
