import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_typography.dart';
import '../providers/grade_students_provider.dart';
import '../providers/student_profile_activity_provider.dart';
import 'grade_students_screen.dart' show gradeAccent;

enum _ActivityRange { all, today, last7Days, last30Days }

/// Comprehensive, real-time per-student activity & video watch audit tab inside
/// the Student Profile screen.
///
/// Shows:
/// - KPI summary (videos opened / completed, total watch time, avg completion,
///   last active timestamp);
/// - Date filter (`الكل`, `اليوم`, `آخر 7 أيام`, `آخر 30 يوم`);
/// - Video & PDF Watch Audit table (exact minute reached vs total duration,
///   completion %, Completed vs Partial badge, PDF page reached, last watch time);
/// - Daily Activity Timeline grouped by day (`analytics_events`);
/// - Quizzes & Exams attempts summary (when present).
class StudentProfileActivityTab extends ConsumerStatefulWidget {
  final GradeStudent student;
  final String gradeKey;

  const StudentProfileActivityTab({
    super.key,
    required this.student,
    required this.gradeKey,
  });

  @override
  ConsumerState<StudentProfileActivityTab> createState() =>
      _StudentProfileActivityTabState();
}

class _StudentProfileActivityTabState
    extends ConsumerState<StudentProfileActivityTab> {
  _ActivityRange _range = _ActivityRange.all;

  Color get _accent => gradeAccent(widget.gradeKey);

  bool _inSelectedRange(DateTime? dt) {
    if (_range == _ActivityRange.all) return true;
    if (dt == null) return false;
    final DateTime now = DateTime.now();
    final DateTime todayStart = DateTime(now.year, now.month, now.day);
    return switch (_range) {
      _ActivityRange.all => true,
      _ActivityRange.today => !dt.isBefore(todayStart),
      _ActivityRange.last7Days =>
        !dt.isBefore(todayStart.subtract(const Duration(days: 6))),
      _ActivityRange.last30Days =>
        !dt.isBefore(todayStart.subtract(const Duration(days: 29))),
    };
  }

  static String _formatDateTime(DateTime? dt) {
    if (dt == null) return '—';
    final String hh = dt.hour.toString().padLeft(2, '0');
    final String mm = dt.minute.toString().padLeft(2, '0');
    return '${dt.day}/${dt.month}/${dt.year} • $hh:$mm';
  }

  static String _dayHeader(DateTime? dt) {
    if (dt == null) return 'تاريخ غير محدد';
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime target = DateTime(dt.year, dt.month, dt.day);
    final int diff = today.difference(target).inDays;
    if (diff == 0) return 'اليوم (${dt.day}/${dt.month}/${dt.year})';
    if (diff == 1) return 'أمس (${dt.day}/${dt.month}/${dt.year})';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<StudentActivityData> activityAsync =
        ref.watch(studentProfileActivityProvider(widget.student.id));

    return Directionality(
      textDirection: TextDirection.rtl,
      child: activityAsync.when(
        loading: () => const SizedBox(
          height: 220,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (Object error, StackTrace _) => Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                'تعذّر تحميل سجل نشاط الطالب حالياً.',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 15,
                  color: Color(0xFF6B7280),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => ref.invalidate(
                  studentProfileActivityProvider(widget.student.id),
                ),
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
        data: (StudentActivityData raw) {
          final List<StudentLectureWatchRecord> lectures = raw.lectures
              .where((StudentLectureWatchRecord r) =>
                  _inSelectedRange(r.updatedAt))
              .toList(growable: false);
          final List<StudentActivityEvent> events = raw.events
              .where((StudentActivityEvent e) => _inSelectedRange(e.createdAt))
              .toList(growable: false);
          final List<StudentAssessmentRecord> assessments = raw.assessments
              .where(
                  (StudentAssessmentRecord a) => _inSelectedRange(a.createdAt))
              .toList(growable: false);

          final StudentActivityData filtered = StudentActivityData(
            lectures: lectures,
            events: events,
            assessments: assessments,
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _RangeFilterBar(
                selected: _range,
                accent: _accent,
                onChanged: (_ActivityRange next) =>
                    setState(() => _range = next),
              ),
              const SizedBox(height: 16),
              _SummaryKpiRow(
                data: filtered,
                accent: _accent,
                lastActivityLabel: _formatDateTime(filtered.lastActivityAt),
              ),
              const SizedBox(height: 20),
              _VideoWatchAuditSection(
                lectures: lectures,
                accent: _accent,
                formatDateTime: _formatDateTime,
              ),
              if (assessments.isNotEmpty) ...<Widget>[
                const SizedBox(height: 20),
                _AssessmentsSection(
                  assessments: assessments,
                  accent: _accent,
                  formatDateTime: _formatDateTime,
                ),
              ],
              const SizedBox(height: 20),
              _DailyEventsTimelineSection(
                events: events,
                accent: _accent,
                dayHeader: _dayHeader,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RangeFilterBar extends StatelessWidget {
  final _ActivityRange selected;
  final Color accent;
  final ValueChanged<_ActivityRange> onChanged;

  const _RangeFilterBar({
    required this.selected,
    required this.accent,
    required this.onChanged,
  });

  static const List<(_ActivityRange, String)> _options =
      <(_ActivityRange, String)>[
    (_ActivityRange.all, 'الكل'),
    (_ActivityRange.today, 'اليوم'),
    (_ActivityRange.last7Days, 'آخر 7 أيام'),
    (_ActivityRange.last30Days, 'آخر 30 يوم'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: <Widget>[
        for (final (_ActivityRange value, String label) in _options)
          ChoiceChip(
            label: Text(
              label,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected == value ? Colors.white : const Color(0xFF374151),
              ),
            ),
            selected: selected == value,
            selectedColor: accent,
            backgroundColor: const Color(0xFFF3F4F6),
            showCheckmark: false,
            onSelected: (_) => onChanged(value),
          ),
      ],
    );
  }
}

class _SummaryKpiRow extends StatelessWidget {
  final StudentActivityData data;
  final Color accent;
  final String lastActivityLabel;

  const _SummaryKpiRow({
    required this.data,
    required this.accent,
    required this.lastActivityLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: <Widget>[
        _KpiCard(
          icon: Icons.play_circle_outline_rounded,
          title: 'الفيديوهات المفتوحة',
          value: '${data.totalVideosOpened}',
          subtitle:
              '${data.completedVideosCount} مكتمل • ${data.partialVideosCount} جزئي',
          accent: accent,
        ),
        _KpiCard(
          icon: Icons.timer_outlined,
          title: 'إجمالي وقت المشاهدة',
          value: formatTotalWatchDurationAr(data.totalWatchedSeconds),
          subtitle: 'مجموع الدقائق المشاهدة',
          accent: accent,
        ),
        _KpiCard(
          icon: Icons.pie_chart_outline_rounded,
          title: 'متوسط إكمال الفيديو',
          value: '${data.averageCompletionPercent.round()}%',
          subtitle: 'نسبة المشاهدة الفعلية',
          accent: accent,
        ),
        _KpiCard(
          icon: Icons.history_rounded,
          title: 'آخر نشاط على التطبيق',
          value: lastActivityLabel,
          subtitle: '${data.events.length} حدث مسجّل',
          accent: accent,
          compactValue: true,
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final Color accent;
  final bool compactValue;

  const _KpiCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.accent,
    this.compactValue = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 222,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: compactValue ? 14.5 : 22,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 11.5,
              color: Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoWatchAuditSection extends StatelessWidget {
  final List<StudentLectureWatchRecord> lectures;
  final Color accent;
  final String Function(DateTime?) formatDateTime;

  const _VideoWatchAuditSection({
    required this.lectures,
    required this.accent,
    required this.formatDateTime,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              children: <Widget>[
                Icon(Icons.ondemand_video_rounded, size: 20, color: accent),
                const SizedBox(width: 8),
                const Text(
                  'سجل مشاهدة الفيديوهات والمحاضرات',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          if (lectures.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32, horizontal: 16),
              child: Center(
                child: Text(
                  'لم يشاهد الطالب أي محاضرات في هذه الفترة.',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 14,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ),
            )
          else
            ResponsiveHorizontalTable(
              minTableWidth: 760,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    height: 38,
                    color: const Color(0xFFF9FAFB),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: const Row(
                      children: <Widget>[
                        Expanded(
                          flex: 4,
                          child: Text(
                            'المحاضرة / المادة',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'الحالة',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            'وصل لحد الدقيقة',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'ملف PDF',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'آخر مشاهدة',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (int i = 0; i < lectures.length; i++) ...<Widget>[
                    if (i > 0) const Divider(height: 1, color: Color(0xFFF3F4F6)),
                    _LectureWatchRow(
                      record: lectures[i],
                      accent: accent,
                      lastWatchedText: formatDateTime(lectures[i].updatedAt),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _LectureWatchRow extends StatelessWidget {
  final StudentLectureWatchRecord record;
  final Color accent;
  final String lastWatchedText;

  const _LectureWatchRow({
    required this.record,
    required this.accent,
    required this.lastWatchedText,
  });

  @override
  Widget build(BuildContext context) {
    final String posStr = formatWatchTimestamp(record.positionSeconds);
    final String durStr = record.durationSeconds > 0
        ? formatWatchTimestamp(record.durationSeconds)
        : '—';
    final int pct = record.progressPercent.round().clamp(0, 100);
    final Color statusColor = record.completed
        ? const Color(0xFF15803D)
        : const Color(0xFFD97706);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  record.lectureTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  record.subjectTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9999),
                ),
                child: Text(
                  record.completed ? 'مكتمل ✓' : 'شاهد جزئياً',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '$posStr / $durStr ($pct%)',
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(9999),
                  child: LinearProgressIndicator(
                    value: pct / 100.0,
                    minHeight: 6,
                    backgroundColor: const Color(0xFFE5E7EB),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      record.completed ? const Color(0xFF15803D) : accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(
              record.hasPdfProgress
                  ? (record.pdfTotalPages != null && record.pdfTotalPages! > 0
                      ? 'ص ${record.pdfLastPage} / ${record.pdfTotalPages}'
                      : 'ص ${record.pdfLastPage}')
                  : '—',
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12.5,
                color: Color(0xFF374151),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              lastWatchedText,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12,
                color: Color(0xFF6B7280),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssessmentsSection extends StatelessWidget {
  final List<StudentAssessmentRecord> assessments;
  final Color accent;
  final String Function(DateTime?) formatDateTime;

  const _AssessmentsSection({
    required this.assessments,
    required this.accent,
    required this.formatDateTime,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              children: <Widget>[
                Icon(Icons.assignment_turned_in_outlined,
                    size: 20, color: accent),
                const SizedBox(width: 8),
                const Text(
                  'الكويزات والامتحانات',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          for (int i = 0; i < assessments.length; i++) ...<Widget>[
            if (i > 0) const Divider(height: 1, color: Color(0xFFF3F4F6)),
            ListTile(
              dense: true,
              leading: Icon(
                assessments[i].kind == 'exam'
                    ? Icons.school_outlined
                    : Icons.quiz_outlined,
                color: accent,
              ),
              title: Text(
                assessments[i].title,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                formatDateTime(assessments[i].createdAt),
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
              trailing: Text(
                assessments[i].percentage != null
                    ? '${assessments[i].percentage!.round()}%'
                    : (assessments[i].score != null
                        ? '${assessments[i].score}'
                        : '—'),
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: assessments[i].passed == false
                      ? const Color(0xFFDC2626)
                      : const Color(0xFF15803D),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DailyEventsTimelineSection extends StatelessWidget {
  final List<StudentActivityEvent> events;
  final Color accent;
  final String Function(DateTime?) dayHeader;

  const _DailyEventsTimelineSection({
    required this.events,
    required this.accent,
    required this.dayHeader,
  });

  @override
  Widget build(BuildContext context) {
    final Map<String, List<StudentActivityEvent>> grouped =
        <String, List<StudentActivityEvent>>{};
    for (final StudentActivityEvent event in events) {
      final String key = dayHeader(event.createdAt);
      grouped.putIfAbsent(key, () => <StudentActivityEvent>[]).add(event);
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              children: <Widget>[
                Icon(Icons.timeline_rounded, size: 20, color: accent),
                const SizedBox(width: 8),
                const Text(
                  'السجل اليومي لنشاط الطالب على التطبيق',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          if (events.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28, horizontal: 16),
              child: Center(
                child: Text(
                  'لا توجد أحداث مسجلة في هذه الفترة.',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 14,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (final MapEntry<String, List<StudentActivityEvent>> entry
                      in grouped.entries) ...<Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 8),
                      child: Text(
                        entry.key,
                        style: TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                    ),
                    for (final StudentActivityEvent ev in entry.value)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: <Widget>[
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                ev.details == null
                                    ? ev.arabicLabel
                                    : '${ev.arabicLabel} — ${ev.details}',
                                style: const TextStyle(
                                  fontFamily: AppTypography.fontFamily,
                                  fontSize: 13.5,
                                  color: Color(0xFF111827),
                                ),
                              ),
                            ),
                            if (ev.createdAt != null)
                              Text(
                                '${ev.createdAt!.hour.toString().padLeft(2, '0')}:${ev.createdAt!.minute.toString().padLeft(2, '0')}',
                                style: const TextStyle(
                                  fontFamily: AppTypography.fontFamily,
                                  fontSize: 12,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
