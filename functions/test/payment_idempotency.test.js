/**
 * payment_idempotency.test.js — duplicate-execution protection for
 * onPaymentLogged (approved single-operator hardening).
 *
 * Mechanism under test: deterministic payment_logs doc ID from the
 * request's business identity (student + receipt + amount + method +
 * date) with transactional get-or-create; identical repeats return the
 * existing payment with no new side effects.
 *
 * Runs against compiled ../lib/index.js with an in-memory Firestore/Auth
 * mock (same pattern as password_reset.test.js). No emulator, no network.
 *
 * Verified behaviors:
 *  1. First valid request succeeds (1 ledger doc + audit/analytics/notify).
 *  2. Identical repeat -> same paymentId, still 1 doc, no new side effects.
 *  3. Concurrent identical repeats -> single doc, same ID.
 *  4. Different receipt -> second payment recorded normally.
 *  5. Same receipt but different amount -> recorded (no false collapse).
 *  6. Doctor-only authorization intact.
 *  7. Over-Net guard intact.
 */
const test = require("firebase-functions-test")({
  projectId: "dr-tarek-platform-functions-test",
});

const assert = require("node:assert/strict");

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

const wrapped = test.wrap(functions.onPaymentLogged);

function calls(collection) {
  return writes.filter((w) => w.collection === collection);
}

const doctorAuth = {uid: "doctor-1", token: {role: "doctor"}};
const adminAuth = {uid: "admin-1", token: {role: "admin"}};

const basePayload = {
  studentId: "student-pay-1",
  amount: 500,
  receiptNumber: "R-9001",
  paymentMethod: "cash",
  collectorName: "Jo",
  paymentDate: "2026-09-09",
  notes: "Cash collected",
};

function seedAccount(net) {
  seedDoc("student_financial_accounts", "student-pay-1", {
    student_id: "student-pay-1",
    price_egp: net,
    discount_egp: 0,
    net_egp: net,
    is_deleted: false,
  });
}

async function run() {
  let passed = 0;
  const ok = (name) => {
    passed++;
    console.log(`ok - ${name}`);
  };
  const fail = (name, detail) => {
    console.error(`FAIL - ${name}: ${detail}`);
    process.exitCode = 1;
  };

  // 1: first valid request succeeds with full side effects.
  resetStore();
  seedAccount(1000);
  let firstId = null;
  try {
    const res = await wrapped({data: {...basePayload}, auth: doctorAuth});
    assert.equal(res.logged, true);
    assert.ok(res.paymentId);
    firstId = res.paymentId;
    ok("first valid request succeeds");
  } catch (err) {
    fail("first", `${err.code}: ${err.message}`);
  }
  if (calls("payment_logs").length !== 1) fail("one-doc", `got ${calls("payment_logs").length}`);
  else ok("exactly one ledger doc created");

  // 2: identical repeat -> same ID, no new doc, no new side effects.
  try {
    const res = await wrapped({data: {...basePayload}, auth: doctorAuth});
    assert.equal(res.logged, true);
    assert.equal(res.paymentId, firstId);
    ok("identical repeat returns same paymentId");
  } catch (err) {
    fail("repeat", `${err.code}: ${err.message}`);
  }
  if (calls("payment_logs").length !== 1) fail("no-dup-doc", `got ${calls("payment_logs").length}`);
  else ok("repeat creates no second ledger doc");
  if (calls("admin_audit_log").length !== 1) fail("no-dup-audit", `got ${calls("admin_audit_log").length}`);
  else ok("repeat creates no duplicate audit");
  if (calls("analytics_events").length !== 1) fail("no-dup-analytics", `got ${calls("analytics_events").length}`);
  else ok("repeat creates no duplicate analytics");
  if (calls("notifications").length !== 1) fail("no-dup-notify", `got ${calls("notifications").length}`);
  else ok("repeat sends no duplicate notification");

  // 3: concurrent identical repeats converge on one doc.
  const results = await Promise.all([
    wrapped({data: {...basePayload}, auth: doctorAuth}),
    wrapped({data: {...basePayload}, auth: doctorAuth}),
  ]);
  const ids = Object.keys(store["payment_logs"] || {});
  if (ids.length === 1 && results[0].paymentId === results[1].paymentId && results[0].paymentId === firstId) {
    ok("concurrent repeats converge on one doc");
  } else {
    fail("concurrent", `docs=${ids.length} ids=${results.map((r) => r.paymentId)}`);
  }

  // 4: different receipt -> second payment recorded normally.
  try {
    const res = await wrapped({data: {...basePayload, receiptNumber: "R-9002"}, auth: doctorAuth});
    assert.equal(res.logged, true);
    assert.notEqual(res.paymentId, firstId);
    ok("different receipt recorded as new payment");
  } catch (err) {
    fail("different", `${err.code}: ${err.message}`);
  }
  if (Object.keys(store["payment_logs"]).length !== 2) fail("two-docs", "expected 2 ledger docs");
  else ok("two genuinely different payments coexist");

  // 5: same receipt but different amount -> recorded (no false collapse).
  // Fresh store: net 2000, one 500 payment, then a 100 variant.
  resetStore();
  seedAccount(2000);
  try {
    await wrapped({data: {...basePayload, receiptNumber: "R-9002"}, auth: doctorAuth});
    const res = await wrapped({data: {...basePayload, receiptNumber: "R-9002", amount: 100}, auth: doctorAuth});
    assert.equal(res.logged, true);
    assert.equal(Object.keys(store["payment_logs"]).length, 2);
    ok("same receipt different amount recorded (no false collapse)");
  } catch (err) {
    fail("variation", `${err.code}: ${err.message}`);
  }

  // 6: authorization intact.
  try {
    await wrapped({data: {...basePayload, receiptNumber: "R-9003"}, auth: adminAuth});
    fail("authz", "expected failure, got success");
  } catch (err) {
    if (err.code === "permission-denied") ok("non-doctor denied");
    else fail("authz", `unexpected ${err.code}`);
  }

  // 7: over-Net guard intact.
  resetStore();
  seedAccount(1000);
  seedDoc("payment_logs", "old-1", {student_id: "student-pay-1", amount: 800, is_deleted: false});
  try {
    await wrapped({data: {...basePayload, amount: 500}, auth: doctorAuth});
    fail("overnet", "expected failure, got success");
  } catch (err) {
    if (err.code === "failed-precondition") ok("over-Net guard intact");
    else fail("overnet", `unexpected ${err.code}`);
  }

  test.cleanup();

  if (process.exitCode === 1) {
    console.error("payment_idempotency tests FAILED");
    process.exit(1);
  }
  console.log(`payment_idempotency.test: PASS - All ${passed} checks passed.`);
}

run();
