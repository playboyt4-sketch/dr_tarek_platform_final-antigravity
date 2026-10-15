/**
 * Manual Student-Subject Pricing — focused callable tests (mocked Admin SDK,
 * student_subject_pricing_database_change_authority.md).
 *
 * Covers setStudentSubjectPricing (Doctor-only, ONE callable for Create
 * and Correct at the deterministic document
 * `student_subject_pricing/{studentId}_{subjectId}`):
 * Doctor create, non-Doctor/Admin rejection, price/discount validation,
 * server-derived Net (client net ignored), deterministic ID, correction
 * preserving created_at/created_by while updating updated_at/updated_by,
 * immutable student_id/subject_id linkage, before/after admin_audit_log,
 * and strict separation (no writes to payment_logs,
 * student_financial_accounts, student_subject_accounts, subscriptions;
 * no payment cap evaluated).
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

function copyDoc(data) {
  // Firestore snapshots are copies; the mock must not hand out live
  // references or a later update would rewrite already-read values.
  return JSON.parse(JSON.stringify(data));
}

function applyWheres(coll, filters) {
  const docs = Object.entries(store[coll] || {})
    .filter(([_, data]) =>
      filters.every(([field, op, value]) => {
        if (op === "==") return data[field] === value;
        return false;
      }),
    )
    .map(([id, data]) => ({id, data: () => copyDoc(data), ref: {id}}));
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
            return {exists: true, data: () => copyDoc(docData)};
          },
          update: async (patch) => {
            Object.assign(store[collPath][docId], patch);
          },
          set: async (data) => {
            if (!store[collPath]) store[collPath] = {};
            store[collPath][docId] = data;
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

// Retired per-pair financial callable must stay absent; the new display-only
// callable must exist under its approved name.
if (typeof functions.setStudentSubjectAccount !== "undefined") {
  console.error("FAIL - setStudentSubjectAccount must not exist (retired).");
  process.exit(1);
}
console.log("ok - setStudentSubjectAccount absent (retired)");

if (typeof functions.setStudentSubjectPricing === "undefined") {
  console.error("FAIL - setStudentSubjectPricing must exist (approved).");
  process.exit(1);
}
console.log("ok - setStudentSubjectPricing present (approved)");

// Payment/subscription callables must remain intact (separation proof target).
for (const name of ["onPaymentLogged", "correctPaymentLog", "setStudentFinancialAccount"]) {
  if (typeof functions[name] === "undefined") {
    console.error(`FAIL - ${name} must still exist (untouched).`);
    process.exit(1);
  }
}
console.log("ok - payment callables intact (untouched)");

const setPricing = test.wrap(functions.setStudentSubjectPricing);

const doctorAuth = {uid: "doctor-1", token: {role: "doctor"}};
const doctor2Auth = {uid: "doctor-2", token: {role: "doctor"}};
const adminAuth = {uid: "admin-1", token: {role: "admin"}};

const FORBIDDEN_COLL = [
  "payment_logs",
  "student_financial_accounts",
  "student_subject_accounts",
  "subscriptions",
];

function assertSeparation(context) {
  for (const coll of FORBIDDEN_COLL) {
    assert.ok(
      !(coll in store),
      `${context}: forbidden collection ${coll} was touched`,
    );
    assert.equal(
      writes.filter((w) => w.collection === coll).length,
      0,
      `${context}: forbidden write to ${coll}`,
    );
  }
  console.log(`ok - ${context}: no payment/subscription/account writes`);
}

async function run() {
  let passed = 0;
  async function checkPass(fn, name, req) {
    try {
      const res = await fn(req);
      passed++;
      console.log(`ok - ${name}`);
      return res;
    } catch (err) {
      console.error(`FAIL - ${name}: expected success, got ${err.code}: ${err.message}`);
      process.exitCode = 1;
      return null;
    }
  }

  async function checkFail(fn, name, req, code) {
    try {
      await fn(req);
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

  // 1+5+7. Doctor can create pricing; stored Net is server-derived (500-50=450).
  resetStore();
  const created = await checkPass(setPricing, "Doctor creates pricing", {
    data: {studentId: "s1", subjectId: "sub1", priceEgp: 500, discountEgp: 50},
    auth: doctorAuth,
  });
  assert.equal(created.pricingId, "s1_sub1");
  assert.equal(created.netEgp, 450);
  const doc = store["student_subject_pricing"]["s1_sub1"];
  assert.equal(doc.student_id, "s1");
  assert.equal(doc.subject_id, "sub1");
  assert.equal(doc.price_egp, 500);
  assert.equal(doc.discount_egp, 50);
  assert.equal(doc.net_egp, 450);
  assert.equal(doc.created_by, "doctor-1");
  assert.equal(doc.updated_by, "doctor-1");
  assert.equal(doc.is_deleted, false);
  assert.equal(doc.deleted_at, null);
  assert.equal(doc.deleted_by, null);
  console.log("ok - create schema + deterministic ID + server Net correct");

  // 11 (create). Creation audit exists.
  const createAudits = writes.filter((w) => w.collection === "admin_audit_log");
  assert.equal(createAudits.length, 1);
  assert.equal(createAudits[0].data.action, "subject_pricing_created");
  assert.equal(createAudits[0].data.entity, "student_subject_pricing");
  assert.equal(createAudits[0].data.student_id, "s1");
  assert.equal(createAudits[0].data.subject_id, "sub1");
  assert.equal(createAudits[0].data.actor_role, "doctor");
  assert.equal(createAudits[0].data.permission_basis, "doctor");
  console.log("ok - creation audit correct");

  // 12. Create touched no finance/subscription collections.
  assertSeparation("create separation");

  // 2. Non-Doctor/Admin cannot create; unauthenticated cannot create.
  resetStore();
  await checkFail(setPricing, "Admin rejected", {
    data: {studentId: "s1", subjectId: "sub1", priceEgp: 100, discountEgp: 0},
    auth: adminAuth,
  }, "permission-denied");
  await checkFail(setPricing, "Unauthenticated rejected", {
    data: {studentId: "s1", subjectId: "sub1", priceEgp: 100, discountEgp: 0},
  }, "unauthenticated");

  // 3. Price validation.
  await checkFail(setPricing, "Missing studentId rejected", {
    data: {subjectId: "sub1", priceEgp: 100, discountEgp: 0},
    auth: doctorAuth,
  }, "invalid-argument");
  await checkFail(setPricing, "Missing subjectId rejected", {
    data: {studentId: "s1", priceEgp: 100, discountEgp: 0},
    auth: doctorAuth,
  }, "invalid-argument");
  await checkFail(setPricing, "Negative price rejected", {
    data: {studentId: "s1", subjectId: "sub1", priceEgp: -1, discountEgp: 0},
    auth: doctorAuth,
  }, "invalid-argument");
  await checkFail(setPricing, "Missing price rejected", {
    data: {studentId: "s1", subjectId: "sub1", discountEgp: 0},
    auth: doctorAuth,
  }, "invalid-argument");

  // 4. Discount validation.
  await checkFail(setPricing, "Negative discount rejected", {
    data: {studentId: "s1", subjectId: "sub1", priceEgp: 100, discountEgp: -1},
    auth: doctorAuth,
  }, "invalid-argument");
  await checkFail(setPricing, "Discount above price rejected", {
    data: {studentId: "s1", subjectId: "sub1", priceEgp: 100, discountEgp: 101},
    auth: doctorAuth,
  }, "invalid-argument");
  await checkFail(setPricing, "Missing discount rejected", {
    data: {studentId: "s1", subjectId: "sub1", priceEgp: 100},
    auth: doctorAuth,
  }, "invalid-argument");

  // 6. Client cannot control Net: bogus client net is ignored.
  resetStore();
  const withBogusNet = await checkPass(setPricing, "Bogus client net ignored", {
    data: {studentId: "s1", subjectId: "sub1", priceEgp: 100, discountEgp: 50, netEgp: 9999, net_egp: 9999},
    auth: doctorAuth,
  });
  assert.equal(withBogusNet.netEgp, 50);
  assert.equal(store["student_subject_pricing"]["s1_sub1"].net_egp, 50);
  console.log("ok - client net ignored, server Net stored");

  // 8+9+10. Correction on the SAME doc preserves linkage/created_*, updates updated_*.
  resetStore();
  seedDoc("student_subject_pricing", "s1_sub1", {
    student_id: "s1",
    subject_id: "sub1",
    price_egp: 500,
    discount_egp: 50,
    net_egp: 450,
    created_at: "ORIGINAL_TS",
    updated_at: "OLD_TS",
    created_by: "doctor-1",
    updated_by: "doctor-1",
    is_deleted: false,
    deleted_at: null,
    deleted_by: null,
  });
  const corrected = await checkPass(setPricing, "Doctor corrects pricing (same ID)", {
    data: {studentId: "s1", subjectId: "sub1", priceEgp: 100, discountEgp: 50},
    auth: doctor2Auth,
  });
  assert.equal(corrected.pricingId, "s1_sub1");
  assert.equal(corrected.netEgp, 50);
  const after = store["student_subject_pricing"]["s1_sub1"];
  assert.equal(after.price_egp, 100);
  assert.equal(after.discount_egp, 50);
  assert.equal(after.net_egp, 50);
  assert.equal(after.student_id, "s1");
  assert.equal(after.subject_id, "sub1");
  assert.equal(after.created_at, "ORIGINAL_TS");
  assert.equal(after.created_by, "doctor-1");
  assert.equal(after.updated_by, "doctor-2");
  assert.deepEqual(after.updated_at, {_serverTimestamp: true});
  assert.ok(!("netEgp" in after));
  console.log("ok - correction same-ID, linkage/created_* preserved, updated_* refreshed");

  // 11 (correct). Before/after audit exists on correction.
  const corrAudits = writes.filter((w) => w.collection === "admin_audit_log");
  assert.equal(corrAudits.length, 1);
  assert.equal(corrAudits[0].data.action, "subject_pricing_updated");
  assert.equal(corrAudits[0].data.entity, "student_subject_pricing");
  assert.equal(corrAudits[0].data.student_id, "s1");
  assert.equal(corrAudits[0].data.subject_id, "sub1");
  assert.deepEqual(corrAudits[0].data.before, {price_egp: 500, discount_egp: 50, net_egp: 450});
  assert.deepEqual(corrAudits[0].data.after, {price_egp: 100, discount_egp: 50, net_egp: 50});
  assert.equal(corrAudits[0].data.actor_id, "doctor-2");
  assert.equal(corrAudits[0].data.actor_role, "doctor");
  assert.equal(corrAudits[0].data.permission_basis, "doctor");
  console.log("ok - correction before/after audit correct");

  // 12. Correction touched no finance/subscription collections.
  assertSeparation("correction separation");

  // 13. No payment cap is evaluated: pricing Net may sit below already-paid
  // student totals and below the student account Net without rejection.
  resetStore();
  seedDoc("student_financial_accounts", "s1", {
    student_id: "s1", price_egp: 1000, discount_egp: 0,
    net_egp: 1000, is_deleted: false,
  });
  seedDoc("payment_logs", "pay-1", {
    student_id: "s1", amount: 900, is_deleted: false,
  });
  await checkPass(setPricing, "Pricing below paid total accepted (no cap)", {
    data: {studentId: "s1", subjectId: "sub1", priceEgp: 100, discountEgp: 50},
    auth: doctorAuth,
  });
  assert.equal(store["student_subject_pricing"]["s1_sub1"].net_egp, 50);
  assert.equal(store["student_financial_accounts"]["s1"].net_egp, 1000);
  assert.equal(store["payment_logs"]["pay-1"].amount, 900);
  console.log("ok - no payment cap evaluated; finance records untouched");

  test.cleanup();

  if (process.exitCode === 1) {
    console.error("subject_pricing tests FAILED");
    process.exit(1);
  }
  console.log(`subject_pricing.test: PASS - All ${passed} checks passed.`);
}

run();
