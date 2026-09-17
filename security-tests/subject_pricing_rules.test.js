/**
 * Manual Student-Subject Pricing — focused Firestore Rules tests
 * (student_subject_pricing_database_change_authority.md §11).
 *
 * Rule under test (firestore.rules):
 *   match /student_subject_pricing/{pricingId} {
 *     allow get, list: if canViewPayments() || canManagePayments() || isTeacher();
 *     allow write: if false;
 *   }
 * where canViewPayments() = teacher OR admin with `admin_payments_view`
 * and canManagePayments() = teacher OR admin with `admin_payments`
 * (the exact existing Payments read authorization — no new model).
 *
 * Proofs:
 * 1. Teacher read → allowed.
 * 2. Authorized Admin (admin_payments_view) read → allowed.
 * 3. Unauthorized Admin read → denied.
 * 4. Student read → denied.
 * 5. Unauthenticated read → denied.
 * 6. Direct create → denied (even Teacher).
 * 7. Direct update → denied (even Teacher).
 * 8. Direct delete → denied (even Teacher).
 *
 * Run with the Firestore emulator:
 *   firebase emulators:exec --only firestore --project <project> "node subject_pricing_rules.test.js"
 */
const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');

const projectId = 'dr-tarek-platform-pricing-rules-test';
const root = path.resolve(__dirname, '..');
let testEnv;

function dbFor(uid, token = {}) {
  return testEnv.authenticatedContext(uid, token).firestore();
}

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.doc('student_subject_pricing/s1_sub1').set({
      student_id: 's1',
      subject_id: 'sub1',
      price_egp: 500,
      discount_egp: 50,
      net_egp: 450,
      created_at: new Date(),
      updated_at: new Date(),
      created_by: 'teacher-1',
      updated_by: 'teacher-1',
      is_deleted: false,
      deleted_at: null,
      deleted_by: null,
    });
    // Authorized Admin: Payments view permission (same key the
    // payment_logs / student_financial_accounts read path uses).
    await db.doc('admin_permissions/admin-payments-view').set({
      admin_id: 'admin-payments-view',
      is_active: true,
      permissions: {admin_payments_view: true},
    });
    // Unauthorized Admin: a valid staff permission, but NOT a Payments one.
    await db.doc('admin_permissions/admin-plain').set({
      admin_id: 'admin-plain',
      is_active: true,
      permissions: {admin_students: true},
    });
  });
}

async function run() {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8'),
    },
  });

  let passed = 0;
  async function checkSucceeds(name, promise) {
    await assertSucceeds(promise);
    passed++;
    console.log(`ok - ${name}`);
  }
  async function checkFails(name, promise) {
    await assertFails(promise);
    passed++;
    console.log(`ok - ${name}`);
  }

  try {
    await testEnv.clearFirestore();
    await seed();

    const pricingDoc = 'student_subject_pricing/s1_sub1';

    // 1. Teacher read → allowed.
    await checkSucceeds(
      'Teacher read allowed',
      dbFor('teacher-1', {role: 'teacher'}).doc(pricingDoc).get(),
    );

    // 2. Authorized Admin (admin_payments_view) read → allowed.
    await checkSucceeds(
      'Authorized Admin (payments-view) read allowed',
      dbFor('admin-payments-view', {role: 'admin'}).doc(pricingDoc).get(),
    );

    // 3. Unauthorized Admin read → denied.
    await checkFails(
      'Unauthorized Admin read denied',
      dbFor('admin-plain', {role: 'admin'}).doc(pricingDoc).get(),
    );

    // 4. Student read → denied.
    await checkFails(
      'Student read denied',
      dbFor('student-safe', {role: 'student', approved: true}).doc(pricingDoc).get(),
    );

    // 5. Unauthenticated read → denied.
    await checkFails(
      'Unauthenticated read denied',
      testEnv.unauthenticatedContext().firestore().doc(pricingDoc).get(),
    );

    // 6. Direct create → denied (even Teacher; writes are callable-only).
    await checkFails(
      'Direct create denied (teacher)',
      dbFor('teacher-1', {role: 'teacher'}).doc('student_subject_pricing/s9_sub9').set({
        student_id: 's9',
        subject_id: 'sub9',
        price_egp: 100,
        discount_egp: 0,
        net_egp: 100,
      }),
    );

    // 7. Direct update → denied (even Teacher).
    await checkFails(
      'Direct update denied (teacher)',
      dbFor('teacher-1', {role: 'teacher'}).doc(pricingDoc).update({price_egp: 1}),
    );

    // 8. Direct delete → denied (even Teacher).
    await checkFails(
      'Direct delete denied (teacher)',
      dbFor('teacher-1', {role: 'teacher'}).doc(pricingDoc).delete(),
    );
  } finally {
    await testEnv.cleanup();
  }

  console.log(`subject_pricing_rules.test: PASS - All ${passed} checks passed.`);
}

run().catch((error) => {
  console.error('subject_pricing_rules tests FAILED:', error);
  process.exit(1);
});
