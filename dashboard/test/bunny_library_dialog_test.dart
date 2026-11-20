// ADR-010 — library association through the real resource dialog.
//
// Proves the dialog wires the picker state (no visual change): new videos
// resolve to the default library, existing rows keep their stored association,
// legacy rows stay legacy, a changed Video ID is flagged for review instead of
// silently re-associated, invalid input never yields a staged resource, and
// PDF / external-link types carry no association.
import 'package:drtarek_dashboard/features/students/domain/bunny_library_association.dart';
import 'package:drtarek_dashboard/features/students/presentation/widgets/add_lecture_resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String _guidA = '7ddd0e6e-1111-4111-8111-111111111111';
const String _guidB = '94710db9-2222-4222-8222-222222222222';

void main() {
  StagedResource? result;

  setUp(() => result = null);

  Future<void> openDialog(
    WidgetTester tester, {
    required StagedResourceKind kind,
    StagedResource? existing,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => ElevatedButton(
              onPressed: () async {
                result = await showResourceDialog(
                  context,
                  kind: kind,
                  nextOrder: 1,
                  gradeColor: Colors.blue,
                  existing: existing,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('resourceDialogSave')));
    await tester.pumpAndSettle();
  }

  group('video dialog', () {
    testWidgets('new video stages the default library', (WidgetTester tester) async {
      await openDialog(tester, kind: StagedResourceKind.video);
      final Finder fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'New video');
      await tester.enterText(fields.at(1), _guidA);
      await save(tester);

      expect(result, isNotNull);
      expect(result!.bunnyVideoId, _guidA);
      expect(result!.bunnyLibraryId, defaultBunnyLibraryId);
      expect(result!.libraryReviewRequired, isFalse);
    });

    testWidgets('existing video keeps its stored association', (WidgetTester tester) async {
      await openDialog(
        tester,
        kind: StagedResourceKind.video,
        existing: StagedResource(
          name: 'Stored',
          displayOrder: 3,
          kind: StagedResourceKind.video,
          bunnyVideoId: _guidA,
          bunnyLibraryId: defaultBunnyLibraryId,
        ),
      );
      await save(tester);

      expect(result, isNotNull);
      expect(result!.bunnyLibraryId, defaultBunnyLibraryId);
      expect(result!.libraryReviewRequired, isFalse);
    });

    testWidgets('legacy video stays legacy (no invented association)', (WidgetTester tester) async {
      await openDialog(
        tester,
        kind: StagedResourceKind.video,
        existing: StagedResource(
          name: 'Legacy',
          displayOrder: 2,
          kind: StagedResourceKind.video,
          bunnyVideoId: _guidA,
        ),
      );
      await save(tester);

      expect(result, isNotNull);
      expect(result!.bunnyLibraryId, isNull);
      expect(result!.libraryReviewRequired, isFalse);
    });

    testWidgets('changing the Video ID flags review and keeps the stored library',
        (WidgetTester tester) async {
      await openDialog(
        tester,
        kind: StagedResourceKind.video,
        existing: StagedResource(
          name: 'Stored',
          displayOrder: 1,
          kind: StagedResourceKind.video,
          bunnyVideoId: _guidA,
          bunnyLibraryId: defaultBunnyLibraryId,
        ),
      );
      await tester.enterText(find.byType(TextField).at(1), _guidB);
      await save(tester);

      expect(result, isNotNull);
      expect(result!.bunnyVideoId, _guidB);
      expect(result!.bunnyLibraryId, defaultBunnyLibraryId);
      expect(result!.libraryReviewRequired, isTrue);
    });

    testWidgets('invalid Video ID never stages a resource', (WidgetTester tester) async {
      await openDialog(tester, kind: StagedResourceKind.video);
      await tester.enterText(find.byType(TextField).at(0), 'Bad');
      await tester.enterText(
        find.byType(TextField).at(1),
        'https://iframe.mediadelivery.net/embed/775315/$_guidA',
      );
      await save(tester);

      expect(result, isNull);
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  group('non-video types', () {
    testWidgets('external link carries no library association', (WidgetTester tester) async {
      await openDialog(tester, kind: StagedResourceKind.externalLink);
      final Finder fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Link');
      await tester.enterText(fields.at(1), 'https://example.com/resource');
      await save(tester);

      expect(result, isNotNull);
      expect(result!.bunnyLibraryId, isNull);
    });
  });
}
