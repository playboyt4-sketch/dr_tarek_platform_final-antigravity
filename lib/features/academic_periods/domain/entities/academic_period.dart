/// Lifecycle of an academic period as approved for the dashboard:
/// a period is either `active` (started) or `ended`.
enum AcademicPeriodStatus { active, ended }

enum AcademicPeriodType { term1, term2, summerCourse, exceptional }

class AcademicPeriod {
  final String id;
  final AcademicPeriodType type;

  /// Free-text period type for exceptional periods created from the
  /// dashboard (e.g. individual training, exceptional circumstances).
  final String periodType;
  final String label;
  final bool isCore;
  final AcademicPeriodStatus status;
  final int displayOrder;
  final DateTime? startedAt;
  final DateTime? endedAt;

  const AcademicPeriod({
    required this.id,
    required this.type,
    required this.periodType,
    required this.label,
    required this.isCore,
    required this.status,
    required this.displayOrder,
    this.startedAt,
    this.endedAt,
  });

  bool get isActive => status == AcademicPeriodStatus.active;

  factory AcademicPeriod.fromMap(Map<String, dynamic> data) {
    final rawType = data['period_type'] as String? ?? data['id'] as String;
    final type = switch (rawType) {
      'term_1' => AcademicPeriodType.term1,
      'term_2' => AcademicPeriodType.term2,
      'summer_course' => AcademicPeriodType.summerCourse,
      _ => AcademicPeriodType.exceptional,
    };

    final rawStatus = (data['status'] as String? ?? '').toLowerCase();
    final status = rawStatus == 'active' || rawStatus == 'started'
        ? AcademicPeriodStatus.active
        : AcademicPeriodStatus.ended;

    return AcademicPeriod(
      id: data['id'] as String,
      type: type,
      periodType: rawType,
      label:
          (data['label'] as String?) ??
          (data['name'] as String?) ??
          data['id'] as String,
      isCore: data['is_core'] == true,
      status: status,
      displayOrder: (data['display_order'] as num?)?.toInt() ?? 99,
      startedAt: _timestampToDate(data['started_at']),
      endedAt: _timestampToDate(data['ended_at']),
    );
  }

  static DateTime? _timestampToDate(Object? value) {
    if (value == null) return null;
    // cloud_functions decodes Firestore timestamps as
    // {_seconds: int, _nanoseconds: int} maps.
    if (value is Map) {
      final seconds = value['_seconds'];
      if (seconds is num) {
        return DateTime.fromMillisecondsSinceEpoch(seconds.toInt() * 1000);
      }
    }
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
