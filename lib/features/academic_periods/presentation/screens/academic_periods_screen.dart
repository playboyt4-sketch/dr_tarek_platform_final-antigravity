import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../authentication/domain/entities/auth_user.dart';
import '../../domain/entities/academic_period.dart';
import '../providers/academic_period_provider.dart';

/// Academic periods control screen.
///
/// Teacher (Platform Owner) only. Every period - core or exceptional - is
/// rendered with a single [CupertinoSwitch]: green means the period is
/// active (started), grey means it has ended.
class AcademicPeriodsScreen extends ConsumerWidget {
  final AuthUser user;

  const AcademicPeriodsScreen({required this.user, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (user.role != 'teacher') {
      return const Scaffold(
        body: Center(child: Text('هذه الشاشة متاحة للمعلم (مالك المنصة) فقط.')),
      );
    }

    final periods = ref.watch(academicPeriodsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('الفترات الدراسية')),
      body: periods.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('تعذر تحميل الفترات الدراسية.\n$error', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => ref.invalidate(academicPeriodsProvider),
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
        ),
        data: (items) => _AcademicPeriodsBody(periods: items),
      ),
    );
  }
}

class _AcademicPeriodsBody extends ConsumerWidget {
  final List<AcademicPeriod> periods;

  const _AcademicPeriodsBody({required this.periods});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final corePeriods = periods.where((period) => period.isCore).toList()
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    final exceptionalPeriods = periods.where((period) => !period.isCore).toList()
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

    final hasCorePeriods = corePeriods.length >= 3;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      children: [
        Text('الفترات الدراسية', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        const Text(
          'تشغيل وإيقاف الفترات متاح للمعلم (مالك المنصة) فقط. الاشتراكات تبدأ مع بداية الفترة وتنتهي تلقائياً عند إنهائها.',
        ),
        const SizedBox(height: 20),

        if (!hasCorePeriods) ...[
          AppButton(
            label: 'تهيئة الفترات الأساسية',
            icon: Icons.calendar_month_outlined,
            onPressed: () => _initialize(context, ref),
          ),
          const SizedBox(height: 16),
        ],

        // Core periods first, in a fixed order.
        ...corePeriods.map((period) => _PeriodCard(period: period)),

        if (exceptionalPeriods.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('فترات استثنائية', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...exceptionalPeriods.map((period) => _PeriodCard(period: period)),
        ],

        const SizedBox(height: 16),

        AppButton(
          label: '+ إضافة فترة استثنائية',
          icon: Icons.add_circle_outline,
          variant: AppButtonVariant.outlined,
          onPressed: () => _createExceptional(context, ref),
        ),
      ],
    );
  }

  Future<void> _initialize(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(academicPeriodRepositoryProvider).initializeDefaultPeriods();
      ref.invalidate(academicPeriodsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تمت تهيئة الفترات الدراسية الأساسية.')),
        );
      }
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _createExceptional(BuildContext context, WidgetRef ref) async {
    final labelController = TextEditingController();

    final label = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('إضافة فترة استثنائية'),
          content: TextField(
            controller: labelController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'اسم الفترة (مثال: تدريب فردي)',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                final value = labelController.text.trim();
                if (value.isEmpty) return;
                Navigator.pop(dialogContext, value);
              },
              child: const Text('إنشاء'),
            ),
          ],
        );
      },
    );

    labelController.dispose();

    if (label == null || !context.mounted) return;

    try {
      await ref
          .read(academicPeriodRepositoryProvider)
          .createExceptionalPeriod(label: label);
      ref.invalidate(academicPeriodsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إنشاء الفترة الاستثنائية.')),
        );
      }
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  void _showError(BuildContext context, Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('فشلت العملية: $error')),
    );
  }
}

class _PeriodCard extends ConsumerWidget {
  final AcademicPeriod period;

  const _PeriodCard({required this.period});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = period.isActive;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        title: Text(period.label),
        subtitle: Text(
          isActive ? 'الفترة نشطة (بدأت)' : 'الفترة منتهية',
          style: TextStyle(
            color: isActive ? AppColors.success : AppColors.muted,
            fontSize: 12,
          ),
        ),
        leading: Icon(
          isActive ? Icons.play_circle_outline : Icons.check_circle_outline,
          color: isActive ? AppColors.success : AppColors.muted,
        ),
        trailing: CupertinoSwitch(
          value: isActive,
          activeTrackColor: AppColors.success,
          onChanged: (value) => _changeStatus(context, ref, value),
        ),
      ),
    );
  }

  Future<void> _changeStatus(
    BuildContext context,
    WidgetRef ref,
    bool activate,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(activate ? 'بدء ${period.label}؟' : 'إنهاء ${period.label}؟'),
          content: Text(
            activate
                ? 'ستصبح الفترة نشطة فوراً وسترتبط بها الاشتراكات الجديدة.'
                : 'سيتم إنهاء الفترة فوراً وإنهاء كل الاشتراكات المرتبطة بها تلقائياً.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('تأكيد'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(academicPeriodRepositoryProvider).setStatus(
            periodId: period.id,
            status: activate
                ? AcademicPeriodStatus.active
                : AcademicPeriodStatus.ended,
          );
      ref.invalidate(academicPeriodsProvider);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشلت العملية: $error')),
        );
      }
    }
  }
}
