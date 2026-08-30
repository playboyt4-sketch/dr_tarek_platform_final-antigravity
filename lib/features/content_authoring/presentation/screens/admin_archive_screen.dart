import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/errors/friendly_error_message.dart'
    show mapFunctionErrorCode;
import '../../../../core/theme/app_colors.dart';
import '../providers/admin_content_providers.dart';

/// Archive System (Part B): every soft-deleted (is_deleted == true)
/// section/lecture/resource of the subject, with clear metadata
/// (deleted_at, deleted_by, archived-from subject) and a one-tap Restore.
/// Restore never hard-deletes anything and never auto-publishes: lectures
/// come back as drafts and resources come back hidden.
class AdminArchiveScreen extends ConsumerWidget {
  final String subjectId;
  final String subjectTitle;

  const AdminArchiveScreen({
    super.key,
    required this.subjectId,
    required this.subjectTitle,
  });

  String _dateLabel(DateTime? d) => d == null
      ? '—'
      : '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  Future<void> _restore(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action,
  ) async {
    try {
      await action();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم الاسترجاع من الأرشيف.')));
      }
    } on Failure catch (failure) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(mapFunctionErrorCode(
                'permission-denied', failure.debugDetail, 'تعذر الاسترجاع.'))));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تعذر الاسترجاع.')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = ref.watch(adminArchivedSectionsProvider(subjectId));
    final lectures = ref.watch(adminArchivedLecturesProvider(subjectId));

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('الأرشيف — $subjectTitle'),
          bottom: const TabBar(tabs: [
            Tab(text: 'الأقسام المؤرشفة'),
            Tab(text: 'المحاضرات المؤرشفة'),
          ]),
        ),
        body: TabBarView(
          children: [
            // ---- Archived sections ----
            sections.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) =>
                  const Center(child: Text('تعذر تحميل الأقسام المؤرشفة.')),
              data: (list) {
                if (list.isEmpty) {
                  return const Center(child: Text('لا توجد أقسام مؤرشفة.'));
                }
                return ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final s = list[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      child: ListTile(
                        leading: const Icon(Icons.inventory_2_outlined,
                            color: AppColors.muted),
                        title: Text(s.title),
                        subtitle: Text(
                          '${s.isSystemSection ? "قسم نظامي" : "قسم مخصص"}'
                          ' • مؤرشف من: $subjectTitle'
                          ' • بتاريخ ${_dateLabel(s.deletedAt)}',
                        ),
                        trailing: FilledButton.tonalIcon(
                          onPressed: () => _restore(
                            context,
                            ref,
                            () => ref
                                .read(restoreSectionUseCaseProvider)
                                .execute(s),
                          ),
                          icon: const Icon(Icons.restore),
                          label: const Text('استرجاع'),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
            // ---- Archived lectures (+ their archived resources) ----
            lectures.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) =>
                  const Center(child: Text('تعذر تحميل المحاضرات المؤرشفة.')),
              data: (list) {
                if (list.isEmpty) {
                  return const Center(child: Text('لا توجد محاضرات مؤرشفة.'));
                }
                return ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final l = list[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      child: ListTile(
                        leading: const Icon(Icons.video_library_outlined,
                            color: AppColors.muted),
                        title: Text(l.title),
                        subtitle: Text(
                          'مؤرشفة من: $subjectTitle'
                          ' • بتاريخ ${_dateLabel(l.deletedAt)}'
                          '${l.deletedBy != null ? " • بواسطة ${l.deletedBy}" : ""}',
                        ),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            tooltip: 'الموارد المؤرشفة',
                            icon: const Icon(Icons.folder_open_outlined),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => _ArchivedResourcesScreen(
                                  lectureId: l.id,
                                  lectureTitle: l.title,
                                  dateLabel: _dateLabel,
                                  onRestore: (context, ref, action) =>
                                      _restore(context, ref, action),
                                ),
                              ),
                            ),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () => _restore(
                              context,
                              ref,
                              () => ref
                                  .read(restoreLectureUseCaseProvider)
                                  .execute(l),
                            ),
                            icon: const Icon(Icons.restore),
                            label: const Text('استرجاع'),
                          ),
                        ]),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Archived resources of one archived lecture (Part B completeness).
class _ArchivedResourcesScreen extends ConsumerWidget {
  final String lectureId;
  final String lectureTitle;
  final String Function(DateTime?) dateLabel;
  final Future<void> Function(
          BuildContext, WidgetRef, Future<void> Function()) onRestore;

  const _ArchivedResourcesScreen({
    required this.lectureId,
    required this.lectureTitle,
    required this.dateLabel,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resources = ref.watch(adminArchivedResourcesProvider(lectureId));
    return Scaffold(
      appBar: AppBar(title: Text('الموارد المؤرشفة — $lectureTitle')),
      body: resources.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('تعذر تحميل الموارد المؤرشفة.')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('لا توجد موارد مؤرشفة.'));
          }
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) {
              final r = list[i];
              return Card(
                margin:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  title: Text(r.title.isEmpty ? 'مورد بدون عنوان' : r.title),
                  subtitle: Text(
                    'مؤرشف • بتاريخ ${dateLabel(r.deletedAt)}',
                  ),
                  trailing: FilledButton.tonalIcon(
                    onPressed: () => onRestore(
                      context,
                      ref,
                      () => ref
                          .read(restoreResourceUseCaseProvider)
                          .execute(r.id),
                    ),
                    icon: const Icon(Icons.restore),
                    label: const Text('استرجاع'),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
