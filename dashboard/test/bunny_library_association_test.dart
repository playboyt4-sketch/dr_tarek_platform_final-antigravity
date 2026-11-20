// ADR-010 — Dashboard library-association data layer (pure, no Firebase).
//
// Locks the write contract the Dashboard now uses: new videos carry the
// default library, non-video types carry none, unrelated edits preserve the
// stored association, legacy rows stay legacy, and malformed ids are rejected
// instead of written.
import 'package:drtarek_dashboard/features/students/domain/bunny_library_association.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeBunnyLibraryId', () {
    test('trims and keeps a numeric id', () {
      expect(normalizeBunnyLibraryId('  736742 '), '736742');
      expect(normalizeBunnyLibraryId('775315'), '775315');
    });

    test('rejects blank, malformed and non-string values', () {
      expect(normalizeBunnyLibraryId(null), isNull);
      expect(normalizeBunnyLibraryId(''), isNull);
      expect(normalizeBunnyLibraryId('   '), isNull);
      expect(normalizeBunnyLibraryId('library-a'), isNull);
      expect(normalizeBunnyLibraryId(736742), isNull);
      expect(isValidBunnyLibraryId('736742'), isTrue);
      expect(isValidBunnyLibraryId('abc'), isFalse);
    });
  });

  group('bunnyLibraryIdForCreate', () {
    test('new video defaults to the default library', () {
      expect(
        bunnyLibraryIdForCreate(resourceType: 'video'),
        defaultBunnyLibraryId,
      );
      expect(defaultBunnyLibraryId, '736742');
    });

    test('a selected library wins over the default', () {
      expect(
        bunnyLibraryIdForCreate(
          resourceType: 'video',
          selectedLibraryId: '775315',
        ),
        '775315',
      );
    });

    test('non-video resources never carry an association', () {
      for (final String type in <String>[
        'pdf',
        'attachment',
        'external_link',
      ]) {
        expect(
          bunnyLibraryIdForCreate(resourceType: type, selectedLibraryId: '775315'),
          isNull,
        );
      }
    });
  });

  group('bunnyLibraryIdForUpdate', () {
    test('null keeps the stored association (unrelated edit)', () {
      expect(bunnyLibraryIdForUpdate(), isNull);
      expect(bunnyLibraryIdForUpdate(selectedLibraryId: null), isNull);
    });

    test('the stored association is preserved on edit', () {
      expect(
        bunnyLibraryIdForUpdate(selectedLibraryId: '736742'),
        '736742',
      );
    });

    test('malformed stored metadata degrades to "keep"', () {
      expect(bunnyLibraryIdForUpdate(selectedLibraryId: ''), isNull);
      expect(bunnyLibraryIdForUpdate(selectedLibraryId: 'abc'), isNull);
    });
  });

  group('validateBunnyLibraryAssociation', () {
    test('a configured video association is valid', () {
      expect(
        validateBunnyLibraryAssociation(
          resourceType: 'video',
          libraryId: '736742',
        ),
        isNull,
      );
    });

    test('unknown library is rejected', () {
      expect(
        validateBunnyLibraryAssociation(
          resourceType: 'video',
          libraryId: '775315',
        ),
        contains('Unknown Bunny library'),
      );
    });

    test('a video without a library is rejected', () {
      expect(
        validateBunnyLibraryAssociation(resourceType: 'video'),
        contains('required'),
      );
    });

    test('non-video with a library is rejected', () {
      expect(
        validateBunnyLibraryAssociation(
          resourceType: 'pdf',
          libraryId: '736742',
        ),
        contains('Only video resources'),
      );
      expect(
        validateBunnyLibraryAssociation(resourceType: 'pdf'),
        isNull,
      );
    });
  });
}
