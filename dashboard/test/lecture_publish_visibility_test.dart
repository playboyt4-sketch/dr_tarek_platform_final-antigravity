import 'package:drtarek_dashboard/features/students/presentation/providers/subject_details_provider.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression proof for the student "No published video source found for this
/// lecture" failure:
///
/// Resources authored while a lecture is a draft are stored hidden
/// (`is_visible: false`). The student listing/serving gate only returns
/// visible rows, so publishing the lecture must republish those rows in the
/// same write — otherwise they stay hidden forever and playback has no source.
void main() {
  late FakeFirebaseFirestore db;
  late SubjectDetailsController controller;

  setUp(() {
    db = FakeFirebaseFirestore();
    controller = SubjectDetailsController(db);
  });

  Future<Map<String, dynamic>> lectureOf(String lectureId) async {
    final snap = await db.collection('lectures').doc(lectureId).get();
    return snap.data()!;
  }

  Future<List<Map<String, dynamic>>> resourcesOf(String lectureId) async {
    final snap = await db
        .collection('lecture_resources')
        .where('lecture_id', isEqualTo: lectureId)
        .get();
    return snap.docs.map((doc) => doc.data()).toList();
  }

  Future<void> publishLecture(String lectureId) {
    return controller.updateLectureFull(
      lectureId: lectureId,
      title: 'L',
      displayOrder: 0,
      publishNow: true,
      guestEnabled: false,
      newResources: const [],
      deleteResourceIds: const [],
      accessByStudent: const {},
    );
  }

  test('Publish Now republishes rows created while the lecture was a draft',
      () async {
    final lectureId = await controller.createLectureFull(
      subjectId: 'sub-1',
      tab: SubjectContentTab.lectures,
      title: 'L',
      displayOrder: 0,
      publishNow: false,
      guestEnabled: false,
      resources: const [
        NewLectureResource(
          type: 'video',
          title: 'V',
          displayOrder: 0,
          bunnyVideoId: '11111111-1111-4111-8111-111111111111',
        ),
      ],
      accessByStudent: const {},
    );

    // Draft: hidden row, null first-video pointer (not servable yet).
    final draftRows = await resourcesOf(lectureId);
    expect(draftRows.single['is_visible'], isFalse);
    expect(draftRows.single['visibility'], isFalse);
    expect((await lectureOf(lectureId))['first_video'], isNull);

    await publishLecture(lectureId);

    final published = await lectureOf(lectureId);
    expect(published['status'], 'published');
    final rowsSnap = await db
        .collection('lecture_resources')
        .where('lecture_id', isEqualTo: lectureId)
        .get();
    final row = rowsSnap.docs.single;
    expect(row.data()['is_visible'], isTrue);
    expect(row.data()['visibility'], isTrue);
    final firstVideo = published['first_video'] as Map;
    expect(firstVideo['resource_id'], row.id);
    expect(
      firstVideo['bunny_video_id'],
      '11111111-1111-4111-8111-111111111111',
    );
  });

  test('Publish Now flips pre-existing hidden rows too', () async {
    final lectureRef = await db.collection('lectures').add({
      'subject_id': 'sub-1',
      'section_id': 'sec-1',
      'title': 'L',
      'display_order': 0,
      'status': 'draft',
      'is_deleted': false,
    });
    await db.collection('lecture_resources').doc('v-hidden').set({
      'lecture_id': lectureRef.id,
      'subject_id': 'sub-1',
      'resource_type': 'video',
      'title': 'V',
      'display_order': 2,
      'bunny_video_id': '22222222-2222-4222-8222-222222222222',
      'is_visible': false,
      'visibility': false,
      'is_deleted': false,
    });

    await publishLecture(lectureRef.id);

    final row = await db.collection('lecture_resources').doc('v-hidden').get();
    expect(row.data()!['is_visible'], isTrue);
    expect(row.data()!['visibility'], isTrue);
    expect(
      ((await lectureOf(lectureRef.id))['first_video'] as Map)['resource_id'],
      'v-hidden',
    );
  });

  test('plain Save keeps deliberate per-resource hiding on a published lecture',
      () async {
    final lectureRef = await db.collection('lectures').add({
      'subject_id': 'sub-1',
      'section_id': 'sec-1',
      'title': 'L',
      'display_order': 0,
      'status': 'published',
      'is_deleted': false,
    });
    await db.collection('lecture_resources').doc('v-hidden').set({
      'lecture_id': lectureRef.id,
      'resource_type': 'video',
      'title': 'hidden',
      'display_order': 0,
      'bunny_video_id': '33333333-3333-4333-8333-333333333333',
      'is_visible': false,
      'is_deleted': false,
    });
    await db.collection('lecture_resources').doc('v-visible').set({
      'lecture_id': lectureRef.id,
      'resource_type': 'video',
      'title': 'visible',
      'display_order': 1,
      'bunny_video_id': '44444444-4444-4444-8444-444444444444',
      'is_visible': true,
      'is_deleted': false,
    });

    await controller.updateLectureFull(
      lectureId: lectureRef.id,
      title: 'L edited',
      displayOrder: 0,
      publishNow: false,
      preserveStatus: true,
      guestEnabled: false,
      newResources: const [],
      deleteResourceIds: const [],
      accessByStudent: const {},
    );

    final hidden = await db.collection('lecture_resources').doc('v-hidden').get();
    expect(hidden.data()!['is_visible'], isFalse);
    expect(
      ((await lectureOf(lectureRef.id))['first_video'] as Map)['resource_id'],
      'v-visible',
    );
  });

  test('plain Save on a published lecture makes newly added rows visible',
      () async {
    final lectureRef = await db.collection('lectures').add({
      'subject_id': 'sub-1',
      'section_id': 'sec-1',
      'title': 'L',
      'display_order': 0,
      'status': 'published',
      'is_deleted': false,
    });

    await controller.updateLectureFull(
      lectureId: lectureRef.id,
      title: 'L edited',
      displayOrder: 0,
      publishNow: false,
      preserveStatus: true,
      guestEnabled: false,
      newResources: const [
        NewLectureResource(
          type: 'video',
          title: 'new',
          displayOrder: 0,
          bunnyVideoId: '66666666-6666-4666-8666-666666666666',
        ),
      ],
      deleteResourceIds: const [],
      accessByStudent: const {},
    );

    final lecture = await lectureOf(lectureRef.id);
    expect(lecture['status'], 'published');
    final rows = await resourcesOf(lectureRef.id);
    expect(rows.single['is_visible'], isTrue);
    expect(rows.single['visibility'], isTrue);
    expect(
      (lecture['first_video'] as Map)['bunny_video_id'],
      '66666666-6666-4666-8666-666666666666',
    );
  });

  test('scheduled save keeps new rows hidden until the scheduler publishes',
      () async {
    final lectureRef = await db.collection('lectures').add({
      'subject_id': 'sub-1',
      'section_id': 'sec-1',
      'title': 'L',
      'display_order': 0,
      'status': 'draft',
      'is_deleted': false,
    });

    await controller.updateLectureFull(
      lectureId: lectureRef.id,
      title: 'L',
      displayOrder: 0,
      publishNow: false,
      publishDateTime: DateTime.now().add(const Duration(hours: 1)),
      guestEnabled: false,
      newResources: const [
        NewLectureResource(
          type: 'video',
          title: 'V',
          displayOrder: 0,
          bunnyVideoId: '55555555-5555-4555-8555-555555555555',
        ),
      ],
      deleteResourceIds: const [],
      accessByStudent: const {},
    );

    final rows = await resourcesOf(lectureRef.id);
    expect(rows.single['is_visible'], isFalse);
    expect((await lectureOf(lectureRef.id))['status'], 'draft');
    expect((await lectureOf(lectureRef.id))['first_video'], isNull);
  });
}
