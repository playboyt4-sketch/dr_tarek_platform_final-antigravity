import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/errors/friendly_error_message.dart'
    show mapFunctionErrorCode;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_input.dart';
import '../../domain/entities/admin_content_entities.dart';
import '../providers/admin_content_providers.dart';

/// Per-lecture student Access UI (approved V1 requirement).
///
/// Core UI only: search + per-student ON/OFF (allow/deny) + explicit
/// Save. No attempt tracking, analytics, monitoring, notifications, or
/// disciplinary logic — deliberately excluded per the approved spec.
///
/// Displayed default: an explicit grant wins when present; otherwise the
/// toggle shows ON, meaning "no override — normal lecture eligibility
/// applies". Saving persists the effective state of every listed student
/// to `lecture_access_grants/{lectureId_studentId}` (repeat-safe batch).
class LectureAccessScreen extends ConsumerStatefulWidget {
  final String lectureId;
  final String lectureTitle;
  final String subjectId;

  const LectureAccessScreen({
    super.key,
    required this.lectureId,
    required this.lectureTitle,
    required this.subjectId,
  });

  @override
  ConsumerState<LectureAccessScreen> createState() =>
      _LectureAccessScreenState();
}

class _LectureAccessScreenState extends ConsumerState<LectureAccessScreen> {
  String? _gradeKey;
  bool _gradeLoaded = false;
  String _query = '';
  final Map<String, bool> _staged = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadGrade();
  }

  Future<void> _loadGrade() async {
    String? grade;
    try {
      grade = await ref
          .read(getSubjectGradeUseCaseProvider)
          .execute(widget.subjectId);
    } catch (_) {
      grade = null;
    }
    if (mounted) {
      setState(() {
        _gradeKey = grade;
        _gradeLoaded = true;
      });
    }
  }

  Future<void> _save(
      List<LectureStudent> students, Map<String, bool> grantById) async {
    setState(() => _saving = true);
    try {
      // Persist the effective state of every listed student: explicit
      // toggle when staged, stored grant when present, otherwise ON
      // (no override). Deterministic ids make this repeat-safe.
      final grants = students
          .map((s) => LectureAccessGrant(
                lectureId: widget.lectureId,
                studentId: s.id,
                allowed: _effective(s.id, grantById),
              ))
          .toList();
      await ref.read(saveLectureAccessUseCaseProvider).execute(grants);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lecture access saved.')),
      );
      Navigator.of(context).pop(true);
    } on Failure catch (failure) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(mapFunctionErrorCode('permission-denied',
              failure.debugDetail, 'Could not save lecture access.'))));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not save lecture access. Please try again.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Explicit staged toggle wins; then the stored grant; otherwise ON
  /// (no override — the student follows normal lecture eligibility).
  bool _effective(String studentId, Map<String, bool> grantById) =>
      _staged[studentId] ?? grantById[studentId] ?? true;

  @override
  Widget build(BuildContext context) {
    if (!_gradeLoaded) {
      return Scaffold(
        appBar: AppBar(title: const Text('Lecture Access')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final students = ref.watch(lectureStudentsProvider(_gradeKey));
    final grants = ref.watch(lectureAccessGrantsProvider(widget.lectureId));

    return Scaffold(
      appBar: AppBar(
        title: Text('Lecture Access — ${widget.lectureTitle}'),
        actions: [
          TextButton(
            onPressed: _saving
                ? null
                : () {
                    final allStudents =
                        students.value ?? const <LectureStudent>[];
                    final grantById = _grantMap(grants.value);
                    _save(allStudents, grantById);
                  },
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: students.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Could not load students.'),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () =>
                  ref.invalidate(lectureStudentsProvider(_gradeKey)),
              child: const Text('Retry'),
            ),
          ]),
        ),
        data: (list) {
          return grants.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Could not load access settings.'),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => ref.invalidate(
                      lectureAccessGrantsProvider(widget.lectureId)),
                  child: const Text('Retry'),
                ),
              ]),
            ),
            data: (grantList) =>
                _body(context, list, _grantMap(grantList)),
          );
        },
      ),
    );
  }

  Map<String, bool> _grantMap(List<LectureAccessGrant>? grants) => {
        for (final g in grants ?? const <LectureAccessGrant>[])
          g.studentId: g.allowed,
      };

  Widget _body(
      BuildContext context, List<LectureStudent> list, Map<String, bool> grantById) {
          final query = _query.trim().toLowerCase();
          final visible = query.isEmpty
              ? list
              : list
                  .where((s) => s.name.toLowerCase().contains(query))
                  .toList();
          if (list.isEmpty) {
            return const Center(child: Text('No students in this grade yet.'));
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: AppInput(
                  hint: 'Search Student',
                  prefixIcon: const Icon(Icons.search),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: visible.isEmpty
                    ? const Center(child: Text('No matching students.'))
                    : ListView.builder(
                        itemCount: visible.length,
                        itemBuilder: (_, i) {
                          final student = visible[i];
                          final allowed =
                              _effective(student.id, grantById);
                          return ListTile(
                            leading: Text(
                              '${(i + 1).toString().padLeft(2, '0')}.',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold),
                            ),
                            title: Text(student.name),
                            trailing: Switch(
                              value: allowed,
                              activeTrackColor: AppColors.success,
                              inactiveTrackColor: Colors.grey,
                              onChanged: _saving
                                  ? null
                                  : (v) => setState(
                                      () => _staged[student.id] = v),
                            ),
                          );
                        },
                      ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _saving
                              ? null
                              : () => _save(list, grantById),
                          child: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
  }
}
