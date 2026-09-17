import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drtarek_dashboard/features/students/presentation/providers/grade_students_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/providers/student_profile_payments_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/providers/student_profile_subjects_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/providers/student_subject_pricing_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/screens/student_profile_overview_screen.dart';
import 'package:drtarek_dashboard/features/students/presentation/screens/student_profile_payments_tab.dart';

const GradeStudent _student = GradeStudent(
  id: 'stu_001',
  name: 'ahmed mohamed gamal',
  isCenter: true,
  plan: 'PRO',
  isActive: true,
  lastSignIn: '12/8/2026',
  phone: '01115800180',
);

// Single student-level account (Figma summary: Net 500).
const StudentFinancialAccount _finAccount = StudentFinancialAccount(
  studentId: 'stu_001',
  priceEgp: 500,
  discountEgp: 0,
  netEgp: 500,
);

// Figma-consistent ledger: Net 500, Paid 200, Balance 300, Partially Paid.
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

ProviderScope _paymentsScope({
  required Widget child,
  StudentLedger? ledger,
}) {
  return ProviderScope(
    overrides: [
      studentLedgerProvider('stu_001')
          .overrideWithValue(AsyncData<StudentLedger>(ledger ?? _demoLedger())),
      studentProfileSubjectsProvider('stu_001').overrideWithValue(
        const AsyncData<List<StudentSubjectRegistration>>(
          <StudentSubjectRegistration>[],
        ),
      ),
      // No registered subjects → the Subjects table renders headers plus
      // its empty state (no priced rows).
      studentPricedSubjectsProvider('stu_001').overrideWithValue(
        const AsyncData<List<StudentPricedSubject>>(
          <StudentPricedSubject>[],
        ),
      ),
    ],
    child: child,
  );
}

Future<void> _pumpPayments(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    _paymentsScope(
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
  group('PaymentMethod canonical enum', () {
    test('wire values and Figma labels', () {
      expect(PaymentMethod.cash.wire, 'cash');
      expect(PaymentMethod.eWallet.wire, 'e_wallet');
      expect(PaymentMethod.instapay.wire, 'instapay');
      expect(PaymentMethod.bank.wire, 'bank');
      expect(PaymentMethod.cash.label, 'Cash');
      expect(PaymentMethod.eWallet.label, 'E-Wallet');
      expect(PaymentMethod.instapay.label, 'InstaPay');
      expect(PaymentMethod.bank.label, 'Bank');
    });

    test('parses canonical spellings, rejects unapproved values', () {
      expect(PaymentMethodWire.parse('cash'), PaymentMethod.cash);
      expect(PaymentMethodWire.parse('E_WALLET'), PaymentMethod.eWallet);
      expect(PaymentMethodWire.parse('InstaPay'), PaymentMethod.instapay);
      expect(PaymentMethodWire.parse('Bank'), PaymentMethod.bank);
      expect(PaymentMethodWire.parse('Wallet'), isNull);
      expect(PaymentMethodWire.parse(null), isNull);
      expect(PaymentMethodWire.parse(''), isNull);
    });
  });

  group('StudentLedger computed properties (student-level)', () {
    test('net / paid / balance aggregate correctly', () {
      final StudentLedger ledger = _demoLedger();

      expect(ledger.netTotal, 500);
      expect(ledger.paidAmount, 200);
      expect(ledger.balanceDue, 300);
    });

    test('status transitions unpaid → partial → paid', () {
      const empty = StudentLedger.empty();
      expect(empty.status, PaymentStatus.unpaid);

      final partial = _demoLedger();
      expect(partial.status, PaymentStatus.partial);

      final paid = StudentLedger(
        account: _finAccount,
        payments: <StudentPayment>[
          StudentPayment(
            id: 'pay_1',
            subjectId: '',
            date: DateTime(2026, 9, 9),
            amountEgp: 500,
            method: PaymentMethod.cash,
            collectedBy: 'Jo',
            receiptNumber: 'R-1',
            notes: null,
          ),
        ],
      );
      expect(paid.status, PaymentStatus.paid);
      expect(paid.balanceDue, 0);
    });

    test('paid never displays above net (legacy over-Net clamp)', () {
      final StudentLedger ledger = StudentLedger(
        account: _finAccount,
        payments: <StudentPayment>[
          StudentPayment(
            id: 'pay_1',
            subjectId: 'legacy-sub',
            date: DateTime(2026, 9, 9),
            amountEgp: 900,
            method: PaymentMethod.cash,
            collectedBy: 'Jo',
            receiptNumber: 'R-1',
            notes: null,
          ),
        ],
      );

      expect(ledger.netTotal, 500);
      expect(ledger.paidAmount, 500);
      expect(ledger.balanceDue, 0);
    });

    test('missing account resolves to zero net, never invented', () {
      final StudentLedger ledger = buildStudentLedger(
        account: null,
        payments: const <StudentPayment>[],
      );

      expect(ledger.netTotal, 0);
      expect(ledger.balanceDue, 0);
      expect(ledger.status, PaymentStatus.unpaid);
    });

    test('buildStudentLedger carries the account and payments', () {
      final StudentLedger ledger = buildStudentLedger(
        account: _finAccount,
        payments: const <StudentPayment>[],
      );

      expect(ledger.account?.netEgp, 500);
      expect(ledger.netTotal, 500);
      expect(ledger.status, PaymentStatus.unpaid);
    });

    test('historical payments with different subject_ids aggregate together', () {
      final StudentLedger ledger = StudentLedger(
        account: _finAccount,
        payments: <StudentPayment>[
          StudentPayment(
            id: 'a',
            subjectId: 'sub-a',
            date: DateTime(2026, 9, 9),
            amountEgp: 200,
            method: PaymentMethod.cash,
            collectedBy: 'Jo',
            receiptNumber: 'R-1',
            notes: null,
          ),
          StudentPayment(
            id: 'b',
            subjectId: 'sub-b',
            date: DateTime(2026, 9, 13),
            amountEgp: 100,
            method: PaymentMethod.bank,
            collectedBy: 'tarek',
            receiptNumber: 'R-2',
            notes: null,
          ),
        ],
      );

      // Subject memos do not split the total: 200 + 100 = 300 paid.
      expect(ledger.paidAmount, 300);
      expect(ledger.balanceDue, 200);
      expect(ledger.status, PaymentStatus.partial);
      // Bank renders verbatim as the Figma history shows it.
      expect(ledger.payments[1].methodLabel, 'Bank');
    });

    test('sortPaymentsOldestNewest orders oldest → newest', () {
      final List<StudentPayment> sorted = sortPaymentsOldestNewest(
        <StudentPayment>[
          StudentPayment(
            id: 'b',
            subjectId: '',
            date: DateTime(2026, 9, 10),
            amountEgp: 100,
            method: PaymentMethod.cash,
            collectedBy: 'Jo',
            receiptNumber: 'R-2',
            notes: null,
          ),
          StudentPayment(
            id: 'a',
            subjectId: '',
            date: DateTime(2026, 9, 9),
            amountEgp: 100,
            method: PaymentMethod.instapay,
            collectedBy: 'Jo',
            receiptNumber: 'R-1',
            notes: null,
          ),
        ],
      );

      expect(sorted.map((p) => p.id).toList(), <String>['a', 'b']);
    });

    test('buildInvoicePdf generates a non-empty document', () async {
      final bytes = await buildInvoicePdf(
        studentName: 'ahmed mohamed gamal',
        phone: '01115800180',
        gradeLabel: 'Grade One',
        dateLabel: '12/8/2026',
        ledger: _demoLedger(),
      );

      expect(bytes.isNotEmpty, isTrue);
    });
  });

  group('Student Profile → Payments tab', () {
    testWidgets('persistent header stays mounted with Payments active',
        (WidgetTester tester) async {
      await _pumpPayments(tester);

      expect(find.text('Tarek el araby Platform'), findsOneWidget);
      expect(find.text('ahmed mohamed gamal'), findsWidgets);
      expect(find.text('Payments'), findsOneWidget);

      // Body: strip + subjects table + history (no overview table).
      // 'Subjects' still appears in the profile navigation chrome and as
      // the restored Subjects-table header; the per-subject
      // Price/Discount/Net columns render from manual subject pricing.
      expect(find.text('Partially Paid'), findsOneWidget);
      expect(find.text('Payment Date'), findsOneWidget);
      expect(find.text('Subjects'), findsWidgets);
      expect(find.text('Price'), findsOneWidget);
      expect(find.text('Discount'), findsOneWidget);
      expect(find.text('Net'), findsOneWidget);
      expect(find.text('Name'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('strip and history render student-level ledger values',
        (WidgetTester tester) async {
      await _pumpPayments(tester);

      expect(find.text('01.'), findsOneWidget);
      expect(find.text('Net Total : 500 EGP'), findsOneWidget);
      expect(find.text('Paid Amount : 200 EGP'), findsOneWidget);
      expect(find.text('Balance Due : 300 EGP'), findsOneWidget);
      expect(find.text('9/9/2026'), findsOneWidget);
      expect(find.text('Cash'), findsWidgets);
      expect(find.text('Jo'), findsWidgets);
      expect(find.text('Add Payment'), findsOneWidget);
      expect(find.text('Print Invoice'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Add Payment opens the dialog; Cancel closes it',
        (WidgetTester tester) async {
      await _pumpPayments(tester);

      await tester.tap(find.text('Add Payment'));
      await tester.pumpAndSettle();

      // Dialog header, balance banner, Figma-only fields, footer.
      // 'Payment Date' also renders in the history table behind the dialog.
      expect(find.text('Add Payment'), findsNWidgets(2));
      expect(find.text('Payment Date'), findsNWidgets(2));
      expect(find.text('Payment Method'), findsOneWidget);
      expect(find.text('Select Method'), findsOneWidget);
      expect(find.text('Payment Amount'), findsOneWidget);
      // 'Collected By' also renders in the history table behind the dialog.
      expect(find.text('Collected By'), findsNWidgets(2));
      // Figma `#add payment` shows no Subject, Notes, or Receipt fields.
      expect(find.text('Subject'), findsNothing);
      expect(find.text('Notes'), findsNothing);
      expect(find.text('Receipt'), findsNothing);
      expect(find.text('Save Payment'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Save Payment'), findsNothing);
    });

    testWidgets('Method dropdown offers Cash, E-Wallet, InstaPay, Bank',
        (WidgetTester tester) async {
      await _pumpPayments(tester);

      await tester.tap(find.text('Add Payment'));
      await tester.pumpAndSettle();

      // Open the method dropdown (closed state shows Select Method).
      await tester.tap(find.byType(DropdownButton<PaymentMethod>));
      await tester.pumpAndSettle();

      // 'Cash' also renders in the history table behind the dialog.
      expect(find.text('Cash'), findsWidgets);
      expect(find.text('E-Wallet'), findsOneWidget);
      expect(find.text('InstaPay'), findsOneWidget);
      expect(find.text('Bank'), findsOneWidget);
      expect(find.text('Wallet'), findsNothing);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('Save Payment validates amount and collector',
        (WidgetTester tester) async {
      await _pumpPayments(tester);

      await tester.tap(find.text('Add Payment'));
      await tester.pumpAndSettle();

      // Add-mode fields are amount then collector (no Subject/Notes).
      final Finder amountField = find.byType(TextField).at(0);

      // Empty amount + empty collector → validation error, dialog stays.
      await tester.enterText(amountField, '');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Payment'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid amount.'), findsOneWidget);
      expect(find.text('Save Payment'), findsOneWidget);

      // Valid amount but no method selected → method error, dialog stays.
      await tester.enterText(amountField, '100');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Payment'));
      await tester.pumpAndSettle();

      expect(find.text('Select a payment method.'), findsOneWidget);
      expect(find.text('Save Payment'), findsOneWidget);
    });

    testWidgets('tapping a history row opens correction',
        (WidgetTester tester) async {
      await _pumpPayments(tester);

      await tester.ensureVisible(find.text('9/9/2026'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('9/9/2026'));
      await tester.pumpAndSettle();

      expect(find.text('Correct Payment'), findsOneWidget);
      expect(find.text('Save Correction'), findsOneWidget);
      expect(find.text('Receipt'), findsOneWidget);
      // Subject-less record: no legacy subject row in correction.
      expect(find.text('Subject'), findsNothing);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Save Correction'), findsNothing);
    });

    testWidgets('tapping the summary numbers opens the account editor',
        (WidgetTester tester) async {
      await _pumpPayments(tester);

      await tester.tap(find.text('Net Total : 500 EGP'));
      await tester.pumpAndSettle();

      expect(find.text('Financial Account'), findsOneWidget);
      expect(find.text('Price (EGP)'), findsOneWidget);
      expect(find.text('Discount (EGP)'), findsOneWidget);

      // Discount above price is rejected client-side.
      await tester.enterText(
        find.byType(TextField).at(1),
        '600',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Discount must not exceed price.'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Financial Account'), findsNothing);
    });

    testWidgets('sub-nav switches Payments back to Overview',
        (WidgetTester tester) async {
      await _pumpPayments(tester);

      expect(find.text('Partially Paid'), findsOneWidget);

      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();

      expect(find.text('Partially Paid'), findsNothing);
      expect(find.text('Name'), findsOneWidget);
    });
  });
}
