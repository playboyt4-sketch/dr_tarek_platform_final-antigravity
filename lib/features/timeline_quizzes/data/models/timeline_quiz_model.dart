import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/timeline_quiz.dart';

class QuizQuestionModel extends QuizQuestion {
  const QuizQuestionModel({
    required super.id,
    required super.questionText,
    required super.options,
    required super.correctOptionIndex,
    super.explanation,
  });

  factory QuizQuestionModel.fromMap(String id, Map<String, dynamic> data) {
    return QuizQuestionModel(
      id: id,
      questionText: (data['question_text'] as String?) ?? '',
      options: List<String>.from(data['options'] ?? const []),
      correctOptionIndex: (data['correct_option_index'] as int?) ?? 0,
      explanation: data['explanation'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'question_text': questionText,
      'options': options,
      'correct_option_index': correctOptionIndex,
      if (explanation != null) 'explanation': explanation,
    };
  }
}

class TimelineQuizModel extends TimelineQuiz {
  const TimelineQuizModel({
    required super.id,
    required super.lectureId,
    required super.subjectId,
    required super.title,
    required super.triggerTimestampSeconds,
    super.isPostLecture,
    required super.questions,
    required super.createdAt,
  });

  factory TimelineQuizModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return TimelineQuizModel.fromMap(doc.id, data);
  }

  factory TimelineQuizModel.fromMap(String id, Map<String, dynamic> data) {
    final createdTimestamp = data['created_at'] as Timestamp?;
    final rawQuestions = (data['questions'] as List<dynamic>?) ?? const [];
    final questions = rawQuestions.asMap().entries.map((entry) {
      final qMap = Map<String, dynamic>.from(entry.value as Map);
      final qId = (qMap['id'] as String?) ?? 'q_${entry.key}';
      return QuizQuestionModel.fromMap(qId, qMap);
    }).toList();

    return TimelineQuizModel(
      id: id,
      lectureId: (data['lecture_id'] as String?) ?? '',
      subjectId: (data['subject_id'] as String?) ?? '',
      title: (data['title'] as String?) ?? '',
      triggerTimestampSeconds: (data['trigger_timestamp_seconds'] as int?) ?? 0,
      isPostLecture: data['is_post_lecture'] == true,
      questions: questions,
      createdAt: createdTimestamp?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'lecture_id': lectureId,
      'subject_id': subjectId,
      'title': title,
      'trigger_timestamp_seconds': triggerTimestampSeconds,
      'is_post_lecture': isPostLecture,
      'questions': questions
          .map((q) => (q is QuizQuestionModel)
              ? q.toMap()
              : {
                  'id': q.id,
                  'question_text': q.questionText,
                  'options': q.options,
                  'correct_option_index': q.correctOptionIndex,
                  if (q.explanation != null) 'explanation': q.explanation,
                })
          .toList(),
      'status': 'published',
      'created_at': FieldValue.serverTimestamp(),
    };
  }
}

class QuizAttemptModel extends QuizAttempt {
  const QuizAttemptModel({
    required super.id,
    required super.quizId,
    required super.studentId,
    required super.lectureId,
    required super.selectedAnswers,
    required super.score,
    required super.totalQuestions,
    required super.skipped,
    super.submittedAt,
    required super.createdAt,
  });

  factory QuizAttemptModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return QuizAttemptModel.fromMap(doc.id, data);
  }

  factory QuizAttemptModel.fromMap(String id, Map<String, dynamic> data) {
    final createdTimestamp = data['created_at'] as Timestamp?;
    final submittedTimestamp = data['submitted_at'] as Timestamp?;
    final rawAnswers = (data['selected_answers'] as Map<dynamic, dynamic>?) ?? {};
    final selectedAnswers = rawAnswers.map(
      (k, v) => MapEntry(k.toString(), (v as num).toInt()),
    );

    return QuizAttemptModel(
      id: id,
      quizId: (data['quiz_id'] as String?) ?? '',
      studentId: (data['student_id'] as String?) ?? '',
      lectureId: (data['lecture_id'] as String?) ?? '',
      selectedAnswers: selectedAnswers,
      score: (data['score'] as int?) ?? 0,
      totalQuestions: (data['total_questions'] as int?) ?? 0,
      skipped: data['skipped'] == true,
      submittedAt: submittedTimestamp?.toDate(),
      createdAt: createdTimestamp?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'quiz_id': quizId,
      'student_id': studentId,
      'lecture_id': lectureId,
      'selected_answers': selectedAnswers,
      'score': score,
      'total_questions': totalQuestions,
      'skipped': skipped,
      'submitted_at': FieldValue.serverTimestamp(),
      'created_at': FieldValue.serverTimestamp(),
    };
  }
}
