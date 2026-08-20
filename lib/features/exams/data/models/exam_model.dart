import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/exam.dart';

class ExamQuestionModel extends ExamQuestion {
  const ExamQuestionModel({
    required super.id,
    required super.questionText,
    required super.options,
    required super.correctOptionIndex,
    super.points = 1,
    super.explanation,
  });

  factory ExamQuestionModel.fromMap(String id, Map<String, dynamic> data) {
    return ExamQuestionModel(
      id: id,
      questionText: (data['question_text'] as String?) ?? '',
      options: List<String>.from(data['options'] ?? const []),
      correctOptionIndex: (data['correct_option_index'] as int?) ?? 0,
      points: (data['points'] as int?) ?? 1,
      explanation: data['explanation'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'question_text': questionText,
      'options': options,
      'correct_option_index': correctOptionIndex,
      'points': points,
      if (explanation != null) 'explanation': explanation,
    };
  }
}

class ExamModel extends Exam {
  const ExamModel({
    required super.id,
    required super.lectureId,
    required super.subjectId,
    required super.title,
    required super.description,
    required super.durationMinutes,
    required super.passingScore,
    required super.totalScore,
    required super.questions,
    required super.isPublished,
    required super.createdAt,
  });

  factory ExamModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return ExamModel.fromMap(doc.id, data);
  }

  factory ExamModel.fromMap(String id, Map<String, dynamic> data) {
    final createdTimestamp = data['created_at'] as Timestamp?;
    final rawQuestions = (data['questions'] as List<dynamic>?) ?? const [];
    final questions = rawQuestions.asMap().entries.map((entry) {
      final qMap = Map<String, dynamic>.from(entry.value as Map);
      final qId = (qMap['id'] as String?) ?? 'eq_${entry.key}';
      return ExamQuestionModel.fromMap(qId, qMap);
    }).toList();

    final totalCalculated =
        questions.fold<int>(0, (total, q) => total + q.points);

    return ExamModel(
      id: id,
      lectureId: (data['lecture_id'] as String?) ?? '',
      subjectId: (data['subject_id'] as String?) ?? '',
      title: (data['title'] as String?) ?? '',
      description: (data['description'] as String?) ?? '',
      durationMinutes: (data['duration_minutes'] as int?) ?? 30,
      passingScore: (data['passing_score'] as int?) ?? (totalCalculated ~/ 2),
      totalScore: (data['total_score'] as int?) ?? totalCalculated,
      questions: questions,
      isPublished: data['status'] == 'published',
      createdAt: createdTimestamp?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'lecture_id': lectureId,
      'subject_id': subjectId,
      'title': title,
      'description': description,
      'duration_minutes': durationMinutes,
      'passing_score': passingScore,
      'total_score': totalScore,
      'questions': questions
          .map((q) => (q is ExamQuestionModel)
              ? q.toMap()
              : {
                  'id': q.id,
                  'question_text': q.questionText,
                  'options': q.options,
                  'correct_option_index': q.correctOptionIndex,
                  'points': q.points,
                  if (q.explanation != null) 'explanation': q.explanation,
                })
          .toList(),
      'status': isPublished ? 'published' : 'draft',
      'created_at': FieldValue.serverTimestamp(),
    };
  }
}

class ExamAttemptModel extends ExamAttempt {
  const ExamAttemptModel({
    required super.id,
    required super.examId,
    required super.studentId,
    required super.lectureId,
    required super.selectedAnswers,
    required super.score,
    required super.totalPossibleScore,
    required super.passed,
    required super.startedAt,
    super.submittedAt,
  });

  factory ExamAttemptModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return ExamAttemptModel.fromMap(doc.id, data);
  }

  factory ExamAttemptModel.fromMap(String id, Map<String, dynamic> data) {
    final startedTimestamp = data['started_at'] as Timestamp?;
    final submittedTimestamp = data['submitted_at'] as Timestamp?;
    final rawAnswers = (data['selected_answers'] as Map<dynamic, dynamic>?) ?? {};
    final selectedAnswers = rawAnswers.map(
      (k, v) => MapEntry(k.toString(), (v as num).toInt()),
    );

    return ExamAttemptModel(
      id: id,
      examId: (data['exam_id'] as String?) ?? '',
      studentId: (data['student_id'] as String?) ?? '',
      lectureId: (data['lecture_id'] as String?) ?? '',
      selectedAnswers: selectedAnswers,
      score: (data['score'] as int?) ?? 0,
      totalPossibleScore: (data['total_possible_score'] as int?) ?? 0,
      passed: data['passed'] == true,
      startedAt: startedTimestamp?.toDate() ?? DateTime.now(),
      submittedAt: submittedTimestamp?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'exam_id': examId,
      'student_id': studentId,
      'lecture_id': lectureId,
      'selected_answers': selectedAnswers,
      'score': score,
      'total_possible_score': totalPossibleScore,
      'passed': passed,
      'started_at': Timestamp.fromDate(startedAt),
      'submitted_at': FieldValue.serverTimestamp(),
    };
  }
}
