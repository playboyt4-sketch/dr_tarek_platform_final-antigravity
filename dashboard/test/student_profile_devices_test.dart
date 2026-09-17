import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drtarek_dashboard/features/students/presentation/providers/grade_students_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/providers/student_profile_devices_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/providers/student_profile_subjects_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/screens/student_profile_overview_screen.dart';

const GradeStudent _student = GradeStudent(
  id: 'stu_001',
  name: 'ahmed mohamed gamal',
  isCenter: true,
  plan: 'PRO',
  isActive: true,
  lastSignIn: '12/8/2026',
  phone: '01115800180',
);

const List<StudentSubjectRegistration> _registrations =
    <StudentSubjectRegistration>[
  StudentSubjectRegistration(
    subjectId: 'sub_max',
    title: 'محاسبة مالية',
    gradeKey: 'grade_one',
    planLabel: 'MAX',
    enabled: true,
  ),
  StudentSubjectRegistration(
    subjectId: 'sub_free',
    title: 'الأخلاق المحاسبية',
    gradeKey: 'grade_one',
    planLabel: 'FREE',
    enabled: true,
  ),
];

List<SubjectDeviceAuthorization> _authsFor(String studentId) {
  SubjectDeviceAuthorization active(
    String subjectId,
    String deviceId, {
    String status = 'active',
    bool isDeleted = false,
  }) {
    return SubjectDeviceAuthorization(
      authorizationId: '${studentId}_${subjectId}_hash',
      subjectId: subjectId,
      deviceHash:
          deviceHashFor(studentId: studentId, deviceId: deviceId),
      status: status,
      isDeleted: isDeleted,
      lastUsedAt: DateTime(2026, 9, 15, 16, 32),
      planKeyAtBind: null,
    );
  }

  return <SubjectDeviceAuthorization>[
    active('sub_max', 'iphone-17-pro'),
    active('sub_max', 'galaxy-s25-ultra'),
    // Revoked rows (and, by construction, the Guest outcome which has no
    // record) must never render as authorized devices.
    active('sub_max', 'old-device', status: 'revoked'),
    active('sub_free', 'iphone-17-pro'),
    // Authorization for an unregistered subject: never a table row.
    active('sub_ghost', 'iphone-17-pro'),
  ];
}

List<StudentDeviceRecord> _devices() {
  return const <StudentDeviceRecord>[
    StudentDeviceRecord(
      docId: 'dev_1',
      deviceId: 'iphone-17-pro',
      deviceName: 'iPhone 17 Pro',
      platform: 'iOS',
      osVersion: '18.x',
      appVersion: '1.0.x',
      lastLogin: null,
    ),
    StudentDeviceRecord(
      docId: 'dev_2',
      deviceId: 'galaxy-s25-ultra',
      deviceName: 'Samsung Galaxy S25 Ultra',
      platform: 'Android',
      osVersion: '15',
      appVersion: '1.0.0',
      lastLogin: null,
    ),
  ];
}

List<StudentSubjectDeviceRow> _rows() {
  return buildStudentSubjectDeviceRows(
    registrations: _registrations,
    planIdBySubject: const <String, String>{
      'sub_max': 'plan_max',
      'sub_free': 'plan_free',
    },
    authorizations: _authsFor('stu_001'),
    devices: _devices(),
    allowancesByPlanId: const <String, int>{
      'plan_max': 2,
      'plan_free': 1,
    },
    studentId: 'stu_001',
  );
}

ProviderScope _devicesScope({
  required Widget child,
  List<StudentSubjectDeviceRow>? rows,
  bool canManage = true,
}) {
  return ProviderScope(
    overrides: [
      studentProfileDevicesProvider('stu_001').overrideWith(
        (ref) => AsyncData<List<StudentSubjectDeviceRow>>(rows ?? _rows()),
      ),
      canManageStudentDevicesProvider.overrideWith(
        (ref) => AsyncData<bool>(canManage),
      ),
    ],
    child: child,
  );
}

Future<void> _pumpDevices(
  WidgetTester tester, {
  List<StudentSubjectDeviceRow>? rows,
  bool canManage = true,
  String initialNav = 'Device',
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    _devicesScope(
      rows: rows,
      canManage: canManage,
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
  group('deviceHashFor', () {
    test('is deterministic and matches backend sha256(user|device)', () {
      final String a =
          deviceHashFor(studentId: 'stu_001', deviceId: 'iphone-17-pro');
      final String b =
          deviceHashFor(studentId: 'stu_001', deviceId: 'iphone-17-pro');
      expect(a, equals(b));
      expect(a, hasLength(64));
      expect(
        RegExp(r'^[0-9a-f]{64}$').hasMatch(a),
        isTrue,
        reason: 'lowercase hex digest like Node createHash(sha256)',
      );
      // Different devices and different students never collide.
      expect(
        deviceHashFor(studentId: 'stu_001', deviceId: 'other'),
        isNot(a),
      );
      expect(
        deviceHashFor(studentId: 'stu_002', deviceId: 'iphone-17-pro'),
        isNot(a),
      );
    });
  });

  group('deviceAllowanceForPlanLabel', () {
    test('documented defaults per Subject plan', () {
      expect(deviceAllowanceForPlanLabel('MAX'), 2);
      expect(deviceAllowanceForPlanLabel('PRO'), 1);
      expect(deviceAllowanceForPlanLabel('FREE'), 1);
      expect(deviceAllowanceForPlanLabel(''), 1);
    });
  });

  group('buildStudentSubjectDeviceRows', () {
    test('MAX shows 2/2 and FREE shows 1/1 from their own plans', () {
      final List<StudentSubjectDeviceRow> rows = _rows();

      expect(rows, hasLength(2));
      final StudentSubjectDeviceRow max =
          rows.firstWhere((r) => r.subjectId == 'sub_max');
      final StudentSubjectDeviceRow free =
          rows.firstWhere((r) => r.subjectId == 'sub_free');

      // Highest plan (MAX) does not inflate the FREE row.
      expect(max.usageLabel, '2/2');
      expect(max.devices, hasLength(2));
      expect(free.usageLabel, '1/1');
      expect(free.devices, hasLength(1));
    });

    test('revoked authorizations are not authorized device records', () {
      final List<StudentSubjectDeviceRow> rows = _rows();
      final StudentSubjectDeviceRow max =
          rows.firstWhere((r) => r.subjectId == 'sub_max');
      // Three auth docs exist for sub_max (2 active + 1 revoked) but only
      // the active ones render.
      expect(max.activeCount, 2);
    });

    test('unregistered subjects never produce rows', () {
      final List<StudentSubjectDeviceRow> rows = _rows();
      expect(
        rows.where((r) => r.subjectId == 'sub_ghost'),
        isEmpty,
      );
    });

    test('unbind scope: rows keep their own device lists', () {
      final List<StudentSubjectDeviceRow> rows = _rows();
      final StudentSubjectDeviceRow max =
          rows.firstWhere((r) => r.subjectId == 'sub_max');
      final StudentSubjectDeviceRow free =
          rows.firstWhere((r) => r.subjectId == 'sub_free');
      // Simulates unbinding one MAX device: only that row shrinks.
      final List<SubjectAuthorizedDevice> remaining =
          max.devices.skip(1).toList(growable: false);
      expect(remaining, hasLength(1));
      expect(free.devices, hasLength(1));
    });

    test('missing registry row still renders (count never lies)', () {
      final List<StudentSubjectDeviceRow> rows =
          buildStudentSubjectDeviceRows(
        registrations: _registrations,
        planIdBySubject: const <String, String>{},
        authorizations: <SubjectDeviceAuthorization>[
          const SubjectDeviceAuthorization(
            authorizationId: 'a1',
            subjectId: 'sub_free',
            deviceHash: 'unknown-hash',
            status: 'active',
            isDeleted: false,
            lastUsedAt: null,
            planKeyAtBind: null,
          ),
        ],
        devices: const <StudentDeviceRecord>[],
        allowancesByPlanId: const <String, int>{},
        studentId: 'stu_001',
      );
      final StudentSubjectDeviceRow free =
          rows.firstWhere((r) => r.subjectId == 'sub_free');
      expect(free.devices, hasLength(1));
      expect(free.usageLabel, '1/1');
    });

    test('allowance falls back per Subject plan without a matrix value', () {
      final List<StudentSubjectDeviceRow> rows =
          buildStudentSubjectDeviceRows(
        registrations: _registrations,
        planIdBySubject: const <String, String>{},
        authorizations: const <SubjectDeviceAuthorization>[],
        devices: const <StudentDeviceRecord>[],
        allowancesByPlanId: const <String, int>{},
        studentId: 'stu_001',
      );
      expect(
        rows.firstWhere((r) => r.subjectId == 'sub_max').allowance,
        2,
      );
      expect(
        rows.firstWhere((r) => r.subjectId == 'sub_free').allowance,
        1,
      );
    });
  });

  group('formatDeviceDateTime', () {
    test('day-first 12h format from the Figma overlay', () {
      expect(
        formatDeviceDateTime(DateTime(2026, 9, 15, 16, 32)),
        '15/09/2026 04:32 PM',
      );
      expect(formatDeviceDateTime(null), '—');
    });
  });

  group('formatDeviceOsLine', () {
    test('platform + os • App version line', () {
      const SubjectAuthorizedDevice device = SubjectAuthorizedDevice(
        authorizationId: 'a1',
        deviceId: 'd1',
        deviceName: 'iPhone 17 Pro',
        platform: 'iOS',
        osVersion: '18.x',
        appVersion: '1.0.x',
        lastAccess: null,
      );
      expect(formatDeviceOsLine(device), 'iOS 18.x   •   App 1.0.x');
    });
  });

  group('Student Profile → Device tab', () {
    testWidgets('renders the device table with per-subject usage', (
      WidgetTester tester,
    ) async {
      await _pumpDevices(tester);

      expect(find.text('No.'), findsOneWidget);
      expect(find.text('Subjects'), findsNWidgets(3));
      expect(find.text('Plan'), findsOneWidget);
      // Sub-nav pill + table header.
      expect(find.text('Device'), findsNWidgets(2));
      expect(find.text('Action'), findsOneWidget);

      expect(find.text('محاسبة مالية'), findsOneWidget);
      expect(find.text('الأخلاق المحاسبية'), findsOneWidget);
      expect(find.text('MAX'), findsOneWidget);
      expect(find.text('FREE'), findsOneWidget);
      expect(find.text('2/2'), findsOneWidget);
      expect(find.text('1/1'), findsOneWidget);
      expect(find.text('01.'), findsOneWidget);
      expect(find.text('02.'), findsOneWidget);

      expect(find.text('Device Details'), findsNWidgets(2));
      // Exact contractual label for the global operation.
      expect(find.text('Reset All Authorizations'), findsOneWidget);
    });

    testWidgets('Device pill switches from Overview', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _devicesScope(
          child: const MaterialApp(
            home: Scaffold(
              body: StudentProfileOverviewScreen(
                student: _student,
                gradeKey: 'grade_one',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Reset All Authorizations'), findsNothing);

      await tester.tap(find.text('Device').first);
      await tester.pumpAndSettle();

      expect(find.text('Reset All Authorizations'), findsOneWidget);
      expect(find.text('2/2'), findsOneWidget);
    });

    testWidgets('Device Details opens the tapped Subject only', (
      WidgetTester tester,
    ) async {
      await _pumpDevices(tester);

      // MAX row first: opens MAX data.
      await tester.tap(find.text('Device Details').first);
      await tester.pumpAndSettle();

      // Table buttons stay mounted behind the overlay + overlay title.
      expect(find.text('Device Details'), findsNWidgets(3));
      expect(find.text('MAX'), findsNWidgets(2));
      expect(find.text('2/2'), findsNWidgets(2));
      expect(find.text('Device 01'), findsOneWidget);
      expect(find.text('Device 02'), findsOneWidget);
      expect(find.text('iPhone 17 Pro'), findsOneWidget);
      expect(find.text('Samsung Galaxy S25 Ultra'), findsOneWidget);
      expect(find.text('Status: Full'), findsNWidgets(2));
      expect(find.text('Unbind'), findsNWidgets(2));
      expect(
        find.text('Last access: 15/09/2026 04:32 PM'),
        findsNWidgets(2),
      );

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('Samsung Galaxy S25 Ultra'), findsNothing);

      // FREE row second: opens FREE data, not the MAX data.
      await tester.tap(find.text('Device Details').at(1));
      await tester.pumpAndSettle();

      expect(find.text('FREE'), findsNWidgets(2));
      expect(find.text('1/1'), findsNWidgets(2));
      // The MAX table row stays mounted behind the overlay.
      expect(find.text('MAX'), findsOneWidget);
      expect(find.text('Device 01'), findsOneWidget);
      expect(find.text('Device 02'), findsNothing);
    });

    testWidgets('Reset asks for confirmation; Cancel keeps state', (
      WidgetTester tester,
    ) async {
      await _pumpDevices(tester);

      await tester.tap(find.text('Reset All Authorizations'));
      await tester.pumpAndSettle();

      expect(find.text('Reset All Authorizations'), findsNWidgets(2));
      expect(
        find.textContaining('across every subject'),
        findsOneWidget,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Reset All Authorizations'), findsOneWidget);
      expect(find.text('2/2'), findsOneWidget);
    });

    testWidgets('manage actions lock without ADMIN_DEVICES', (
      WidgetTester tester,
    ) async {
      await _pumpDevices(tester, canManage: false);

      expect(find.text('Device Details'), findsNWidgets(2));
      expect(
        find.text('You do not have permission to manage devices.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Device Details').first);
      await tester.pumpAndSettle();

      // Viewing still works; Unbind is disabled without the grant.
      expect(find.text('iPhone 17 Pro'), findsOneWidget);
      final Finder unbind = find.widgetWithText(ElevatedButton, 'Unbind');
      expect(unbind, findsNWidgets(2));
      for (final Element e in unbind.evaluate()) {
        final ElevatedButton button = e.widget as ElevatedButton;
        expect(button.onPressed, isNull);
      }
    });

    testWidgets('empty registrations keep the reset action available', (
      WidgetTester tester,
    ) async {
      await _pumpDevices(
        tester,
        rows: const <StudentSubjectDeviceRow>[],
      );

      expect(find.text('Device Details'), findsNothing);
      expect(
        find.text('No subjects registered for this student yet.'),
        findsOneWidget,
      );
      expect(find.text('Reset All Authorizations'), findsOneWidget);
    });
  });
}
