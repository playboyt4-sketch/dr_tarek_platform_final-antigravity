import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../domain/entities/assessment_submit_result.dart';
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

  /// Published exams list — powers the hub Exams screen.
  Stream<List<ExamModel>> watchPublishedExams() {
    return _examsRef
        .where('status', isEqualTo: 'published')
        .snapshots()
        .map((snap) => snap.docs.map(ExamModel.fromFirestore).toList());
  }

  /// Starts an attempt document (rules-whitelisted fields only) and returns
  /// its id; grading/submission happen server-side via callable.
  Future<String> startAttempt({
    required String assessmentId,
    required String studentId,
  }) async {
    final docRef = await _attemptsRef.add({
      'student_id': studentId,
      'assessment_id': assessmentId,
      'status': 'started',
      'started_at': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  /// Submits answers through the server-side grader (submitAssessmentAttempt).
  Future<AssessmentSubmitResult> submitAnswers({
    required String attemptId,
    required Map<String, String> answers,
  }) async {
    final callable = FirebaseFunctions.instance
        .httpsCallable('submitAssessmentAttempt');
    final response = await callable.call({
      'attemptId': attemptId,
      'attemptType': 'exam',
      'answers': answers,
    });
    final data = response.data as Map<dynamic, dynamic>? ?? {};
    return AssessmentSubmitResult(
      submitted: data['submitted'] == true,
      score: (data['score'] as num?)?.toInt(),
      totalMarks: (data['totalMarks'] as num?)?.toInt() ?? 0,
      percentage: (data['percentage'] as num?)?.toDouble(),
      needsManualGrading: data['needsManualGrading'] == true,
    );
  }

  /// Evaluates a single answer statelessly on the server for immediate feedback.
  Future<Map<String, dynamic>> evaluateAnswer({
    required String attemptId,
    required String questionId,
    required String answer,
  }) async {
    final callable = FirebaseFunctions.instance.httpsCallable('evaluateQuestionAnswer');
    final response = await callable.call({
      'attemptId': attemptId,
      'attemptType': 'exam',
      'questionId': questionId,
      'answer': answer,
    });
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// Securely fetches questions for an attempt without correct answers or explanations.
  Future<List<Map<String, dynamic>>> getAssessmentQuestions({
    required String attemptId,
  }) async {
    final callable = FirebaseFunctions.instance.httpsCallable('getAssessmentQuestions');
    final response = await callable.call({
      'attemptId': attemptId,
      'attemptType': 'exam',
    });
    final data = response.data as Map<dynamic, dynamic>? ?? {};
    final questions = data['questions'] as List<dynamic>? ?? [];
    return questions.map((q) => Map<String, dynamic>.from(q as Map)).toList();
  }
}
