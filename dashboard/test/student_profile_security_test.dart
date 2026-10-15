import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drtarek_dashboard/features/students/presentation/providers/grade_students_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/providers/student_profile_security_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/screens/student_profile_overview_screen.dart';

const GradeStudent _student = GradeStudent(
  id: 'stu_001',
  name: 'ahmed mohamed gamal',
  isCenter: true,
  isActive: true,
  lastSignIn: '12/8/2026',
  phone: '01115800180',
);

SecurityEvent _event({
  required String id,
  required String type,
  required SecuritySeverity severity,
  required String severityLabel,
  DateTime? createdAt,
  String context = 'Device mismatch',
  String device = 'Samsung Galaxy S24 • Android',
  String action = 'Login blocked',
}) {
  return SecurityEvent(
    id: id,
    eventType: type,
    severity: severity,
    severityLabel: severityLabel,
    createdAt: createdAt,
    contextSummary: context,
    deviceSummary: device,
    actionTaken: action,
    screenshotDetected: false,
    screenRecordDetected: false,
  );
}

final List<SecurityEvent> _events = <SecurityEvent>[
  _event(
    id: 'ev_1',
    type: 'Unauthorized Device',
    severity: SecuritySeverity.high,
    severityLabel: 'high',
    createdAt: DateTime(2026, 9, 17, 18, 31),
  ),
  _event(
    id: 'ev_2',
    type: 'Screen Recording',
    severity: SecuritySeverity.medium,
    severityLabel: 'medium',
    createdAt: DateTime(2026, 9, 10, 9, 5),
    context: 'Screen recording detected during lecture playback',
    device: 'iPhone 17 Pro • iOS',
    action: 'Session flagged for review',
  ),
  _event(
    id: 'ev_3',
    type: 'Screenshot',
    severity: SecuritySeverity.low,
    severityLabel: 'low',
    createdAt: DateTime(2026, 8, 1, 12, 0),
    context: 'Screenshot attempt detected',
    device: 'Xiaomi Redmi Note 13 • Android',
    action: 'Warning issued',
  ),
];

const StudentSecuritySummary _summary = StudentSecuritySummary(
  accountStatus: 'active',
  passwordLastChangedAt: null,
);

Future<void> _pumpSecurity(
  WidgetTester tester, {
  List<SecurityEvent>? events,
  bool canReset = true,
  String initialNav = 'Security',
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        studentSecurityEventsProvider('stu_001')
            .overrideWith((ref) => Stream.value(events ?? _events)),
        studentSecuritySummaryProvider('stu_001')
            .overrideWith((ref) => Stream.value(_summary)),
        canResetStudentPasswordProvider
            .overrideWith((ref) => AsyncData<bool>(canReset)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: StudentProfileOverviewScreen(
            student: _student,
            gradeKey: 'grade_one',
            initialNav: initialNav,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('security severity parsing (backend values only)', () {
    test('parses known severities case-insensitively', () {
      expect(parseSecuritySeverity('low'), SecuritySeverity.low);
      expect(parseSecuritySeverity('Medium'), SecuritySeverity.medium);
      expect(parseSecuritySeverity('HIGH'), SecuritySeverity.high);
      expect(parseSecuritySeverity('Critical'), SecuritySeverity.critical);
    });

    test('unknown / missing values map to unknown, never invented', () {
      expect(parseSecuritySeverity(null), SecuritySeverity.unknown);
      expect(parseSecuritySeverity(''), SecuritySeverity.unknown);
      expect(parseSecuritySeverity('urgent'), SecuritySeverity.unknown);
    });
  });

  group('security event filtering (pure)', () {
    test('type filter matches backend event_type verbatim', () {
      final List<SecurityEvent> filtered = filterSecurityEvents(
        events: _events,
        eventType: 'Screenshot',
      );
      expect(filtered.map((e) => e.id), <String>['ev_3']);
    });

    test('severity filter isolates one level', () {
      final List<SecurityEvent> filtered = filterSecurityEvents(
        events: _events,
        severity: SecuritySeverity.medium,
      );
      expect(filtered.map((e) => e.id), <String>['ev_2']);
    });

    test('distinct types derive from data, never invented', () {
      expect(
        distinctSecurityEventTypes(_events),
        <String>['Screen Recording', 'Screenshot', 'Unauthorized Device'],
      );
      expect(distinctSecurityEventTypes(const <SecurityEvent>[]), isEmpty);
    });

    test('date formatting never invents values', () {
      expect(formatSecurityDateTime(null), '—');
      expect(
        formatSecurityDateTime(DateTime(2026, 9, 17, 18, 31)),
        '17 Sep 2026 • 6:31 PM',
      );
    });
  });

  group('Security tab (Figma 58136:841)', () {
    testWidgets('renders subtitle, status card and password card',
        (WidgetTester tester) async {
      await _pumpSecurity(tester);

      expect(
        find.text('Student account security & access control'),
        findsOneWidget,
      );
      expect(find.text('Security Status'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      // V1: no backend score exists — honest empty state, never 92/100.
      expect(find.text('Not available'), findsOneWidget);
      expect(find.text('92/100'), findsNothing);
      // Account status + last event come from providers.
      expect(find.text('active'), findsOneWidget);
      expect(find.textContaining('Unauthorized Device'), findsWidgets);
      expect(find.text('Security Event Log'), findsOneWidget);
      expect(find.text('Change Password'), findsOneWidget);
      // No Device tab duplication.
      expect(find.text('Device Details'), findsNothing);
      expect(find.text('Reset All Authorizations'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Security pill navigates from Overview',
        (WidgetTester tester) async {
      await _pumpSecurity(tester, initialNav: 'Overview');

      expect(find.text('Security Status'), findsNothing);
      await tester.tap(find.text('Security'));
      await tester.pumpAndSettle();

      expect(find.text('Security Status'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('event log overlay lists cards with no View button',
        (WidgetTester tester) async {
      await _pumpSecurity(tester);

      await tester.tap(find.text('Security Event Log'));
      await tester.pumpAndSettle();

      expect(find.text('Security Event Log'), findsWidgets);
      expect(
        find.text('Security events recorded for this student'),
        findsOneWidget,
      );
      // Full card contents render directly.
      expect(find.text('Screen Recording'), findsOneWidget);
      expect(find.text('Screenshot'), findsOneWidget);
      expect(find.text('Login blocked'), findsOneWidget);
      // Spec: there is NO View button — cards render everything directly.
      expect(find.text('View'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty events render empty states, never fake events',
        (WidgetTester tester) async {
      await _pumpSecurity(tester, events: const <SecurityEvent>[]);

      expect(
        find.text('No security events recorded.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Security Event Log'));
      await tester.pumpAndSettle();
      expect(
        find.text('No security events match these filters.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('change password overlay shows temp workflow (Teacher)',
        (WidgetTester tester) async {
      await _pumpSecurity(tester, canReset: true);

      await tester.tap(find.text('Change Password'));
      await tester.pumpAndSettle();

      expect(find.text('Change Password'), findsWidgets);
      expect(find.text('Enter Temporary Password'), findsOneWidget);
      expect(find.text('Re-Enter Temporary Password'), findsOneWidget);
      expect(
        find.text(
          'The student will be required to change this password on the next login (minimum 6 characters)',
        ),
        findsOneWidget,
      );
      expect(find.text('Save'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Admin sees restricted state, no reset capability claimed',
        (WidgetTester tester) async {
      await _pumpSecurity(tester, canReset: false);

      // Restricted note on the card; button present but disabled.
      expect(
        find.text(
          'Password reset is available to the Teacher (Platform Owner) and to Admins granted password-reset permission.',
        ),
        findsOneWidget,
      );
      final Finder button = find.widgetWithText(ElevatedButton, 'Change Password');
      expect(button, findsOneWidget);
      expect(
        tester.widget<ElevatedButton>(button).onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
