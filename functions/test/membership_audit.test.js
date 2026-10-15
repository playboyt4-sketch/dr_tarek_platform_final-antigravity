/**
 * membership_audit.test.js — admin_audit_log coverage for membership
 * plan changes (upgrade/downgrade via changeMembershipPlan, renew).
 *
 * Runs against compiled ../lib/index.js with an in-memory Firestore/Auth
 * mock (same pattern as password_reset.test.js). No emulator, no network.
 *
 * Verified behaviors:
 *  1. upgrade writes admin_audit_log action=membership_plan_changed with
 *     actor/target/subscription/previous/new plan attribution.
 *  2. renew writes admin_audit_log action=membership_renewed with
 *     actor/target/subscription attribution.
 *  3. plan change still applies (membership plan_id updated).
 */
const test = require("firebase-functions-test")({
  projectId: "dr-tarek-platform-functions-test",
});

const assert = require("node:assert/strict");

const store = {};
const captured = { audit: [] };

function docRef(collPath, docId) {
  const key = `${collPath}/${docId}`;
  return {
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
      if (store[key] !== undefined) store[key] = { ...store[key], ...data };
    },
  };
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

const upgrade = test.wrap(functions.upgrade);
const renew = test.wrap(functions.renew);

const doctorAuth = { uid: "doctor-1", token: { role: "doctor" } };

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

  store["users/stu-1"] = { role: "student", student_type: "center_student" };
  store["subscriptions/sub-1"] = {
    student_id: "stu-1",
    subject_id: "subj-1",
    status: "active",
    plan_id: "free",
    end_date: null,
  };
  store["plans/pro"] = { is_active: true, student_type: "center_student" };
  store["subject_access_assignments/stu-1_subj-1"] = {};
  store["academic_periods/term-1"] = { is_core: true, status: "active", display_order: 1, end_date: null };

  // 1+3: upgrade applies the plan change and audits it.
  try {
    const res = await upgrade({
      data: { studentId: "stu-1", subjectId: "subj-1", newPlanId: "pro" },
      auth: doctorAuth,
    });
    if (res && res.subscriptionId === "sub-1") ok("upgrade succeeds");
    else fail("upgrade", JSON.stringify(res));
  } catch (err) {
    fail("upgrade", `${err.code}: ${err.message}`);
  }
  if (store["subscriptions/sub-1"].plan_id === "pro") ok("membership plan_id updated");
  else fail("plan", JSON.stringify(store["subscriptions/sub-1"]));
  const changed = captured.audit.find((a) => a.action === "membership_plan_changed");
  if (
    changed &&
    changed.entity === "subscriptions" &&
    changed.target_id === "stu-1" &&
    changed.subscription_id === "sub-1" &&
    changed.previous_plan_id === "free" &&
    changed.new_plan_id === "pro" &&
    changed.actor_id === "doctor-1" &&
    changed.actor_role === "doctor"
  ) {
    ok("upgrade audit has full attribution");
  } else {
    fail("upgrade-audit", JSON.stringify(changed));
  }

  // 2: renew audits.
  try {
    const res = await renew({
      data: { studentId: "stu-1", subjectId: "subj-1" },
      auth: doctorAuth,
    });
    if (res && res.subscriptionId === "sub-1") ok("renew succeeds");
    else fail("renew", JSON.stringify(res));
  } catch (err) {
    fail("renew", `${err.code}: ${err.message}`);
  }
  const renewed = captured.audit.find((a) => a.action === "membership_renewed");
  if (
    renewed &&
    renewed.entity === "subscriptions" &&
    renewed.target_id === "stu-1" &&
    renewed.subscription_id === "sub-1" &&
    renewed.actor_id === "doctor-1" &&
    renewed.actor_role === "doctor"
  ) {
    ok("renew audit has full attribution");
  } else {
    fail("renew-audit", JSON.stringify(renewed));
  }

  test.cleanup();

  if (process.exitCode === 1) {
    console.error("membership_audit tests FAILED");
    process.exit(1);
  }
  console.log(`membership_audit.test: PASS - All ${passed} checks passed.`);
}

run();
