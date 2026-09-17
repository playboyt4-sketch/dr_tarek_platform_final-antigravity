/// Student entity for the "Student Profile Overview" screens.
///
/// Lives in the domain layer: pure Dart, no Flutter/Firebase imports.
/// UI labels match the Figma spec exactly
/// ('Grade One' … 'Grade Four', 'Center' / 'Guest').
enum StudentGrade {
  gradeOne('Grade One'),
  gradeTwo('Grade Two'),
  gradeThree('Grade Three'),
  gradeFour('Grade Four');

  final String label;
  const StudentGrade(this.label);
}

enum StudentType {
  center('Center'),
  guest('Guest');

  final String label;
  const StudentType(this.label);
}

class Student {
  final String id;
  final String name;
  final String phone;
  final StudentGrade grade;
  final StudentType studentType;

  const Student({
    required this.id,
    required this.name,
    required this.phone,
    required this.grade,
    required this.studentType,
  });

  Student copyWith({
    String? id,
    String? name,
    String? phone,
    StudentGrade? grade,
    StudentType? studentType,
  }) {
    return Student(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      grade: grade ?? this.grade,
      studentType: studentType ?? this.studentType,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Student &&
        other.id == id &&
        other.name == name &&
        other.phone == phone &&
        other.grade == grade &&
        other.studentType == studentType;
  }

  @override
  int get hashCode => Object.hash(id, name, phone, grade, studentType);

  @override
  String toString() =>
      'Student(id: $id, name: $name, phone: $phone, '
      'grade: ${grade.label}, studentType: ${studentType.label})';
}
