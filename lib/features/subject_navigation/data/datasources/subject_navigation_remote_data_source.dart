import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/subject_learning_entities.dart';

class SubjectNavigationRemoteDataSource {
  final FirebaseFirestore firestore;

  const SubjectNavigationRemoteDataSource({required this.firestore});

  Query<Map<String, dynamic>> _sectionsQuery(String subjectId) => firestore
      .collection('subject_sections')
      .where('subject_id', isEqualTo: subjectId)
      .where('is_deleted', isEqualTo: false)
      .where('is_visible', isEqualTo: true)
      .orderBy('display_order');

  List<LearningSection> _mapSections(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    return snapshot.docs
        .where((doc) => doc.data()['is_archived'] != true)
        .map((doc) {
          final data = doc.data();
          final String? key = data['section_key'] as String?;
          return LearningSection(
            id: doc.id,
            title:
                _text(data['title']) ??
                _text(data['section_name']) ??
                'قسم تعليمي',
            sectionKey: key,
            isSystemSection: (data['is_system_section'] as bool?) ??
                (key == 'explanation' ||
                    key == 'revision' ||
                    key == 'final_review'),
            displayOrder: (data['display_order'] as num?)?.toInt() ?? 0,
            isVisible: data['is_visible'] != false,
            isLocked: data['is_locked'] == true,
          );
        })
        .toList();
  }

  Stream<List<LearningSection>> watchSections(String subjectId) {
    return _sectionsQuery(subjectId).snapshots().map(_mapSections);
  }

  Future<List<LearningSection>> getSections(
    String subjectId, {
    int? limit,
    DocumentSnapshot? startAfter,
  }) async {
    var query = _sectionsQuery(subjectId);

    if (startAfter != null) query = query.startAfterDocument(startAfter);
    if (limit != null) query = query.limit(limit);

    final snapshot = await query.get();
    return _mapSections(snapshot);
  }

  Query<Map<String, dynamic>> _lecturesQuery(String sectionId) => firestore
      .collection('lectures')
      .where('section_id', isEqualTo: sectionId)
      .where('is_deleted', isEqualTo: false)
      .where('status', isEqualTo: 'published')
      .orderBy('display_order');

  List<LectureSummary> _mapLectures(
    QuerySnapshot<Map<String, dynamic>> snapshot, {
    required String sectionId,
  }) {
    return snapshot.docs
        .where((doc) => doc.data()['is_archived'] != true)
        .map((doc) {
          final data = doc.data();
          return LectureSummary(
            id: doc.id,
            title:
                _text(data['title']) ?? _text(data['lecture_title']) ?? 'محاضرة',
            description: _text(data['description']),
            status: _text(data['learning_status']) ?? 'not_started',
            displayOrder: (data['display_order'] as num?)?.toInt() ?? 0,
            isLocked: data['is_locked'] == true,
            subjectId: _text(data['subject_id']),
            sectionId: _text(data['section_id']) ?? sectionId,
            thumbnailUrl:
                _text(data['thumbnail_url']) ?? _text(data['thumbnail']),
            duration: _duration(data['duration_seconds'] ?? data['duration']),
            skipIntroStart: _offset(
              data['skip_intro_start'] ?? data['intro_start'],
            ),
            skipIntroEnd: _offset(data['skip_intro_end'] ?? data['intro_end']),
            updatedAt: _timestamp(data['updated_at']),
            // Denormalized first-video pointer (05 Database §lectures). Null
            // when absent/malformed — callers keep the legacy tap-time path.
            firstVideo: FirstVideoRef.fromLectureData(data),
          );
        })
        .toList();
  }

  Stream<List<LectureSummary>> watchLectures(String sectionId) {
    return _lecturesQuery(sectionId)
        .snapshots()
        .map((snap) => _mapLectures(snap, sectionId: sectionId));
  }

  Future<List<LectureSummary>> getLectures(
    String sectionId, {
    int? limit,
    DocumentSnapshot? startAfter,
  }) async {
    var query = _lecturesQuery(sectionId);

    if (startAfter != null) query = query.startAfterDocument(startAfter);
    if (limit != null) query = query.limit(limit);

    final snapshot = await query.get();
    return _mapLectures(snapshot, sectionId: sectionId);
  }

  DateTime? _timestamp(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  Duration? _duration(Object? value) {
    if (value is! num || value <= 0) return null;
    return Duration(seconds: value.round());
  }

  Duration? _offset(Object? value) {
    if (value is! num || value < 0) return null;
    return Duration(seconds: value.round());
  }
}
