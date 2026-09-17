import 'package:flutter_test/flutter_test.dart';

import 'package:dr_tarek_platform/features/content_authoring/data/datasources/admin_content_remote_data_source_impl.dart'
    show lectureAccessGrantWrite, LectureAccessGrantWrite;
import 'package:dr_tarek_platform/features/content_authoring/data/repositories/admin_content_repository_impl.dart';
import 'package:dr_tarek_platform/features/content_authoring/domain/entities/admin_content_entities.dart';

import 'admin_content_repository_test.dart'
    show FakeAdminContentDataSource, FakeResourceStorageGateway;

/// V1 per-lecture student access backend tests.
///
/// Covers: allow/deny grant shapes, existing-grant update preserving
/// created_* audit info, repeat-save idempotence, deterministic ids
/// (no duplicates), documented no-grant fallback, and repository
/// passthrough of save + grants stream.
void main() {
  const stamp = 'SERVER_TIMESTAMP';

  LectureAccessGrant grant(String student, bool allowed) =>
      LectureAccessGrant(
          lectureId: 'lec1', studentId: student, allowed: allowed);

  group('grant document identity', () {
    test('deterministic id lectureId_studentId', () {
      expect(lectureAccessGrantDocId('lec1', 'stu9'), 'lec1_stu9');
    });

    test('same pair always maps to the same id (no duplicates possible)',
        () {
      expect(lectureAccessGrantDocId('lec1', 'stu9'),
          lectureAccessGrantDocId('lec1', 'stu9'));
    });
  });

  group('grant write fields', () {
    test('1. allowed=true grant carries allowed true + full audit stamps',
        () {
      final write = lectureAccessGrantWrite(
        grant: grant('stu1', true),
        existingCreatedAt: null,
        existingCreatedBy: null,
        hadExistingDoc: false,
        actorId: 'teacher1',
        serverTimestamp: stamp,
      );
      expect(write.isNew, true);
      expect(
          write.fields,
          {
            'lecture_id': 'lec1',
            'student_id': 'stu1',
            'allowed': true,
            'updated_at': stamp,
            'updated_by': 'teacher1',
            'is_deleted': false,
            'deleted_at': null,
            'deleted_by': null,
            'created_at': stamp,
            'created_by': 'teacher1',
          });
    });

    test('2. allowed=false grant carries allowed false', () {
      final write = lectureAccessGrantWrite(
        grant: grant('stu1', false),
        existingCreatedAt: null,
        existingCreatedBy: null,
        hadExistingDoc: false,
        actorId: 'teacher1',
        serverTimestamp: stamp,
      );
      expect(write.isNew, true);
      expect(write.fields['allowed'], false);
    });

    test('3. existing grant update preserves created_* and updates state',
        () {
      final write = lectureAccessGrantWrite(
        grant: grant('stu1', false),
        existingCreatedAt: 'ORIGINAL_CREATED',
        existingCreatedBy: 'original_teacher',
        hadExistingDoc: true,
        actorId: 'teacher2',
        serverTimestamp: stamp,
      );
      expect(write.isNew, false);
      expect(write.fields['allowed'], false);
      expect(write.fields['created_at'], 'ORIGINAL_CREATED');
      expect(write.fields['created_by'], 'original_teacher');
      expect(write.fields['updated_at'], stamp);
      expect(write.fields['updated_by'], 'teacher2');
    });

    test('4. repeated save produces identical output (repeat-safe)', () {
      LectureAccessGrantWrite build() => lectureAccessGrantWrite(
            grant: grant('stu1', true),
            existingCreatedAt: 'ORIGINAL_CREATED',
            existingCreatedBy: 'original_teacher',
            hadExistingDoc: true,
            actorId: 'teacher1',
            serverTimestamp: stamp,
          );
      final first = build();
      final second = build();
      expect(second.fields, first.fields);
      expect(second.isNew, first.isNew);
    });

    test('11. legacy grant missing created_* falls back to current stamps',
        () {
      final write = lectureAccessGrantWrite(
        grant: grant('stu1', true),
        existingCreatedAt: null,
        existingCreatedBy: null,
        hadExistingDoc: true,
        actorId: 'teacher1',
        serverTimestamp: stamp,
      );
      expect(write.isNew, false);
      expect(write.fields['created_at'], stamp);
      expect(write.fields['created_by'], 'teacher1');
    });

    test('writes always carry the active soft-delete state', () {
      for (final isNew in [true, false]) {
        final write = lectureAccessGrantWrite(
          grant: grant('stu1', true),
          existingCreatedAt: isNew ? null : 'C',
          existingCreatedBy: isNew ? null : 'B',
          hadExistingDoc: !isNew,
          actorId: 'teacher1',
          serverTimestamp: stamp,
        );
        expect(write.fields['is_deleted'], false);
        expect(write.fields['deleted_at'], isNull);
        expect(write.fields['deleted_by'], isNull);
      }
    });
  });

  group('fallback behavior', () {
    test('5. no grant defers to normal eligibility (never denies)', () {
      expect(isLectureAccessDeniedByGrant(null), false);
    });

    test('allowed=true grant does not deny', () {
      expect(isLectureAccessDeniedByGrant(true), false);
    });

    test('explicit allowed=false denies', () {
      expect(isLectureAccessDeniedByGrant(false), true);
    });

    test('displayed default is ON without staged toggle or grant', () {
      expect(resolveEffectiveAccess(), true);
    });

    test('stored grant drives the default when unstaged', () {
      expect(resolveEffectiveAccess(grantAllowed: false), false);
      expect(resolveEffectiveAccess(grantAllowed: true), true);
    });

    test('explicit staged toggle wins over the stored grant', () {
      expect(
          resolveEffectiveAccess(staged: true, grantAllowed: false), true);
      expect(
          resolveEffectiveAccess(staged: false, grantAllowed: true), false);
    });
  });

  group('repository passthrough', () {
    AdminContentRepositoryImpl repoWith(FakeAdminContentDataSource fake) =>
        AdminContentRepositoryImpl(
          dataSource: fake,
          gateways: {
            ResourceStorageProvider.firebase:
                FakeResourceStorageGateway(ResourceStorageProvider.firebase),
            ResourceStorageProvider.bunny:
                FakeResourceStorageGateway(ResourceStorageProvider.bunny),
          },
        );

    test('save forwards every staged grant to the data source', () async {
      final fake = FakeAdminContentDataSource();
      final repo = repoWith(fake);
      final grants = [grant('stu1', true), grant('stu2', false)];
      await repo.saveLectureAccess(grants);
      expect(fake.accessSaveCalls, hasLength(1));
      expect(fake.accessSaveCalls.single, grants);
    });

    test('empty save is a no-op for the data source', () async {
      final fake = FakeAdminContentDataSource();
      final repo = repoWith(fake);
      await repo.saveLectureAccess(const []);
      expect(fake.accessSaveCalls.single, isEmpty);
    });
  });
}
