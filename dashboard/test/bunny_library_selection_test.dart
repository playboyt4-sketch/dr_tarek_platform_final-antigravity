// ADR-010 — nonvisual picker scaffolding (catalog + selection state).
//
// Proves the state model the future Figma selector will bind to: catalog
// availability/selectability, legacy rows, invalid selections, Video ID change
// review, edit preservation, quick-upload defaults and serialization.
import 'package:drtarek_dashboard/features/students/domain/bunny_library_association.dart';
import 'package:drtarek_dashboard/features/students/domain/bunny_library_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

const String _guidA = '7ddd0e6e-1111-4111-8111-111111111111';
const String _guidB = '94710db9-2222-4222-8222-222222222222';

void main() {
  group('catalog', () {
    test('default library is available and selectable', () {
      final BunnyLibraryOption? option =
          findBunnyLibraryOption(defaultBunnyLibraryId);
      expect(option, isNotNull);
      expect(option!.isAvailable, isTrue);
      expect(option.isSelectable, isTrue);
    });

    test('second library is known but not selectable (Figma + activation pending)', () {
      final BunnyLibraryOption? option = findBunnyLibraryOption('775315');
      expect(option, isNotNull);
      expect(option!.isAvailable, isTrue);
      expect(option.isSelectable, isFalse);
    });

    test('catalog exposes no secrets', () {
      for (final BunnyLibraryOption option in defaultBunnyLibraryCatalog) {
        final Map<String, Object?> json = option.toJson();
        expect(json.keys.toSet(), <String>{
          'id',
          'displayName',
          'isAvailable',
          'isSelectable',
        });
      }
    });

    test('unknown and blank ids are not found', () {
      expect(findBunnyLibraryOption('999999'), isNull);
      expect(findBunnyLibraryOption(null), isNull);
      expect(findBunnyLibraryOption('  '), isNull);
    });
  });

  group('selection validation', () {
    test('no selection is valid (legacy / default rule)', () {
      expect(validateLibrarySelection(libraryId: null), isNull);
      expect(validateLibrarySelection(libraryId: ' '), isNull);
    });

    test('selectable library passes', () {
      expect(
        validateLibrarySelection(libraryId: defaultBunnyLibraryId),
        isNull,
      );
    });

    test('not-yet-selectable library is rejected', () {
      expect(
        validateLibrarySelection(libraryId: '775315'),
        contains('cannot be selected yet'),
      );
    });

    test('unknown library is rejected', () {
      expect(
        validateLibrarySelection(libraryId: '123456'),
        contains('Unknown Bunny library'),
      );
    });

    test('custom catalog availability is honoured', () {
      const List<BunnyLibraryOption> catalog = <BunnyLibraryOption>[
        BunnyLibraryOption(
          id: '424242',
          displayName: 'Offline',
          isAvailable: false,
        ),
      ];
      expect(
        validateLibrarySelection(libraryId: '424242', catalog: catalog),
        contains('not available'),
      );
    });
  });

  group('selection state', () {
    test('new video starts with no explicit choice and no stored value', () {
      final BunnyLibrarySelection selection =
          BunnyLibrarySelection.forNewVideo(videoId: _guidA);
      expect(selection.isLegacy, isTrue);
      expect(selection.libraryIdForWrite, isNull);
      expect(selection.requiresReview, isFalse);
    });

    test('existing legacy resource reports legacy and keeps the video id', () {
      final BunnyLibrarySelection selection = BunnyLibrarySelection.forExisting(
        videoId: _guidA,
      );
      expect(selection.isLegacy, isTrue);
      expect(selection.libraryIdForWrite, isNull);
      expect(selection.toResourceFields(), <String, String?>{
        'bunny_video_id': _guidA,
        'bunny_library_id': null,
      });
    });

    test('existing resource echoes its stored association', () {
      final BunnyLibrarySelection selection = BunnyLibrarySelection.forExisting(
        videoId: _guidA,
        storedLibraryId: defaultBunnyLibraryId,
      );
      expect(selection.isLegacy, isFalse);
      expect(selection.libraryIdForWrite, defaultBunnyLibraryId);
    });

    test('a valid explicit choice becomes the write value', () {
      final BunnyLibrarySelection selection =
          BunnyLibrarySelection.forNewVideo(videoId: _guidA)
              .selectLibrary(defaultBunnyLibraryId);
      expect(selection.isValid, isTrue);
      expect(selection.libraryIdForWrite, defaultBunnyLibraryId);
    });

    test('an invalid choice keeps the error and never becomes the write value', () {
      final BunnyLibrarySelection selection =
          BunnyLibrarySelection.forExisting(
        videoId: _guidA,
        storedLibraryId: defaultBunnyLibraryId,
      ).selectLibrary('775315');
      expect(selection.isValid, isFalse);
      expect(selection.validationError, contains('cannot be selected yet'));
      // Falls back to the stored value rather than persisting an invalid one.
      expect(selection.libraryIdForWrite, defaultBunnyLibraryId);
    });

    test('editing unrelated fields preserves the stored association', () {
      final BunnyLibrarySelection selection = BunnyLibrarySelection.forExisting(
        videoId: _guidA,
        storedLibraryId: defaultBunnyLibraryId,
      );
      expect(selection.selectLibrary(null).libraryIdForWrite,
          defaultBunnyLibraryId);
      expect(selection.resetSelection().libraryIdForWrite,
          defaultBunnyLibraryId);
    });

    test('changing the Video ID flags the association for review', () {
      final BunnyLibrarySelection selection = BunnyLibrarySelection.forExisting(
        videoId: _guidA,
        storedLibraryId: defaultBunnyLibraryId,
      ).withVideoId(_guidB);
      expect(selection.requiresReview, isTrue);
      // Still the stored value: nothing is silently re-associated.
      expect(selection.libraryIdForWrite, defaultBunnyLibraryId);
    });

    test('same Video ID does not flag review', () {
      final BunnyLibrarySelection selection = BunnyLibrarySelection.forExisting(
        videoId: _guidA,
        storedLibraryId: defaultBunnyLibraryId,
      ).withVideoId('  $_guidA  ');
      expect(selection.requiresReview, isFalse);
    });

    test('an explicit choice clears the review flag', () {
      final BunnyLibrarySelection selection = BunnyLibrarySelection.forExisting(
        videoId: _guidA,
        storedLibraryId: defaultBunnyLibraryId,
      ).withVideoId(_guidB).selectLibrary(defaultBunnyLibraryId);
      expect(selection.requiresReview, isFalse);
      expect(selection.isValid, isTrue);
      expect(selection.libraryIdForWrite, defaultBunnyLibraryId);
    });

    test('quick upload (new video, no choice) leaves library defaulting to the writer', () {
      final BunnyLibrarySelection selection =
          BunnyLibrarySelection.forNewVideo();
      expect(selection.libraryIdForWrite, isNull);
      expect(
        bunnyLibraryIdForCreate(
          resourceType: 'video',
          selectedLibraryId: selection.libraryIdForWrite,
        ),
        defaultBunnyLibraryId,
      );
    });

    test('malformed ids are normalized away instead of serialized', () {
      final BunnyLibrarySelection selection = BunnyLibrarySelection.forExisting(
        videoId: '   ',
        storedLibraryId: 'library-a',
      );
      expect(selection.libraryIdForWrite, isNull);
      expect(selection.toResourceFields(), <String, String?>{
        'bunny_video_id': null,
        'bunny_library_id': null,
      });
    });
  });
}
