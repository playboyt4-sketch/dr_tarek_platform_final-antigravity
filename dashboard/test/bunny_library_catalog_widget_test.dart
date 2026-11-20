import 'package:drtarek_dashboard/features/home/presentation/widgets/quick_upload_modal.dart';
import 'package:drtarek_dashboard/features/students/domain/bunny_library_catalog.dart';
import 'package:drtarek_dashboard/features/students/domain/repositories/bunny_library_catalog_repository.dart';
import 'package:drtarek_dashboard/features/students/presentation/providers/bunny_library_catalog_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const String _guidA = '11111111-2222-3333-4444-555555555555';
const String _guidB = '99999999-8888-7777-6666-555555555555';

class _FakeCatalogRepository implements BunnyLibraryCatalogRepository {
  final BunnyDiscoveryResult discoveryResult;
  final List<BunnyLibraryOption> libraries;
  bool shouldFailCatalog;
  int catalogFetchCount = 0;

  _FakeCatalogRepository({
    this.discoveryResult = const BunnyDiscoveryResult(
      status: BunnyDiscoveryStatus.found,
      libraryId: '780700',
    ),
    List<BunnyLibraryOption>? customLibraries,
    this.shouldFailCatalog = false,
  }) : libraries = customLibraries ??
            const <BunnyLibraryOption>[
              BunnyLibraryOption(id: '780700', displayName: 'Staging Primary'),
              BunnyLibraryOption(id: '775315', displayName: 'Legacy Unsigned'),
            ];

  @override
  Future<BunnyDiscoveryResult> discoverVideoLibrary(String videoId) async {
    return discoveryResult;
  }

  @override
  Future<List<BunnyLibraryOption>> getEligibleLibraries() async {
    catalogFetchCount++;
    if (shouldFailCatalog) {
      throw Exception('Network error loading catalog');
    }
    return libraries;
  }
}

void main() {
  Widget buildTestableWidget({required _FakeCatalogRepository repository}) {
    return ProviderScope(
      overrides: [
        bunnyLibraryCatalogRepositoryProvider.overrideWithValue(repository),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: QuickUploadForm(),
          ),
        ),
      ),
    );
  }

  group('ADR-010 Batch 3b — Catalog & Auto-Discovery Widget Tests', () {
    testWidgets('Scenario 1: Successful auto-discovery shows verified badge',
        (WidgetTester tester) async {
      final repository = _FakeCatalogRepository(
        discoveryResult: const BunnyDiscoveryResult(
          status: BunnyDiscoveryStatus.found,
          libraryId: '780700',
        ),
      );

      await tester.pumpWidget(buildTestableWidget(repository: repository));
      await tester.pumpAndSettle();

      // Enter a valid Bunny GUID into Video ID field
      final bunnyField = find.widgetWithText(TextField, 'Bunny Video ID');
      expect(bunnyField, findsOneWidget);

      await tester.enterText(bunnyField, _guidA);
      await tester.pumpAndSettle();

      // Verified badge should be shown
      expect(
        find.text('تم التعرف على المكتبة تلقائياً: 780700'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets(
        'Scenario 2: Video not found triggers fallback dropdown with eligible libraries',
        (WidgetTester tester) async {
      final repository = _FakeCatalogRepository(
        discoveryResult: const BunnyDiscoveryResult(
          status: BunnyDiscoveryStatus.notFound,
        ),
      );

      await tester.pumpWidget(buildTestableWidget(repository: repository));
      await tester.pumpAndSettle();

      final bunnyField = find.widgetWithText(TextField, 'Bunny Video ID');
      await tester.enterText(bunnyField, _guidB);
      await tester.pumpAndSettle();

      // No auto-discovered badge
      expect(find.byIcon(Icons.check_circle), findsNothing);

      // Fallback dropdown should appear with eligible libraries
      final dropdown = find.byType(DropdownButtonFormField<String>);
      expect(dropdown, findsWidgets); // Grade, section, and library dropdowns

      expect(find.text('اختر مكتبة الفيديو'), findsOneWidget);
    });

    testWidgets('Scenario 3: Catalog error shows retry button and recovers',
        (WidgetTester tester) async {
      final repository = _FakeCatalogRepository(
        discoveryResult: const BunnyDiscoveryResult(
          status: BunnyDiscoveryStatus.notFound,
        ),
        shouldFailCatalog: true,
      );

      await tester.pumpWidget(buildTestableWidget(repository: repository));
      await tester.pumpAndSettle();

      final bunnyField = find.widgetWithText(TextField, 'Bunny Video ID');
      await tester.enterText(bunnyField, _guidB);
      await tester.pumpAndSettle();

      // Error message should be rendered
      expect(find.text('تعذر تحميل قائمة المكتبات.'), findsOneWidget);
      final retryBtn = find.text('إعادة المحاولة');
      expect(retryBtn, findsOneWidget);

      // Recover and tap retry
      repository.shouldFailCatalog = false;
      await tester.tap(retryBtn);
      await tester.pumpAndSettle();

      // Should now render dropdown
      expect(find.text('اختر مكتبة الفيديو'), findsOneWidget);
      expect(repository.catalogFetchCount, greaterThanOrEqualTo(2));
    });

    testWidgets('Scenario 4: Clearing or invalidating Video ID clears discovery state',
        (WidgetTester tester) async {
      final repository = _FakeCatalogRepository(
        discoveryResult: const BunnyDiscoveryResult(
          status: BunnyDiscoveryStatus.found,
          libraryId: '780700',
        ),
      );

      await tester.pumpWidget(buildTestableWidget(repository: repository));
      await tester.pumpAndSettle();

      final bunnyField = find.widgetWithText(TextField, 'Bunny Video ID');
      await tester.enterText(bunnyField, _guidA);
      await tester.pumpAndSettle();

      expect(find.text('تم التعرف على المكتبة تلقائياً: 780700'), findsOneWidget);

      // Invalidate text
      await tester.enterText(bunnyField, 'not-a-guid');
      await tester.pumpAndSettle();

      expect(find.text('تم التعرف على المكتبة تلقائياً: 780700'), findsNothing);
      expect(find.text('اختر مكتبة الفيديو'), findsNothing);
    });
  });
}
