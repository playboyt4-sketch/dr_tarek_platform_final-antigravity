class AuthUser {
  final String id;
  final String fullName;
  final String? profilePhoto;
  final String phoneNumber;
  final String role;
  final String? studentType;
  final String? grade;
  final String approvalStatus;
  final String accountStatus;
  final String? currentDeviceId;

  const AuthUser({
    required this.id,
    required this.fullName,
    this.profilePhoto,
    required this.phoneNumber,
    required this.role,
    this.studentType,
    this.grade,
    required this.approvalStatus,
    required this.accountStatus,
    this.currentDeviceId,
  });
}
