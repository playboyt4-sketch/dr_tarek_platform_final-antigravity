import 'package:drtarek_dashboard/features/students/presentation/widgets/add_subject_overlay.dart';
import 'package:drtarek_dashboard/features/students/presentation/widgets/edit_subject_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'AddSubjectOverlay renders Upload Image button alongside Subject Cover URL field',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: AddSubjectOverlay(
              gradeKey: 'grade_one',
              gradeColor: Color(0xFF00C08B),
              nextDisplayOrder: 1,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Subject Cover URL'), findsOneWidget);
    expect(
      find.byKey(const Key('upload-subject-cover-button')),
      findsOneWidget,
    );
    expect(find.text('Upload Image'), findsOneWidget);
  });

  testWidgets(
      'EditSubjectOverlay keeps prefilled cover URL and renders Upload Image button',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: EditSubjectOverlay(
              gradeKey: 'grade_two',
              initialTitle: 'Physics',
              initialCoverUrl: 'https://example.com/poster.png',
              gradeColor: const Color(0xFF00C08B),
              onSave: ({
                required String gradeKey,
                required String title,
                required String coverUrl,
              }) async {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('https://example.com/poster.png'), findsOneWidget);
    expect(
      find.byKey(const Key('upload-subject-cover-button')),
      findsOneWidget,
    );
  });
}
