/**
 * free_plan_activation.test.js — duplicate protection for activateFreePlan
 * (approved single-operator hardening against double-click / retry).
 *
 * Mechanism under test: the active-subscription existence check and the
 * creation run inside one Firestore transaction, so duplicate submissions
 * resolve to the single active subscription (established alreadyActive
 * convention preserved).
 *
 * Runs against compiled ../lib/index.js with an in-memory Firestore/Auth
 * mock (same pattern as password_reset.test.js). No emulator, no network.
 *
 * Verified behaviors:
 *  1. First activation succeeds (one active sub, fields intact).
 *  2. Repeat -> same subscriptionId, alreadyActive true, still one sub.
 *  3. Concurrent duplicate activations -> single active subscription.
 *  4. Different subject -> new subscription (not incorrectly collapsed).
 *  5. Subscription fields unchanged (status/renewal_count/plan/audit).
 *  6. Authorization intact (student denied).
 */
const test = require("firebase-functions-test")({
  projectId: "dr-tarek-platform-functions-test",
});

const assert = require("node:assert/strict");

const store = {};
const writes = [];
let txQueue = Promise.resolve();

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
        limit: () => ({get: async () => applyWheres(collPath, filters)}),
        get: async () => applyWheres(collPath, filters),
      });
      return {
        limit: () => ({
          get: async () => {
            const docs = Object.entries(store[collPath] || {})
              .slice(0, 1)
              .map(([id, data]) => ({id, data: () => data, ref: {id}}));
            return {empty: docs.length === 0, docs};
          },
        }),
        doc: (docId) => {
          const id = docId || `${collPath}-doc-${writes.length}`;
          return {
            id,
            get: async () => {
              const docData = (store[collPath] || {})[id];
              if (docData === undefined) return {exists: false};
              return {exists: true, data: () => docData};
            },
            update: async (data) => {
              if ((store[collPath] || {})[id] !== undefined) {
                store[collPath][id] = {...store[collPath][id], ...data};
              }
              writes.push({collection: collPath, id, update: data});
            },
            set: async (data) => {
              if (!store[collPath]) store[collPath] = {};
              store[collPath][id] = data;
              writes.push({collection: collPath, id, data});
            },
          };
        },
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
    // Serialized runner: emulates Firestore's serializable transaction
    // execution (contenders observe committed writes; real retries would
    // only strengthen this). Required for the concurrent-duplicate case.
    runTransaction: (fn) => {
      const txRef = (ref) => ref;
      const tx = {
        get: (ref) => txRef(ref).get(),
        update: (ref, data) => txRef(ref).update(data),
        set: (ref, data, options) => txRef(ref).set(data, options),
      };
      const result = txQueue.then(() => fn(tx));
      txQueue = result.catch(() => {});
      return result;
    },
  }),
  FieldValue: {serverTimestamp: () => ({_serverTimestamp: true})},
  Timestamp: class MockTimestamp {
    constructor(ms) {
      this.ms = ms;
    }
    toMillis() {
      return this.ms;
    }
    toDate() {
      return new Date(this.ms);
    }
    static now() {
      return new MockTimestamp(Date.now());
    }
    static fromDate(d) {
      return new MockTimestamp(d.getTime());
    }
    static fromMillis(ms) {
      return new MockTimestamp(ms);
    }
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

const wrapped = test.wrap(functions.activateFreePlan);

const doctorAuth = {uid: "doctor-1", token: {role: "doctor"}};
const studentAuth = {uid: "student-1", token: {role: "student"}};

function seedCommon() {
  seedDoc("users", "student-1", {student_type: "center_student"});
  seedDoc("subjects", "subj-1", {is_deleted: false});
  seedDoc("subjects", "subj-2", {is_deleted: false});
  seedDoc("subject_access_assignments", "student-1_subj-1", {
    student_id: "student-1",
    subject_id: "subj-1",
    is_deleted: false,
    enabled: true,
  });
  seedDoc("subject_access_assignments", "student-1_subj-2", {
    student_id: "student-1",
    subject_id: "subj-2",
    is_deleted: false,
    enabled: true,
  });
  seedDoc("system_settings", "default", {free_plan_enabled: true, default_plan: "free"});
  seedDoc("plans", "plan-free", {plan_key: "free", student_type: "center_student", is_active: true});
  seedDoc("academic_periods", "term-1", {is_core: true, status: "active", display_order: 1});
}

function activeSubs(studentId, subjectId) {
  return Object.entries(store["subscriptions"] || {}).filter(
    ([_, d]) => d.student_id === studentId && d.subject_id === subjectId && d.status === "active",
  );
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

  // 1: first activation succeeds with intact fields.
  resetStore();
  seedCommon();
  let firstId = null;
  try {
    const res = await wrapped({
      data: {studentId: "student-1", subjectId: "subj-1", studentType: "center_student"},
      auth: doctorAuth,
    });
    assert.equal(res.alreadyActive, false);
    assert.ok(res.subscriptionId);
    firstId = res.subscriptionId;
    ok("first activation succeeds");
  } catch (err) {
    fail("first", `${err.code}: ${err.message}`);
  }
  const created = (store["subscriptions"] || {})[firstId];
  if (
    created &&
    created.status === "active" &&
    created.renewal_count === 0 &&
    created.plan_id === "plan-free" &&
    created.student_id === "student-1" &&
    created.subject_id === "subj-1"
  ) {
    ok("subscription fields intact");
  } else {
    fail("fields", JSON.stringify(created));
  }
  if (activeSubs("student-1", "subj-1").length === 1) ok("exactly one active subscription");
  else fail("one-sub", "unexpected active count");

  // 2: repeat -> same ID, alreadyActive, still one sub, no new analytics.
  const analyticsBefore = writes.filter((w) => w.collection === "analytics_events").length;
  try {
    const res = await wrapped({
      data: {studentId: "student-1", subjectId: "subj-1", studentType: "center_student"},
      auth: doctorAuth,
    });
    assert.equal(res.alreadyActive, true);
    assert.equal(res.subscriptionId, firstId);
    ok("repeat returns same ID with alreadyActive");
  } catch (err) {
    fail("repeat", `${err.code}: ${err.message}`);
  }
  if (activeSubs("student-1", "subj-1").length === 1) ok("repeat creates no second subscription");
  else fail("no-dup", "duplicate subscription created");
  if (writes.filter((w) => w.collection === "analytics_events").length === analyticsBefore) {
    ok("repeat emits no duplicate analytics");
  } else {
    fail("no-dup-analytics", "duplicate analytics emitted");
  }

  // 3: concurrent duplicates converge.
  resetStore();
  seedCommon();
  const results = await Promise.all([
    wrapped({data: {studentId: "student-1", subjectId: "subj-1", studentType: "center_student"}, auth: doctorAuth}),
    wrapped({data: {studentId: "student-1", subjectId: "subj-1", studentType: "center_student"}, auth: doctorAuth}),
  ]);
  if (activeSubs("student-1", "subj-1").length === 1 && results[0].subscriptionId === results[1].subscriptionId) {
    ok("concurrent duplicates converge on one subscription");
  } else {
    fail("concurrent", `count=${activeSubs("student-1", "subj-1").length}`);
  }

  // 4: different subject is not collapsed.
  try {
    const res = await wrapped({
      data: {studentId: "student-1", subjectId: "subj-2", studentType: "center_student"},
      auth: doctorAuth,
    });
    assert.equal(res.alreadyActive, false);
    ok("different subject creates its own subscription");
  } catch (err) {
    fail("separate", `${err.code}: ${err.message}`);
  }
  if (activeSubs("student-1", "subj-2").length === 1) ok("separate subject not blocked");
  else fail("separate-count", "unexpected");

  // 5: deterministic settings lookup — the gate is read from the
  // canonical system_settings/default document, never an unordered
  // first document. The decoy is seeded FIRST so that even an
  // insertion-ordered limit(1) read would pick it (old behavior).
  resetStore();
  seedDoc("system_settings", "settings-1", {free_plan_enabled: false, default_plan: "pro"});
  seedCommon();
  try {
    const res = await wrapped({
      data: {studentId: "student-1", subjectId: "subj-1", studentType: "center_student"},
      auth: doctorAuth,
    });
    assert.equal(res.alreadyActive, false);
    ok("decoy settings doc does not shadow system_settings/default");
  } catch (err) {
    fail("decoy-shadow", `${err.code}: ${err.message}`);
  }

  // 5b: reverse direction — gate OFF in default blocks activation even
  // when a decoy doc has it ON (proves default is authoritative).
  resetStore();
  seedCommon();
  store["system_settings"]["default"] = {free_plan_enabled: false, default_plan: "free"};
  seedDoc("system_settings", "settings-1", {free_plan_enabled: true, default_plan: "free"});
  try {
    await wrapped({
      data: {studentId: "student-1", subjectId: "subj-1", studentType: "center_student"},
      auth: doctorAuth,
    });
    fail("gate-off", "expected failure, got success");
  } catch (err) {
    if (err.code === "failed-precondition") ok("gate OFF in default blocks activation despite enabled decoy");
    else fail("gate-off", `unexpected ${err.code}: ${err.message}`);
  }

  // 6: authorization intact.
  try {
    await wrapped({
      data: {studentId: "student-1", subjectId: "subj-1", studentType: "center_student"},
      auth: studentAuth,
    });
    fail("authz", "expected failure, got success");
  } catch (err) {
    if (err.code === "permission-denied") ok("student denied");
    else fail("authz", `unexpected ${err.code}`);
  }

  test.cleanup();

  if (process.exitCode === 1) {
    console.error("free_plan_activation tests FAILED");
    process.exit(1);
  }
  console.log(`free_plan_activation.test: PASS - All ${passed} checks passed.`);
}

run();
