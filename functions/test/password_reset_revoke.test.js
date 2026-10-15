/**
 * password_reset_revoke.test.js — mid-session staleness fix (approved).
 *
 * onPasswordResetApproved must call auth.revokeRefreshTokens(uid) AFTER the
 * password change (auth.updateUser) and the student reset data (claims,
 * users doc, user_secrets) are durably updated — never before — so a revoke
 * failure can never strand mismatched credentials. Existing sequential
 * error handling applies (no try/catch, consistent with the notification /
 * analytics / audit steps): a revoke failure propagates, the request stays
 * processing, and the same actor can reclaim and retry.
 *
 * Runs against compiled ../lib/index.js with an in-memory Firestore/Auth
 * mock (same pattern as password_reset.test.js). No emulator, no network.
 *
 * Verified behaviors:
 *  1. successful reset calls revokeRefreshTokens exactly once for the
 *     student uid, AFTER updateUser (call order asserted).
 *  2. force_password_change=true is still set (claims + users update path
 *     reached before revoke).
 *  3. revoke failure does NOT hide the password-change success: updateUser,
 *     claims, and user_secrets writes all happened before the throw; the
 *     error propagates (request stays processing/reclaimable).
 *  4. doctor/admin targets remain rejected with permission-denied and
 *     revoke is never called for them.
 */
const test = require("firebase-functions-test")({
  projectId: "dr-tarek-platform-functions-test",
});

let dbMockData = {};
const captured = { calls: [], updateUser: [], setClaims: [], revoke: [] };
let revokeBehavior = "ok";

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
            if (collPath === "user_secrets") captured.calls.push(`secrets:${docId}`);
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
      captured.calls.push(`updateUser:${uid}`);
      captured.updateUser.push({ uid, props });
    },
    getUser: async () => ({ customClaims: {} }),
    setCustomUserClaims: async (uid, claims) => {
      captured.calls.push(`setClaims:${uid}`);
      captured.setClaims.push({ uid, claims });
    },
    revokeRefreshTokens: async (uid) => {
      captured.calls.push(`revoke:${uid}`);
      captured.revoke.push(uid);
      if (revokeBehavior === "fail") throw new Error("revoke-transport-failure");
    },
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
const STRONG = "Aa1!bcde";

function resetCapture() {
  captured.calls.length = 0;
  captured.updateUser.length = 0;
  captured.setClaims.length = 0;
  captured.revoke.length = 0;
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

  dbMockData["users/student-1"] = { role: "student", approval_status: "approved" };
  dbMockData["users/doctor-9"] = { role: "doctor", approval_status: "approved" };
  dbMockData["users/admin-9"] = { role: "admin", approval_status: "approved" };
  dbMockData["user_secrets/student-1"] = { password_hash: "old-hash" };

  // 1+2: revoke after updateUser; force flag still set.
  dbMockData["password_reset_requests/req-ok"] = { status: "pending", student_id: "student-1" };
  resetCapture();
  try {
    const res = await wrapped({ data: { requestId: "req-ok", newPassword: STRONG }, auth: doctorAuth });
    if (!res || res.resolved !== true) {
      fail("revoke-order", JSON.stringify(res));
    } else {
      const updateIdx = captured.calls.indexOf("updateUser:student-1");
      const revokeIdx = captured.calls.indexOf("revoke:student-1");
      let pass = true;
      if (captured.revoke.length !== 1 || captured.revoke[0] !== "student-1") {
        fail("revoke-order", `revoke calls: ${JSON.stringify(captured.revoke)}`);
        pass = false;
      }
      if (updateIdx === -1 || revokeIdx === -1 || !(updateIdx < revokeIdx)) {
        fail("revoke-order", `order violated: ${JSON.stringify(captured.calls)}`);
        pass = false;
      }
      const claims = captured.setClaims.find((c) => c.uid === "student-1");
      if (!claims || claims.claims.force_password_change !== true) {
        fail("revoke-order", `force flag missing: ${JSON.stringify(captured.setClaims)}`);
        pass = false;
      }
      if (!captured.calls.some((c) => c === "secrets:student-1")) {
        fail("revoke-order", "user_secrets write missing before resolve");
        pass = false;
      }
      if (pass) ok("revoke called once for student AFTER updateUser; force_password_change=true; secrets written");
    }
  } catch (err) {
    fail("revoke-order", `${err.code}: ${err.message}`);
  }

  // 3: revoke failure propagates but does not hide the password-change success.
  dbMockData["password_reset_requests/req-revoke-fail"] = { status: "pending", student_id: "student-1" };
  dbMockData["user_secrets/student-1"] = { password_hash: "old-hash" };
  revokeBehavior = "fail";
  resetCapture();
  try {
    await wrapped({ data: { requestId: "req-revoke-fail", newPassword: STRONG }, auth: doctorAuth });
    fail("revoke-fail", "expected failure, got success");
  } catch (err) {
    const updateDone = captured.updateUser.some((u) => u.uid === "student-1");
    const claimsDone = captured.setClaims.some(
      (c) => c.uid === "student-1" && c.claims.force_password_change === true,
    );
    const secretsDone =
      dbMockData["user_secrets/student-1"] &&
      typeof dbMockData["user_secrets/student-1"].password_hash === "string" &&
      dbMockData["user_secrets/student-1"].password_hash !== "old-hash";
    if (!updateDone || !claimsDone || !secretsDone) {
      fail(
        "revoke-fail",
        `password-change success hidden (update:${updateDone} claims:${claimsDone} secrets:${secretsDone}); err=${err.code}`,
      );
    } else {
      ok(`revoke failure propagates (${err.code || "transport-error"}) with password change + claims + secrets intact`);
    }
  } finally {
    revokeBehavior = "ok";
  }

  // 4: staff targets rejected, revoke never called for them.
  for (const [reqId, target] of [["req-doc", "doctor-9"], ["req-adm", "admin-9"]]) {
    dbMockData[`password_reset_requests/${reqId}`] = { status: "pending", student_id: target };
    resetCapture();
    try {
      await wrapped({ data: { requestId: reqId, newPassword: STRONG }, auth: doctorAuth });
      fail(`staff-target-${target}`, "expected failure, got success");
    } catch (err) {
      if (err.code !== "permission-denied") fail(`staff-target-${target}`, `unexpected ${err.code}`);
      else if (captured.revoke.length !== 0) fail(`staff-target-${target}`, "revoke was called");
      else ok(`staff target ${target} rejected, revoke never called`);
    }
  }

  test.cleanup();

  if (process.exitCode === 1) {
    console.error("password_reset_revoke tests FAILED");
    process.exit(1);
  }
  console.log(`password_reset_revoke.test: PASS - All ${passed} checks passed.`);
}

run();
