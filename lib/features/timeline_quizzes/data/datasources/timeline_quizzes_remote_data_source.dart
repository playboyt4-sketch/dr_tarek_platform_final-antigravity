import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../domain/entities/assessment_submit_result.dart';
import '../models/timeline_quiz_model.dart';

class TimelineQuizzesRemoteDataSource {
  final FirebaseFirestore _firestore;

  TimelineQuizzesRemoteDataSource({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _quizzesRef =>
      _firestore.collection('timeline_quizzes');

  CollectionReference<Map<String, dynamic>> get _attemptsRef =>
      _firestore.collection('quiz_attempts');

  Future<List<TimelineQuizModel>> getQuizzesForLecture({
    required String lectureId,
  }) async {
    final snap = await _quizzesRef
        .where('lecture_id', isEqualTo: lectureId)
        .where('status', isEqualTo: 'published')
        .get();
    return snap.docs
        .map(TimelineQuizModel.fromFirestore)
        .where((q) => q.questions.isNotEmpty)
        .toList();
  }

  Future<QuizAttemptModel?> getLatestAttempt({
    required String quizId,
    required String studentId,
  }) async {
    final snap = await _attemptsRef
        .where('quiz_id', isEqualTo: quizId)
        .where('student_id', isEqualTo: studentId)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return QuizAttemptModel.fromFirestore(snap.docs.first);
  }

  /// Published quizzes list — powers the hub Quizzes screen.
  Stream<List<TimelineQuizModel>> watchPublishedQuizzes() {
    return _quizzesRef
        .where('status', isEqualTo: 'published')
        .snapshots()
        .map((snap) => snap.docs.map(TimelineQuizModel.fromFirestore).toList());
  }

  /// Starts an attempt document (rules-whitelisted fields only).
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
      'attemptType': 'quiz',
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
      'attemptType': 'quiz',
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
      'attemptType': 'quiz',
    });
    final data = response.data as Map<dynamic, dynamic>? ?? {};
    final questions = data['questions'] as List<dynamic>? ?? [];
    return questions.map((q) => Map<String, dynamic>.from(q as Map)).toList();
  }
}
