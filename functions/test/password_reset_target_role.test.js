/**
 * password_reset_target_role.test.js — onPasswordResetApproved target-role
 * hardening (residual item 11).
 *
 * Approved workflow is student-only, but approval previously never read
 * users/{target} and never checked the target role: a crafted/stale pending
 * request doc pointing at a doctor/admin UID would overwrite a STAFF
 * account's Auth password, claims, users doc, and secrets (staff-account
 * takeover via a delegated password_reset grant).
 *
 * Hardening: approval re-validates target exists AND target role is
 * student-kind (student/new_student). Doctor/admin targets are rejected
 * with permission-denied BEFORE any Auth/Firestore/secret write.
 *
 * Runs against compiled ../lib/index.js with an in-memory Firestore/Auth
 * mock (same pattern as password_reset.test.js). No emulator, no network.
 *
 * Verified behaviors:
 *  1. student target + doctor caller -> resolved.
 *  2. new_student target + doctor caller -> resolved.
 *  3. student target + delegated admin caller -> resolved.
 *  4. doctor target -> permission-denied, zero Auth writes.
 *  5. admin target -> permission-denied, zero Auth writes.
 *  6. missing target user -> not-found, zero Auth writes.
 *  7. legacy teacher target -> permission-denied (inert role, never reset).
 *  8. unauthorized caller (no grant) still denied (unchanged).
 *  9. weak temp password still invalid-argument (contract unchanged).
 */
const test = require("firebase-functions-test")({
  projectId: "dr-tarek-platform-functions-test",
});

const assert = require("node:assert/strict");

let dbMockData = {};
const captured = { updateUser: [], setClaims: [] };

const adminMock = {
  initializeApp: () => ({}),
  getFirestore: () => ({
    collection: (collPath) => ({
      doc: (docId) => {
        const key = `${collPath}/${docId}`;
        return {
          get: async () => {
            const docData = dbMockData[key];
            if (docData === undefined) return { exists: false };
            return { exists: true, data: () => docData };
          },
          update: async () => {},
          set: async (data, options) => {
            if (options && options.merge && dbMockData[key] !== undefined) {
              dbMockData[key] = { ...dbMockData[key], ...data };
            } else {
              dbMockData[key] = data;
            }
          },
        };
      },
      add: async () => ({ id: "mock-id" }),
    }),
    runTransaction: async (fn) => {
      const txRef = (ref) => ref;
      return fn({
        get: (ref) => txRef(ref).get(),
        update: (ref, data) => txRef(ref).update(data),
        set: (ref, data, options) => txRef(ref).set(data, options),
      });
    },
  }),
  FieldValue: { serverTimestamp: () => ({ _serverTimestamp: true }) },
  Timestamp: { now: () => ({ toMillis: () => Date.now() }) },
  getAuth: () => ({
    updateUser: async (uid, props) => {
      captured.updateUser.push({ uid, props });
    },
    getUser: async () => ({ customClaims: {} }),
    setCustomUserClaims: async (uid, claims) => {
      captured.setClaims.push({ uid, claims });
    },
    revokeRefreshTokens: async () => {},
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

const wrapped = test.wrap(functions.onPasswordResetApproved);

const doctorAuth = { uid: "doctor-1", token: { role: "doctor" } };
const delegatedAuth = { uid: "admin_delegated", token: { role: "admin" } };
const plainAdminAuth = { uid: "admin_plain", token: { role: "admin" } };
const STRONG = "Aa1!bcde";

function seedRequest(id, studentId) {
  dbMockData[`password_reset_requests/${id}`] = { status: "pending", student_id: studentId };
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

  dbMockData["admin_permissions/admin_delegated"] = {
    is_active: true,
    permissions: { "password_reset": true },
  };
  dbMockData["admin_permissions/admin_plain"] = {
    is_active: true,
    permissions: {},
  };
  dbMockData["users/student-1"] = { role: "student", approval_status: "approved" };
  dbMockData["users/newstudent-1"] = { role: "new_student", approval_status: "pending" };
  dbMockData["users/doctor-9"] = { role: "doctor", approval_status: "approved" };
  dbMockData["users/admin-9"] = { role: "admin", approval_status: "approved" };
  dbMockData["users/legacy-teacher"] = { role: "teacher", approval_status: "approved" };

  // 1-2: student-kind targets resolve.
  seedRequest("req-student", "student-1");
  try {
    const res = await wrapped({ data: { requestId: "req-student", newPassword: STRONG }, auth: doctorAuth });
    if (res && res.resolved === true) ok("student target + doctor caller -> resolved");
    else fail("student-pass", JSON.stringify(res));
  } catch (err) {
    fail("student-pass", `${err.code}: ${err.message}`);
  }
  seedRequest("req-newstudent", "newstudent-1");
  try {
    const res = await wrapped({ data: { requestId: "req-newstudent", newPassword: STRONG }, auth: doctorAuth });
    if (res && res.resolved === true) ok("new_student target + doctor caller -> resolved");
    else fail("newstudent-pass", JSON.stringify(res));
  } catch (err) {
    fail("newstudent-pass", `${err.code}: ${err.message}`);
  }

  // 3: delegated admin keeps legitimate student resets.
  seedRequest("req-delegated", "student-1");
  try {
    const res = await wrapped({ data: { requestId: "req-delegated", newPassword: STRONG }, auth: delegatedAuth });
    if (res && res.resolved === true) ok("student target + delegated admin caller -> resolved");
    else fail("delegated-pass", JSON.stringify(res));
  } catch (err) {
    fail("delegated-pass", `${err.code}: ${err.message}`);
  }

  // 4-7: staff/missing/legacy targets rejected with zero Auth writes.
  const attackCases = [
    ["req-doctor", "doctor-9", "doctor target -> permission-denied"],
    ["req-admin", "admin-9", "admin target -> permission-denied"],
    ["req-ghost", "ghost-uid", "missing target -> not-found"],
    ["req-legacy", "legacy-teacher", "legacy teacher target -> permission-denied"],
  ];
  for (const [reqId, target, label] of attackCases) {
    seedRequest(reqId, target);
    captured.updateUser.length = 0;
    captured.setClaims.length = 0;
    try {
      await wrapped({ data: { requestId: reqId, newPassword: STRONG }, auth: doctorAuth });
      fail(label, "expected failure, got success");
    } catch (err) {
      const want = target === "ghost-uid" ? "not-found" : "permission-denied";
      if (err.code !== want) {
        fail(label, `expected ${want}, got ${err.code}: ${err.message}`);
        continue;
      }
      if (captured.updateUser.length !== 0 || captured.setClaims.length !== 0) {
        fail(label, `Auth writes occurred: ${JSON.stringify(captured)}`);
        continue;
      }
      ok(`${label} (zero Auth writes)`);
    }
  }

  // 8: caller without grant still denied (unchanged contract).
  seedRequest("req-nogrant", "student-1");
  try {
    await wrapped({ data: { requestId: "req-nogrant", newPassword: STRONG }, auth: plainAdminAuth });
    fail("no-grant", "expected failure, got success");
  } catch (err) {
    if (err.code === "permission-denied") ok("caller without grant still denied");
    else fail("no-grant", `unexpected ${err.code}`);
  }

  // 9: weak temp password still invalid-argument (unchanged contract).
  try {
    await wrapped({ data: { requestId: "req-nogrant", newPassword: "weak" }, auth: doctorAuth });
    fail("weak-temp", "expected failure, got success");
  } catch (err) {
    if (err.code === "invalid-argument") ok("weak temp password still invalid-argument");
    else fail("weak-temp", `unexpected ${err.code}`);
  }

  test.cleanup();

  if (process.exitCode === 1) {
    console.error("password_reset_target_role tests FAILED");
    process.exit(1);
  }
  console.log(`password_reset_target_role.test: PASS - All ${passed} checks passed.`);
}

run();
