import 'package:drtarek_dashboard/features/home/presentation/widgets/quick_upload_modal.dart';
import 'package:drtarek_dashboard/features/students/presentation/providers/subject_details_provider.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// Writer-sync proof for `lectures/{id}.first_video` (Phase 3): drives the
/// real Dashboard mutation paths against FakeFirebaseFirestore and asserts
/// the denormalized pointer after every create/update/delete/reorder.
///
/// NOTE: no restore path exists in the codebase (no write ever resets a
/// resource `is_deleted` to false), so restore coverage is N/A by
/// construction — deletion recompute is covered instead.
void main() {
  late FakeFirebaseFirestore db;
  late SubjectDetailsController controller;

  setUp(() {
    db = FakeFirebaseFirestore();
    controller = SubjectDetailsController(db);
  });

  Future<Map<String, dynamic>?> firstVideoOf(String lectureId) async {
    final snap = await db.collection('lectures').doc(lectureId).get();
    final data = snap.data();
    if (data == null || data['first_video'] == null) return null;
    return Map<String, dynamic>.from(data['first_video'] as Map);
  }

  Future<String> seedLecture() async {
    final ref = await db.collection('lectures').add({
      'subject_id': 'sub-1',
      'section_id': 'sec-1',
      'title': 'L',
      'display_order': 0,
      'status': 'published',
      'is_deleted': false,
    });
    return ref.id;
  }

  Future<String> seedResource(
    String lectureId,
    String id, {
    String type = 'video',
    int order = 0,
    String? bunnyVideoId = '99999999-9999-4999-8999-999999999999',
    bool visible = true,
    bool deleted = false,
    String title = 'R',
  }) async {
    await db.collection('lecture_resources').doc(id).set({
      'lecture_id': lectureId,
      'resource_type': type,
      'title': title,
      'display_order': order,
      'bunny_video_id': bunnyVideoId,
      'is_visible': visible,
      'visibility': visible,
      'is_deleted': deleted,
    });
    return id;
  }

  Future<void> updateLecture(
    String lectureId, {
    List<NewLectureResource> created = const [],
    List<String> deleted = const [],
    List<UpdatedLectureResource> updated = const [],
  }) {
    return controller.updateLectureFull(
      lectureId: lectureId,
      title: 'L',
      displayOrder: 0,
      publishNow: false,
      preserveStatus: true,
      guestEnabled: false,
      newResources: created,
      deleteResourceIds: deleted,
      updatedResources: updated,
      accessByStudent: const {},
    );
  }

  group('createLectureFull writes first_video in the same batch', () {
    test('eligible video becomes first_video', () async {
      final lectureId = await controller.createLectureFull(
        subjectId: 'sub-1',
        tab: SubjectContentTab.lectures,
        title: 'L',
        displayOrder: 0,
        publishNow: true,
        guestEnabled: false,
        resources: [
          const NewLectureResource(
            type: 'video',
            title: 'V',
            displayOrder: 3,
            bunnyVideoId: '11111111-1111-4111-8111-111111111111',
          ),
        ],
        accessByStudent: const {},
      );

      final fv = await firstVideoOf(lectureId);
      expect(fv, isNotNull);
      expect(fv!['bunny_video_id'], '11111111-1111-4111-8111-111111111111');
      expect(fv['title'], 'V');
      expect(fv['display_order'], 3);
      final resources = await db
          .collection('lecture_resources')
          .where('lecture_id', isEqualTo: lectureId)
          .get();
      expect(fv['resource_id'], resources.docs.single.id);
    });

    test('non-eligible video never becomes first_video', () async {
      final lectureId = await controller.createLectureFull(
        subjectId: 'sub-1',
        tab: SubjectContentTab.lectures,
        title: 'L',
        displayOrder: 0,
        publishNow: true,
        guestEnabled: false,
        resources: [
          const NewLectureResource(
            type: 'pdf',
            title: 'P',
            displayOrder: 0,
          ),
          const NewLectureResource(
            type: 'video',
            title: 'V-noid',
            displayOrder: 1,
          ),
        ],
        accessByStudent: const {},
      );

      expect(await firstVideoOf(lectureId), isNull);
    });

    test('draft lecture keeps first_video null (invisible rows)', () async {
      final lectureId = await controller.createLectureFull(
        subjectId: 'sub-1',
        tab: SubjectContentTab.lectures,
        title: 'L',
        displayOrder: 0,
        publishNow: false,
        guestEnabled: false,
        resources: [
          const NewLectureResource(
            type: 'video',
            title: 'V',
            displayOrder: 0,
            bunnyVideoId: '11111111-1111-4111-8111-111111111111',
          ),
        ],
        accessByStudent: const {},
      );

      expect(await firstVideoOf(lectureId), isNull);
    });
  });

  group('updateLectureFull recomputes first_video', () {
    test('bunny id empty → valid updates selection', () async {
      final lectureId = await seedLecture();
      await seedResource(lectureId, 'v1', bunnyVideoId: null);
      await updateLecture(lectureId);
      expect(await firstVideoOf(lectureId), isNull);

      await updateLecture(lectureId, updated: [
        const UpdatedLectureResource(
          id: 'v1',
          title: 'V',
          displayOrder: 0,
          bunnyVideoId: '11111111-1111-4111-8111-111111111111',
        ),
      ]);
      final fv = await firstVideoOf(lectureId);
      expect(fv?['resource_id'], 'v1');
      expect(fv?['bunny_video_id'], '11111111-1111-4111-8111-111111111111');
    });

    test('bunny id valid → empty falls back to next winner', () async {
      final lectureId = await seedLecture();
      await seedResource(lectureId, 'v1', order: 0, bunnyVideoId: '11111111-1111-4111-8111-111111111111');
      await seedResource(lectureId, 'v2', order: 5, bunnyVideoId: '22222222-2222-4222-8222-222222222222');
      await updateLecture(lectureId);
      expect((await firstVideoOf(lectureId))?['resource_id'], 'v1');

      await updateLecture(lectureId, updated: [
        const UpdatedLectureResource(
          id: 'v1',
          title: 'V',
          displayOrder: 0,
          bunnyVideoId: '',
        ),
      ]);
      expect((await firstVideoOf(lectureId))?['resource_id'], 'v2');
    });

    test('invisible persisted rows are ignored', () async {
      final lectureId = await seedLecture();
      await seedResource(lectureId, 'v-hidden', order: 0, visible: false);
      await seedResource(lectureId, 'v1', order: 1);
      await updateLecture(lectureId);
      expect((await firstVideoOf(lectureId))?['resource_id'], 'v1');
    });

    test('soft delete recomputes; last video deleted clears to null',
        () async {
      final lectureId = await seedLecture();
      await seedResource(lectureId, 'v1', order: 0, bunnyVideoId: '11111111-1111-4111-8111-111111111111');
      await seedResource(lectureId, 'v2', order: 1, bunnyVideoId: '22222222-2222-4222-8222-222222222222');
      await updateLecture(lectureId);
      expect((await firstVideoOf(lectureId))?['resource_id'], 'v1');

      await updateLecture(lectureId, deleted: ['v1']);
      expect((await firstVideoOf(lectureId))?['resource_id'], 'v2');

      await updateLecture(lectureId, deleted: ['v2']);
      expect(await firstVideoOf(lectureId), isNull);
    });

    test('display_order swap recomputes the winner', () async {
      final lectureId = await seedLecture();
      await seedResource(lectureId, 'v1', order: 0, bunnyVideoId: '11111111-1111-4111-8111-111111111111');
      await seedResource(lectureId, 'v2', order: 1, bunnyVideoId: '22222222-2222-4222-8222-222222222222');
      await updateLecture(lectureId);
      expect((await firstVideoOf(lectureId))?['resource_id'], 'v1');

      await updateLecture(lectureId, updated: [
        const UpdatedLectureResource(
          id: 'v1',
          title: 'V1',
          displayOrder: 9,
        ),
      ]);
      expect((await firstVideoOf(lectureId))?['resource_id'], 'v2');
    });

    test('order tie uses document id ascending', () async {
      final lectureId = await seedLecture();
      await seedResource(lectureId, 'zzz', order: 2, bunnyVideoId: '77777777-7777-4777-8777-777777777777');
      await seedResource(lectureId, 'aaa', order: 2, bunnyVideoId: '88888888-8888-4888-8888-888888888888');
      await updateLecture(lectureId);
      expect((await firstVideoOf(lectureId))?['resource_id'], 'aaa');
    });

    test('unrelated lecture update preserves existing first_video',
        () async {
      final lectureId = await seedLecture();
      await seedResource(lectureId, 'v1', order: 0, bunnyVideoId: '11111111-1111-4111-8111-111111111111');
      await updateLecture(lectureId);
      final before = await firstVideoOf(lectureId);
      expect(before?['resource_id'], 'v1');

      await updateLecture(lectureId);
      expect(await firstVideoOf(lectureId), before);
    });
  });

  group('publishQuickLecture maintains first_video', () {
    test('video quick upload sets first_video', () async {
      final lectureId = await publishQuickLecture(
        db: db,
        actorId: 'dashboard',
        subjectId: 'sub-1',
        tabKey: 'online',
        title: 'Q',
        bunnyVideoId: '55555555-5555-4555-8555-555555555555',
        publishNow: true,
      );

      final fv = await firstVideoOf(lectureId);
      expect(fv?['bunny_video_id'], '55555555-5555-4555-8555-555555555555');
      expect(fv?['display_order'], 1);
    });

    test('pdf-only quick upload keeps first_video null', () async {
      final lectureId = await publishQuickLecture(
        db: db,
        actorId: 'dashboard',
        subjectId: 'sub-1',
        tabKey: 'online',
        title: 'Q',
        pdfPath: 'docs/q.pdf',
        publishNow: true,
      );

      expect(await firstVideoOf(lectureId), isNull);
    });
  });
}
