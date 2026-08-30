import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../providers/admin_content_providers.dart';
import 'admin_sections_screen.dart';

/// Functional subject picker — entry point of the Phase-1 authoring stack.
/// Plain placeholder UI (Presentation-Final is Figma-blocked); mirrors the
/// existing admin screens' look (Cards + ListTiles + AppColors.primary).
class AdminSubjectPickerScreen extends ConsumerWidget {
  const AdminSubjectPickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subjects = ref.watch(adminSubjectsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('إدارة الأقسام والمحاضرات')),
      body: subjects.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('تعذر تحميل المواد.'),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.invalidate(adminSubjectsProvider),
              child: const Text('إعادة المحاولة'),
            ),
          ]),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
                child: Text('لا توجد مواد. أنشئ مادة أولًا من شاشة إدارة المواد.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) => Card(
              child: ListTile(
                leading:
                    const Icon(Icons.menu_book_outlined, color: AppColors.primary),
                title: Text(list[i].title),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => AdminSectionsScreen(
                      subjectId: list[i].id, subjectTitle: list[i].title),
                )),
              ),
            ),
          );
        },
      ),
    );
  }
}
