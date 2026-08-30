import 'package:flutter/material.dart';

import '../providers/assessment_taking_state.dart';

class AssessmentSummaryScreen extends StatelessWidget {
  final AssessmentTakingState state;

  const AssessmentSummaryScreen({
    super.key,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final needsManual = state.needsManualGrading == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Assessment Complete'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.check_circle_outline,
                size: 80,
                color: Colors.green,
              ),
              const SizedBox(height: 24),
              Text(
                'Assessment Submitted!',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              if (needsManual) ...[
                const Text(
                  'Your assessment includes questions that require manual grading. '
                  'Your final score will be available once your teacher reviews them.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.blueGrey),
                ),
              ] else if (state.finalScore != null && state.totalMarks != null) ...[
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        const Text('Your Score', style: TextStyle(fontSize: 18)),
                        const SizedBox(height: 8),
                        Text(
                          '${state.finalScore} / ${state.totalMarks}',
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Back to Course'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
