import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drtarek_dashboard/features/students/presentation/providers/subject_details_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/screens/subject_details_screen.dart';
import 'package:drtarek_dashboard/features/students/presentation/widgets/edit_subject_overlay.dart';

/// Subject Details content-tab mapping.
///
/// Locks the canonical product-category routing (05 Database §9 Subject
/// Sections + §"Section Type": system `explanation` / `revision` /
/// `final_review`; Online Sessions is a normal custom section with a
/// `null` key distinguished by title). Persisted legacy Online sections
/// (`section_key == 'online'`, written by earlier dashboard builds) are
/// honored read-only — never renamed — while new Online sections use the
/// canonical custom representation.
///
/// Online is a recorded-lesson lecture like any other: no meeting,
/// Google Meet, live class, or virtual classroom exists in V1.
SubjectSection _section({
  required String id,
  required String? key,
  required String title,
  int order = 0,
}) {
  final bool isSystem =
      key == 'explanation' || key == 'revision' || key == 'final_review';
  return SubjectSection(
    id: id,
    sectionKey: key,
    isSystemSection: isSystem,
    title: title,
    displayOrder: order,
  );
}

void main() {
  group('sectionVisibleInTab', () {
    test('Lectures tab shows explanation sections only', () {
      expect(
          sectionVisibleInTab(
              _section(id: 's', key: 'explanation', title: 'Lectures'),
              SubjectContentTab.lectures),
          isTrue);
      for (final SubjectSection other in <SubjectSection>[
        _section(id: 's', key: 'revision', title: 'Revisions'),
        _section(id: 's', key: 'final', title: 'Final'),
        _section(id: 's', key: 'final_review', title: 'Final'),
        _section(id: 's', key: 'online', title: 'Online'),
        _section(id: 's', key: 'center', title: 'Center'),
        _section(id: 's', key: null, title: 'Online Sessions'),
        _section(id: 's', key: null, title: 'Bonus Lectures'),
      ]) {
        expect(
          sectionVisibleInTab(other, SubjectContentTab.lectures),
          isFalse,
          reason: 'key=${other.sectionKey} title=${other.title}',
        );
      }
    });

    test('Revisions tab shows revision sections only', () {
      expect(
          sectionVisibleInTab(
              _section(id: 's', key: 'revision', title: 'Revisions'),
              SubjectContentTab.revisions),
          isTrue);
      expect(
          sectionVisibleInTab(
              _section(id: 's', key: 'explanation', title: 'Lectures'),
              SubjectContentTab.revisions),
          isFalse);
      expect(
          sectionVisibleInTab(
              _section(id: 's', key: 'final', title: 'Final'),
              SubjectContentTab.revisions),
          isFalse);
      expect(
          sectionVisibleInTab(
              _section(id: 's', key: 'final_review', title: 'Final'),
              SubjectContentTab.revisions),
          isFalse);
      expect(
          sectionVisibleInTab(
              _section(id: 's', key: 'online', title: 'Online'),
              SubjectContentTab.revisions),
          isFalse);
      expect(
          sectionVisibleInTab(
              _section(id: 's', key: null, title: 'Online Sessions'),
              SubjectContentTab.revisions),
          isFalse);
    });

    test('Final tab shows final_review sections only', () {
      expect(
          sectionVisibleInTab(
              _section(id: 's', key: 'final_review', title: 'Final'),
              SubjectContentTab.finalTab),
          isTrue);
      expect(
          sectionVisibleInTab(
              _section(id: 's', key: 'final', title: 'Final'),
              SubjectContentTab.finalTab),
          isFalse);
      expect(
          sectionVisibleInTab(
              _section(id: 's', key: 'revision', title: 'Revisions'),
              SubjectContentTab.finalTab),
          isFalse);
      expect(
          sectionVisibleInTab(
              _section(id: 's', key: 'explanation', title: 'Lectures'),
              SubjectContentTab.finalTab),
          isFalse);
      expect(
          sectionVisibleInTab(
              _section(id: 's', key: null, title: 'Online Sessions'),
              SubjectContentTab.finalTab),
          isFalse);
    });

    test('Online tab shows Online custom sections only', () {
      // Canonical custom representation (null key + Online title).
      expect(
          sectionVisibleInTab(
              _section(id: 's', key: null, title: 'Online Sessions'),
              SubjectContentTab.online),
          isTrue);
      // Legacy persisted representation (never renamed, read-only).
      expect(
          sectionVisibleInTab(
              _section(id: 's', key: 'online', title: 'أونلاين'),
              SubjectContentTab.online),
          isTrue);
      // System sections never appear under Online.
      for (final SubjectSection system in <SubjectSection>[
        _section(id: 's', key: 'explanation', title: 'Lectures'),
        _section(id: 's', key: 'revision', title: 'Revisions'),
        _section(id: 's', key: 'final_review', title: 'Final'),
      ]) {
        expect(
          sectionVisibleInTab(system, SubjectContentTab.online),
          isFalse,
          reason: 'key=${system.sectionKey}',
        );
      }
      // Other custom sections and legacy non-online keys stay excluded.
      for (final SubjectSection other in <SubjectSection>[
        _section(id: 's', key: null, title: 'Bonus Lectures'),
        _section(id: 's', key: null, title: 'Important Announcements'),
        _section(id: 's', key: 'center', title: 'Center'),
        _section(id: 's', key: 'final', title: 'Final'),
      ]) {
        expect(
          sectionVisibleInTab(other, SubjectContentTab.online),
          isFalse,
          reason: 'key=${other.sectionKey} title=${other.title}',
        );
      }
    });
  });

  group('isOnlineSection / findOnlineSection', () {
    test('legacy online key is honored without renaming', () {
      final SubjectSection legacy =
          _section(id: 'legacy-1', key: 'online', title: 'أونلاين');
      expect(isOnlineSection(legacy), isTrue);
      expect(legacy.sectionKey, 'online');
    });

    test('canonical custom online section matches by title', () {
      expect(
          isOnlineSection(
              _section(id: 'c', key: null, title: 'Online Sessions')),
          isTrue);
      expect(
          isOnlineSection(_section(id: 'c', key: null, title: 'Online')),
          isTrue);
    });

    test('non-online custom sections do not match', () {
      expect(
          isOnlineSection(
              _section(id: 'c', key: null, title: 'Bonus Lectures')),
          isFalse);
      expect(
          isOnlineSection(
              _section(id: 'c', key: null, title: 'Exam Instructions')),
          isFalse);
    });

    test('findOnlineSection prefers the existing record by order', () {
      final SubjectSection first = _section(
          id: 'on-1', key: null, title: 'Online Sessions', order: 5);
      final SubjectSection second = _section(
          id: 'on-2', key: null, title: 'Online', order: 9);
      final List<SubjectSection> sections = <SubjectSection>[
        _section(id: 'ex', key: 'explanation', title: 'Lectures', order: 1),
        second,
        _section(id: 'rev', key: 'revision', title: 'Revisions', order: 2),
        first,
      ];
      expect(findOnlineSection(sections)?.id, 'on-1');
    });

    test('findOnlineSection returns null when no online section exists', () {
      expect(
          findOnlineSection(<SubjectSection>[
            _section(id: 'ex', key: 'explanation', title: 'Lectures'),
            _section(id: 'rev', key: 'revision', title: 'Revisions'),
          ]),
          isNull);
    });
  });

  group('contentNameLabel', () {
    test('middle-column header follows the active tab', () {
      expect(SubjectContentTab.lectures.contentNameLabel, 'Lecture Name');
      expect(
          SubjectContentTab.revisions.contentNameLabel, 'Revision Name');
      expect(SubjectContentTab.finalTab.contentNameLabel, 'Final Name');
      expect(SubjectContentTab.online.contentNameLabel, 'Online Name');
    });
  });

  group('emptyStateLabel', () {
    test('empty-state message follows the active tab', () {
      expect(SubjectContentTab.lectures.emptyStateLabel,
          'No lectures yet.');
      expect(SubjectContentTab.revisions.emptyStateLabel,
          'No revisions yet.');
      expect(SubjectContentTab.finalTab.emptyStateLabel,
          'No final yet.');
      expect(SubjectContentTab.online.emptyStateLabel,
          'No online sessions yet.');
    });
  });

  group('SubjectDetailsScreen header centering', () {
    Future<void> pumpWithTitle(WidgetTester tester, String title) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            subjectDetailsProvider('sub-1').overrideWith(
              (ref) => Stream.value(
                SubjectDetails(
                    id: 'sub-1', title: title, isVisible: true),
              ),
            ),
            for (final SubjectContentTab tab in SubjectContentTab.values)
              tabLecturesProvider((subjectId: 'sub-1', tab: tab))
                  .overrideWith((ref) => Stream.value(
                      const <SubjectLecture>[])),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SubjectDetailsScreen(
                gradeKey: 'grade_one',
                subjectId: 'sub-1',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// The toggle + title form ONE shrink-wrapped group centered as a unit
    /// inside the 540x88 card: the header Row (mainAxisSize.min) holds both
    /// the Switch and the title, and the combined Row's center matches the
    /// card's center on both axes for any name, in any language, at any
    /// length. Centers are derived from the actual card and Row rects —
    /// no Row width is ever hardcoded.
    void expectGroupCentered(WidgetTester tester, String title) {
      final Finder textFinder = find.text(title);
      expect(textFinder, findsOneWidget);
      final Text widget = tester.widget<Text>(textFinder);
      expect(widget.textAlign, TextAlign.center);
      expect(widget.maxLines, 1);
      expect(widget.overflow, TextOverflow.ellipsis);

      // 1. The header card keeps its expected size.
      final Finder cardFinder = find.ancestor(
        of: textFinder,
        matching: find.byType(Container),
      );
      expect(cardFinder, findsOneWidget);
      final Rect card = tester.getRect(cardFinder);
      expect(card.size, const Size(540, 88));

      // 2-3. The header Row exists and shrink-wraps its children
      // (innermost Row ancestor of the title).
      final Finder rowFinder = find.ancestor(
        of: textFinder,
        matching: find.byType(Row),
      );
      expect(rowFinder, findsWidgets);
      final Row rowWidget = tester.widget<Row>(rowFinder.first);
      expect(rowWidget.mainAxisSize, MainAxisSize.min);

      // 5-6. Toggle and title live in the same Row/group.
      final Finder toggleFinder = find.descendant(
        of: rowFinder.first,
        matching: find.byType(Switch),
      );
      expect(toggleFinder, findsOneWidget);
      expect(
        find.descendant(of: rowFinder.first, matching: textFinder),
        findsOneWidget,
      );

      // 9. Toggle stays wired (value + callback).
      final Switch toggle = tester.widget<Switch>(toggleFinder);
      expect(toggle.value, isTrue);
      expect(toggle.onChanged, isNotNull);

      // 4+7. Combined group centered in the card on both axes.
      final Rect row = tester.getRect(rowFinder.first);
      expect(
        row.left + row.width / 2,
        moreOrLessEquals(card.left + card.width / 2),
      );
      expect(
        row.top + row.height / 2,
        moreOrLessEquals(card.top + card.height / 2),
      );
    }

    testWidgets('Arabic subject name is card-centered',
        (WidgetTester tester) async {
      await pumpWithTitle(tester, 'محاسبة مالية');
      expectGroupCentered(tester, 'محاسبة مالية');
    });

    testWidgets('long Arabic name keeps the same center',
        (WidgetTester tester) async {
      await pumpWithTitle(
          tester, 'محاسبة مالية متقدمة للفرقة الأولى بكل التفاصيل');
      expectGroupCentered(
          tester, 'محاسبة مالية متقدمة للفرقة الأولى بكل التفاصيل');
    });

    testWidgets('short English name keeps the same center',
        (WidgetTester tester) async {
      await pumpWithTitle(tester, 'Math');
      expectGroupCentered(tester, 'Math');
    });

    testWidgets('empty states follow the active tab', (
      WidgetTester tester,
    ) async {
      await pumpWithTitle(tester, 'محاسبة مالية');
      expect(find.text('No lectures yet.'), findsOneWidget);
      await tester.tap(find.text('Revisions'));
      await tester.pumpAndSettle();
      expect(find.text('No revisions yet.'), findsOneWidget);
      await tester.tap(find.text('Final'));
      await tester.pumpAndSettle();
      expect(find.text('No final yet.'), findsOneWidget);
      await tester.tap(find.text('Online'));
      await tester.pumpAndSettle();
      expect(find.text('No online sessions yet.'), findsOneWidget);
    });
  });

  group('EditSubjectOverlay', () {
    testWidgets('shows prefilled grade, name, and cover URL', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Placeholder())),
      );
      await tester.pumpAndSettle();
      EditSubjectOverlay.show(
        tester.element(find.byType(Scaffold)),
        gradeKey: 'grade_one',
        initialTitle: 'محاسبة مالية',
        initialCoverUrl: 'https://cdn.example.com/cover.png',
        gradeColor: const Color(0xFFF59E0B),
        onSave: ({
          required String gradeKey,
          required String title,
          required String coverUrl,
        }) async {},
      );
      await tester.pumpAndSettle();
      expect(find.text('Edit Subject'), findsOneWidget);
      final DropdownButton<String> dropdown =
          tester.widget(find.byType(DropdownButton<String>));
      expect(dropdown.value, 'grade_one');
      expect(
        tester
            .widget<TextField>(find.byType(TextField).at(0))
            .controller
            ?.text,
        'محاسبة مالية',
      );
      expect(
        tester
            .widget<TextField>(find.byType(TextField).at(1))
            .controller
            ?.text,
        'https://cdn.example.com/cover.png',
      );
    });

    testWidgets('save submits trimmed name and cover URL', (
      WidgetTester tester,
    ) async {
      final List<Map<String, String>> savedCalls = <Map<String, String>>[];
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Placeholder())),
      );
      await tester.pumpAndSettle();
      final Future<bool?> result = EditSubjectOverlay.show(
        tester.element(find.byType(Scaffold)),
        gradeKey: 'grade_one',
        initialTitle: 'محاسبة مالية',
        initialCoverUrl: '',
        gradeColor: const Color(0xFFF59E0B),
        onSave: ({
          required String gradeKey,
          required String title,
          required String coverUrl,
        }) async {
          savedCalls.add(
              {'gradeKey': gradeKey, 'title': title, 'coverUrl': coverUrl});
        },
      );
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byType(TextField).at(0), '  محاسبة متقدمة  ');
      await tester.enterText(find.byType(TextField).at(1),
          'https://cdn.example.com/new.png');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(await result, isTrue);
      expect(savedCalls, hasLength(1));
      expect(savedCalls.single['title'], 'محاسبة متقدمة');
      expect(savedCalls.single['coverUrl'],
          'https://cdn.example.com/new.png');
      expect(savedCalls.single['gradeKey'], 'grade_one');
      // Success closes the overlay.
      expect(find.text('Edit Subject'), findsNothing);
    });

    testWidgets('empty name is rejected and keeps overlay open', (
      WidgetTester tester,
    ) async {
      bool called = false;
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Placeholder())),
      );
      await tester.pumpAndSettle();
      EditSubjectOverlay.show(
        tester.element(find.byType(Scaffold)),
        gradeKey: 'grade_one',
        initialTitle: 'محاسبة مالية',
        initialCoverUrl: '',
        gradeColor: const Color(0xFFF59E0B),
        onSave: ({
          required String gradeKey,
          required String title,
          required String coverUrl,
        }) async {
          called = true;
        },
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '   ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(called, isFalse);
      expect(find.text('Enter the subject name.'), findsOneWidget);
      expect(find.text('Edit Subject'), findsOneWidget);
    });

    testWidgets('save failure keeps overlay open with error', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Placeholder())),
      );
      await tester.pumpAndSettle();
      EditSubjectOverlay.show(
        tester.element(find.byType(Scaffold)),
        gradeKey: 'grade_one',
        initialTitle: 'محاسبة مالية',
        initialCoverUrl: '',
        gradeColor: const Color(0xFFF59E0B),
        onSave: ({
          required String gradeKey,
          required String title,
          required String coverUrl,
        }) async {
          throw Exception('rules deny');
        },
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Could not save. Try again.'), findsOneWidget);
      expect(find.text('Edit Subject'), findsOneWidget);
    });
  });

  group('SubjectDetailsScreen Edit button', () {
    Future<void> pumpScreen(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            subjectDetailsProvider('sub-1').overrideWith(
              (ref) => Stream.value(
                const SubjectDetails(
                  id: 'sub-1',
                  title: 'محاسبة مالية',
                  isVisible: true,
                  coverUrl: 'https://cdn.example.com/cover.png',
                ),
              ),
            ),
            for (final SubjectContentTab tab in SubjectContentTab.values)
              tabLecturesProvider((subjectId: 'sub-1', tab: tab))
                  .overrideWith((ref) => Stream.value(
                      const <SubjectLecture>[])),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SubjectDetailsScreen(
                gradeKey: 'grade_one',
                subjectId: 'sub-1',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('Edit button opens the overlay with current data', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester);
      // Only the header action exists (table is empty).
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Edit Subject'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byType(TextField).at(0))
            .controller
            ?.text,
        'محاسبة مالية',
      );
      expect(
        tester
            .widget<TextField>(find.byType(TextField).at(1))
            .controller
            ?.text,
        'https://cdn.example.com/cover.png',
      );
    });
  });
}
