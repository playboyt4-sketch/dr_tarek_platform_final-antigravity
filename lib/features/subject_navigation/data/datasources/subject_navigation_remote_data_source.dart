import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/subject_learning_entities.dart';

class SubjectNavigationRemoteDataSource {
  final FirebaseFirestore firestore;

  const SubjectNavigationRemoteDataSource({required this.firestore});

  Future<List<LearningSection>> getSections(
    String subjectId, {
    int? limit,
    DocumentSnapshot? startAfter,
  }) async {
    var query = firestore
        .collection('subject_sections')
        .where('subject_id', isEqualTo: subjectId)
        .where('is_deleted', isEqualTo: false)
        .where('is_visible', isEqualTo: true)
        .orderBy('display_order');

    if (startAfter != null) query = query.startAfterDocument(startAfter);
    if (limit != null) query = query.limit(limit);

    final snapshot = await query.get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      return LearningSection(
        id: doc.id,
        title:
            _text(data['title']) ?? _text(data['section_name']) ?? 'قسم تعليمي',
        displayOrder: (data['display_order'] as num?)?.toInt() ?? 0,
        isVisible: data['is_visible'] != false,
        isLocked: data['is_locked'] == true,
      );
    }).toList();
  }

  Future<List<LectureSummary>> getLectures(
    String sectionId, {
    int? limit,
    DocumentSnapshot? startAfter,
  }) async {
    var query = firestore
        .collection('lectures')
        .where('section_id', isEqualTo: sectionId)
        .where('is_deleted', isEqualTo: false)
        .where('status', isEqualTo: 'published')
        .orderBy('display_order');

    if (startAfter != null) query = query.startAfterDocument(startAfter);
    if (limit != null) query = query.limit(limit);

    final snapshot = await query.get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      return LectureSummary(
        id: doc.id,
        title: _text(data['title']) ?? _text(data['lecture_title']) ?? 'محاضرة',
        description: _text(data['description']),
        status: _text(data['learning_status']) ?? 'not_started',
        displayOrder: (data['display_order'] as num?)?.toInt() ?? 0,
        isLocked: data['is_locked'] == true,
        subjectId: _text(data['subject_id']),
        sectionId: _text(data['section_id']) ?? sectionId,
        thumbnailUrl: _text(data['thumbnail_url']) ?? _text(data['thumbnail']),
        duration: _duration(data['duration_seconds'] ?? data['duration']),
        skipIntroStart: _offset(
          data['skip_intro_start'] ?? data['intro_start'],
        ),
        skipIntroEnd: _offset(data['skip_intro_end'] ?? data['intro_end']),
      );
    }).toList();
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
