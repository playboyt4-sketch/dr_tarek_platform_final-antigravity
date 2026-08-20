import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../student_dashboard/domain/entities/dashboard_subject.dart';
import '../../domain/entities/subject_learning_entities.dart';
import '../providers/subject_navigation_providers.dart';
import '../../../video_streaming/presentation/screens/video_streaming_screen.dart';

/// TODO: replace with Figma-precise geometry when 03_UI_UX.md is Approved for this screen.
class SubjectNavigationScreen extends ConsumerStatefulWidget {
  final DashboardSubject subject;

  const SubjectNavigationScreen({required this.subject, super.key});

  @override
  ConsumerState<SubjectNavigationScreen> createState() =>
      _SubjectNavigationScreenState();
}

class _SubjectNavigationScreenState
    extends ConsumerState<SubjectNavigationScreen> {
  String? selectedSectionId;

  @override
  Widget build(BuildContext context) {
    final sections = ref.watch(subjectSectionsProvider(widget.subject.id));

    return Scaffold(
      appBar: AppBar(title: Text(widget.subject.title)),
      body: sections.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _MessageState(
          message: 'تعذر تحميل أقسام المادة.',
          action: TextButton(
            onPressed: () =>
                ref.invalidate(subjectSectionsProvider(widget.subject.id)),
            child: const Text('إعادة المحاولة'),
          ),
        ),
        data: (items) {
          final visible = items.where((item) => item.isVisible).toList();
          if (visible.isEmpty) {
            return const _MessageState(
              message: 'لا توجد أقسام منشورة في هذه المادة بعد.',
            );
          }
          final currentId = selectedSectionId ?? visible.first.id;
          final current = visible.firstWhere(
            (item) => item.id == currentId,
            orElse: () => visible.first,
          );
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SectionSelector(
                sections: visible,
                selectedId: current.id,
                onSelected: (section) =>
                    setState(() => selectedSectionId = section.id),
              ),
              const SizedBox(height: 24),
              Text('المحاضرات', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              if (current.isLocked)
                const _MessageState(
                  message: 'هذا القسم مقفل ضمن اشتراكك الحالي.',
                )
              else
                _LecturesList(
                  subjectId: widget.subject.id,
                  sectionId: current.id,
                  seasons: visible,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionSelector extends StatelessWidget {
  final List<LearningSection> sections;
  final String selectedId;
  final ValueChanged<LearningSection> onSelected;

  const _SectionSelector({
    required this.sections,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: sections.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          final section = sections[index];
          final selected = section.id == selectedId;
          return ChoiceChip(
            selected: selected,
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (section.isLocked) const Icon(Icons.lock_outline, size: 16),
                if (section.isLocked) const SizedBox(width: 4),
                Text(section.title),
              ],
            ),
            selectedColor: AppColors.primary.withValues(alpha: .16),
            onSelected: (_) => onSelected(section),
          );
        },
      ),
    );
  }
}

class _LecturesList extends ConsumerWidget {
  final String subjectId;
  final String sectionId;
  final List<LearningSection> seasons;

  const _LecturesList({
    required this.subjectId,
    required this.sectionId,
    required this.seasons,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lectures = ref.watch(sectionLecturesProvider(sectionId));
    return lectures.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) =>
          const _MessageState(message: 'تعذر تحميل المحاضرات.'),
      data: (items) => items.isEmpty
          ? const _MessageState(message: 'لا توجد محاضرات منشورة في هذا القسم.')
          : Column(
              children: items
                  .map(
                    (lecture) => _LectureTile(
                      subjectId: subjectId,
                      sectionId: sectionId,
                      seasons: seasons,
                      episodes: items,
                      loadEpisodes: (id) =>
                          ref.read(sectionLecturesProvider(id).future),
                      lecture: lecture,
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

class _LectureTile extends StatelessWidget {
  final String subjectId;
  final String sectionId;
  final List<LearningSection> seasons;
  final List<LectureSummary> episodes;
  final Future<List<LectureSummary>> Function(String sectionId) loadEpisodes;
  final LectureSummary lecture;

  const _LectureTile({
    required this.subjectId,
    required this.sectionId,
    required this.seasons,
    required this.episodes,
    required this.loadEpisodes,
    required this.lecture,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: lecture.isLocked
              ? AppColors.divider
              : AppColors.primary.withValues(alpha: .12),
          child: Icon(
            lecture.isLocked ? Icons.lock_outline : Icons.play_arrow_rounded,
            color: lecture.isLocked ? AppColors.muted : AppColors.primary,
          ),
        ),
        title: Text(lecture.title),
        subtitle: Text(_statusLabel(lecture.status)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: lecture.isLocked
            ? null
            : () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => VideoStreamingScreen(
                    subjectId: subjectId,
                    initialEpisode: lecture,
                    episodes: episodes,
                    seasons: seasons,
                    loadEpisodes: loadEpisodes,
                  ),
                ),
              ),
      ),
    );
  }

  String _statusLabel(String status) => switch (status) {
    'completed' => 'مكتملة',
    'in_progress' => 'قيد المشاهدة',
    _ => 'لم تبدأ بعد',
  };
}

List<Widget> _optionalAction(Widget? action) =>
    action == null ? const [] : [action];

class _MessageState extends StatelessWidget {
  final String message;
  final Widget? action;

  const _MessageState({required this.message, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.menu_book_outlined,
              size: 48,
              color: AppColors.muted,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            ..._optionalAction(action),
          ],
        ),
      ),
    );
  }
}
