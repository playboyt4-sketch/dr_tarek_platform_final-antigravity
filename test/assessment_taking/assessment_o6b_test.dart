import 'package:dr_tarek_platform/features/assessment_taking/presentation/providers/assessment_taking_provider.dart';
import 'package:dr_tarek_platform/features/exams/domain/entities/assessment_submit_result.dart';
import 'package:dr_tarek_platform/features/exams/domain/entities/exam.dart';
import 'package:dr_tarek_platform/features/exams/domain/repositories/exams_repository.dart';
import 'package:dr_tarek_platform/features/exams/presentation/providers/exams_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// O6-B regression suite: before final submission the client handles only
/// sanitized questions and locally recorded answers — no answer keys,
/// correctness flags, explanations, or trusted scores exist anywhere in
/// client state. Grading happens once, server-side, at finalize.
class RecordingExamsRepository implements ExamsRepository {
  int submitCalls = 0;
  Map<String, String> lastSubmitted = const {};

  @override
  Future<List<Map<String, dynamic>>> getAssessmentQuestions({
    required String attemptId,
  }) async {
    // Hostile payload: even if keys/explanations arrived, the client model
    // must drop them (AssessmentQuestion has no such fields).
    return [
      {
        'id': 'q1',
        'type': 'mcq',
        'text': 'What is 2 + 2?',
        'options': ['3', '4', '5'],
        'marks': 2,
        'correct_option_index': 1,
        'correct_answer': '4',
        'explanation': 'Basic arithmetic',
        'score': 999,
      },
    ];
  }

  @override
  Future<AssessmentSubmitResult> submitExamAnswers({
    required String attemptId,
    required Map<String, String> answers,
  }) async {
    submitCalls++;
    lastSubmitted = Map<String, String>.from(answers);
    return const AssessmentSubmitResult(
      submitted: true,
      score: 2,
      totalMarks: 2,
      percentage: 100.0,
      needsManualGrading: false,
    );
  }

  @override
  Stream<List<Exam>> watchPublishedExams() => throw UnimplementedError();
  @override
  Future<String> startExamAttempt(
          {required String examId, required String studentId}) =>
      throw UnimplementedError();
  @override
  Future<Exam?> getExamForLecture({required String lectureId}) =>
      throw UnimplementedError();
  @override
  Future<List<Exam>> getExamsForSubject({required String subjectId}) =>
      throw UnimplementedError();
  @override
  Future<ExamAttempt?> getLatestAttempt(
          {required String examId, required String studentId}) =>
      throw UnimplementedError();
}

Future<void> _flushMicrotasks() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late ProviderContainer container;
  late RecordingExamsRepository fake;
  final params = AssessmentTakingParams(
    attemptId: 'att_1',
    assessmentId: 'exam_1',
    type: 'exam',
  );

  setUp(() {
    fake = RecordingExamsRepository();
    container = ProviderContainer(overrides: [
      examsRepositoryProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);
  });

  test('initialize maps sanitized questions and drops any key material',
      () async {
    container.read(assessmentTakingControllerProvider(params));
    await _flushMicrotasks();

    final state =
        container.read(assessmentTakingControllerProvider(params));
    expect(state.isLoading, isFalse);
    expect(state.errorMessage, isNull);
    expect(state.questions.length, 1);
    final q = state.questions.single;
    expect(q.id, 'q1');
    expect(q.text, 'What is 2 + 2?');
    expect(q.options, ['3', '4', '5']);
    expect(q.marks, 2);
  });

  test('submitAnswer records locally with zero server interaction', () async {
    final notifier = container
        .read(assessmentTakingControllerProvider(params).notifier);
    await _flushMicrotasks();

    await notifier.submitAnswer('4');
    final state =
        container.read(assessmentTakingControllerProvider(params));
    expect(state.selectedAnswers, {'q1': '4'});
    // No per-question grading exists: nothing submitted, no correctness
    // or explanation state is even representable anymore.
    expect(fake.submitCalls, 0);
    expect(state.isFinished, isFalse);
    expect(state.finalScore, isNull);
  });

  test('answering twice keeps the first answer (no overwrite)', () async {
    final notifier = container
        .read(assessmentTakingControllerProvider(params).notifier);
    await _flushMicrotasks();

    await notifier.submitAnswer('3');
    await notifier.submitAnswer('4');
    final state =
        container.read(assessmentTakingControllerProvider(params));
    expect(state.selectedAnswers, {'q1': '3'});
    expect(fake.submitCalls, 0);
  });

  test('finalize submits once with typed result and finishes', () async {
    final notifier = container
        .read(assessmentTakingControllerProvider(params).notifier);
    await _flushMicrotasks();

    await notifier.submitAnswer('4');
    await notifier.finalizeAttempt();
    final state =
        container.read(assessmentTakingControllerProvider(params));
    expect(fake.submitCalls, 1);
    expect(fake.lastSubmitted, {'q1': '4'});
    expect(state.isFinished, isTrue);
    expect(state.finalScore, 2);
    expect(state.totalMarks, 2);
    expect(state.needsManualGrading, isFalse);
  });
}
