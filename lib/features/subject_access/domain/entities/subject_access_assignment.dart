class SubjectAccessAssignment {
  final String studentId;
  final String subjectId;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;
  final String updatedBy;
  final bool isDeleted;
  final DateTime? deletedAt;
  final String? deletedBy;

  const SubjectAccessAssignment({
    required this.studentId,
    required this.subjectId,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
    required this.isDeleted,
    required this.deletedAt,
    required this.deletedBy,
  });

  String get documentId => documentIdFor(studentId, subjectId);

  bool get grantsAccess => !isDeleted && enabled;

  static String documentIdFor(String studentId, String subjectId) {
    if (studentId.isEmpty || subjectId.isEmpty) {
      throw ArgumentError('studentId and subjectId must not be empty.');
    }
    return '${studentId}_$subjectId';
  }

  SubjectAccessAssignment copyWith({
    String? studentId,
    String? subjectId,
    bool? enabled,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdBy,
    String? updatedBy,
    bool? isDeleted,
    DateTime? deletedAt,
    String? deletedBy,
    bool clearDeletedAt = false,
    bool clearDeletedBy = false,
  }) {
    return SubjectAccessAssignment(
      studentId: studentId ?? this.studentId,
      subjectId: subjectId ?? this.subjectId,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
      updatedBy: updatedBy ?? this.updatedBy,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
      deletedBy: clearDeletedBy ? null : (deletedBy ?? this.deletedBy),
    );
  }
}
