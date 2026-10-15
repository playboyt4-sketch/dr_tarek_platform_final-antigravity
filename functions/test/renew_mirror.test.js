/**
 * renew_mirror.test.js — renew syncs the subscription-expiry mirror.
 *
 * Expiry-drift fix: renew updates subscriptions.end_date but previously left
 * subject_access_assignments.subscription_expires_at stale, so the Rules
 * hasEntitlement gate (end_date semantics) could deny a renewed student.
 * renew now writes membership end_date and the assignment mirror with the
 * same binding value inside one transaction.
 *
 * Runs against compiled ../lib/index.js with an in-memory Firestore mock
 * (same pattern as membership_audit.test.js). No emulator, no network.
 *
 * Verified behaviors:
 *  1. renew writes subscriptions.end_date AND the assignment mirror with
 *     the same new value (ms-equal), increments renewal_count, keeps the
 *     same subscriptionId and return contract.
 *  2. re-executing renew creates NO second subscription doc, keeps exactly
 *     one active membership for the pair, and keeps the mirror synced.
 *  3. renew without an assignment row still succeeds (mirror step skipped,
 *     no stub row created) — unchanged behavior for that path.
 *  4. missing membership still fails not-found (lookup contract unchanged).
 */
const test = require("firebase-functions-test")({
  projectId: "dr-tarek-platform-functions-test",
});

const store = {};
const captured = { audit: [], analytics: [] };

function docRef(collPath, docId) {
  const key = `${collPath}/${docId}`;
  const ref = {
    id: docId,
    get: async () => {
      if (store[key] === undefined) return { exists: false };
      return { exists: true, data: () => store[key] };
    },
    set: async (data, options) => {
      if (options && options.merge && store[key] !== undefined) {
        store[key] = { ...store[key], ...data };
      } else {
        store[key] = { ...data };
      }
    },
    update: async (data) => {
      if (store[key] === undefined) throw new Error(`not-found: ${key}`);
      store[key] = { ...store[key], ...data };
    },
    delete: async () => {
      delete store[key];
    },
  };
  return ref;
}

function query(collPath, filters) {
  const docs = Object.entries(store)
    .filter(([key]) => key.startsWith(`${collPath}/`))
    .map(([key, data]) => ({ id: key.slice(collPath.length + 1), data: () => data, ref: docRef(collPath, key.slice(collPath.length + 1)) }))
    .filter((d) => filters.every(([f, op, v]) => (op === "==" ? d.data()[f] === v : false)));
  const q = {
    where: (f, op, v) => query(collPath, [...filters, [f, op, v]]),
    limit: () => q,
    get: async () => ({ empty: docs.length === 0, docs }),
  };
  return q;
}

const adminMock = {
  initializeApp: () => ({}),
  getFirestore: () => ({
    collection: (collPath) => ({
      where: (f, op, v) => query(collPath, [[f, op, v]]),
      doc: (docId) => docRef(collPath, docId),
      add: async (data) => {
        if (collPath === "admin_audit_log") captured.audit.push(data);
        if (collPath === "analytics_events") captured.analytics.push(data);
        return { id: "mock-id" };
      },
    }),
    runTransaction: async (fn) =>
      fn({
        get: (ref) => ref.get(),
        update: (ref, data) => ref.update(data),
        set: (ref, data, options) => ref.set(data, options),
      }),
    batch: () => ({ set: () => {}, update: () => {}, delete: () => {}, commit: async () => {} }),
  }),
  FieldValue: { serverTimestamp: () => ({}), delete: () => ({ __delete: true }) },
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
    getUser: async () => ({ customClaims: {} }),
    setCustomUserClaims: async () => {},
    createCustomToken: async () => "mock-token",
    createUser: async () => ({ uid: "new-uid" }),
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
  if (id === "firebase-admin/auth") return { getAuth: adminMock.getAuth };
  if (id === "firebase-admin/messaging") return { getMessaging: adminMock.getMessaging };
  if (id === "firebase-admin/storage") return { getStorage: adminMock.getStorage };
  if (id === "firebase-admin/app") return { initializeApp: adminMock.initializeApp };
  return originalRequire.apply(this, arguments);
};

let functions;
try {
  functions = require("../lib/index.js");
} catch (error) {
  console.error("Failed to load functions:", error);
  process.exit(1);
}

const renew = test.wrap(functions.renew);
const doctorAuth = { uid: "doctor-1", token: { role: "doctor" } };

const T_OLD = Date.now() - 30 * 24 * 60 * 60 * 1000;
const T_END = Date.now() + 60 * 24 * 60 * 60 * 1000;

function activeMemberships(studentId, subjectId) {
  return Object.entries(store).filter(
    ([key, data]) =>
      key.startsWith("subscriptions/") &&
      data.student_id === studentId &&
      data.subject_id === subjectId &&
      data.status === "active" &&
      data.is_deleted !== true,
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

  store["academic_periods/term-1"] = {
    is_core: true,
    status: "active",
    is_deleted: false,
    display_order: 1,
    end_date: new adminMock.Timestamp(T_END),
  };
  store["subscriptions/sub-1"] = {
    student_id: "student-1",
    subject_id: "subject-1",
    plan_id: "plan-pro",
    status: "active",
    is_deleted: false,
    end_date: new adminMock.Timestamp(T_OLD),
    renewal_count: 0,
  };
  store["subject_access_assignments/student-1_subject-1"] = {
    student_id: "student-1",
    subject_id: "subject-1",
    enabled: true,
    is_deleted: false,
    entitlements: ["notes.create"],
    subscription_expires_at: new adminMock.Timestamp(T_OLD),
  };

  // 1: renew writes end_date and mirror with the same new value.
  try {
    const res = await renew({
      data: { studentId: "student-1", subjectId: "subject-1" },
      auth: doctorAuth,
      rawRequest: {},
    });
    if (!res || res.subscriptionId !== "sub-1") fail("renew-once", `unexpected result ${JSON.stringify(res)}`);
    else {
      const sub = store["subscriptions/sub-1"];
      const mirror = store["subject_access_assignments/student-1_subject-1"].subscription_expires_at;
      let pass = true;
      if (!sub.end_date || sub.end_date.toMillis() !== T_END) {
        fail("renew-once", `end_date not renewed: ${sub.end_date && sub.end_date.toMillis()}`);
        pass = false;
      }
      if (!mirror || mirror.toMillis() !== T_END) {
        fail("renew-once", `mirror not synced: ${mirror && mirror.toMillis()}`);
        pass = false;
      }
      if (sub.end_date && mirror && sub.end_date.toMillis() !== mirror.toMillis()) {
        fail("renew-once", "end_date and mirror differ");
        pass = false;
      }
      if (sub.renewal_count !== 1) {
        fail("renew-once", `renewal_count ${sub.renewal_count}`);
        pass = false;
      }
      if (sub.status !== "active") {
        fail("renew-once", `status ${sub.status}`);
        pass = false;
      }
      if (pass) ok("renew writes end_date + mirror with the same value (renewal_count 1, same id)");
    }
  } catch (err) {
    fail("renew-once", `${err.code}: ${err.message}`);
  }

  // 2: re-execution creates no second subscription and keeps mirror synced.
  try {
    const res = await renew({
      data: { studentId: "student-1", subjectId: "subject-1" },
      auth: doctorAuth,
      rawRequest: {},
    });
    const actives = activeMemberships("student-1", "subject-1");
    let pass = true;
    if (!res || res.subscriptionId !== "sub-1") {
      fail("renew-twice", `unexpected result ${JSON.stringify(res)}`);
      pass = false;
    }
    if (actives.length !== 1) {
      fail("renew-twice", `expected exactly 1 active membership, found ${actives.length}`);
      pass = false;
    }
    const sub = store["subscriptions/sub-1"];
    const mirror = store["subject_access_assignments/student-1_subject-1"].subscription_expires_at;
    if (sub.end_date.toMillis() !== T_END || mirror.toMillis() !== T_END) {
      fail("renew-twice", "end_date/mirror drifted on re-execution");
      pass = false;
    }
    if (sub.renewal_count !== 2) {
      fail("renew-twice", `renewal_count ${sub.renewal_count}`);
      pass = false;
    }
    if (pass) ok("re-execution: exactly 1 membership, mirror still synced, same id");
  } catch (err) {
    fail("renew-twice", `${err.code}: ${err.message}`);
  }

  // 3: renew without an assignment row still succeeds and creates no stub.
  delete store["subject_access_assignments/student-1_subject-1"];
  try {
    const res = await renew({
      data: { studentId: "student-1", subjectId: "subject-1" },
      auth: doctorAuth,
      rawRequest: {},
    });
    if (!res || res.subscriptionId !== "sub-1") fail("renew-noassign", JSON.stringify(res));
    else if (store["subject_access_assignments/student-1_subject-1"] !== undefined) {
      fail("renew-noassign", "stub assignment row was created");
    } else if (store["subscriptions/sub-1"].end_date.toMillis() !== T_END) {
      fail("renew-noassign", "end_date not renewed");
    } else ok("renew without assignment row succeeds, mirror skipped, no stub created");
  } catch (err) {
    fail("renew-noassign", `${err.code}: ${err.message}`);
  }

  // 4: missing membership still not-found (lookup contract unchanged).
  try {
    await renew({
      data: { studentId: "ghost", subjectId: "subject-1" },
      auth: doctorAuth,
      rawRequest: {},
    });
    fail("renew-missing", "expected failure, got success");
  } catch (err) {
    if (err.code === "not-found") ok("missing membership still not-found");
    else fail("renew-missing", `unexpected ${err.code}`);
  }

  test.cleanup();

  if (process.exitCode === 1) {
    console.error("renew_mirror tests FAILED");
    process.exit(1);
  }
  console.log(`renew_mirror.test: PASS - All ${passed} checks passed.`);
}

run();
