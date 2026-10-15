import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drtarek_dashboard/features/students/presentation/providers/grade_students_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/providers/student_profile_payments_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/providers/student_profile_subjects_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/providers/student_subject_pricing_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/screens/student_profile_overview_screen.dart';

const GradeStudent _student = GradeStudent(
  id: 'stu_001',
  name: 'ahmed mohamed gamal',
  isCenter: true,
  isActive: true,
  lastSignIn: '12/8/2026',
  phone: '01115800180',
);

const StudentFinancialAccount _finAccount = StudentFinancialAccount(
  studentId: 'stu_001',
  priceEgp: 500,
  discountEgp: 0,
  netEgp: 500,
);

StudentLedger _demoLedger() => StudentLedger(
      account: _finAccount,
      payments: <StudentPayment>[
        StudentPayment(
          id: 'pay_1',
          subjectId: '',
          date: DateTime(2026, 9, 9),
          amountEgp: 200,
          method: PaymentMethod.cash,
          collectedBy: 'Jo',
          receiptNumber: 'R-1',
          notes: null,
        ),
      ],
    );

const List<StudentSubjectRegistration> _demoRegs =
    <StudentSubjectRegistration>[
  StudentSubjectRegistration(
    subjectId: 'sub_acc',
    title: 'Financial Accounting',
    gradeKey: 'grade_one',
    planLabel: 'PRO',
    enabled: true,
  ),
  StudentSubjectRegistration(
    subjectId: 'sub_eth',
    title: 'Accounting Ethics',
    gradeKey: 'grade_one',
    planLabel: 'FREE',
    enabled: true,
  ),
  StudentSubjectRegistration(
    subjectId: 'sub_chem',
    title: 'Chemistry',
    gradeKey: 'grade_two',
    planLabel: '',
    enabled: true,
  ),
];

// Figma rows: Financial Accounting 500/50/450, Accounting Ethics
// 100/50/50; Chemistry stays unpriced (renders `—`, never invented 0).
const List<StudentPricedSubject> _demoPriced = <StudentPricedSubject>[
  StudentPricedSubject(
    subjectId: 'sub_acc',
    title: 'Financial Accounting',
    gradeKey: 'grade_one',
    enabled: true,
    pricing: StudentSubjectPricing(
      subjectId: 'sub_acc',
      priceEgp: 500,
      discountEgp: 50,
      netEgp: 450,
    ),
  ),
  StudentPricedSubject(
    subjectId: 'sub_eth',
    title: 'Accounting Ethics',
    gradeKey: 'grade_one',
    enabled: true,
    pricing: StudentSubjectPricing(
      subjectId: 'sub_eth',
      priceEgp: 100,
      discountEgp: 50,
      netEgp: 50,
    ),
  ),
  StudentPricedSubject(
    subjectId: 'sub_chem',
    title: 'Chemistry',
    gradeKey: 'grade_two',
    enabled: true,
    pricing: null,
  ),
];

ProviderScope _pricingScope({required Widget child}) {
  return ProviderScope(
    overrides: [
      studentLedgerProvider('stu_001')
          .overrideWithValue(AsyncData<StudentLedger>(_demoLedger())),
      studentProfileSubjectsProvider('stu_001').overrideWithValue(
        const AsyncData<List<StudentSubjectRegistration>>(_demoRegs),
      ),
      studentPricedSubjectsProvider('stu_001').overrideWithValue(
        const AsyncData<List<StudentPricedSubject>>(_demoPriced),
      ),
    ],
    child: child,
  );
}

Future<void> _pumpPricing(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    _pricingScope(
      child: const MaterialApp(
        home: Scaffold(
          body: StudentProfileOverviewScreen(
            student: _student,
            gradeKey: 'grade_one',
            initialNav: 'Payments',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('StudentSubjectPricing parsing (display/reference only)', () {
    test('fromDoc parses stored price/discount/net', () async {
      final FakeFirebaseFirestore fake = FakeFirebaseFirestore();
      await fake.collection('student_subject_pricing').doc('s1_sub1').set(
        <String, dynamic>{
          'student_id': 's1',
          'subject_id': 'sub1',
          'price_egp': 500,
          'discount_egp': 50,
          'net_egp': 450,
          'is_deleted': false,
        },
      );
      final QuerySnapshot<Map<String, dynamic>> snap =
          await fake.collection('student_subject_pricing').get();
      final StudentSubjectPricing pricing =
          StudentSubjectPricing.fromDoc(snap.docs.single);

      expect(pricing.subjectId, 'sub1');
      expect(pricing.priceEgp, 500);
      expect(pricing.discountEgp, 50);
      expect(pricing.netEgp, 450);
    });

    test('fromDoc derives net when the stored value is absent', () async {
      final FakeFirebaseFirestore fake = FakeFirebaseFirestore();
      await fake.collection('student_subject_pricing').doc('s1_sub1').set(
        <String, dynamic>{
          'student_id': 's1',
          'subject_id': 'sub1',
          'price_egp': 100,
          'discount_egp': 50,
          'is_deleted': false,
        },
      );
      final QuerySnapshot<Map<String, dynamic>> snap =
          await fake.collection('student_subject_pricing').get();

      expect(StudentSubjectPricing.fromDoc(snap.docs.single).netEgp, 50);
    });
  });

  group('buildStudentPricedSubjects join (pure)', () {
    test('attaches pricing by subject, missing stays null, sorted', () {
      final List<StudentPricedSubject> rows = buildStudentPricedSubjects(
        registrations: _demoRegs,
        pricings: const <StudentSubjectPricing>[
          StudentSubjectPricing(
            subjectId: 'sub_acc',
            priceEgp: 500,
            discountEgp: 50,
            netEgp: 450,
          ),
        ],
      );

      expect(rows.map((r) => r.title).toList(),
          <String>['Accounting Ethics', 'Chemistry', 'Financial Accounting']);
      expect(
        rows.firstWhere((r) => r.subjectId == 'sub_acc').pricing?.netEgp,
        450,
      );
      // Unpriced rows keep null pricing — the table renders `—`.
      expect(
        rows.firstWhere((r) => r.subjectId == 'sub_eth').pricing,
        isNull,
      );
      expect(
        rows.firstWhere((r) => r.subjectId == 'sub_chem').pricing,
        isNull,
      );
    });

    test('pricing never feeds the student ledger totals', () {
      final StudentLedger ledger = _demoLedger();

      // Even with priced subjects present, the summary stays
      // student-level: Net 500 / Paid 200 / Balance 300.
      expect(ledger.netTotal, 500);
      expect(ledger.paidAmount, 200);
      expect(ledger.balanceDue, 300);
    });
  });

  group('Payments → Subjects table', () {
    testWidgets('renders Figma rows above Payment History',
        (WidgetTester tester) async {
      await _pumpPricing(tester);

      // Table 1 headers.
      expect(find.text('Subjects'), findsWidgets);
      expect(find.text('Grade'), findsOneWidget);
      expect(find.text('Price'), findsOneWidget);
      expect(find.text('Discount'), findsOneWidget);
      expect(find.text('Net'), findsOneWidget);

      // Figma rows with manual pricing.
      expect(find.text('Financial Accounting'), findsOneWidget);
      expect(find.text('Grade One'), findsWidgets);
      expect(find.text('500 EGP'), findsWidgets);
      expect(find.text('50 EGP'), findsWidgets);
      expect(find.text('450 EGP'), findsOneWidget);

      // Unpriced Chemistry renders `—`, never an invented 0. (`Grade Two`
      // also appears in the grade navigation chrome, hence findsWidgets.)
      expect(find.text('Chemistry'), findsOneWidget);
      expect(find.text('Grade Two'), findsWidgets);
      expect(find.text('—'), findsWidgets);

      // Payment History (Table 2) is preserved below the Subjects table.
      expect(find.text('Payment Date'), findsOneWidget);
      expect(find.text('9/9/2026'), findsOneWidget);

      // Student-level summary is untouched by subject pricing.
      expect(find.text('Net Total : 500 EGP'), findsOneWidget);
      expect(find.text('Paid Amount : 200 EGP'), findsOneWidget);
      expect(find.text('Balance Due : 300 EGP'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping a priced row opens the pricing editor',
        (WidgetTester tester) async {
      await _pumpPricing(tester);

      await tester.ensureVisible(find.text('Financial Accounting'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Financial Accounting'));
      await tester.pumpAndSettle();

      // Dialog is titled with the subject and prefills stored values.
      expect(find.text('Price (EGP)'), findsOneWidget);
      expect(find.text('Discount (EGP)'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Price (EGP)'), findsNothing);
    });

    testWidgets('pricing dialog rejects discount above price',
        (WidgetTester tester) async {
      await _pumpPricing(tester);

      await tester.ensureVisible(find.text('Accounting Ethics'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Accounting Ethics'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(1), '600');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Discount must not exceed price.'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
    testWidgets('Figma vertical order: Subjects, Summary, History',
        (WidgetTester tester) async {
      await _pumpPricing(tester);

      // Profile tabs live in the shell above the tab body; within the
      // Payments body the Subjects table renders above the Payment
      // Summary, which renders above Payment History.
      final double subjectsDy =
          tester.getTopLeft(find.text('Financial Accounting')).dy;
      final double summaryDy =
          tester.getTopLeft(find.text('Net Total : 500 EGP')).dy;
      final double historyDy =
          tester.getTopLeft(find.text('Payment Date')).dy;

      expect(subjectsDy, lessThan(summaryDy));
      expect(summaryDy, lessThan(historyDy));
      expect(tester.takeException(), isNull);
    });
  });
}
