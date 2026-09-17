/**
 * Approved student-level payment model — account + correction tests
 * (mocked Admin SDK, payments_student_level_database_change_authority.md).
 *
 * Covers setStudentFinancialAccount (teacher-only Financial Account with
 * discount <= price, net floor at already-paid student total) and
 * correctPaymentLog (teacher-only in-place correction preserving
 * student_id/created_by/created_at, with student-level over-Net re-check
 * excluding self; historical subject_id stays frozen/descriptive and
 * never affects the calculation).
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

if (typeof functions.setStudentSubjectAccount !== "undefined") {
  console.error("FAIL - setStudentSubjectAccount must not exist (retired).");
  process.exit(1);
}
console.log("ok - setStudentSubjectAccount absent (retired)");

const setAccount = test.wrap(functions.setStudentFinancialAccount);
const correctLog = test.wrap(functions.correctPaymentLog);

const teacherAuth = {uid: "teacher-1", token: {role: "teacher"}};
const adminAuth = {uid: "admin-1", token: {role: "admin"}};

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

  // ---- setStudentFinancialAccount (student-level, doc id == studentId) ----
  resetStore();
  const created = await checkPass(setAccount, "Account created", {
    data: {studentId: "s1", priceEgp: 500, discountEgp: 50},
    auth: teacherAuth,
  });
  assert.equal(created.accountId, "s1");
  assert.equal(created.netEgp, 450);
  const createdDoc = store["student_financial_accounts"]["s1"];
  assert.equal(createdDoc.student_id, "s1");
  assert.equal(createdDoc.price_egp, 500);
  assert.equal(createdDoc.discount_egp, 50);
  assert.equal(createdDoc.net_egp, 450);
  assert.equal(createdDoc.created_by, "teacher-1");
  assert.equal(createdDoc.updated_by, "teacher-1");
  assert.ok(!("subject_id" in createdDoc));
  const createdAudits = writes.filter((w) => w.collection === "admin_audit_log");
  assert.equal(createdAudits.length, 1);
  assert.equal(createdAudits[0].data.action, "financial_account_created");
  assert.equal(createdAudits[0].data.entity, "student_financial_accounts");
  console.log("ok - student financial account schema + audit correct");

  resetStore();
  await checkFail(setAccount, "Missing studentId rejected", {
    data: {priceEgp: 100, discountEgp: 0},
    auth: teacherAuth,
  }, "invalid-argument");
  await checkFail(setAccount, "Discount above price rejected", {
    data: {studentId: "s1", priceEgp: 100, discountEgp: 101},
    auth: teacherAuth,
  }, "invalid-argument");
  await checkFail(setAccount, "Negative price rejected", {
    data: {studentId: "s1", priceEgp: -1, discountEgp: 0},
    auth: teacherAuth,
  }, "invalid-argument");
  await checkFail(setAccount, "Negative discount rejected", {
    data: {studentId: "s1", priceEgp: 100, discountEgp: -1},
    auth: teacherAuth,
  }, "invalid-argument");
  await checkFail(setAccount, "Admin rejected", {
    data: {studentId: "s1", priceEgp: 100, discountEgp: 0},
    auth: adminAuth,
  }, "permission-denied");

  // Net floor uses the STUDENT-level paid total (subject tags ignored).
  resetStore();
  seedDoc("student_financial_accounts", "s1", {
    student_id: "s1", price_egp: 500, discount_egp: 0,
    net_egp: 500, created_by: "teacher-1", is_deleted: false,
  });
  seedDoc("payment_logs", "p1", {
    student_id: "s1", subject_id: "legacy-sub", amount: 400, is_deleted: false,
  });
  await checkFail(setAccount, "Narrowing below student paid rejected", {
    data: {studentId: "s1", priceEgp: 300, discountEgp: 0},
    auth: teacherAuth,
  }, "failed-precondition");
  const updated = await checkPass(setAccount, "Narrowing above paid accepted", {
    data: {studentId: "s1", priceEgp: 500, discountEgp: 50},
    auth: teacherAuth,
  });
  assert.equal(updated.netEgp, 450);
  assert.equal(store["student_financial_accounts"]["s1"].created_by, "teacher-1");
  assert.equal(store["student_financial_accounts"]["s1"].updated_by, "teacher-1");

  // ---- correctPaymentLog (student-level cap, self excluded) ----
  resetStore();
  seedDoc("student_financial_accounts", "s1", {
    student_id: "s1", price_egp: 1000, discount_egp: 0,
    net_egp: 1000, is_deleted: false,
  });
  seedDoc("payment_logs", "pay-1", {
    student_id: "s1", amount: 200,
    payment_method: "cash", collected_by: "teacher-1",
    receipt_number: "R-1", created_by: "teacher-1", is_deleted: false,
  });
  const corr = await checkPass(correctLog, "Partial correction", {
    data: {paymentId: "pay-1", amount: 250, collectorName: "Jo", paymentMethod: "e_wallet"},
    auth: teacherAuth,
  });
  assert.equal(corr.corrected, true);
  const after = store["payment_logs"]["pay-1"];
  assert.equal(after.amount, 250);
  assert.equal(after.collected_by, "Jo");
  assert.equal(after.payment_method, "e_wallet");
  assert.equal(after.created_by, "teacher-1");
  assert.equal(after.updated_by, "teacher-1");
  const corrAudits = writes.filter((w) => w.collection === "admin_audit_log");
  assert.equal(corrAudits.length, 1);
  assert.equal(corrAudits[0].data.action, "payment_corrected");
  assert.equal(corrAudits[0].data.before.amount, 200);
  assert.equal(corrAudits[0].data.after.amount, 250);

  // Historical subject_id memo stays frozen and out of the math.
  resetStore();
  seedDoc("student_financial_accounts", "s1", {
    student_id: "s1", price_egp: 1000, discount_egp: 0,
    net_egp: 1000, is_deleted: false,
  });
  seedDoc("payment_logs", "pay-sub", {
    student_id: "s1", subject_id: "legacy-sub", amount: 200,
    payment_method: "bank", collected_by: "Jo",
    receipt_number: "R-9", created_by: "teacher-1", is_deleted: false,
  });
  await checkPass(correctLog, "Correction keeps legacy subject frozen", {
    data: {paymentId: "pay-sub", amount: 250},
    auth: teacherAuth,
  });
  assert.equal(store["payment_logs"]["pay-sub"].subject_id, "legacy-sub");
  assert.equal(store["payment_logs"]["pay-sub"].amount, 250);
  console.log("ok - historical subject_id frozen/descriptive");

  // Bank correction accepted (approved method set).
  await checkPass(correctLog, "Bank correction accepted", {
    data: {paymentId: "pay-sub", paymentMethod: "Bank"},
    auth: teacherAuth,
  });
  assert.equal(store["payment_logs"]["pay-sub"].payment_method, "bank");

  await checkFail(correctLog, "Unknown id rejected", {
    data: {paymentId: "missing", amount: 10}, auth: teacherAuth,
  }, "not-found");
  await checkFail(correctLog, "Empty patch rejected", {
    data: {paymentId: "pay-sub"}, auth: teacherAuth,
  }, "invalid-argument");
  await checkFail(correctLog, "Future date rejected", {
    data: {paymentId: "pay-sub", paymentDate: "2999-01-01"}, auth: teacherAuth,
  }, "invalid-argument");
  await checkFail(correctLog, "Admin rejected", {
    data: {paymentId: "pay-sub", amount: 10}, auth: adminAuth,
  }, "permission-denied");

  // Student-level cap across mixed subjects, self excluded correctly.
  seedDoc("payment_logs", "pay-2", {
    student_id: "s1", subject_id: "sub-X", amount: 400, is_deleted: false,
  });
  seedDoc("payment_logs", "pay-3", {
    student_id: "s1", subject_id: "sub-Y", amount: 400, is_deleted: false,
  });
  // 400 + 400 + raise pay-sub (250) to 700 => 1500 > 1000: reject.
  await checkFail(correctLog, "Over-Net excluding self rejected", {
    data: {paymentId: "pay-sub", amount: 700}, auth: teacherAuth,
  }, "failed-precondition");
  await checkPass(correctLog, "Within-Net correction accepted", {
    data: {paymentId: "pay-sub", amount: 200}, auth: teacherAuth,
  });

  seedDoc("payment_logs", "pay-del", {
    student_id: "s1", amount: 10, is_deleted: true,
  });
  await checkFail(correctLog, "Deleted record rejected", {
    data: {paymentId: "pay-del", amount: 5}, auth: teacherAuth,
  }, "failed-precondition");

  test.cleanup();

  if (process.exitCode === 1) {
    console.error("payment_correction tests FAILED");
    process.exit(1);
  }
  console.log(`payment_correction.test: PASS - All ${passed} checks passed.`);
}

run();
