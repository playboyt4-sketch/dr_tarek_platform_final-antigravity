/**
 * acceptance_notification.test.js — onStudentApproved acceptance notification
 * contract (Arabic copy, deterministic idempotency, deleted/disabled guard).
 *
 * Runs against compiled ../lib/index.js with an in-memory Firestore/Auth mock
 * (same pattern as student_claims_sync.test.js). No emulator, no network.
 *
 * Verified behaviors:
 *  1. A pending -> approved transition writes exactly one notification with the
 *     required Arabic title/body, critical priority, and /home deep link.
 *  2. The deterministic document id (`approval_{userId}`) makes a retried
 *     trigger a no-op: still one notification, no duplicate.
 *  3. A soft-deleted approval never notifies.
 *  4. A disabled approval never notifies.
 *  5. An already-approved record never re-notifies.
 */
const test = require("firebase-functions-test")({
  projectId: "dr-tarek-platform-functions-test",
});

const assert = require("node:assert/strict");

const store = {};
const claimsWrites = [];

function matches(data, [field, op, value]) {
  if (op === "==") return data[field] === value;
  if (op === "in") return Array.isArray(value) && value.includes(data[field]);
  return false;
}

function runQuery(collPath, filters, limit) {
  let docs = Object.entries(store[collPath] || {})
    .filter(([, data]) => filters.every((f) => matches(data, f)))
    .map(([id, data]) => ({id, data: () => data}));
  if (typeof limit === "number") docs = docs.slice(0, limit);
  return {empty: docs.length === 0, docs};
}

function queryFor(collPath, filters = [], limit) {
  return {
    where: (field, op, value) => queryFor(collPath, [...filters, [field, op, value]], limit),
    limit: (n) => queryFor(collPath, filters, n),
    get: async () => runQuery(collPath, filters, limit),
  };
}

function docRef(collPath, docId) {
  const id = docId;
  return {
    id,
    get: async () => {
      const data = (store[collPath] || {})[id];
      return data === undefined ? {exists: false} : {exists: true, data: () => data};
    },
    set: async (data) => {
      if (!store[collPath]) store[collPath] = {};
      store[collPath][id] = {...data};
    },
    create: async (data) => {
      if (!store[collPath]) store[collPath] = {};
      if (store[collPath][id] !== undefined) {
        const error = new Error(`Document already exists: ${collPath}/${id}`);
        error.code = 6;
        throw error;
      }
      store[collPath][id] = {...data};
    },
    update: async (data) => {
      if (!store[collPath]) store[collPath] = {};
      store[collPath][id] = {...(store[collPath][id] || {}), ...data};
    },
  };
}

const adminMock = {
  initializeApp: () => ({}),
  getFirestore: () => ({
    collection: (collPath) => ({
      where: (field, op, value) => queryFor(collPath, [[field, op, value]]),
      doc: (docId) => docRef(collPath, docId),
      add: async (data) => {
        const id = `${collPath}-doc-${Object.keys(store[collPath] || {}).length}`;
        if (!store[collPath]) store[collPath] = {};
        store[collPath][id] = {...data};
        return {id};
      },
      get: async () => runQuery(collPath, [], undefined),
    }),
  }),
  FieldValue: {serverTimestamp: () => ({__serverTimestamp: true})},
  Timestamp: {
    now: () => ({toMillis: () => Date.now()}),
    fromDate: (d) => ({toMillis: () => d.getTime(), toDate: () => d}),
    fromMillis: (ms) => ({toMillis: () => ms, toDate: () => new Date(ms)}),
  },
  getAuth: () => ({
    setCustomUserClaims: async (uid, claims) => {
      claimsWrites.push({uid, claims});
    },
    getUser: async () => ({customClaims: {}}),
    updateUser: async () => {},
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

const onStudentApproved = test.wrap(functions.onStudentApproved);

const TITLE = "تم قبول طلب تسجيلك";
const BODY =
  "تم قبول تسجيلك بنجاح في Dr. Tarek Platform. يمكنك الآن تسجيل الدخول والاستفادة من المحتوى الدراسي.";

function resetStore() {
  for (const k of Object.keys(store)) delete store[k];
  claimsWrites.length = 0;
}

function seed() {
  store.system_settings = {
    default: {
      free_plan_enabled: true,
      default_plan: "free",
    },
  };
  store.plans = {
    "plan-free": {
      plan_key: "free",
      student_type: "center_student",
      is_active: true,
    },
  };
  store.plan_features = {
    "feature-devices": {
      plan_id: "plan-free",
      feature_key: "device.max_count",
      feature_value: 1,
    },
  };
  store.users = {
    "student-1": {
      role: "new_student",
      approval_status: "pending",
      student_type: "center_student",
      is_deleted: false,
      account_status: "active",
    },
  };
}

function event(beforeData, afterData, userId = "student-1") {
  return {
    params: {userId},
    data: {
      before: test.firestore.makeDocumentSnapshot(beforeData, `users/${userId}`),
      after: test.firestore.makeDocumentSnapshot(afterData, `users/${userId}`),
    },
  };
}

const pending = {
  role: "new_student",
  approval_status: "pending",
  student_type: "center_student",
  is_deleted: false,
  account_status: "active",
};
const approved = {
  role: "student",
  approval_status: "approved",
  student_type: "center_student",
  is_deleted: false,
  account_status: "active",
};

function notifications() {
  return Object.entries(store.notifications || {});
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

  // 1 + 2: one Arabic notification, deterministic id, retry-safe.
  resetStore();
  seed();
  try {
    await onStudentApproved(event(pending, approved));
    const rows = notifications();
    if (rows.length !== 1) {
      fail("single-notification", `expected 1, got ${rows.length}`);
    } else {
      const [id, data] = rows[0];
      assert.equal(id, "approval_student-1");
      assert.equal(data.user_id, "student-1");
      assert.equal(data.notification_type, "system");
      assert.equal(data.title, TITLE);
      assert.equal(data.body, BODY);
      assert.equal(data.priority, "critical");
      assert.equal(data.deep_link, "/home");
      assert.equal(data.delivery_status, "pending");
      assert.equal(data.is_read, false);
      ok("approval writes the exact Arabic acceptance notification");
    }
  } catch (err) {
    fail("approval", `${err.code}: ${err.message}`);
  }

  try {
    await onStudentApproved(event(pending, approved));
    if (notifications().length === 1) ok("retried trigger does not duplicate the notification");
    else fail("idempotent", `got ${notifications().length} notifications`);
  } catch (err) {
    fail("retry", `${err.code}: ${err.message}`);
  }

  // 3: a legacy acceptance notification (random id, pre-deterministic deploy)
  // blocks a duplicate on re-approval.
  resetStore();
  seed();
  store.notifications = {
    "legacy-notification-id": {
      user_id: "student-1",
      notification_type: "system",
      title: TITLE,
      body: BODY,
      delivery_status: "in_app_only",
    },
  };
  try {
    await onStudentApproved(event(pending, approved));
    const rows = notifications();
    if (rows.length === 1 && rows[0][0] === "legacy-notification-id") {
      ok("legacy acceptance notification blocks a duplicate");
    } else {
      fail("legacy-idempotent", JSON.stringify(rows.map((r) => r[0])));
    }
  } catch (err) {
    fail("legacy", `${err.code}: ${err.message}`);
  }

  // 4: soft-deleted account never notifies.
  resetStore();
  seed();
  const claimsBeforeDeleted = claimsWrites.length;
  try {
    await onStudentApproved(event(pending, {...approved, is_deleted: true, account_status: "disabled"}));
    if (notifications().length === 0) ok("soft-deleted approval never notifies");
    else fail("deleted-guard", JSON.stringify(notifications()));
    if (claimsWrites.length === claimsBeforeDeleted) ok("soft-deleted approval writes no claims");
    else fail("deleted-claims", JSON.stringify(claimsWrites));
  } catch (err) {
    fail("deleted", `${err.code}: ${err.message}`);
  }

  // 5: disabled account never notifies.
  resetStore();
  seed();
  try {
    await onStudentApproved(event(pending, {...approved, account_status: "disabled"}));
    if (notifications().length === 0) ok("disabled approval never notifies");
    else fail("disabled-guard", JSON.stringify(notifications()));
  } catch (err) {
    fail("disabled", `${err.code}: ${err.message}`);
  }

  // 6: already-approved record never re-notifies.
  resetStore();
  seed();
  try {
    await onStudentApproved(event(approved, {...approved, student_type: "center_student"}));
    if (notifications().length === 0) ok("already-approved update never re-notifies");
    else fail("already-approved", JSON.stringify(notifications()));
  } catch (err) {
    fail("already-approved-run", `${err.code}: ${err.message}`);
  }

  test.cleanup();

  if (process.exitCode === 1) {
    console.error("acceptance_notification tests FAILED");
    process.exit(1);
  }
  console.log(`acceptance_notification.test: PASS - All ${passed} checks passed.`);
}

run();
