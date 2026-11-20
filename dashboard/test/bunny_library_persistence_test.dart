// ADR-010 — Dashboard persistence of the SERVER-VERIFIED library association.
//
// Drives the real Dashboard controller against FakeFirebaseFirestore with a
// recording gateway, and asserts the security contract of Mission 4:
//   * the client NEVER writes `bunny_video_id`/`bunny_library_id` itself,
//   * each new video row is handed to the server gateway with the resolved
//     library (explicit choice → default fallback), and
//   * unrelated edits never touch a stored association, while
//     PDF/external-link rows never reach the gateway.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drtarek_dashboard/features/home/presentation/widgets/quick_upload_modal.dart';
import 'package:drtarek_dashboard/features/students/data/bunny_association_gateway.dart';
import 'package:drtarek_dashboard/features/students/domain/bunny_library_association.dart';
import 'package:drtarek_dashboard/features/students/presentation/providers/subject_details_provider.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

const String _guid = '7ddd0e6e-1111-4111-8111-111111111111';
const String _guid2 = '8eee0e6e-2222-4222-8222-222222222222';

class _Call {
  const _Call({
    required this.resourceId,
    required this.lectureId,
    required this.libraryId,
    required this.videoId,
    required this.replaceVideo,
  });

  final String resourceId;
  final String lectureId;
  final String libraryId;
  final String videoId;
  final bool replaceVideo;
}

/// Records every association request. Optionally mimics the server write so a
/// follow-up read can prove the association lives on the row.
class _FakeGateway implements BunnyAssociationGateway {
  _FakeGateway({this.persist = false, this.fail = false});

  final bool persist;
  final bool fail;
  final List<_Call> calls = <_Call>[];
  FakeFirebaseFirestore? db;

  @override
  Future<void> associate({
    required String resourceId,
    required String lectureId,
    required String libraryId,
    required String videoId,
    bool replaceVideo = false,
  }) async {
    calls.add(_Call(
      resourceId: resourceId,
      lectureId: lectureId,
      libraryId: libraryId,
      videoId: videoId,
      replaceVideo: replaceVideo,
    ));
    if (fail) throw Exception('server rejected');
    if (persist && db != null) {
      await db!.collection('lecture_resources').doc(resourceId).set(
        <String, Object?>{
          'bunny_video_id': videoId,
          'bunny_library_id': libraryId,
        },
        SetOptions(merge: true),
      );
    }
  }
}

void main() {
  late FakeFirebaseFirestore db;
  late _FakeGateway gateway;
  late SubjectDetailsController controller;

  setUp(() {
    db = FakeFirebaseFirestore();
    gateway = _FakeGateway()..db = db;
    controller = SubjectDetailsController(db, null, gateway);
  });

  Future<Map<String, dynamic>> onlyResourceOf(String lectureId) async {
    final snap = await db
        .collection('lecture_resources')
        .where('lecture_id', isEqualTo: lectureId)
        .get();
    expect(snap.docs, hasLength(1));
    return snap.docs.single.data();
  }

  Future<String> createVideo({
    String type = 'video',
    String? videoId = _guid,
    String? libraryId,
  }) {
    return controller.createLectureFull(
      subjectId: 'sub-1',
      tab: SubjectContentTab.lectures,
      title: 'Lecture',
      displayOrder: 0,
      publishNow: true,
      guestEnabled: false,
      resources: <NewLectureResource>[
        NewLectureResource(
          type: type,
          title: 'Resource',
          displayOrder: 1,
          bunnyVideoId: videoId,
          bunnyLibraryId: libraryId,
        ),
      ],
      accessByStudent: const <String, bool>{},
    );
  }

  Future<String> seedLecture() async {
    final ref = await db.collection('lectures').add(<String, Object?>{
      'subject_id': 'sub-1',
      'section_id': 'sec-1',
      'title': 'Seed',
      'display_order': 0,
      'status': 'published',
      'is_deleted': false,
    });
    return ref.id;
  }

  Future<String> seedResource(
    String lectureId, {
    String type = 'video',
    bool withLibrary = false,
  }) async {
    final Map<String, Object?> data = <String, Object?>{
      'lecture_id': lectureId,
      'subject_id': 'sub-1',
      'resource_type': type,
      'title': 'Stored',
      'display_order': 1,
      'bunny_video_id': type == 'video' ? _guid : null,
      'is_visible': true,
      'is_deleted': false,
    };
    if (withLibrary) data['bunny_library_id'] = defaultBunnyLibraryId;
    final ref = await db.collection('lecture_resources').add(data);
    return ref.id;
  }

  group('createLectureFull', () {
    test('the client writes no association; the server gateway does', () async {
      final String lectureId = await createVideo(
        libraryId: defaultBunnyLibraryId,
      );
      final data = await onlyResourceOf(lectureId);
      // Security contract: client-written association/video id are absent.
      expect(data['bunny_library_id'], isNull);
      expect(data['bunny_video_id'], isNull);
      // The row is therefore pending (unplayable) until the server confirms.
      expect(gateway.calls, hasLength(1));
      expect(gateway.calls.single.libraryId, defaultBunnyLibraryId);
      expect(gateway.calls.single.videoId, _guid);
      expect(gateway.calls.single.lectureId, lectureId);
      expect(gateway.calls.single.replaceVideo, isFalse);
    });

    test('no explicit choice resolves to the default library', () async {
      final String lectureId = await createVideo();
      expect(gateway.calls.single.libraryId, defaultBunnyLibraryId);
      final data = await onlyResourceOf(lectureId);
      expect(data['bunny_library_id'], isNull);
    });

    test('malformed library input never reaches the server verbatim', () async {
      await createVideo(libraryId: 'library-a');
      expect(gateway.calls.single.libraryId, defaultBunnyLibraryId);
    });

    test('PDF resources are never associated', () async {
      final String lectureId = await createVideo(
        type: 'pdf',
        videoId: null,
        libraryId: defaultBunnyLibraryId,
      );
      final data = await onlyResourceOf(lectureId);
      expect(data['bunny_library_id'], isNull);
      expect(gateway.calls, isEmpty);
    });

    test('external links are never associated', () async {
      final String lectureId = await createVideo(
        type: 'external_link',
        videoId: null,
      );
      final data = await onlyResourceOf(lectureId);
      expect(data['bunny_library_id'], isNull);
      expect(gateway.calls, isEmpty);
    });
  });

  group('getLectureForEdit', () {
    test('legacy rows read back as legacy (null association)', () async {
      final String lectureId = await seedLecture();
      await seedResource(lectureId);
      final LectureEditData data = await controller.getLectureForEdit(lectureId);
      expect(data.resources.single.bunnyLibraryId, isNull);
    });

    test('stored association is surfaced for editing', () async {
      final String lectureId = await seedLecture();
      await seedResource(lectureId, withLibrary: true);
      final LectureEditData data = await controller.getLectureForEdit(lectureId);
      expect(data.resources.single.bunnyLibraryId, defaultBunnyLibraryId);
    });
  });

  group('updateLectureFull', () {
    test('unrelated edit preserves the stored association', () async {
      final String lectureId = await seedLecture();
      final String resourceId =
          await seedResource(lectureId, withLibrary: true);
      await controller.updateLectureFull(
        lectureId: lectureId,
        title: 'Renamed',
        displayOrder: 0,
        publishNow: true,
        guestEnabled: false,
        newResources: const <NewLectureResource>[],
        deleteResourceIds: const <String>[],
        updatedResources: <UpdatedLectureResource>[
          UpdatedLectureResource(
            id: resourceId,
            title: 'Renamed resource',
            displayOrder: 1,
            bunnyVideoId: null,
            bunnyLibraryId: null,
          ),
        ],
        accessByStudent: const <String, bool>{},
      );
      final snap =
          await db.collection('lecture_resources').doc(resourceId).get();
      expect(snap.data()!['title'], 'Renamed resource');
      expect(snap.data()!['bunny_library_id'], defaultBunnyLibraryId);
      expect(snap.data()!['bunny_video_id'], _guid);
      // The client never rewrote the association.
      expect(gateway.calls, isEmpty);
    });

    test('an edited Video ID goes through the server, not the client', () async {
      final String lectureId = await seedLecture();
      final String resourceId =
          await seedResource(lectureId, withLibrary: true);
      await controller.updateLectureFull(
        lectureId: lectureId,
        title: 'Renamed',
        displayOrder: 0,
        publishNow: true,
        guestEnabled: false,
        newResources: const <NewLectureResource>[],
        deleteResourceIds: const <String>[],
        updatedResources: <UpdatedLectureResource>[
          UpdatedLectureResource(
            id: resourceId,
            title: 'Stored',
            displayOrder: 1,
            bunnyVideoId: _guid2,
            bunnyLibraryId: defaultBunnyLibraryId,
          ),
        ],
        accessByStudent: const <String, bool>{},
      );
      final snap =
          await db.collection('lecture_resources').doc(resourceId).get();
      // Rules forbid the client pointer swap: the row still holds the old id
      // until the server (gateway) verifies and rebinds it.
      expect(snap.data()!['bunny_video_id'], _guid);
      expect(gateway.calls, hasLength(1));
      expect(gateway.calls.single.videoId, _guid2);
      expect(gateway.calls.single.libraryId, defaultBunnyLibraryId);
      expect(gateway.calls.single.replaceVideo, isTrue);
    });

    test('new resource added during an edit is associated server-side',
        () async {
      final String lectureId = await seedLecture();
      await controller.updateLectureFull(
        lectureId: lectureId,
        title: 'Unchanged',
        displayOrder: 0,
        publishNow: true,
        guestEnabled: false,
        newResources: <NewLectureResource>[
          NewLectureResource(
            type: 'video',
            title: 'Added later',
            displayOrder: 2,
            bunnyVideoId: _guid,
          ),
        ],
        deleteResourceIds: const <String>[],
        accessByStudent: const <String, bool>{},
      );
      final snap = await db
          .collection('lecture_resources')
          .where('lecture_id', isEqualTo: lectureId)
          .get();
      expect(snap.docs, hasLength(1));
      expect(snap.docs.single.data()['bunny_library_id'], isNull);
      expect(gateway.calls, hasLength(1));
      expect(gateway.calls.single.libraryId, defaultBunnyLibraryId);
      expect(gateway.calls.single.resourceId, snap.docs.single.id);
    });

    test('a rejected association leaves the resource pending (no downgrade)',
        () async {
      gateway = _FakeGateway(fail: true)..db = db;
      controller = SubjectDetailsController(db, null, gateway);
      await expectLater(createVideo(), throwsA(isA<Exception>()));
      final snap = await db.collection('lecture_resources').get();
      expect(snap.docs.single.data()['bunny_library_id'], isNull);
      expect(snap.docs.single.data()['bunny_video_id'], isNull);
    });
  });

  group('server-confirmed association', () {
    test('persisted association is visible on the row after the gateway',
        () async {
      gateway = _FakeGateway(persist: true)..db = db;
      controller = SubjectDetailsController(db, null, gateway);
      final String lectureId = await createVideo();
      final data = await onlyResourceOf(lectureId);
      expect(data['bunny_library_id'], defaultBunnyLibraryId);
      expect(data['bunny_video_id'], _guid);
    });
  });

  group('publishQuickLecture', () {
    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> resourcesOf(
      String lectureId,
    ) async {
      final snap = await db
          .collection('lecture_resources')
          .where('lecture_id', isEqualTo: lectureId)
          .get();
      return snap.docs;
    }

    test('never writes the association client-side; delegates to the server',
        () async {
      final String lectureId = await publishQuickLecture(
        db: db,
        actorId: 'dashboard',
        subjectId: 'sub-1',
        tabKey: 'online',
        title: 'Quick',
        bunnyVideoId: _guid,
        publishNow: true,
        associationGateway: gateway,
      );
      final docs = await resourcesOf(lectureId);
      expect(docs, hasLength(1));
      final data = docs.single.data();
      // The client wrote only the pointer; the association is server-owned.
      expect(data['bunny_library_id'], isNull);
      expect(data['bunny_video_id'], _guid);
      expect(gateway.calls, hasLength(1));
      expect(gateway.calls.single.resourceId, docs.single.id);
      expect(gateway.calls.single.lectureId, lectureId);
      expect(gateway.calls.single.libraryId, defaultBunnyLibraryId);
      expect(gateway.calls.single.videoId, _guid);
      expect(gateway.calls.single.replaceVideo, isFalse);
    });

    test('server-confirmed quick upload ends up on the row', () async {
      gateway = _FakeGateway(persist: true)..db = db;
      final String lectureId = await publishQuickLecture(
        db: db,
        actorId: 'dashboard',
        subjectId: 'sub-1',
        tabKey: 'online',
        title: 'Quick',
        bunnyVideoId: _guid,
        publishNow: true,
        associationGateway: gateway,
      );
      final data = (await resourcesOf(lectureId)).single.data();
      expect(data['bunny_library_id'], defaultBunnyLibraryId);
      expect(data['bunny_video_id'], _guid);
    });

    test('a rejected association leaves the quick video pending', () async {
      gateway = _FakeGateway(fail: true)..db = db;
      await expectLater(
        publishQuickLecture(
          db: db,
          actorId: 'dashboard',
          subjectId: 'sub-1',
          tabKey: 'online',
          title: 'Quick',
          bunnyVideoId: _guid,
          publishNow: true,
          associationGateway: gateway,
        ),
        throwsA(isA<Exception>()),
      );
      final snap = await db.collection('lecture_resources').get();
      expect(snap.docs.single.data()['bunny_library_id'], isNull);
      expect(snap.docs.single.data()['bunny_video_id'], _guid);
    });

    test('pdf-only quick upload never calls the gateway', () async {
      final String lectureId = await publishQuickLecture(
        db: db,
        actorId: 'dashboard',
        subjectId: 'sub-1',
        tabKey: 'online',
        title: 'Quick',
        pdfPath: 'docs/q.pdf',
        publishNow: true,
        associationGateway: gateway,
      );
      final data = (await resourcesOf(lectureId)).single.data();
      expect(data['resource_type'], 'pdf');
      expect(data['bunny_library_id'], isNull);
      expect(gateway.calls, isEmpty);
    });
  });
}
