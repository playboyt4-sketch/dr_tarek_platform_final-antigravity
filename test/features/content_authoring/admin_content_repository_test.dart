import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dr_tarek_platform/features/content_authoring/data/datasources/admin_content_data_source.dart';
import 'package:dr_tarek_platform/features/content_authoring/data/datasources/admin_content_remote_data_source_impl.dart'
    show adminResourceFields;
import 'package:dr_tarek_platform/features/content_authoring/data/repositories/admin_content_repository_impl.dart';
import 'package:dr_tarek_platform/features/content_authoring/data/storage/resource_storage_gateway.dart'
    show ResourceAccessUrl, StoredResourceFile, ResourceStorageGateway;
import 'package:dr_tarek_platform/features/content_authoring/domain/entities/admin_content_entities.dart';
import 'package:dr_tarek_platform/core/errors/failure.dart';
import 'package:dr_tarek_platform/features/lecture/domain/entities/lecture.dart';
import 'package:dr_tarek_platform/features/lecture/domain/entities/lecture_resource.dart'
    show LectureResourceType;

/// Records every call so tests can assert the exact write shapes the
/// repository produces, without any Firebase SDK involvement.
class FakeAdminContentDataSource implements AdminContentDataSource {
  final List<AdminSection> sectionSeed;
  final List<Lecture> lectureSeed;
  final List<AdminLectureResource> resourceSeed;

  final setDocCalls = <({String resourceId, Map<String, dynamic> fields})>[];
  final updateDocCalls =
      <({String resourceId, Map<String, dynamic> fields})>[];
  final sectionReorderCalls = <List<({String id, int displayOrder})>>[];
  final lectureCreateCalls = <({
    String subjectId,
    String sectionId,
    int displayOrder,
    DateTime? publishDate,
    bool publicFreeEnabled,
    int? publicFreePreviewMinutes,
  })>[];
  final lectureUpdateCalls = <Map<String, dynamic>>[];
  int activeLectureCountOverride = 0;
  final restoredSections = <String>[];
  final restoredLectures = <String>[];
  final restoredResources = <String>[];

  FakeAdminContentDataSource({
    this.sectionSeed = const [],
    this.lectureSeed = const [],
    this.resourceSeed = const [],
  });

  @override
  Future<List<({String id, String title})>> listSubjects() async =>
      [(id: 'subject-1', title: 'مادة تجريبية')];

  @override
  Stream<List<AdminSection>> watchSections(String subjectId) =>
      Stream.value(sectionSeed);

  @override
  Stream<List<AdminSection>> watchArchivedSections(String subjectId) =>
      const Stream.empty();

  @override
  Future<String> createSection({
    required String subjectId,
    required String title,
    required bool isVisible,
    required int displayOrder,
  }) async =>
      'new-section';

  @override
  Future<void> updateSection({
    required String sectionId,
    required String title,
    required bool isVisible,
  }) async {}

  @override
  Future<void> reorderSections(
      List<({String id, int displayOrder})> order) async {
    sectionReorderCalls.add(order);
  }

  @override
  Future<void> deleteSection(String sectionId) async {}

  @override
  Future<void> restoreSection(String sectionId) async {
    restoredSections.add(sectionId);
  }

  @override
  Stream<List<Lecture>> watchLectures(String sectionId) =>
      Stream.value(lectureSeed);

  @override
  Stream<List<ArchivedLecture>> watchArchivedLectures(String subjectId) =>
      const Stream.empty();

  @override
  Future<int> countActiveLectures(String sectionId) async =>
      activeLectureCountOverride;

  @override
  Future<String> createLecture({
    required String subjectId,
    required String sectionId,
    required String title,
    required String description,
    required int displayOrder,
    DateTime? publishDate,
    bool publicFreeEnabled = false,
    int? publicFreePreviewMinutes,
  }) async {
    lectureCreateCalls.add((
      subjectId: subjectId,
      sectionId: sectionId,
      displayOrder: displayOrder,
      publishDate: publishDate,
      publicFreeEnabled: publicFreeEnabled,
      publicFreePreviewMinutes: publicFreePreviewMinutes,
    ));
    return 'new-lecture';
  }

  @override
  Future<void> updateLectureMetadata({
    required String lectureId,
    required String title,
    required String description,
    required int displayOrder,
    DateTime? publishDate,
    bool? publicFreeEnabled,
    int? publicFreePreviewMinutes,
  }) async {
    lectureUpdateCalls.add({
      'lectureId': lectureId,
      'publicFreeEnabled': publicFreeEnabled,
      'publicFreePreviewMinutes': publicFreePreviewMinutes,
    });
  }

  @override
  Future<void> setLectureStatus(
      {required String lectureId, required String status}) async {}

  @override
  Future<void> archiveLecture(String lectureId) async {}

  @override
  Future<void> restoreLecture(String lectureId) async {
    restoredLectures.add(lectureId);
  }

  @override
  Future<void> reorderLectures(
      List<({String id, int displayOrder})> order) async {}

  @override
  Stream<List<AdminLectureResource>> watchResources(String lectureId) =>
      Stream.value(resourceSeed);

  @override
  Stream<List<AdminLectureResource>> watchArchivedResources(
          String lectureId) =>
      const Stream.empty();

  @override
  Future<void> setResourceDoc({
    required String resourceId,
    required Map<String, dynamic> fields,
  }) async {
    setDocCalls.add((resourceId: resourceId, fields: fields));
  }

  @override
  Future<void> updateResourceDoc(
      String resourceId, Map<String, dynamic> fields) async {
    updateDocCalls.add((resourceId: resourceId, fields: fields));
  }

  @override
  Future<void> reorderResources(
      List<({String id, int displayOrder})> order) async {}

  @override
  Future<void> restoreResource(String resourceId) async {
    restoredResources.add(resourceId);
  }
}

/// In-memory gateway recording which backend the repository dispatched to.
class FakeResourceStorageGateway implements ResourceStorageGateway {
  final ResourceStorageProvider storedProvider;
  final uploads = <({String lectureId, String resourceId, String fileName})>[];
  final accessRequests = <({String resourceId, bool forDownload})>[];

  FakeResourceStorageGateway(this.storedProvider);

  @override
  ResourceStorageProvider get provider => storedProvider;

  @override
  Future<StoredResourceFile> upload({
    required String lectureId,
    required String resourceId,
    required File file,
    String? contentTypeOverride,
    void Function(double progress)? onProgress,
  }) async {
    uploads.add((
      lectureId: lectureId,
      resourceId: resourceId,
      fileName: file.uri.pathSegments.last,
    ));
    onProgress?.call(1.0);
    return StoredResourceFile(
      storagePath:
          'lecture_resources/$lectureId/$resourceId/${file.uri.pathSegments.last}',
      provider: storedProvider,
    );
  }

  @override
  Future<ResourceAccessUrl> getSignedAccessUrl({
    required String resourceId,
    required bool forDownload,
  }) async {
    accessRequests.add((resourceId: resourceId, forDownload: forDownload));
    return ResourceAccessUrl(
      url: 'https://signed.example/$resourceId',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    );
  }

  @override
  Future<void> delete({
    required String lectureId,
    required String resourceId,
    required String fileName,
  }) async {}
}

AdminSection _section({
  String id = 'sec-1',
  bool isSystem = false,
  int order = 1,
}) =>
    AdminSection(
      id: id,
      subjectId: 'subject-1',
      sectionKey: isSystem ? 'explanation' : null,
      isSystemSection: isSystem,
      title: 'قسم',
      displayOrder: order,
      isVisible: true,
    );

AdminContentRepositoryImpl _repoWithFakes(
  FakeAdminContentDataSource fake, {
  Future<String?> Function()? defaultLoader,
}) {
  return AdminContentRepositoryImpl(
    dataSource: fake,
    gateways: {
      ResourceStorageProvider.firebase:
          FakeResourceStorageGateway(ResourceStorageProvider.firebase),
      ResourceStorageProvider.bunny:
          FakeResourceStorageGateway(ResourceStorageProvider.bunny),
    },
    platformDefaultProviderLoader:
        defaultLoader ?? () async => 'firebase',
  );
}

void main() {
  group('AdminContentRepositoryImpl — system-section guard (Feature 03)', () {
    test('deleting a SYSTEM section throws permissionDenied and never '
        'reaches the datasource', () async {
      final fake = FakeAdminContentDataSource();
      final repo = _repoWithFakes(fake);

      await expectLater(
        repo.deleteCustomSection(_section(id: 'sec-system', isSystem: true)),
        throwsA(isA<Failure>().having(
            (f) => f.code, 'code', FailureCode.permissionDenied)),
      );
    });
  });

  group('AdminContentRepositoryImpl — section-deletion block (Part B)', () {
    test('deleting a section with ACTIVE lectures throws the specific '
        'catchable Failure carrying the ratified Arabic message', () async {
      final fake = FakeAdminContentDataSource()
        ..activeLectureCountOverride = 3;
      final repo = _repoWithFakes(fake);

      await expectLater(
        repo.deleteCustomSection(_section(id: 'sec-custom')),
        throwsA(isA<Failure>()
            .having((f) => f.code, 'code',
                FailureCode.sectionHasActiveLectures)
            .having(
                (f) => f.debugDetail,
                'debugDetail',
                'لا يمكن حذف القسم لوجود محاضرات نشطة بداخله. '
                    'يرجى أرشفة المحاضرات أولاً.')),
      );
    });

    test('deleting a fully-archived section is allowed', () async {
      final fake = FakeAdminContentDataSource()
        ..activeLectureCountOverride = 0;
      final repo = _repoWithFakes(fake);

      await expectLater(
        repo.deleteCustomSection(_section(id: 'sec-custom')),
        completes,
      );
    });

    test('restore flows reach the datasource', () async {
      final fake = FakeAdminContentDataSource();
      final repo = _repoWithFakes(fake);

      await repo.restoreSection(_section(id: 'sec-9'));
      await repo.restoreLecture(ArchivedLecture(
        id: 'lec-9',
        subjectId: 'subject-1',
        sectionId: 'sec-1',
        title: 'مؤرشفة',
        statusAtArchive: LectureStatus.published,
      ));
      await repo.restoreResource('res-9');

      expect(fake.restoredSections, ['sec-9']);
      expect(fake.restoredLectures, ['lec-9']);
      expect(fake.restoredResources, ['res-9']);
    });
  });

  group('AdminContentRepositoryImpl — ordering contracts', () {
    test('reorder rewrites display_order as dense 1..n atomically',
        () async {
      final fake = FakeAdminContentDataSource();
      final repo = _repoWithFakes(fake);

      await repo.reorderSections([
        _section(id: 'a', order: 7),
        _section(id: 'b', order: 3),
        _section(id: 'c', order: 9),
      ]);

      expect(fake.sectionReorderCalls, hasLength(1));
      expect(
        fake.sectionReorderCalls.single
            .map((e) => (e.id, e.displayOrder))
            .toList(),
        [
          ('a', 1),
          ('b', 2),
          ('c', 3),
        ],
      );
    });

    test('createLecture forwards subject_id and Public Free fields '
        '(callable contract + FINAL_DECISIONS §11)', () async {
      final fake = FakeAdminContentDataSource();
      final repo = _repoWithFakes(fake);

      await repo.createLecture(
        subjectId: 'subject-1',
        sectionId: 'sec-1',
        title: 'محاضرة',
        description: '',
        publishDate: DateTime(2026, 9, 1),
        publicFreeEnabled: true,
        publicFreePreviewMinutes: 5,
      );

      expect(fake.lectureCreateCalls.single.subjectId, 'subject-1');
      expect(fake.lectureCreateCalls.single.displayOrder, 1); // appended
      expect(fake.lectureCreateCalls.single.publicFreeEnabled, true);
      expect(fake.lectureCreateCalls.single.publicFreePreviewMinutes, 5);
    });
  });

  group('adminResourceFields — lecture_resources schema mapping', () {
    test('video resources map to bunny_video_id and carry NO provider field',
        () {
      final fields = adminResourceFields(const AdminLectureResource(
        id: 'r-1',
        lectureId: 'lec-1',
        resourceType: LectureResourceType.video,
        title: 'الجزء الأول',
        displayOrder: 2,
        bunnyVideoId: 'bunny-123',
        isVisible: true,
        isDeleted: false,
      ));

      expect(fields['resource_type'], 'video');
      expect(fields['bunny_video_id'], 'bunny-123');
      // Video stays implicitly Bunny — no storage_provider field (§15).
      expect(fields.containsKey('storage_provider'), isFalse);
      expect(fields['resource_url'], '');
      expect(fields['visibility'], true); // legacy mirror kept in sync
    });

    test('pdf resources persist their storage_provider wire value', () {
      final cases = <ResourceStorageProvider?, String>{
        ResourceStorageProvider.bunny: 'bunny',
        ResourceStorageProvider.firebase: 'firebase',
        null: 'firebase', // absent falls back to the legacy default
      };
      cases.forEach((provider, expectedWire) {
        final fields = adminResourceFields(AdminLectureResource(
          id: 'r-3',
          lectureId: 'lec-1',
          resourceType: LectureResourceType.pdf,
          title: 'ملف',
          displayOrder: 1,
          storagePath: 'lecture_resources/lec-1/r-3/file.pdf',
          storageProvider: provider,
          isVisible: true,
          isDeleted: false,
        ));

        expect(fields['storage_provider'], expectedWire);
        expect(
            fields['storage_path'], 'lecture_resources/lec-1/r-3/file.pdf');
      });
    });

    test('thumbnail provider is written when supplied', () {
      final fields = adminResourceFields(const AdminLectureResource(
        id: 'r-4',
        lectureId: 'lec-1',
        resourceType: LectureResourceType.video,
        title: 'فيديو بصورة',
        displayOrder: 1,
        bunnyVideoId: 'bunny-x',
        thumbnail: 'lecture_resources/lec-1/r-4/thumb.png',
        thumbnailProvider: ResourceStorageProvider.bunny,
        isVisible: true,
        isDeleted: false,
      ));

      expect(fields['thumbnail_storage_provider'], 'bunny');
    });
  });

  group('Dual-provider dispatch (FINAL_DECISIONS §15 / Part A.3)', () {
    Future<Directory> tempFile(String name) async {
      final dir = Directory.systemTemp.createTempSync('cta_dual');
      File('${dir.path}/$name').writeAsBytesSync(List.filled(64, 7));
      return dir;
    }

    AdminLectureResource pdfRequest(String lectureId) => AdminLectureResource(
          id: '',
          lectureId: lectureId,
          resourceType: LectureResourceType.pdf,
          title: 'ملف',
          displayOrder: 0,
          isVisible: true,
          isDeleted: false,
        );

    test('explicit bunny choice routes to the Bunny gateway and persists '
        'storage_provider=bunny', () async {
      final dir = await tempFile('bunny.pdf');
      addTearDown(() => dir.deleteSync(recursive: true));

      final fake = FakeAdminContentDataSource();
      final repo = _repoWithFakes(fake);
      final firebaseGateway =
          repo.gateways[ResourceStorageProvider.firebase]!
              as FakeResourceStorageGateway;
      final bunnyGateway = repo.gateways[ResourceStorageProvider.bunny]!
          as FakeResourceStorageGateway;

      final id = await repo.createUploadedResource(
        resource: pdfRequest('lec-b'),
        file: File('${dir.path}/bunny.pdf'),
        storageProvider: ResourceStorageProvider.bunny,
      );

      expect(bunnyGateway.uploads, hasLength(1));
      expect(firebaseGateway.uploads, isEmpty);
      final doc = fake.setDocCalls.single;
      expect(doc.resourceId, id);
      expect(doc.fields['storage_provider'], 'bunny');
    });

    test('explicit firebase choice routes to the Firebase gateway and '
        'persists storage_provider=firebase', () async {
      final dir = await tempFile('fb.pdf');
      addTearDown(() => dir.deleteSync(recursive: true));

      final fake = FakeAdminContentDataSource();
      final repo = _repoWithFakes(fake);
      final firebaseGateway =
          repo.gateways[ResourceStorageProvider.firebase]!
              as FakeResourceStorageGateway;
      final bunnyGateway = repo.gateways[ResourceStorageProvider.bunny]!
          as FakeResourceStorageGateway;

      await repo.createUploadedResource(
        resource: pdfRequest('lec-f'),
        file: File('${dir.path}/fb.pdf'),
        storageProvider: 'firebase', // wire-string form from the UI selector
      );

      expect(firebaseGateway.uploads, hasLength(1));
      expect(bunnyGateway.uploads, isEmpty);
      expect(fake.setDocCalls.single.fields['storage_provider'], 'firebase');
    });

    test('no choice uses the platform default from system_settings',
        () async {
      final dir = await tempFile('default.pdf');
      addTearDown(() => dir.deleteSync(recursive: true));

      final fake = FakeAdminContentDataSource();
      final repo = _repoWithFakes(
        fake,
        defaultLoader: () async => 'bunny',
      );
      final bunnyGateway = repo.gateways[ResourceStorageProvider.bunny]!
          as FakeResourceStorageGateway;

      await repo.createUploadedResource(
        resource: pdfRequest('lec-d'),
        file: File('${dir.path}/default.pdf'),
        storageProvider: null,
      );

      expect(bunnyGateway.uploads, hasLength(1));
      expect(fake.setDocCalls.single.fields['storage_provider'], 'bunny');
    });

    test('thumbnails record their own thumbnail_storage_provider',
        () async {
      final dir = await tempFile('thumb.jpg');
      addTearDown(() => dir.deleteSync(recursive: true));

      final fake = FakeAdminContentDataSource();
      final repo = _repoWithFakes(fake);

      await repo.uploadThumbnail(
        lectureId: 'lec-t',
        resourceId: 'res-t',
        file: File('${dir.path}/thumb.jpg'),
        storageProvider: ResourceStorageProvider.bunny,
      );

      final call = fake.updateDocCalls.single;
      expect(call.fields['thumbnail_storage_provider'], 'bunny');
      expect(call.fields['thumbnail'],
          'lecture_resources/lec-t/res-t/thumb.jpg');
    });
  });

  group('AdminContentRepositoryImpl — upload orchestration', () {
    test('uploads under the REAL resource document id then writes metadata',
        () async {
      final dir = Directory.systemTemp.createTempSync('cta_test');
      final file = File('${dir.path}/notes.pdf')
        ..writeAsBytesSync(List.filled(1024, 42));
      addTearDown(() => dir.deleteSync(recursive: true));

      final fake = FakeAdminContentDataSource();
      final repo = _repoWithFakes(fake);
      final progressValues = <double>[];

      final resourceId = await repo.createUploadedResource(
        resource: AdminLectureResource(
          id: '',
          lectureId: 'lec-9',
          resourceType: LectureResourceType.pdf,
          title: 'ملف المحاضرة',
          displayOrder: 0, // auto-append
          isVisible: true,
          isDeleted: false,
        ),
        file: file,
        onProgress: progressValues.add,
      );

      expect(fake.setDocCalls, hasLength(1));
      final call = fake.setDocCalls.single;
      expect(call.resourceId, resourceId);
      expect(call.fields['storage_path'],
          'lecture_resources/lec-9/$resourceId/notes.pdf');
      expect(call.fields['is_visible'], true);
      expect(call.fields['visibility'], true);
      expect(call.fields['is_deleted'], false);
      expect(progressValues, [1.0]);
    });

    test('rejects files above the placeholder 50MB ceiling BEFORE uploading',
        () async {
      final dir = Directory.systemTemp.createTempSync('cta_big');
      final file = File('${dir.path}/huge.pdf');
      final raf = await file.open(mode: FileMode.write);
      await raf.truncate(AdminContentDataSource.maxDocumentBytes + 1);
      await raf.close();
      addTearDown(() => dir.deleteSync(recursive: true));

      final fake = FakeAdminContentDataSource();
      final repo = _repoWithFakes(fake);

      await expectLater(
        repo.createUploadedResource(
          resource: AdminLectureResource(
            id: '',
            lectureId: 'lec-1',
            resourceType: LectureResourceType.pdf,
            title: 'ضخم',
            displayOrder: 1,
            isVisible: true,
            isDeleted: false,
          ),
          file: file,
        ),
        throwsA(isA<Failure>()
            .having((f) => f.code, 'code', FailureCode.validation)),
      );
      expect(fake.setDocCalls, isEmpty); // nothing was persisted
    });
  });

  group('AdminContentDataSource limits — documented placeholders', () {
    test('50MB documents / 5MB images mirror storage.rules', () {
      expect(AdminContentDataSource.maxDocumentBytes, 50 * 1024 * 1024);
      expect(AdminContentDataSource.maxImageBytes, 5 * 1024 * 1024);
    });
  });
}
