import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/exam.dart';
import '../models/exam_model.dart';

class ExamsRemoteDataSource {
  final FirebaseFirestore _firestore;

  ExamsRemoteDataSource({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _examsRef =>
      _firestore.collection('exams');

  CollectionReference<Map<String, dynamic>> get _attemptsRef =>
      _firestore.collection('exam_attempts');

  Future<ExamModel?> getExamForLecture({
    required String lectureId,
  }) async {
    final snap = await _examsRef
        .where('lecture_id', isEqualTo: lectureId)
        .where('status', isEqualTo: 'published')
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return ExamModel.fromFirestore(snap.docs.first);
  }

  Future<List<ExamModel>> getExamsForSubject({
    required String subjectId,
  }) async {
    final snap = await _examsRef
        .where('subject_id', isEqualTo: subjectId)
        .where('status', isEqualTo: 'published')
        .get();
    return snap.docs.map(ExamModel.fromFirestore).toList();
  }

  Future<ExamAttemptModel?> getLatestAttempt({
    required String examId,
    required String studentId,
  }) async {
    final snap = await _attemptsRef
        .where('exam_id', isEqualTo: examId)
        .where('student_id', isEqualTo: studentId)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return ExamAttemptModel.fromFirestore(snap.docs.first);
  }

  Future<ExamAttemptModel> submitExamAttempt({
    required String examId,
    required String studentId,
    required String lectureId,
    required Map<String, int> selectedAnswers,
    required List<ExamQuestion> questions,
    required int passingScore,
    required DateTime startedAt,
  }) async {
    int totalScore = 0;
    int totalPossible = 0;

    for (final q in questions) {
      totalPossible += q.points;
      if (selectedAnswers[q.id] == q.correctOptionIndex) {
        totalScore += q.points;
      }
    }

    final passed = totalScore >= passingScore;

    final docRef = _attemptsRef.doc();
    final model = ExamAttemptModel(
      id: docRef.id,
      examId: examId,
      studentId: studentId,
      lectureId: lectureId,
      selectedAnswers: selectedAnswers,
      score: totalScore,
      totalPossibleScore: totalPossible,
      passed: passed,
      startedAt: startedAt,
      submittedAt: DateTime.now(),
    );

    await docRef.set(model.toMap());
    return model;
  }
}
