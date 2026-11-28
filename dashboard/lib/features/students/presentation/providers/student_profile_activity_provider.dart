import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/firebase_providers.dart';
import 'live_users_streams.dart';

/// One watched video / opened lecture record from `lecture_progress`.
class StudentLectureWatchRecord {
  final String lectureId;
  final String lectureTitle;
  final String? subjectId;
  final String subjectTitle;
  final double positionSeconds;
  final double durationSeconds;
  final double progressPercent;
  final bool completed;
  final int? pdfLastPage;
  final int? pdfTotalPages;
  final DateTime? updatedAt;
  final DateTime? completedAt;

  const StudentLectureWatchRecord({
    required this.lectureId,
    required this.lectureTitle,
    required this.subjectId,
    required this.subjectTitle,
    required this.positionSeconds,
    required this.durationSeconds,
    required this.progressPercent,
    required this.completed,
    this.pdfLastPage,
    this.pdfTotalPages,
    this.updatedAt,
    this.completedAt,
  });

  bool get hasPdfProgress => pdfLastPage != null && pdfLastPage! > 0;
}

/// One event from `analytics_events` for the student's daily activity feed.
class StudentActivityEvent {
  final String id;
  final String eventType;
  final String arabicLabel;
  final String? details;
  final DateTime? createdAt;

  const StudentActivityEvent({
    required this.id,
    required this.eventType,
    required this.arabicLabel,
    this.details,
    this.createdAt,
  });
}

/// One quiz or exam attempt from `quiz_attempts` / `exam_attempts`.
class StudentAssessmentRecord {
  final String id;
  final String kind; // 'quiz' or 'exam'
  final String title;
  final double? score;
  final double? percentage;
  final bool? passed;
  final DateTime? createdAt;

  const StudentAssessmentRecord({
    required this.id,
    required this.kind,
    required this.title,
    this.score,
    this.percentage,
    this.passed,
    this.createdAt,
  });
}

/// Aggregated, real-time activity snapshot for one student.
class StudentActivityData {
  final List<StudentLectureWatchRecord> lectures;
  final List<StudentActivityEvent> events;
  final List<StudentAssessmentRecord> assessments;

  const StudentActivityData({
    required this.lectures,
    required this.events,
    required this.assessments,
  });

  int get totalVideosOpened => lectures.length;

  int get completedVideosCount =>
      lectures.where((StudentLectureWatchRecord r) => r.completed).length;

  int get partialVideosCount => totalVideosOpened - completedVideosCount;

  double get totalWatchedSeconds => lectures.fold<double>(
        0,
        (double sum, StudentLectureWatchRecord r) => sum + r.positionSeconds,
      );

  double get averageCompletionPercent {
    if (lectures.isEmpty) return 0;
    final double total = lectures.fold<double>(
      0,
      (double sum, StudentLectureWatchRecord r) => sum + r.progressPercent,
    );
    return (total / lectures.length).clamp(0, 100);
  }

  DateTime? get lastActivityAt {
    DateTime? latest;
    for (final StudentLectureWatchRecord r in lectures) {
      if (r.updatedAt != null &&
          (latest == null || r.updatedAt!.isAfter(latest))) {
        latest = r.updatedAt;
      }
    }
    for (final StudentActivityEvent e in events) {
      if (e.createdAt != null &&
          (latest == null || e.createdAt!.isAfter(latest))) {
        latest = e.createdAt;
      }
    }
    for (final StudentAssessmentRecord a in assessments) {
      if (a.createdAt != null &&
          (latest == null || a.createdAt!.isAfter(latest))) {
        latest = a.createdAt;
      }
    }
    return latest;
  }
}

/// Formats seconds as `MM:SS` or `HH:MM:SS` (e.g. `24:15` or `1:05:30`).
String formatWatchTimestamp(double seconds) {
  final int total = seconds.isFinite && seconds > 0 ? seconds.floor() : 0;
  final int hours = total ~/ 3600;
  final int minutes = (total % 3600) ~/ 60;
  final int secs = total % 60;
  final String mm = minutes.toString().padLeft(2, '0');
  final String ss = secs.toString().padLeft(2, '0');
  if (hours > 0) return '$hours:$mm:$ss';
  return '$mm:$ss';
}

/// Formats total watched time into readable Arabic text (e.g. `1 س 25 د` or `18 دقيقة`).
String formatTotalWatchDurationAr(double seconds) {
  final int totalMinutes =
      seconds.isFinite && seconds > 0 ? (seconds / 60).round() : 0;
  if (totalMinutes <= 0) {
    final int secs = seconds.isFinite && seconds > 0 ? seconds.floor() : 0;
    return secs > 0 ? '$secs ثانية' : '0 دقيقة';
  }
  final int hours = totalMinutes ~/ 60;
  final int mins = totalMinutes % 60;
  if (hours == 0) return '$mins دقيقة';
  if (mins == 0) return '$hours ساعة';
  return '$hours س $mins د';
}

String _arabicEventLabel(String eventType) {
  final String lower = eventType.trim().toLowerCase();
  if (lower.contains('login') || lower.contains('sign in')) {
    return 'تسجيل دخول للتطبيق';
  }
  if (lower.contains('registration')) return 'تقديم طلب تسجيل';
  if (lower.contains('video') || lower.contains('playback') || lower.contains('signed')) {
    return 'تشغيل محاضرة فيديو';
  }
  if (lower.contains('pdf') || lower.contains('document')) {
    return 'فتح ملف PDF';
  }
  if (lower.contains('quiz')) return 'حل كويز';
  if (lower.contains('exam')) return 'أداء امتحان';
  if (lower.contains('password')) return 'تغيير / إعادة تعيين كلمة المرور';
  if (lower.contains('bookmark')) return 'حفظ إشارة مرجعية';
  if (lower.contains('note')) return 'إضافة ملاحظة';
  if (lower.contains('approve')) return 'اعتماد الحساب';
  return eventType.trim().isEmpty ? 'نشاط على التطبيق' : eventType.trim();
}

DateTime? _parseTimestamp(Object? raw) {
  if (raw is Timestamp) return raw.toDate();
  if (raw is String && raw.isNotEmpty) return DateTime.tryParse(raw);
  return null;
}

double _parseDouble(Object? raw) {
  if (raw is num && raw.isFinite) return raw.toDouble();
  if (raw is String) return double.tryParse(raw.trim()) ?? 0;
  return 0;
}

int? _parseInt(Object? raw) {
  if (raw is num && raw.isFinite) return raw.toInt();
  if (raw is String) return int.tryParse(raw.trim());
  return null;
}

/// Real-time comprehensive activity provider for a single student.
///
/// Subscribes live to `lecture_progress` and `analytics_events` via
/// [watchQuerySnapshot] so watching a video or taking an action on the mobile
/// app updates the student's Activity tab automatically without manual refresh.
final studentProfileActivityProvider =
    FutureProvider.family<StudentActivityData, String>(
  (Ref ref, String studentId) async {
    final FirebaseFirestore db = ref.watch(firebaseFirestoreProvider);

    // 1. Live video & PDF watch progress (`lecture_progress`).
    final QuerySnapshot<Map<String, dynamic>> progressSnap =
        await watchQuerySnapshot(
      ref,
      db
          .collection('lecture_progress')
          .where('student_id', isEqualTo: studentId)
          .limit(300),
    );

    // 2. Live daily activity events (`analytics_events`).
    List<QueryDocumentSnapshot<Map<String, dynamic>>> eventDocs =
        const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    try {
      final QuerySnapshot<Map<String, dynamic>> eventsSnap =
          await watchQuerySnapshot(
        ref,
        db
            .collection('analytics_events')
            .where('user_id', isEqualTo: studentId)
            .limit(200),
      );
      eventDocs = eventsSnap.docs;
    } catch (_) {
      // Best-effort: never block video watch progress if analytics_events fails.
    }

    // 3. Quiz & exam attempts (best-effort).
    final List<StudentAssessmentRecord> assessments =
        <StudentAssessmentRecord>[];
    try {
      final QuerySnapshot<Map<String, dynamic>> quizSnap = await db
          .collection('quiz_attempts')
          .where('student_id', isEqualTo: studentId)
          .limit(100)
          .get();
      for (final doc in quizSnap.docs) {
        final Map<String, dynamic> d = doc.data();
        assessments.add(
          StudentAssessmentRecord(
            id: doc.id,
            kind: 'quiz',
            title: (d['quiz_title'] as String?) ??
                (d['title'] as String?) ??
                'كويز ${(d['quiz_id'] ?? doc.id)}',
            score: d['score'] is num ? (d['score'] as num).toDouble() : null,
            percentage: d['percentage'] is num
                ? (d['percentage'] as num).toDouble()
                : null,
            passed: d['passed'] is bool ? d['passed'] as bool : null,
            createdAt: _parseTimestamp(d['submitted_at'] ?? d['created_at']),
          ),
        );
      }
    } catch (_) {}

    try {
      final QuerySnapshot<Map<String, dynamic>> examSnap = await db
          .collection('exam_attempts')
          .where('student_id', isEqualTo: studentId)
          .limit(100)
          .get();
      for (final doc in examSnap.docs) {
        final Map<String, dynamic> d = doc.data();
        assessments.add(
          StudentAssessmentRecord(
            id: doc.id,
            kind: 'exam',
            title: (d['exam_title'] as String?) ??
                (d['title'] as String?) ??
                'امتحان ${(d['exam_id'] ?? doc.id)}',
            score: d['score'] is num ? (d['score'] as num).toDouble() : null,
            percentage: d['percentage'] is num
                ? (d['percentage'] as num).toDouble()
                : null,
            passed: d['passed'] is bool ? d['passed'] as bool : null,
            createdAt: _parseTimestamp(d['submitted_at'] ?? d['created_at']),
          ),
        );
      }
    } catch (_) {}

    assessments.sort((a, b) {
      final DateTime? at = a.createdAt;
      final DateTime? bt = b.createdAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });

    // 4. Resolve subject titles for display.
    final Map<String, String> subjectTitles = <String, String>{};
    try {
      final QuerySnapshot<Map<String, dynamic>> subjectsSnap = await db
          .collection('subjects')
          .where('is_deleted', isEqualTo: false)
          .get();
      for (final doc in subjectsSnap.docs) {
        final Map<String, dynamic> d = doc.data();
        final String title =
            ((d['title'] as String?) ?? (d['name'] as String?) ?? '').trim();
        if (title.isNotEmpty) {
          subjectTitles[doc.id] = title;
        }
      }
    } catch (_) {}

    // 5. Map lecture_progress docs cleanly.
    final List<StudentLectureWatchRecord> lectures =
        <StudentLectureWatchRecord>[];
    for (final doc in progressSnap.docs) {
      final Map<String, dynamic> d = doc.data();
      final String lectureId = ((d['lecture_id'] as String?) ??
              doc.id.replaceFirst('${studentId}_', ''))
          .trim();
      final String? subjectId = (d['subject_id'] as String?)?.trim();
      final double position = _parseDouble(
        d['position_seconds'] ?? d['video_position_seconds'],
      );
      final double duration = _parseDouble(d['duration_seconds']);
      double percent = _parseDouble(d['progress_percent']);
      if (percent <= 0 && duration > 0 && position > 0) {
        percent = (position / duration) * 100;
      } else if (percent > 0 && percent <= 1.0 && duration > 0 && position > 10) {
        // Handle fractional 0..1 storage if present.
        percent = percent * 100;
      }
      percent = percent.clamp(0, 100);
      final bool completed = d['completed'] == true ||
          d['is_completed'] == true ||
          percent >= 90;
      final String rawTitle = ((d['lecture_title'] as String?) ?? '').trim();
      lectures.add(
        StudentLectureWatchRecord(
          lectureId: lectureId,
          lectureTitle: rawTitle.isEmpty ? 'محاضرة ($lectureId)' : rawTitle,
          subjectId: subjectId,
          subjectTitle: (subjectId != null && subjectTitles[subjectId] != null)
              ? subjectTitles[subjectId]!
              : (subjectId ?? '—'),
          positionSeconds: position,
          durationSeconds: duration,
          progressPercent: completed ? (percent < 95 ? 100 : percent) : percent,
          completed: completed,
          pdfLastPage: _parseInt(d['pdf_last_page']),
          pdfTotalPages: _parseInt(d['pdf_total_pages']),
          updatedAt: _parseTimestamp(d['updated_at']),
          completedAt: _parseTimestamp(d['completed_at']),
        ),
      );
    }

    lectures.sort((a, b) {
      final DateTime? at = a.updatedAt;
      final DateTime? bt = b.updatedAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });

    // 6. Map analytics_events docs.
    final List<StudentActivityEvent> events = <StudentActivityEvent>[];
    for (final doc in eventDocs) {
      final Map<String, dynamic> d = doc.data();
      final String type = ((d['event_type'] as String?) ?? '').trim();
      final Object? rawMeta = d['metadata'];
      String? details;
      if (rawMeta is Map) {
        final List<String> parts = <String>[];
        final Object? subjectId = rawMeta['subject_id'] ?? rawMeta['subjectId'];
        if (subjectId is String && subjectTitles[subjectId] != null) {
          parts.add(subjectTitles[subjectId]!);
        }
        final Object? lectureTitle =
            rawMeta['lecture_title'] ?? rawMeta['title'];
        if (lectureTitle is String && lectureTitle.trim().isNotEmpty) {
          parts.add(lectureTitle.trim());
        }
        final Object? quality = rawMeta['quality'];
        if (quality is String && quality.trim().isNotEmpty) {
          parts.add('جودة: ${quality.trim()}');
        }
        if (parts.isNotEmpty) details = parts.join(' • ');
      }
      events.add(
        StudentActivityEvent(
          id: doc.id,
          eventType: type,
          arabicLabel: _arabicEventLabel(type),
          details: details,
          createdAt: _parseTimestamp(d['created_at']),
        ),
      );
    }

    events.sort((a, b) {
      final DateTime? at = a.createdAt;
      final DateTime? bt = b.createdAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });

    return StudentActivityData(
      lectures: lectures,
      events: events,
      assessments: assessments,
    );
  },
);
