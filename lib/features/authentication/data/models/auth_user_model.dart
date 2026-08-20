import '../../domain/entities/auth_user.dart';

class AuthUserModel extends AuthUser {
  const AuthUserModel({
    required super.id,
    required super.fullName,
    super.profilePhoto,
    required super.phoneNumber,
    required super.role,
    super.studentType,
    super.grade,
    required super.approvalStatus,
    required super.accountStatus,
    super.currentDeviceId,
  });

  factory AuthUserModel.fromMap(String id, Map<String, dynamic> map) {
    return AuthUserModel(
      id: id,
      fullName: map['full_name'] as String? ?? '',
      profilePhoto: map['profile_photo'] as String?,
      phoneNumber: map['phone_number'] as String? ?? '',
      role: map['role'] as String? ?? 'new_student',
      studentType: map['student_type'] as String?,
      grade: map['grade'] as String?,
      approvalStatus: map['approval_status'] as String? ?? 'pending',
      accountStatus: map['account_status'] as String? ?? 'active',
      currentDeviceId: map['current_device_id'] as String?,
    );
  }
}
