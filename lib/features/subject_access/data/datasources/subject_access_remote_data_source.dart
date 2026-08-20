import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../domain/entities/subject_access_assignment.dart';
import '../models/subject_access_assignment_model.dart';
import 'subject_access_data_source.dart';
import 'subject_access_mutation_data_source.dart';

class SubjectAccessRemoteDataSource
    implements SubjectAccessDataSource, SubjectAccessMutationDataSource {
  static const collectionName = 'subject_access_assignments';

  final FirebaseFirestore firestore;
  final FirebaseFunctions functions;

  const SubjectAccessRemoteDataSource({
    required this.firestore,
    required this.functions,
  });

  @override
  Future<SubjectAccessAssignmentModel?> getAssignment({
    required String studentId,
    required String subjectId,
  }) async {
    final documentId = SubjectAccessAssignment.documentIdFor(
      studentId,
      subjectId,
    );
    final snapshot = await firestore
        .collection(collectionName)
        .doc(documentId)
        .get();

    if (!snapshot.exists) return null;

    final assignment = SubjectAccessAssignmentModel.fromFirestoreData(
      documentId: snapshot.id,
      data: snapshot.data() ?? const <String, dynamic>{},
    );
    if (assignment.isDeleted) return null;
    return assignment;
  }

  @override
  Future<List<SubjectAccessAssignmentModel>> getAssignmentsForStudent({
    required String studentId,
    bool includeDeleted = false,
  }) {
    Query<Map<String, dynamic>> query = firestore
        .collection(collectionName)
        .where('student_id', isEqualTo: studentId);
    if (!includeDeleted) {
      query = query.where('is_deleted', isEqualTo: false);
    }
    return _getAssignments(query, includeDeleted: includeDeleted);
  }

  @override
  Future<List<SubjectAccessAssignmentModel>> getAssignmentsForSubject({
    required String subjectId,
    bool includeDeleted = false,
  }) {
    Query<Map<String, dynamic>> query = firestore
        .collection(collectionName)
        .where('subject_id', isEqualTo: subjectId);
    if (!includeDeleted) {
      query = query.where('is_deleted', isEqualTo: false);
    }
    return _getAssignments(query, includeDeleted: includeDeleted);
  }

  @override
  Future<void> setSubjectAccess({
    required String studentId,
    required String subjectId,
    required bool enabled,
    bool? isDeleted,
  }) async {
    final payload = <String, dynamic>{
      'studentId': studentId,
      'subjectId': subjectId,
      'enabled': enabled,
    };
    if (isDeleted case final value?) {
      payload['isDeleted'] = value;
    }
    await functions.httpsCallable('setSubjectAccess').call(payload);
  }

  Future<List<SubjectAccessAssignmentModel>> _getAssignments(
    Query<Map<String, dynamic>> query, {
    required bool includeDeleted,
  }) async {
    final snapshot = await query.get();
    return snapshot.docs
        .map(
          (doc) => SubjectAccessAssignmentModel.fromFirestoreData(
            documentId: doc.id,
            data: doc.data(),
          ),
        )
        .where((assignment) => includeDeleted || assignment.isDeleted == false)
        .toList(growable: false);
  }
}
