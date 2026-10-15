/**
 * admin_claims_merge.test.js — merge-preserving custom claims on
 * addAdmin/removeAdmin (mirrors changePassword/syncStaffStoredClaims).
 *
 * Runs against compiled ../lib/index.js with an in-memory Firestore/Auth
 * mock (same pattern as password_reset.test.js). No emulator, no network.
 *
 * Verified behaviors:
 *  1. addAdmin sets role=admin + approved=true (doctor-only).
 *  2. addAdmin preserves unrelated stored claims (max_devices,
 *     force_password_change, student_type) instead of stripping them.
 *  3. removeAdmin sets role=student + approved=false (doctor-only).
 *  4. removeAdmin preserves unrelated stored claims.
 *  5. addAdmin refuses to reassign the doctor account.
 *  6. removeAdmin refuses non-admin targets.
 */
const test = require("firebase-functions-test")({
  projectId: "dr-tarek-platform-functions-test",
});

const assert = require("node:assert/strict");

const store = {};
const captured = { claims: [], audit: [] };

function docRef(collPath, docId) {
  const key = `${collPath}/${docId}`;
  return {
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

const EXISTING_CLAIMS = {
  role: "student",
  approved: false,
  max_devices: 5,
  force_password_change: false,
  student_type: "center_student",
};

const adminMock = {
  initializeApp: () => ({}),
  getFirestore: () => ({
    collection: (collPath) => ({
      where: () => ({
        limit: () => ({ get: async () => ({ empty: true, docs: [] }) }),
        get: async () => ({ empty: true, docs: [] }),
      }),
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
  Timestamp: {
    now: () => ({ toMillis: () => Date.now() }),
    fromDate: (d) => ({ toMillis: () => d.getTime(), toDate: () => d }),
    fromMillis: (ms) => ({ toMillis: () => ms, toDate: () => new Date(ms) }),
  },
  getAuth: () => ({
    updateUser: async () => {},
    getUser: async () => ({ customClaims: { ...EXISTING_CLAIMS } }),
    setCustomUserClaims: async (uid, claims) => {
      captured.claims.push({ uid, claims });
    },
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

const addAdmin = test.wrap(functions.addAdmin);
const removeAdmin = test.wrap(functions.removeAdmin);

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

  store["users/student-1"] = { role: "student", approval_status: "approved" };
  store["users/admin-1"] = { role: "admin", approval_status: "approved" };
  store["users/doctor-1"] = { role: "doctor", approval_status: "approved" };

  // 1+2: addAdmin sets admin claims and preserves unrelated keys.
  try {
    const res = await addAdmin({ data: { userId: "student-1", permissions: {} }, auth: doctorAuth });
    if (res && res.success === true) ok("addAdmin succeeds (doctor)");
    else fail("addAdmin", JSON.stringify(res));
  } catch (err) {
    fail("addAdmin", `${err.code}: ${err.message}`);
  }
  const added = captured.claims.find((c) => c.uid === "student-1");
  if (added && added.claims.role === "admin" && added.claims.approved === true) {
    ok("addAdmin sets role=admin, approved=true");
  } else {
    fail("addAdmin-claims", JSON.stringify(added));
  }
  if (
    added &&
    added.claims.max_devices === 5 &&
    added.claims.force_password_change === false &&
    added.claims.student_type === "center_student"
  ) {
    ok("addAdmin preserves unrelated stored claims");
  } else {
    fail("addAdmin-merge", JSON.stringify(added && added.claims));
  }

  // 3+4: removeAdmin demotes and preserves unrelated keys.
  try {
    const res = await removeAdmin({ data: { userId: "admin-1" }, auth: doctorAuth });
    if (res && res.success === true) ok("removeAdmin succeeds (doctor)");
    else fail("removeAdmin", JSON.stringify(res));
  } catch (err) {
    fail("removeAdmin", `${err.code}: ${err.message}`);
  }
  const removed = captured.claims.find((c) => c.uid === "admin-1");
  if (removed && removed.claims.role === "student" && removed.claims.approved === false) {
    ok("removeAdmin sets role=student, approved=false");
  } else {
    fail("removeAdmin-claims", JSON.stringify(removed));
  }
  if (removed && removed.claims.max_devices === 5 && removed.claims.student_type === "center_student") {
    ok("removeAdmin preserves unrelated stored claims");
  } else {
    fail("removeAdmin-merge", JSON.stringify(removed && removed.claims));
  }

  // 5: doctor account cannot be reassigned.
  try {
    await addAdmin({ data: { userId: "doctor-1", permissions: {} }, auth: doctorAuth });
    fail("doctor-guard", "expected failure, got success");
  } catch (err) {
    if (err.code === "failed-precondition") ok("addAdmin refuses doctor reassignment");
    else fail("doctor-guard", `${err.code}: ${err.message}`);
  }

  // 6: non-admin target cannot be removed as admin (fresh non-admin doc;
  // student-1 was already promoted by the addAdmin case above).
  store["users/student-9"] = { role: "student", approval_status: "approved" };
  try {
    await removeAdmin({ data: { userId: "student-9" }, auth: doctorAuth });
    fail("nonadmin-guard", "expected failure, got success");
  } catch (err) {
    if (err.code === "failed-precondition") ok("removeAdmin refuses non-admin target");
    else fail("nonadmin-guard", `${err.code}: ${err.message}`);
  }

  test.cleanup();

  if (process.exitCode === 1) {
    console.error("admin_claims_merge tests FAILED");
    process.exit(1);
  }
  console.log(`admin_claims_merge.test: PASS - All ${passed} checks passed.`);
}

run();
