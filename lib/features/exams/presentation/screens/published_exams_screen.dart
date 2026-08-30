import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/friendly_error_message.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../assessment_taking/presentation/screens/assessment_question_screen.dart';
import '../../../assessment_taking/presentation/providers/assessment_taking_provider.dart';
import '../providers/exams_providers.dart';

/// Published exams list. Starting an attempt goes through the exams
/// repository; submission/grading happen server-side via the
/// submitAssessmentAttempt callable (never written by the client).
class ExamsScreen extends ConsumerWidget {
  final String studentId;
  const ExamsScreen({required this.studentId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final examsAsync = ref.watch(publishedExamsStreamProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('الامتحانات')),
      body: examsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('لا توجد اختبارات متاحة حالياً.')),
        data: (exams) {
          final available =
              exams.where((exam) => exam.questions.isNotEmpty).toList();
          if (available.isEmpty) {
            return const Center(child: Text('لا توجد اختبارات متاحة حالياً.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: available.length,
            itemBuilder: (_, index) {
              final exam = available[index];
              return Card(
                child: ListTile(
                  leading:
                      const Icon(Icons.assignment_outlined, color: AppColors.primary),
                  title: Text(exam.title),
                  subtitle: Text(
                    exam.description.isEmpty
                        ? '${exam.questions.length} سؤال · ${exam.durationMinutes} دقيقة'
                        : exam.description,
                  ),
                  trailing: const Icon(Icons.play_arrow_rounded),
                  onTap: () => _startAttempt(context, ref, exam),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _startAttempt(
    BuildContext context,
    WidgetRef ref,
    dynamic exam,
  ) async {
    try {
      final attemptId = await ref
          .read(examsRepositoryProvider)
          .startExamAttempt(examId: exam.id, studentId: studentId);
      if (!context.mounted) return;

      final params = AssessmentTakingParams(
        attemptId: attemptId,
        assessmentId: exam.id,
        type: 'exam',
      );

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AssessmentQuestionScreen(params: params),
        ),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تسليم الامتحان بنجاح.')),
        );
      }
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyFunctionErrorMessage(error, 'تعذر بدء الاختبار.'))),
      );
    }
  }
}
