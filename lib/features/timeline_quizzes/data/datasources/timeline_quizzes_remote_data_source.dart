import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/timeline_quiz.dart';
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

  Future<QuizAttemptModel> submitAttempt({
    required String quizId,
    required String studentId,
    required String lectureId,
    required Map<String, int> selectedAnswers,
    required List<QuizQuestion> questions,
    required bool skipped,
  }) async {
    int score = 0;
    if (!skipped) {
      for (final q in questions) {
        if (selectedAnswers[q.id] == q.correctOptionIndex) {
          score++;
        }
      }
    }

    final docRef = _attemptsRef.doc();
    final model = QuizAttemptModel(
      id: docRef.id,
      quizId: quizId,
      studentId: studentId,
      lectureId: lectureId,
      selectedAnswers: selectedAnswers,
      score: score,
      totalQuestions: questions.length,
      skipped: skipped,
      submittedAt: DateTime.now(),
      createdAt: DateTime.now(),
    );

    await docRef.set(model.toMap());
    return model;
  }
}
