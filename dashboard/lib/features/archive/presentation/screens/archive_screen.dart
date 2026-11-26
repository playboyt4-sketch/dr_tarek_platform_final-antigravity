import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../students/presentation/widgets/grade_theme.dart';
import '../providers/archive_provider.dart';

enum ArchiveTab { students, subjects, lectures }

/// Responsive Archive screen under Management: displays soft-deleted
/// Students, Subjects, and Lectures with one-tap Restore and confirmed
/// permanent deletion.
class ArchiveScreen extends ConsumerStatefulWidget {
  const ArchiveScreen({super.key});

  @override
  ConsumerState<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends ConsumerState<ArchiveScreen> {
  ArchiveTab _tab = ArchiveTab.students;
  final Set<String> _busyIds = <String>{};

  Future<void> _confirmAndRestore({
    required String itemKey,
    required String itemLabel,
    required String entityLabel,
    required Future<void> Function() action,
  }) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('Restore $entityLabel'),
        content: Text(
          'Restore "$itemLabel" back to active lists?\n'
          'سيتم استعادة "$itemLabel" إلى القوائم النشطة.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _runMutation(
      itemKey: itemKey,
      action: action,
      successMessage: '$entityLabel restored successfully.',
    );
  }

  Future<void> _confirmAndDeletePermanently({
    required String itemKey,
    required String itemLabel,
    required String entityType,
    required String entityLabel,
    required String targetId,
  }) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text(
          'Delete Permanently',
          style: TextStyle(color: Color(0xFFDC2626)),
        ),
        content: Text(
          'Are you sure you want to permanently delete "$itemLabel"? '
          'This action cannot be undone and removes the record from Firestore.\n\n'
          'تحذير: الحذف النهائي لا يمكن التراجع عنه وسيحذف البيانات بشكل دائم.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _runMutation(
      itemKey: itemKey,
      action: () => ref.read(archiveControllerProvider).permanentlyDelete(
            entityType: entityType,
            targetId: targetId,
          ),
      successMessage: '$entityLabel permanently deleted.',
    );
  }

  Future<void> _runMutation({
    required String itemKey,
    required Future<void> Function() action,
    required String successMessage,
  }) async {
    setState(() => _busyIds.add(itemKey));
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      if (!mounted) return;
      invalidateArchiveDependents(ref);
      messenger.showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFDC2626),
          content: Text('Operation failed: $error'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busyIds.remove(itemKey));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<ArchivedStudentItem>> studentsAsync =
        ref.watch(archivedStudentsProvider);
    final AsyncValue<List<ArchivedSubjectItem>> subjectsAsync =
        ref.watch(archivedSubjectsProvider);
    final AsyncValue<List<ArchivedLectureItem>> lecturesAsync =
        ref.watch(archivedLecturesProvider);

    final int studentsCount = studentsAsync.asData?.value.length ?? 0;
    final int subjectsCount = subjectsAsync.asData?.value.length ?? 0;
    final int lecturesCount = lecturesAsync.asData?.value.length ?? 0;

    return ColoredBox(
      color: AppColors.background,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final DashboardBreakpoint breakpoint =
              breakpointForWidth(constraints.maxWidth);
          final bool isMobile = breakpoint == DashboardBreakpoint.mobile;
          final double horizontalPadding = switch (breakpoint) {
            DashboardBreakpoint.mobile => 16,
            DashboardBreakpoint.tablet => 28,
            DashboardBreakpoint.desktop => 48,
          };

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              isMobile ? 16 : 24,
              horizontalPadding,
              32,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const ResponsiveScreenHeader(),
                SizedBox(height: isMobile ? 16 : 24),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1080),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(
                          'Archive',
                          style: TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontSize: isMobile ? 28 : 38,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Manage archived students, subjects, and lectures. Restore items to active lists or delete them permanently.',
                          style: TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontSize: 15,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _ArchiveTabBar(
                          selected: _tab,
                          studentsCount: studentsCount,
                          subjectsCount: subjectsCount,
                          lecturesCount: lecturesCount,
                          onSelect: (ArchiveTab tab) =>
                              setState(() => _tab = tab),
                        ),
                        const SizedBox(height: 20),
                        _buildTabContent(
                          isMobile: isMobile,
                          studentsAsync: studentsAsync,
                          subjectsAsync: subjectsAsync,
                          lecturesAsync: lecturesAsync,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTabContent({
    required bool isMobile,
    required AsyncValue<List<ArchivedStudentItem>> studentsAsync,
    required AsyncValue<List<ArchivedSubjectItem>> subjectsAsync,
    required AsyncValue<List<ArchivedLectureItem>> lecturesAsync,
  }) {
    switch (_tab) {
      case ArchiveTab.students:
        return studentsAsync.when(
          loading: () => const _ArchiveLoading(),
          error: (Object err, StackTrace _) =>
              _ArchiveError('Could not load archived students: $err'),
          data: (List<ArchivedStudentItem> items) {
            if (items.isEmpty) {
              return const _ArchiveEmpty('No archived students.');
            }
            return Column(
              children: <Widget>[
                for (int i = 0; i < items.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(height: 12),
                  _ArchiveItemCard(
                    isMobile: isMobile,
                    busy: _busyIds.contains('student:${items[i].id}'),
                    icon: Icons.person_off_outlined,
                    badgeColor: GradeTheme.fromKey(items[i].gradeKey).primaryColor,
                    badgeText: GradeTheme.fromKey(items[i].gradeKey).title,
                    title: items[i].name,
                    subtitle:
                        '${items[i].phone}  •  ${items[i].isCenter ? 'Center Student' : 'Guest'}',
                    archivedAtText:
                        'Archived: ${formatArchiveDate(items[i].archivedAt)}',
                    onRestore: () => _confirmAndRestore(
                      itemKey: 'student:${items[i].id}',
                      itemLabel: items[i].name,
                      entityLabel: 'Student',
                      action: () => ref
                          .read(archiveControllerProvider)
                          .restoreStudent(items[i].id),
                    ),
                    onDeletePermanently: () => _confirmAndDeletePermanently(
                      itemKey: 'student:${items[i].id}',
                      itemLabel: items[i].name,
                      entityType: 'student',
                      entityLabel: 'Student',
                      targetId: items[i].id,
                    ),
                  ),
                ],
              ],
            );
          },
        );
      case ArchiveTab.subjects:
        return subjectsAsync.when(
          loading: () => const _ArchiveLoading(),
          error: (Object err, StackTrace _) =>
              _ArchiveError('Could not load archived subjects: $err'),
          data: (List<ArchivedSubjectItem> items) {
            if (items.isEmpty) {
              return const _ArchiveEmpty('No archived subjects.');
            }
            return Column(
              children: <Widget>[
                for (int i = 0; i < items.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(height: 12),
                  _ArchiveItemCard(
                    isMobile: isMobile,
                    busy: _busyIds.contains('subject:${items[i].id}'),
                    icon: Icons.menu_book_outlined,
                    badgeColor: GradeTheme.fromKey(items[i].gradeKey).primaryColor,
                    badgeText: GradeTheme.fromKey(items[i].gradeKey).title,
                    title: items[i].title,
                    subtitle: 'Subject ID: ${items[i].id}',
                    archivedAtText:
                        'Archived: ${formatArchiveDate(items[i].archivedAt)}',
                    onRestore: () => _confirmAndRestore(
                      itemKey: 'subject:${items[i].id}',
                      itemLabel: items[i].title,
                      entityLabel: 'Subject',
                      action: () => ref
                          .read(archiveControllerProvider)
                          .restoreSubject(items[i].id),
                    ),
                    onDeletePermanently: () => _confirmAndDeletePermanently(
                      itemKey: 'subject:${items[i].id}',
                      itemLabel: items[i].title,
                      entityType: 'subject',
                      entityLabel: 'Subject',
                      targetId: items[i].id,
                    ),
                  ),
                ],
              ],
            );
          },
        );
      case ArchiveTab.lectures:
        return lecturesAsync.when(
          loading: () => const _ArchiveLoading(),
          error: (Object err, StackTrace _) =>
              _ArchiveError('Could not load archived lectures: $err'),
          data: (List<ArchivedLectureItem> items) {
            if (items.isEmpty) {
              return const _ArchiveEmpty('No archived lectures.');
            }
            return Column(
              children: <Widget>[
                for (int i = 0; i < items.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(height: 12),
                  _ArchiveItemCard(
                    isMobile: isMobile,
                    busy: _busyIds.contains('lecture:${items[i].id}'),
                    icon: Icons.video_library_outlined,
                    badgeColor: const Color(0xFF4B5563),
                    badgeText: 'Lecture',
                    title: items[i].title,
                    subtitle: 'Subject: ${items[i].subjectTitle}',
                    archivedAtText:
                        'Archived: ${formatArchiveDate(items[i].archivedAt)}',
                    onRestore: () => _confirmAndRestore(
                      itemKey: 'lecture:${items[i].id}',
                      itemLabel: items[i].title,
                      entityLabel: 'Lecture',
                      action: () => ref
                          .read(archiveControllerProvider)
                          .restoreLecture(items[i].id),
                    ),
                    onDeletePermanently: () => _confirmAndDeletePermanently(
                      itemKey: 'lecture:${items[i].id}',
                      itemLabel: items[i].title,
                      entityType: 'lecture',
                      entityLabel: 'Lecture',
                      targetId: items[i].id,
                    ),
                  ),
                ],
              ],
            );
          },
        );
    }
  }
}

class _ArchiveTabBar extends StatelessWidget {
  final ArchiveTab selected;
  final int studentsCount;
  final int subjectsCount;
  final int lecturesCount;
  final ValueChanged<ArchiveTab> onSelect;

  const _ArchiveTabBar({
    required this.selected,
    required this.studentsCount,
    required this.subjectsCount,
    required this.lecturesCount,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          _TabPill(
            label: 'Students ($studentsCount)',
            selected: selected == ArchiveTab.students,
            onTap: () => onSelect(ArchiveTab.students),
          ),
          const SizedBox(width: 10),
          _TabPill(
            label: 'Subjects ($subjectsCount)',
            selected: selected == ArchiveTab.subjects,
            onTap: () => onSelect(ArchiveTab.subjects),
          ),
          const SizedBox(width: 10),
          _TabPill(
            label: 'Lectures ($lecturesCount)',
            selected: selected == ArchiveTab.lectures,
            onTap: () => onSelect(ArchiveTab.lectures),
          ),
        ],
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF111827) : Colors.white,
          borderRadius: BorderRadius.circular(9999),
          border: Border.all(
            color: selected ? const Color(0xFF111827) : const Color(0xFFD1D5DB),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: selected ? Colors.white : const Color(0xFF374151),
          ),
        ),
      ),
    );
  }
}

class _ArchiveItemCard extends StatelessWidget {
  final bool isMobile;
  final bool busy;
  final IconData icon;
  final Color badgeColor;
  final String badgeText;
  final String title;
  final String subtitle;
  final String archivedAtText;
  final VoidCallback onRestore;
  final VoidCallback onDeletePermanently;

  const _ArchiveItemCard({
    required this.isMobile,
    required this.busy,
    required this.icon,
    required this.badgeColor,
    required this.badgeText,
    required this.title,
    required this.subtitle,
    required this.archivedAtText,
    required this.onRestore,
    required this.onDeletePermanently,
  });

  @override
  Widget build(BuildContext context) {
    final Widget actions = busy
        ? const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        : Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: onRestore,
                icon: const Icon(Icons.restore_rounded, size: 18),
                label: const Text('Restore'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF059669),
                  side: const BorderSide(color: Color(0xFF10B981)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9999),
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: onDeletePermanently,
                icon: const Icon(Icons.delete_forever_outlined, size: 18),
                label: const Text('Delete Permanently'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9999),
                  ),
                ),
              ),
            ],
          );

    final Widget info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text(
              title,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9999),
              ),
              child: Text(
                badgeText,
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: badgeColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 13,
            color: Color(0xFF4B5563),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          archivedAtText,
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 12,
            color: Color(0xFF6B7280),
          ),
        ),
      ],
    );

    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: const Color(0xFFF3F4F6),
                      child: Icon(icon, color: const Color(0xFF4B5563), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: info),
                  ],
                ),
                const SizedBox(height: 14),
                actions,
              ],
            )
          : Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 22,
                  backgroundColor: const Color(0xFFF3F4F6),
                  child: Icon(icon, color: const Color(0xFF4B5563), size: 22),
                ),
                const SizedBox(width: 16),
                Expanded(child: info),
                const SizedBox(width: 16),
                actions,
              ],
            ),
    );
  }
}

class _ArchiveLoading extends StatelessWidget {
  const _ArchiveLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _ArchiveEmpty extends StatelessWidget {
  final String message;

  const _ArchiveEmpty(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      alignment: Alignment.center,
      child: Text(
        message,
        style: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 15,
          color: Color(0xFF6B7280),
        ),
      ),
    );
  }
}

class _ArchiveError extends StatelessWidget {
  final String message;

  const _ArchiveError(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 14,
          color: Color(0xFFB91C1C),
        ),
      ),
    );
  }
}
