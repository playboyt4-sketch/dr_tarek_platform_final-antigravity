import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/lecture.dart';
import '../../domain/entities/lecture_resource.dart';

class LectureRemoteDataSource {
  final FirebaseFirestore _firestore;

  LectureRemoteDataSource({
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  Future<List<Lecture>> getLecturesForSection(
    String sectionId,
  ) async {
    final snapshot = await _firestore
        .collection('lectures')
        .where('section_id', isEqualTo: sectionId)
        .where('is_deleted', isEqualTo: false)
        .orderBy('display_order')
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();

      return Lecture(
        id: doc.id,
        sectionId: data['section_id'] as String,
        title: data['title'] as String? ?? '',
        description: data['description'] as String? ?? '',
        displayOrder: (data['display_order'] as num?)?.toInt() ?? 0,
        publishDate: (data['publish_date'] as Timestamp?)?.toDate(),
        status: switch (data['status']) {
          'published' => LectureStatus.published,
          'archived' => LectureStatus.archived,
          _ => LectureStatus.draft,
        },
      );
    }).toList();
  }

  Future<List<LectureResource>> getResourcesForLecture(
    String lectureId,
  ) async {
    final snapshot = await _firestore
        .collection('lecture_resources')
        .where('lecture_id', isEqualTo: lectureId)
        .where('visibility', isEqualTo: true)
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();

      return LectureResource(
        id: doc.id,
        lectureId: lectureId,
        resourceType: switch (data['resource_type']) {
          'video' => LectureResourceType.video,
          'pdf' => LectureResourceType.pdf,
          'attachment' => LectureResourceType.attachment,
          _ => LectureResourceType.externalLink,
        },
        resourceUrl: data['resource_url'] as String? ?? '',
        bunnyVideoId: data['bunny_video_id'] as String?,
        thumbnail: data['thumbnail'] as String?,
        duration: (data['duration'] as num?)?.toInt(),
        visibility: data['visibility'] as bool? ?? false,
      );
    }).toList();
  }
}

