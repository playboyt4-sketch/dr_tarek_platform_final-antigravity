import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_typography.dart';
import '../providers/subject_details_provider.dart';
import '../widgets/add_lecture_overlay.dart';
import '../widgets/dashboard_brand_lockup.dart';
import '../widgets/edit_subject_overlay.dart';
import '../widgets/grade_capsule_button.dart';
import '../widgets/grade_nav_bar.dart';
import '../widgets/grade_theme.dart';
import '../widgets/lecture_overlays.dart';

/// Dashboard Subject Details page (`Grade → Subject → Subject Details`).
///
/// Fixed 1280 x 800 canvas (same shell convention as the grade screens):
/// brand (370,24,540x80), grade nav (310,136,660x40), Students/Subjects
/// tabs (Subjects active), subject header card (540x88, radius 28,
/// grade border), three grade-fill capsule actions, four content tabs
/// (Lectures active), and the white lectures table (1118x251, radius 16).
///
/// One implementation serves all four grades and all four content tabs —
/// only the [GradeTheme] semantic color changes. Subject/lecture names,
/// ordering, and visibility render from the existing data model; the UI
/// only renders state and dispatches to [SubjectDetailsController].
class SubjectDetailsScreen extends ConsumerStatefulWidget {
  final String gradeKey;
  final String subjectId;

  final ValueChanged<String>? onGradeSelected;
  final VoidCallback? onStudentsTab;
  final VoidCallback? onSubjectsTab;
  final VoidCallback? onSubjectDeleted;

  /// Fired when the subject's grade changes through the Edit overlay so
  /// the shell can synchronize the details grade context without
  /// navigating away.
  final ValueChanged<String>? onSubjectGradeChanged;

  const SubjectDetailsScreen({
    super.key,
    required this.gradeKey,
    required this.subjectId,
    this.onGradeSelected,
    this.onStudentsTab,
    this.onSubjectsTab,
    this.onSubjectDeleted,
    this.onSubjectGradeChanged,
  });

  @override
  ConsumerState<SubjectDetailsScreen> createState() =>
      _SubjectDetailsScreenState();
}

class _SubjectDetailsScreenState extends ConsumerState<SubjectDetailsScreen> {
  SubjectContentTab _tab = SubjectContentTab.lectures;

  Color get _accent => GradeTheme.fromKey(widget.gradeKey).primaryColor;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<SubjectDetails> detailsAsync = ref.watch(
      subjectDetailsProvider(widget.subjectId),
    );

    return Material(
      color: const Color(0xFFFFFFFF),
      child: SizedBox(
        width: 1280,
        height: 800,
        child: Stack(
          children: <Widget>[
            const Positioned(
              left: 370,
              top: 24,
              width: 540,
              height: 80,
              child: IgnorePointer(child: DashboardBrandLockup()),
            ),
            Positioned(
              left: 310,
              top: 136,
              width: 660,
              height: 42,
              child: GradeNavBar(
                gradeKey: widget.gradeKey,
                onGradeSelected: (String key) =>
                    widget.onGradeSelected?.call(key),
              ),
            ),
            Positioned(
              left: 474,
              top: 190,
              width: 332,
              height: 40,
              child: StudentsSubjectsTabs(
                studentsActive: false,
                accent: _accent,
                onStudentsTap: widget.onStudentsTab,
                onSubjectsTap: widget.onSubjectsTab,
              ),
            ),
            Positioned(
              left: 320,
              top: 252,
              width: 640,
              height: 56,
              child: detailsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (Object error, StackTrace stackTrace) => const Center(
                  child: Text(
                    'Could not load subject.',
                    style: TextStyle(
                      fontFamily: 'Google Sans Flex',
                      fontSize: 14,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ),
                data: (SubjectDetails details) => _SubjectHeaderCard(
                  title: details.title,
                  isVisible: details.isVisible,
                  accent: _accent,
                  onToggle: (bool value) => ref
                      .read(subjectDetailsControllerProvider)
                      .setSubjectVisible(widget.subjectId, value),
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 324,
              width: 1280,
              height: 36,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  GradeCapsuleButton(
                    label: 'Edit',
                    gradeColor: _accent,
                    textColor: Colors.white,
                    width: 90,
                    height: 36,
                    onPressed: () =>
                        _openEditSubject(context, detailsAsync.value),
                  ),
                  const SizedBox(width: 14),
                  GradeCapsuleButton(
                    label: 'Add Lecture',
                    gradeColor: _accent,
                    textColor: Colors.white,
                    width: 130,
                    height: 36,
                    onPressed: () => _openAddLecture(context),
                  ),
                  const SizedBox(width: 14),
                  GradeCapsuleButton(
                    label: 'Delete Subject',
                    gradeColor: _accent,
                    textColor: Colors.white,
                    width: 130,
                    height: 36,
                    onPressed: () =>
                        _confirmDeleteSubject(context, detailsAsync.value),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 224,
              top: 396,
              width: 831,
              height: 32,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  for (final SubjectContentTab tab
                      in SubjectContentTab.values) ...<Widget>[
                    if (tab != SubjectContentTab.values.first)
                      const SizedBox(width: 48),
                    _ContentTab(
                      label: tab.label,
                      active: tab == _tab,
                      accent: _accent,
                      onTap: () => setState(() => _tab = tab),
                    ),
                  ],
                ],
              ),
            ),
            Positioned(
              left: 80,
              top: 440,
              width: 1120,
              height: 251,
              child: _LecturesTable(
                subjectId: widget.subjectId,
                tab: _tab,
                accent: _accent,
                onGradeFill: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAddLecture(BuildContext context) async {
    int initialOrder = 1;
    try {
      initialOrder = await ref
          .read(subjectDetailsControllerProvider)
          .nextLectureOrder(subjectId: widget.subjectId, tab: _tab);
    } catch (_) {
      initialOrder = 1;
    }
    if (!context.mounted) return;
    await AddLectureOverlay.show(
      context,
      subjectId: widget.subjectId,
      gradeKey: widget.gradeKey,
      tab: _tab,
      initialOrder: initialOrder,
      gradeColor: _accent,
    );
    // Saved lectures refresh the table through the live streams.
  }

  Future<void> _openEditSubject(
    BuildContext context,
    SubjectDetails? details,
  ) async {
    if (details == null) return;
    final bool? saved = await EditSubjectOverlay.show(
      context,
      gradeKey: widget.gradeKey,
      initialTitle: details.title,
      initialCoverUrl: details.coverUrl,
      gradeColor: _accent,
      onSave:
          ({
            required String gradeKey,
            required String title,
            required String coverUrl,
          }) async {
            await ref
                .read(subjectDetailsControllerProvider)
                .updateSubject(
                  widget.subjectId,
                  title: title,
                  gradeKey: gradeKey,
                  coverUrl: coverUrl,
                );
            if (gradeKey != widget.gradeKey) {
              widget.onSubjectGradeChanged?.call(gradeKey);
            }
          },
    );
    // On success the overlay closes itself; the live details stream
    // refreshes the header automatically. Nothing to do here.
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Subject saved.')));
    }
  }

  Future<void> _confirmDeleteSubject(
    BuildContext context,
    SubjectDetails? details,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Delete Subject'),
        content: Text(
          'Delete "${details?.title ?? 'this subject'}"? '
          'It will be archived and hidden from students.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFDC2626),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref
          .read(subjectDetailsControllerProvider)
          .deleteSubject(widget.subjectId);
      widget.onSubjectDeleted?.call();
    }
  }
}

/// Subject header bar — Figma `640 x 56`, radius 9999, `2px gradeColor`
/// border. Left: active toggle (`#10B981`); Right: Arabic subject title
/// (`22px Medium #111827`). White fill.
class _SubjectHeaderCard extends StatelessWidget {
  final String title;
  final bool isVisible;
  final Color accent;
  final ValueChanged<bool> onToggle;

  const _SubjectHeaderCard({
    required this.title,
    required this.isVisible,
    required this.accent,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 640,
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(color: accent, width: 2.0),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Switch(
            value: isVisible,
            activeTrackColor: const Color(0xFF10B981),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: onToggle,
          ),
          Flexible(
            child: Text(
              title,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Google Sans Flex',
                fontWeight: FontWeight.w500,
                fontSize: 22,
                color: Color(0xFF111827),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One content tab — label with a 60 x 2 grade underline when active.
class _ContentTab extends StatelessWidget {
  final String label;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  const _ContentTab({
    required this.label,
    required this.active,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 16,
              fontWeight: active ? FontWeight.w500 : FontWeight.w400,
              color: active ? accent : const Color(0xFF111827),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(top: 2),
            width: 60,
            height: 2,
            color: active ? accent : Colors.transparent,
          ),
        ],
      ),
    );
  }
}

/// Lectures table — Figma `1120` wide, radius 16, `#E5E7EB` border.
///
/// Header: No. (`80px`) / Lecture Name (Expanded) / Action (`160px`),
/// 14 px Regular #6B7280. Rows render `01.` + lecture name + Edit / Del
/// grade pills; row Edit opens the edit overlay, Delete archives after
/// confirmation.
class _LecturesTable extends ConsumerWidget {
  final String subjectId;
  final SubjectContentTab tab;
  final Color accent;
  final Color onGradeFill;

  const _LecturesTable({
    required this.subjectId,
    required this.tab,
    required this.accent,
    required this.onGradeFill,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<SubjectLecture>> lecturesAsync = ref.watch(
      tabLecturesProvider((subjectId: subjectId, tab: tab)),
    );

    return Container(
      width: 1120,
      height: 251,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: <Widget>[
          SizedBox(
            height: 32,
            child: Row(
              children: <Widget>[
                const SizedBox(
                  width: 80,
                  child: Text(
                    'No.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Google Sans Flex',
                      fontWeight: FontWeight.w400,
                      fontSize: 14,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    tab.contentNameLabel,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Google Sans Flex',
                      fontWeight: FontWeight.w400,
                      fontSize: 14,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ),
                const SizedBox(
                  width: 160,
                  child: Text(
                    'Action',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontFamily: 'Google Sans Flex',
                      fontWeight: FontWeight.w400,
                      fontSize: 14,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: const Color(0xFFE5E7EB)),
          Expanded(
            child: lecturesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object error, StackTrace stackTrace) => Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Could not load lectures.',
                      style: TextStyle(
                        fontFamily: 'Google Sans Flex',
                        fontSize: 14,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                    TextButton(
                      onPressed: () => ref.invalidate(
                        tabLecturesProvider((subjectId: subjectId, tab: tab)),
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (List<SubjectLecture> lectures) {
                if (lectures.isEmpty) {
                  return Center(
                    child: Text(
                      tab.emptyStateLabel,
                      style: const TextStyle(
                        fontFamily: 'Google Sans Flex',
                        fontSize: 14,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: lectures.length,
                  itemBuilder: (BuildContext context, int index) {
                    final SubjectLecture lecture = lectures[index];
                    return SizedBox(
                      height: 44,
                      child: Row(
                        children: <Widget>[
                          SizedBox(
                            width: 80,
                            child: Text(
                              '${lecture.displayOrder.toString().padLeft(2, '0')}.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: 'Google Sans Flex',
                                fontWeight: FontWeight.w400,
                                fontSize: 16,
                                color: Color(0xFF111827),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              lecture.title,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'Google Sans Flex',
                                fontWeight: FontWeight.w400,
                                fontSize: 16,
                                color: Color(0xFF111827),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 160,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: <Widget>[
                                GradeCapsuleButton(
                                  label: 'Edit',
                                  gradeColor: accent,
                                  textColor: onGradeFill,
                                  width: 64,
                                  height: 28,
                                  fontSize: 13,
                                  onPressed: () => showEditLectureOverlay(
                                    context,
                                    lectureTitle: lecture.title,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GradeCapsuleButton(
                                  label: 'Del',
                                  gradeColor: accent,
                                  textColor: onGradeFill,
                                  width: 56,
                                  height: 28,
                                  fontSize: 13,
                                  onPressed: () => _confirmDeleteLecture(
                                    context,
                                    ref,
                                    lecture,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteLecture(
    BuildContext context,
    WidgetRef ref,
    SubjectLecture lecture,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Delete Lecture'),
        content: Text(
          'Delete "${lecture.title}"? '
          'It will be archived and hidden from students.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFDC2626),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref
          .read(subjectDetailsControllerProvider)
          .deleteLecture(lecture.id);
    }
  }
}
