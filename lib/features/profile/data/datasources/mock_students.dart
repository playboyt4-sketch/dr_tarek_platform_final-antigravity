import '../../domain/entities/student.dart';

/// Dummy students for visual testing of the Profile Overview screens.
///
/// Covers every grade (One–Four) and both student types (Center/Guest)
/// so each UI state can be exercised. Data layer only — no repository
/// or use-case wiring yet; inject directly into your controllers, e.g.:
///
/// ```dart
/// final student = mockStudents[0];
/// nameController.text = student.name;
/// phoneController.text = student.phone;
/// selectedGrade = student.grade.label;
/// selectedStudentType = student.studentType.label;
/// ```
const List<Student> mockStudents = [
  Student(
    id: 'stu_001',
    name: 'ahmed mohamed gamal',
    phone: '01115800180',
    grade: StudentGrade.gradeOne,
    studentType: StudentType.center,
  ),
  Student(
    id: 'stu_002',
    name: 'omar khaled abdelrahman',
    phone: '01023456789',
    grade: StudentGrade.gradeTwo,
    studentType: StudentType.guest,
  ),
  Student(
    id: 'stu_003',
    name: 'youssef mostafa ibrahim',
    phone: '01234567890',
    grade: StudentGrade.gradeThree,
    studentType: StudentType.center,
  ),
  Student(
    id: 'stu_004',
    name: 'mariam ahmed el sayed',
    phone: '01512345678',
    grade: StudentGrade.gradeFour,
    studentType: StudentType.guest,
  ),
  Student(
    id: 'stu_005',
    name: 'fatma hussein ali',
    phone: '01198765432',
    grade: StudentGrade.gradeOne,
    studentType: StudentType.guest,
  ),
  Student(
    id: 'stu_006',
    name: 'karim tarek fouad',
    phone: '01011223344',
    grade: StudentGrade.gradeTwo,
    studentType: StudentType.center,
  ),
];
