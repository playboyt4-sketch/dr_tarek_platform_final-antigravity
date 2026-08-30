import 'package:cloud_firestore/cloud_firestore.dart';

import '../grade.dart';

class JoinApplication {
  const JoinApplication({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.gradeKey,
    required this.studentType,
    required this.createdAt,
  });

  final String id;
  final String fullName;
  final String phone;
  final String? gradeKey;
  final String? studentType;
  final DateTime? createdAt;

  factory JoinApplication.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> data = doc.data();
    final String fullName = (data['full_name'] as String?)?.trim() ?? '';
    return JoinApplication(
      id: doc.id,
      fullName: fullName.isEmpty ? 'طالب جديد' : fullName,
      phone: (data['phone_number'] as String?) ?? '',
      gradeKey: normalizeGradeKey(data['grade']),
      studentType: data['student_type'] as String?,
      createdAt: (data['created_at'] as Timestamp?)?.toDate(),
    );
  }
}
