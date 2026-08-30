import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'assessment_summary_screen.dart';
import '../providers/assessment_taking_provider.dart';

class AssessmentQuestionScreen extends ConsumerWidget {
  final AssessmentTakingParams params;

  const AssessmentQuestionScreen({
    super.key,
    required this.params,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(assessmentTakingControllerProvider(params));
    final notifier = ref.read(assessmentTakingControllerProvider(params).notifier);

        if (state.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (state.errorMessage != null && state.questions.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('Error')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(state.errorMessage!, style: const TextStyle(color: Colors.red)),
              ),
            ),
          );
        }

        if (state.isFinished) {
          // Defer navigation slightly so it doesn't happen during build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => AssessmentSummaryScreen(state: state),
              ),
            );
          });
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final question = state.currentQuestion;
        if (question == null) {
          return const Scaffold(
            body: Center(child: Text('No questions available.')),
          );
        }

        final isAnswered = state.isCurrentQuestionAnswered;
        final isCorrect = state.isCurrentQuestionCorrect;
        final explanation = state.currentExplanation;
        final selectedAnswer = state.selectedAnswers[question.id];

        return Scaffold(
          appBar: AppBar(
            title: Text('Question ${state.currentIndex + 1} of ${state.questions.length}'),
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    question.text,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: ListView.separated(
                      itemCount: question.options.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final option = question.options[index];
                        final isSelected = selectedAnswer == option;
                        
                        Color? bgColor;
                        Color? borderColor;
                        if (isAnswered) {
                          if (isSelected) {
                            bgColor = isCorrect ? Colors.green.shade100 : Colors.red.shade100;
                            borderColor = isCorrect ? Colors.green : Colors.red;
                          } else {
                            bgColor = Colors.grey.shade100;
                            borderColor = Colors.grey.shade300;
                          }
                        } else {
                          bgColor = Colors.white;
                          borderColor = Theme.of(context).primaryColor;
                        }

                        return InkWell(
                          onTap: isAnswered || state.isSubmitting
                              ? null
                              : () => notifier.submitAnswer(option),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: bgColor,
                              border: Border.all(color: borderColor),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              option,
                              style: TextStyle(
                                color: isAnswered && !isSelected ? Colors.grey : Colors.black87,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  if (state.isSubmitting)
                    const Center(child: CircularProgressIndicator())
                  else if (isAnswered) ...[
                    if (explanation != null && explanation.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Explanation: $explanation',
                          style: const TextStyle(color: Colors.blueGrey),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: state.isLastQuestion
                          ? () => notifier.finalizeAttempt()
                          : () => notifier.nextQuestion(),
                      child: Text(state.isLastQuestion ? 'Finish' : 'Next Question'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
  }
}
