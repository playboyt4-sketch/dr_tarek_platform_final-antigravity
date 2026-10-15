import 'package:flutter_test/flutter_test.dart';

import 'package:drtarek_dashboard/features/students/data/repositories/lecture_access_repository_impl.dart'
    show lectureAccessGrantWrite;
import 'package:drtarek_dashboard/features/students/domain/entities/lecture_access.dart';

/// Pure unit tests for Configure Access business rules. No Firebase app
/// is initialized — the grant-write mapping takes an injected
/// timestamp, so audit/merge behavior is verified without Firestore.
void main() {
  group('lectureAccessGrantDocId', () {
    test('is deterministic {lectureId}_{studentId}', () {
      expect(
        lectureAccessGrantDocId('lec1', 'std1'),
        'lec1_std1',
      );
    });
  });

  group('resolveLectureAccess', () {
    test('defaults ON with no staged toggle or stored grant', () {
      expect(resolveLectureAccess(), isTrue);
    });

    test('staged toggle wins over the stored grant', () {
      expect(
        resolveLectureAccess(staged: false, grantAllowed: true),
        isFalse,
      );
      expect(
        resolveLectureAccess(staged: true, grantAllowed: false),
        isTrue,
      );
    });

    test('stored grant wins when nothing is staged', () {
      expect(resolveLectureAccess(grantAllowed: false), isFalse);
      expect(resolveLectureAccess(grantAllowed: true), isTrue);
    });
  });

  group('matchesLectureAccessQuery', () {
    test('empty query matches every eligible student', () {
      expect(
        matchesLectureAccessQuery(
            name: 'Ahmed', phone: '010', plan: 'MAX', query: '  '),
        isTrue,
      );
    });

    test('matches name, phone, or plan case-insensitively', () {
      expect(
        matchesLectureAccessQuery(
            name: 'Sara Ali',
            phone: '011234',
            plan: 'PRO',
            query: 'sara'),
        isTrue,
      );
      expect(
        matchesLectureAccessQuery(
            name: 'Sara Ali',
            phone: '011234',
            plan: 'PRO',
            query: '1234'),
        isTrue,
      );
      expect(
        matchesLectureAccessQuery(
            name: 'Sara Ali',
            phone: '011234',
            plan: 'PRO',
            query: 'pro'),
        isTrue,
      );
      expect(
        matchesLectureAccessQuery(
            name: 'Sara Ali',
            phone: '011234',
            plan: 'PRO',
            query: 'zzz'),
        isFalse,
      );
    });
  });

  group('lectureAccessGrantWrite', () {
    const Object ts = 'TS';

    test('new grant sets created_* and updated_* from the actor', () {
      final write = lectureAccessGrantWrite(
        grant: const LectureAccessGrant(
          lectureId: 'lec1',
          studentId: 'std1',
          allowed: false,
        ),
        existingCreatedAt: null,
        existingCreatedBy: null,
        hadExistingDoc: false,
        actorId: 'doctor1',
        serverTimestamp: ts,
      );
      expect(write.isNew, isTrue);
      expect(
        write.fields,
        <String, Object?>{
          'lecture_id': 'lec1',
          'student_id': 'std1',
          'allowed': false,
          'updated_at': ts,
          'updated_by': 'doctor1',
          'is_deleted': false,
          'deleted_at': null,
          'deleted_by': null,
          'created_at': ts,
          'created_by': 'doctor1',
        },
      );
    });

    test('existing grant merges and preserves created_* audit info', () {
      final write = lectureAccessGrantWrite(
        grant: const LectureAccessGrant(
          lectureId: 'lec1',
          studentId: 'std1',
          allowed: true,
        ),
        existingCreatedAt: 'OLD_TS',
        existingCreatedBy: 'doctor0',
        hadExistingDoc: true,
        actorId: 'doctor1',
        serverTimestamp: ts,
      );
      expect(write.isNew, isFalse);
      expect(write.fields['created_at'], 'OLD_TS');
      expect(write.fields['created_by'], 'doctor0');
      expect(write.fields['updated_by'], 'doctor1');
      expect(write.fields['allowed'], isTrue);
      expect(write.fields['is_deleted'], isFalse);
    });
  });
}
