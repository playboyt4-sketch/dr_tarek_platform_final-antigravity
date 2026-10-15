/**
 * T-CF.14 onPaymentLogged — unit tests with mocked Admin SDK.
 *
 * Approved student-level payment model
 * (payments_student_level_database_change_authority.md):
 * - Doctor ONLY. No delegated admin may create payment records.
 * - Payment is student-level, NOT Student x Subject.
 * - subjectId is optional legacy/descriptive metadata only; it is never
 *   required and never affects aggregation or caps.
 * - Financial source is student_financial_accounts/{studentId}
 *   (price/discount/net). student_subject_accounts is retired/inert.
 * - Cap: SUM(non-deleted payments for student) + amount <= net_egp.
 * - payment_method in {cash, e_wallet, instapay, bank} (descriptive only).
 * - collected_by = manual free-text collector name (never a UID).
 * - created_by/updated_by = transcribing Doctor, server-derived.
 * - paymentDate required, today or past (no future dates).
 * - No subscription/membership mutation.
 */
const test = require("firebase-functions-test")({
  projectId: "dr-tarek-platform-functions-test",
});

const assert = require("node:assert/strict");

// In-memory store: {collection: {docId: data}}.
const store = {};
const writes = [];

function resetStore() {
  for (const k of Object.keys(store)) delete store[k];
  writes.length = 0;
}

function seedDoc(coll, id, data) {
  if (!store[coll]) store[coll] = {};
  store[coll][id] = data;
}

function applyWheres(coll, filters) {
  const docs = Object.entries(store[coll] || {})
    .filter(([_, data]) =>
      filters.every(([field, op, value]) => {
        if (op === "==") return data[field] === value;
        return false;
      }),
    )
    .map(([id, data]) => ({id, data: () => data, ref: {id}}));
  return {empty: docs.length === 0, docs};
}

const adminMock = {
  initializeApp: () => ({}),
  getFirestore: () => ({
    collection: (collPath) => {
      const query = (filters) => ({
        where: (f, op, v) => query([...filters, [f, op, v]]),
        get: async () => applyWheres(collPath, filters),
      });
      return {
        doc: (docId) => ({
          id: docId,
          get: async () => {
            const docData = (store[collPath] || {})[docId];
            if (docData === undefined) return {exists: false};
            return {exists: true, data: () => docData};
          },
          update: async () => {},
          // Records set() writes (transactional deterministic-ID creation
          // in onPaymentLogged) exactly like add() so existing assertions
          // on writes[] keep working unchanged.
          set: async (data) => {
            if (!store[collPath]) store[collPath] = {};
            store[collPath][docId] = data;
            writes.push({collection: collPath, id: docId, data});
          },
        }),
        where: (f, op, v) => query([[f, op, v]]),
        get: async () => applyWheres(collPath, []),
        add: async (data) => {
          const id = `${collPath}-doc-${writes.length}`;
          if (!store[collPath]) store[collPath] = {};
          store[collPath][id] = data;
          writes.push({collection: collPath, id, data});
          return {id};
        },
      };
    },
    // Passthrough runner for the payment idempotency transaction
    // (get-or-create on the deterministic payment doc; no contention
    // semantics — see payment_idempotency.test.js).
    runTransaction: async (fn) => {
      const txRef = (ref) => ref;
      return fn({
        get: (ref) => txRef(ref).get(),
        update: (ref, data) => txRef(ref).update(data),
        set: (ref, data, options) => txRef(ref).set(data, options),
      });
    },
  }),
  FieldValue: {serverTimestamp: () => ({_serverTimestamp: true})},
  Timestamp: {
    now: () => ({toMillis: () => Date.now()}),
    fromDate: (d) => ({toMillis: () => d.getTime()}),
  },
  getAuth: () => ({
    updateUser: async () => {},
    getUser: async () => ({customClaims: {}}),
    setCustomUserClaims: async () => {},
  }),
  getMessaging: () => ({}),
  getStorage: () => ({}),
};

const Module = require("node:module");
const originalRequire = Module.prototype.require;
Module.prototype.require = function (id) {
  if (id === "firebase-admin/firestore") {
    return {
      getFirestore: adminMock.getFirestore,
      FieldValue: adminMock.FieldValue,
      Timestamp: adminMock.Timestamp,
    };
  }
  if (id === "firebase-admin/auth") return {getAuth: adminMock.getAuth};
  if (id === "firebase-admin/messaging") return {getMessaging: adminMock.getMessaging};
  if (id === "firebase-admin/storage") return {getStorage: adminMock.getStorage};
  if (id === "firebase-admin/app") return {initializeApp: adminMock.initializeApp};
  return originalRequire.apply(this, arguments);
};

let functions;
try {
  functions = require("../lib/index.js");
} catch (error) {
  console.error("Failed to load functions:", error);
  process.exit(1);
}

if (typeof functions.recordStudentPayment !== "undefined") {
  console.error("FAIL - recordStudentPayment must not exist (unapproved).");
  process.exit(1);
}
console.log("ok - recordStudentPayment absent");

if (typeof functions.setStudentSubjectAccount !== "undefined") {
  console.error("FAIL - setStudentSubjectAccount must not exist (retired).");
  process.exit(1);
}
console.log("ok - setStudentSubjectAccount absent (retired)");

const wrapped = test.wrap(functions.onPaymentLogged);

function calls(collection) {
  return writes.filter((w) => w.collection === collection);
}

const doctorAuth = {uid: "doctor-1", token: {role: "doctor"}};
const adminAuth = {uid: "admin-1", token: {role: "admin"}};

// Student-level contract: no subjectId required.
const validPayload = {
  studentId: "student-pay-1",
  amount: 500,
  receiptNumber: "R-1001",
  paymentMethod: "cash",
  collectorName: "Jo",
  paymentDate: "2026-09-09",
  notes: "Cash collected",
};

function seedAccount(net, studentId) {
  const sid = studentId || "student-pay-1";
  seedDoc("student_financial_accounts", sid, {
    student_id: sid,
    price_egp: net,
    discount_egp: 0,
    net_egp: net,
    is_deleted: false,
  });
}

async function run() {
  let passed = 0;
  async function checkPass(name, req) {
    try {
      const res = await wrapped(req);
      passed++;
      console.log(`ok - ${name}`);
      return res;
    } catch (err) {
      console.error(`FAIL - ${name}: expected success, got ${err.code}: ${err.message}`);
      process.exitCode = 1;
      return null;
    }
  }

  async function checkFail(name, req, code) {
    try {
      await wrapped(req);
      console.error(`FAIL - ${name}: expected failure, got success`);
      process.exitCode = 1;
    } catch (err) {
      if (code && err.code !== code) {
        console.error(`FAIL - ${name}: expected ${code}, got ${err.code}`);
        process.exitCode = 1;
        return;
      }
      passed++;
      console.log(`ok - ${name}`);
    }
  }

  // 1. Doctor records with the student-level contract (no subjectId).
  resetStore();
  seedAccount(1000);
  const res = await checkPass("Doctor logs payment without subjectId", {
    data: {...validPayload},
    auth: doctorAuth,
  });
  assert.equal(res.logged, true);
  assert.ok(res.paymentId);
  const payments = calls("payment_logs");
  assert.equal(payments.length, 1);
  const doc = payments[0].data;
  assert.equal(doc.student_id, "student-pay-1");
  assert.equal(doc.amount, 500);
  assert.equal(doc.payment_method, "cash");
  assert.equal(doc.collected_by, "Jo");
  assert.equal(doc.created_by, "doctor-1");
  assert.equal(doc.updated_by, "doctor-1");
  assert.equal(doc.receipt_number, "R-1001");
  assert.equal(doc.notes, "Cash collected");
  assert.ok(doc.payment_date);
  assert.ok(!("subject_id" in doc));
  console.log("ok - payment_logs student-level schema correct (no subject_id)");

  const audits = calls("admin_audit_log");
  assert.equal(audits.length, 1);
  assert.equal(audits[0].data.action, "payment_logged");
  assert.equal(audits[0].data.entity, "payment_logs");
  assert.equal(audits[0].data.actor_id, "doctor-1");
  assert.equal(audits[0].data.actor_role, "doctor");
  assert.equal(audits[0].data.permission_basis, "doctor");
  console.log("ok - doctor audit event generated");

  const analytics = calls("analytics_events");
  assert.equal(analytics.length, 1);
  assert.equal(calls("notifications").length, 1);
  assert.equal(calls("subscriptions").length, 0);
  assert.equal(calls("subject_access_assignments").length, 0);
  assert.equal(calls("student_payments").length, 0);
  assert.equal(calls("student_subject_accounts").length, 0);
  console.log("ok - analytics/notification intact, no subscription change, no retired writes");

  // 1b. Legacy subjectId memo is accepted but stays descriptive only.
  resetStore();
  seedAccount(1000);
  const memoRes = await checkPass("Legacy subjectId memo accepted", {
    data: {...validPayload, subjectId: "legacy-sub-1", receiptNumber: "R-1002"},
    auth: doctorAuth,
  });
  assert.ok(memoRes.paymentId);
  const memoDoc = calls("payment_logs")[0].data;
  assert.equal(memoDoc.subject_id, "legacy-sub-1");
  console.log("ok - subject_id stored as legacy memo only");

  // 1c. bank method accepted, case-insensitively.
  resetStore();
  seedAccount(1000);
  const bankRes = await checkPass("Bank method accepted", {
    data: {...validPayload, paymentMethod: "bank", receiptNumber: "R-1003"},
    auth: doctorAuth,
  });
  assert.ok(bankRes.paymentId);
  assert.equal(calls("payment_logs")[0].data.payment_method, "bank");
  const bankUpperRes = await checkPass("Bank method case-insensitive", {
    data: {...validPayload, paymentMethod: "Bank", receiptNumber: "R-1004"},
    auth: doctorAuth,
  });
  assert.ok(bankUpperRes.paymentId);
  assert.equal(calls("payment_logs")[1].data.payment_method, "bank");
  console.log("ok - bank wire value stored verbatim");

  // 2. Enum + transcription validations.
  resetStore();
  seedAccount(1000);
  await checkFail("Unknown method rejected", {
    data: {...validPayload, paymentMethod: "cheque"}, auth: doctorAuth,
  }, "invalid-argument");
  await checkFail("Missing method rejected", {
    data: {...validPayload, paymentMethod: undefined}, auth: doctorAuth,
  }, "invalid-argument");
  await checkFail("Blank collector rejected", {
    data: {...validPayload, collectorName: "   "}, auth: doctorAuth,
  }, "invalid-argument");
  await checkFail("Long collector rejected", {
    data: {...validPayload, collectorName: "x".repeat(101)}, auth: doctorAuth,
  }, "invalid-argument");
  await checkFail("Long notes rejected", {
    data: {...validPayload, notes: "n".repeat(501)}, auth: doctorAuth,
  }, "invalid-argument");
  await checkFail("Future date rejected", {
    data: {...validPayload, paymentDate: "2999-01-01"}, auth: doctorAuth,
  }, "invalid-argument");
  await checkFail("Missing date rejected", {
    data: {...validPayload, paymentDate: undefined}, auth: doctorAuth,
  }, "invalid-argument");
  await checkFail("Missing receipt rejected", {
    data: {...validPayload, receiptNumber: undefined}, auth: doctorAuth,
  }, "invalid-argument");
  await checkFail("Negative amount rejected", {
    data: {...validPayload, amount: -5}, auth: doctorAuth,
  }, "invalid-argument");

  // 3. Doctor-only gate (delegated admin has no create rights).
  resetStore();
  seedAccount(1000);
  seedDoc("admin_permissions", "admin-1", {
    is_active: true,
    permissions: {"admin_payments": true, "admin_payments_view": true},
  });
  await checkFail("Delegated admin rejected", {
    data: {...validPayload, receiptNumber: "R-1002"}, auth: adminAuth,
  }, "permission-denied");
  await checkFail("Unauthenticated rejected", {data: {...validPayload}}, "unauthenticated");

  // 4. Student-level Over-Net protection (subject_id ignored).
  resetStore();
  seedAccount(1000);
  seedDoc("payment_logs", "old-1", {
    student_id: "student-pay-1",
    subject_id: "subject-legacy-9",
    amount: 800,
    is_deleted: false,
  });
  await checkFail("Over-Net rejected (legacy subject ignored)", {
    data: {...validPayload, amount: 500}, auth: doctorAuth,
  }, "failed-precondition");
  const okRes = await checkPass("At-Net accepted", {
    data: {...validPayload, amount: 200}, auth: doctorAuth,
  });
  assert.ok(okRes.paymentId);

  // 5. Missing student financial account.
  resetStore();
  await checkFail("Missing account rejected", {
    data: {...validPayload}, auth: doctorAuth,
  }, "failed-precondition");

  // 6. Mixed-subject history aggregates into one student Paid total.
  // Payment A (subject A, 200) + Payment B (subject B, 100), net 300:
  // cap reached; any third payment rejected regardless of subject.
  resetStore();
  seedAccount(300);
  seedDoc("payment_logs", "pay-A", {
    student_id: "student-pay-1",
    subject_id: "subject-A",
    amount: 200,
    is_deleted: false,
  });
  seedDoc("payment_logs", "pay-B", {
    student_id: "student-pay-1",
    subject_id: "subject-B",
    amount: 100,
    is_deleted: false,
  });
  await checkFail("Third payment rejected after mixed-subject cap", {
    data: {...validPayload, amount: 1, subjectId: "subject-C"}, auth: doctorAuth,
  }, "failed-precondition");
  await checkFail("Third payment rejected without subject too", {
    data: {...validPayload, amount: 1}, auth: doctorAuth,
  }, "failed-precondition");

  test.cleanup();

  if (process.exitCode === 1) {
    console.error("payment_logged tests FAILED");
    process.exit(1);
  }
  console.log(`payment_logged.test: PASS - All ${passed} checks passed.`);
}

run();
