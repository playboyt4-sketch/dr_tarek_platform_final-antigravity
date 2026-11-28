import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drtarek_dashboard/core/di/firebase_providers.dart';
import 'package:drtarek_dashboard/features/students/presentation/providers/grade_students_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/providers/student_profile_activity_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/screens/student_profile_activity_tab.dart';

void main() {
  group('StudentProfileActivityTab & studentProfileActivityProvider', () {
    test('formats watch timestamps and Arabic total duration accurately', () {
      expect(formatWatchTimestamp(0), '00:00');
      expect(formatWatchTimestamp(1455), '24:15');
      expect(formatWatchTimestamp(3930), '1:05:30');
      expect(formatTotalWatchDurationAr(1500), '25 دقيقة');
      expect(formatTotalWatchDurationAr(5100), '1 س 25 د');
    });

    testWidgets(
      'displays video watch minute, full vs partial status, PDF page, and daily events',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final FakeFirebaseFirestore fake = FakeFirebaseFirestore();
        final DateTime now = DateTime.now();

        await fake.collection('subjects').doc('sub-1').set(<String, dynamic>{
          'title': 'المحاسبة المالية',
          'is_deleted': false,
        });

        await fake
            .collection('lecture_progress')
            .doc('stu-1_lec-1')
            .set(<String, dynamic>{
          'student_id': 'stu-1',
          'lecture_id': 'lec-1',
          'subject_id': 'sub-1',
          'lecture_title': 'المحاضرة الأولى',
          'position_seconds': 1455, // 24:15
          'duration_seconds': 3000, // 50:00
          'progress_percent': 48.5,
          'completed': false,
          'pdf_last_page': 12,
          'pdf_total_pages': 30,
          'updated_at': Timestamp.fromDate(now),
        });

        await fake
            .collection('lecture_progress')
            .doc('stu-1_lec-2')
            .set(<String, dynamic>{
          'student_id': 'stu-1',
          'lecture_id': 'lec-2',
          'subject_id': 'sub-1',
          'lecture_title': 'المحاضرة الثانية',
          'position_seconds': 1800, // 30:00
          'duration_seconds': 1800, // 30:00
          'progress_percent': 100,
          'completed': true,
          'updated_at': Timestamp.fromDate(now),
        });

        await fake.collection('analytics_events').add(<String, dynamic>{
          'user_id': 'stu-1',
          'event_type': 'Video Play',
          'reference_id': 'lec-1',
          'metadata': <String, dynamic>{
            'subject_id': 'sub-1',
            'lecture_title': 'المحاضرة الأولى',
          },
          'created_at': Timestamp.fromDate(now),
        });

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              firebaseFirestoreProvider.overrideWithValue(fake),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: StudentProfileActivityTab(
                    student: GradeStudent(
                      id: 'stu-1',
                      name: 'طالب تجريبي',
                      isCenter: true,
                      isActive: true,
                      lastSignIn: '28/11/2026',
                    ),
                    gradeKey: 'grade_three',
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('المحاضرة الأولى'), findsOneWidget);
        expect(find.text('المحاضرة الثانية'), findsOneWidget);
        expect(find.text('24:15 / 50:00 (49%)'), findsOneWidget);
        expect(find.text('30:00 / 30:00 (100%)'), findsOneWidget);
        expect(find.text('شاهد جزئياً'), findsOneWidget);
        expect(find.text('مكتمل ✓'), findsOneWidget);
        expect(find.text('ص 12 / 30'), findsOneWidget);
        expect(find.textContaining('تشغيل محاضرة فيديو'), findsOneWidget);
      },
    );
  });
}
