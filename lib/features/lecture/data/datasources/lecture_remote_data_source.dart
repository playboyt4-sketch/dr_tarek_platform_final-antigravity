import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../domain/entities/lecture.dart';
import '../../domain/entities/lecture_resource.dart';

class LectureRemoteDataSource {
  final FirebaseFirestore? firestore;
  final FirebaseFunctions? functions;

  LectureRemoteDataSource({
    this.firestore,
    this.functions,
  });

  FirebaseFirestore get _db => firestore ?? FirebaseFirestore.instance;

  FirebaseFunctions get _fn => functions ?? FirebaseFunctions.instance;

  Future<List<Lecture>> getLecturesForSection(
    String sectionId,
  ) async {
    final snapshot = await _db
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

  /// Lists a lecture's visible resources through the authorized
  /// `getLectureResources` callable (index.ts getLectureResources), which
  /// re-validates subject access, subscription and plan features server-side
  /// (06 Firebase Architecture Sections 4.2/5.2). Direct Firestore reads of
  /// `lecture_resources` are denied by Security Rules because raw documents
  /// carry `resource_url` values that must never reach the client.
  Future<List<LectureResource>> getResourcesForLecture(
    String lectureId,
  ) async {
    final callable = _fn.httpsCallable('getLectureResources');
    final result = await callable.call<Map<String, dynamic>>({
      'lectureId': lectureId,
    });

    final resources =
        (result.data['resources'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<dynamic, dynamic>>()
            .map((doc) {
      final resourceType = switch (doc['resourceType'] as String?) {
        'video' => LectureResourceType.video,
        'pdf' => LectureResourceType.pdf,
        'attachment' => LectureResourceType.attachment,
        _ => LectureResourceType.externalLink,
      };

      return LectureResource(
        id: doc['id'] as String? ?? '',
        lectureId: lectureId,
        resourceType: resourceType,
        // Raw URLs stay server-side; playback/PDF access is granted through
        // generateBunnySignedUrl / generateProtectedPdfUrl callables.
        resourceUrl: '',
        bunnyVideoId: doc['bunnyVideoId'] as String?,
        thumbnail: doc['thumbnail'] as String?,
        // Dual-provider key (FINAL_DECISIONS §15) — routed in the Data layer.
        storageProvider: doc['storageProvider'] as String? ?? 'firebase',
        duration: (doc['duration'] as num?)?.toInt(),
        // The callable only returns resources whose visibility gate passed.
        visibility: true,
      );
    }).where((resource) => resource.id.isNotEmpty).toList();

    return resources;
  }
}
