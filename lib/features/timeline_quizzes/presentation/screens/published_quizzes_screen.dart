import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/friendly_error_message.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../assessment_taking/presentation/screens/assessment_question_screen.dart';
import '../../../assessment_taking/presentation/providers/assessment_taking_provider.dart';
import '../providers/timeline_quizzes_providers.dart';

/// Published timeline quizzes list. Starting an attempt goes through the
/// quizzes repository; submission/grading happen server-side via the
/// submitAssessmentAttempt callable (never written by the client).
class QuizzesScreen extends ConsumerWidget {
  final String studentId;
  const QuizzesScreen({required this.studentId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quizzesAsync = ref.watch(publishedQuizzesStreamProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('الاختبارات القصيرة')),
      body: quizzesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('لا توجد اختبارات متاحة حالياً.')),
        data: (quizzes) {
          final available =
              quizzes.where((quiz) => quiz.questions.isNotEmpty).toList();
          if (available.isEmpty) {
            return const Center(child: Text('لا توجد اختبارات متاحة حالياً.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: available.length,
            itemBuilder: (_, index) {
              final quiz = available[index];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.quiz_outlined, color: AppColors.primary),
                  title: Text(quiz.title),
                  subtitle: Text('${quiz.questions.length} سؤال'),
                  trailing: const Icon(Icons.play_arrow_rounded),
                  onTap: () => _startAttempt(context, ref, quiz),
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
    dynamic quiz,
  ) async {
    try {
      final attemptId = await ref
          .read(timelineQuizzesRepositoryProvider)
          .startQuizAttempt(quizId: quiz.id, studentId: studentId);
      if (!context.mounted) return;

      final params = AssessmentTakingParams(
        attemptId: attemptId,
        assessmentId: quiz.id,
        type: 'quiz',
      );

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AssessmentQuestionScreen(params: params),
        ),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تسليم الاختبار بنجاح.')),
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

