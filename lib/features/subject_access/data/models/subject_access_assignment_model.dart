import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/subject_access_assignment.dart';

class SubjectAccessAssignmentModel extends SubjectAccessAssignment {
  const SubjectAccessAssignmentModel({
    required super.studentId,
    required super.subjectId,
    required super.enabled,
    required super.createdAt,
    required super.updatedAt,
    required super.createdBy,
    required super.updatedBy,
    required super.isDeleted,
    required super.deletedAt,
    required super.deletedBy,
  });

  factory SubjectAccessAssignmentModel.fromFirestoreData({
    required String documentId,
    required Map<String, dynamic> data,
  }) {
    final studentId = _requiredString(data, 'student_id');
    final subjectId = _requiredString(data, 'subject_id');
    final expectedDocumentId = SubjectAccessAssignment.documentIdFor(
      studentId,
      subjectId,
    );
    if (documentId != expectedDocumentId) {
      throw StateError(
        'Subject Access document ID does not match its student/subject pair.',
      );
    }

    return SubjectAccessAssignmentModel(
      studentId: studentId,
      subjectId: subjectId,
      enabled: data['enabled'] == true,
      createdAt: _requiredTimestamp(data, 'created_at').toDate(),
      updatedAt: _requiredTimestamp(data, 'updated_at').toDate(),
      createdBy: _requiredString(data, 'created_by'),
      updatedBy: _requiredString(data, 'updated_by'),
      isDeleted: data['is_deleted'] == true,
      deletedAt: _optionalTimestamp(data, 'deleted_at')?.toDate(),
      deletedBy: data['deleted_by'] as String?,
    );
  }

  factory SubjectAccessAssignmentModel.fromEntity(
    SubjectAccessAssignment assignment,
  ) {
    return SubjectAccessAssignmentModel(
      studentId: assignment.studentId,
      subjectId: assignment.subjectId,
      enabled: assignment.enabled,
      createdAt: assignment.createdAt,
      updatedAt: assignment.updatedAt,
      createdBy: assignment.createdBy,
      updatedBy: assignment.updatedBy,
      isDeleted: assignment.isDeleted,
      deletedAt: assignment.deletedAt,
      deletedBy: assignment.deletedBy,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'student_id': studentId,
      'subject_id': subjectId,
      'enabled': enabled,
      'created_at': Timestamp.fromDate(createdAt),
      'updated_at': Timestamp.fromDate(updatedAt),
      'created_by': createdBy,
      'updated_by': updatedBy,
      'is_deleted': isDeleted,
      'deleted_at': deletedAt == null ? null : Timestamp.fromDate(deletedAt!),
      'deleted_by': deletedBy,
    };
  }

  static String _requiredString(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is! String || value.isEmpty) {
      throw StateError(
        'Subject Access field "$key" must be a non-empty string.',
      );
    }
    return value;
  }

  static Timestamp _requiredTimestamp(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is! Timestamp) {
      throw StateError('Subject Access field "$key" must be a Timestamp.');
    }
    return value;
  }

  static Timestamp? _optionalTimestamp(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value == null) return null;
    if (value is! Timestamp) {
      throw StateError(
        'Subject Access field "$key" must be a Timestamp or null.',
      );
    }
    return value;
  }
}
