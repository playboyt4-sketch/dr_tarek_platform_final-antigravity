import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dr_tarek_platform/features/subject_access/data/datasources/subject_access_data_source.dart';
import 'package:dr_tarek_platform/features/subject_access/data/datasources/subject_access_mutation_data_source.dart';
import 'package:dr_tarek_platform/features/subject_access/data/models/subject_access_assignment_model.dart';
import 'package:dr_tarek_platform/features/subject_access/data/repositories/subject_access_repository_impl.dart';
import 'package:dr_tarek_platform/features/subject_access/domain/entities/subject_access_assignment.dart';

void main() {
  final createdAt = DateTime.utc(2026, 8, 15, 10);
  final updatedAt = DateTime.utc(2026, 8, 15, 11);

  SubjectAccessAssignmentModel assignment({
    bool enabled = true,
    bool isDeleted = false,
    DateTime? deletedAt,
    String? deletedBy,
  }) {
    return SubjectAccessAssignmentModel(
      studentId: 'student-1',
      subjectId: 'subject-2',
      enabled: enabled,
      createdAt: createdAt,
      updatedAt: updatedAt,
      createdBy: 'teacher-1',
      updatedBy: 'teacher-1',
      isDeleted: isDeleted,
      deletedAt: deletedAt,
      deletedBy: deletedBy,
    );
  }

  group('SubjectAccessAssignment identity and serialization', () {
    test('builds the approved deterministic document ID', () {
      expect(
        SubjectAccessAssignment.documentIdFor('student-1', 'subject-2'),
        'student-1_subject-2',
      );
      expect(assignment().documentId, 'student-1_subject-2');
    });

    test('rejects an empty identity component', () {
      expect(
        () => SubjectAccessAssignment.documentIdFor('', 'subject-2'),
        throwsArgumentError,
      );
    });

    test('serializes without duplicating the Firestore document ID', () {
      final data = assignment().toFirestore();

      expect(data['student_id'], 'student-1');
      expect(data['subject_id'], 'subject-2');
      expect(data['enabled'], isTrue);
      expect(data['is_deleted'], isFalse);
      expect(data.containsKey('id'), isFalse);
      expect(data['created_at'], Timestamp.fromDate(createdAt));
      expect(data['updated_at'], Timestamp.fromDate(updatedAt));
    });

    test('round-trips the approved fields from Firestore data', () {
      final original = assignment(
        enabled: false,
        isDeleted: true,
        deletedAt: DateTime.utc(2026, 8, 15, 12),
        deletedBy: 'teacher-1',
      );

      final restored = SubjectAccessAssignmentModel.fromFirestoreData(
        documentId: original.documentId,
        data: original.toFirestore(),
      );

      expect(restored.studentId, original.studentId);
      expect(restored.subjectId, original.subjectId);
      expect(restored.enabled, isFalse);
      expect(restored.isDeleted, isTrue);
      expect(
        restored.deletedAt!.isAtSameMomentAs(original.deletedAt!),
        isTrue,
      );
      expect(restored.deletedBy, 'teacher-1');
      expect(restored.grantsAccess, isFalse);
    });

    test('rejects a non-deterministic document ID during deserialization', () {
      expect(
        () => SubjectAccessAssignmentModel.fromFirestoreData(
          documentId: 'wrong-id',
          data: assignment().toFirestore(),
        ),
        throwsStateError,
      );
    });
  });

  group('SubjectAccessRepositoryImpl', () {
    test(
      'delegates assignment reads and preserves soft-delete options',
      () async {
        final source = _FakeSubjectAccessDataSource(assignment: assignment());
        final repository = SubjectAccessRepositoryImpl(
          remoteDataSource: source,
          mutationDataSource: _FakeSubjectAccessMutationDataSource(),
        );

        final result = await repository.getAssignment(
          studentId: 'student-1',
          subjectId: 'subject-2',
        );
        final studentResults = await repository.getAssignmentsForStudent(
          studentId: 'student-1',
          includeDeleted: true,
        );
        expect(source.lastIncludeDeleted, isTrue);

        final subjectResults = await repository.getAssignmentsForSubject(
          subjectId: 'subject-2',
        );

        expect(result?.documentId, 'student-1_subject-2');
        expect(studentResults, hasLength(1));
        expect(subjectResults, hasLength(1));
        expect(source.lastStudentId, 'student-1');
        expect(source.lastSubjectId, 'subject-2');
      },
    );
  });
}

class _FakeSubjectAccessMutationDataSource
    implements SubjectAccessMutationDataSource {
  @override
  Future<void> setSubjectAccess({
    required String studentId,
    required String subjectId,
    required bool enabled,
    bool? isDeleted,
  }) async {}
}

class _FakeSubjectAccessDataSource implements SubjectAccessDataSource {
  final SubjectAccessAssignment assignment;
  bool? lastIncludeDeleted;
  String? lastStudentId;
  String? lastSubjectId;

  _FakeSubjectAccessDataSource({required this.assignment});

  @override
  Future<SubjectAccessAssignment?> getAssignment({
    required String studentId,
    required String subjectId,
  }) async {
    lastStudentId = studentId;
    lastSubjectId = subjectId;
    return assignment;
  }

  @override
  Future<List<SubjectAccessAssignment>> getAssignmentsForStudent({
    required String studentId,
    bool includeDeleted = false,
  }) async {
    lastStudentId = studentId;
    lastIncludeDeleted = includeDeleted;
    return [assignment];
  }

  @override
  Future<List<SubjectAccessAssignment>> getAssignmentsForSubject({
    required String subjectId,
    bool includeDeleted = false,
  }) async {
    lastSubjectId = subjectId;
    lastIncludeDeleted = includeDeleted;
    return [assignment];
  }
}
