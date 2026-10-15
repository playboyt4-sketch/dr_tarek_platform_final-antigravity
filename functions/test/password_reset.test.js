const test = require("firebase-functions-test")({
  projectId: "dr-tarek-platform-functions-test",
});

const assert = require("node:assert/strict");

let dbMockData = {};

const adminMock = {
  initializeApp: () => ({}),
  getFirestore: () => ({
    collection: (collPath) => ({
      doc: (docId) => {
        const key = `${collPath}/${docId}`;
        const ref = {
          get: async () => {
            const docData = dbMockData[key];
            if (docData === undefined) return { exists: false };
            return { exists: true, data: () => docData };
          },
          update: async () => {},
          // Honor {merge:true} so permission-key migration is observable;
          // update() stays a no-op so shared fixtures (req-1) remain pending.
          set: async (data, options) => {
            if (options && options.merge && dbMockData[key] !== undefined) {
              dbMockData[key] = {...dbMockData[key], ...data};
            } else {
              dbMockData[key] = data;
            }
          }
        };
        return ref;
      },
      add: async () => {}
    }),
    // Passthrough runner for the reset single-flight claim transaction
    // (added when onPasswordResetApproved gained transactional claiming;
    // no contention semantics — see reset_claim.test.js).
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
  Timestamp: {now: () => ({toMillis: () => Date.now()})},
  getAuth: () => ({
    updateUser: async () => {},
    getUser: async () => ({ customClaims: {} }),
    setCustomUserClaims: async () => {},
    revokeRefreshTokens: async () => {}
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

const wrapped = test.wrap(functions.onPasswordResetApproved);

async function run() {
  let passed = 0;
  async function checkPass(name, authContext, data) {
    try {
      await wrapped({ data, auth: authContext });
      passed++;
      console.log(`ok - ${name}`);
    } catch (err) {
      console.error(`FAIL - ${name}: expected success, got error: ${err.message}`);
      process.exitCode = 1;
    }
  }

  async function checkFail(name, authContext, data) {
    try {
      await wrapped({ data, auth: authContext });
      console.error(`FAIL - ${name}: expected failure, got success`);
      process.exitCode = 1;
    } catch (err) {
      passed++;
      console.log(`ok - ${name}`);
    }
  }

  async function checkFailCode(name, authContext, data, code) {
    try {
      await wrapped({ data, auth: authContext });
      console.error(`FAIL - ${name}: expected failure, got success`);
      process.exitCode = 1;
    } catch (err) {
      if (err.code !== code) {
        console.error(`FAIL - ${name}: expected code ${code}, got ${err.code}: ${err.message}`);
        process.exitCode = 1;
        return;
      }
      passed++;
      console.log(`ok - ${name}`);
    }
  }

  // Set up mock DB data (sole key is `password_reset`).
  dbMockData["admin_permissions/admin_with_reset"] = {
    is_active: true,
    permissions: { "password_reset": true }
  };
  dbMockData["admin_permissions/admin_without_reset"] = {
    is_active: true,
    permissions: { "password_reset": false }
  };
  dbMockData["admin_permissions/admin_legacy"] = {
    is_active: true,
    permissions: { "password_reset": true }
  };
  dbMockData["admin_permissions/admin_revoke"] = {
    is_active: true,
    permissions: { "password_reset": true }
  };
  dbMockData["password_reset_requests/req-1"] = {
    status: "pending",
    student_id: "student-123"
  };
  dbMockData["password_reset_requests/req-2"] = {
    status: "pending",
    student_id: "student-123"
  };
  // Target-role hardening (item 11): approval re-validates the target user
  // exists with a student-kind role; the fixture target is a student.
  dbMockData["users/student-123"] = {
    role: "student",
    approval_status: "approved",
    account_status: "active"
  };

  // Fixture must satisfy the strong policy (>=8 + upper/lower/digit/special),
  // shared with changePassword via STRONG_PASSWORD_REGEX.
  const requestData = { requestId: "req-1", newPassword: "Aa1!bcde" };

  await checkPass("Doctor reset -> PASS", { uid: "t1", token: { role: "doctor" } }, requestData);
  await checkPass("Admin with password_reset -> PASS", { uid: "admin_with_reset", token: { role: "admin" } }, requestData);
  await checkFail("Admin without password_reset -> DENIED", { uid: "admin_without_reset", token: { role: "admin" } }, requestData);
  await checkFail("Student -> DENIED", { uid: "s1", token: { role: "student" } }, requestData);
  await checkFail("Unauthenticated -> DENIED", null, requestData);

  // Sole `password_reset` grant authorizes (no migration exists in the
  // backend — the key is enforced at read time by requirePasswordResetManager).
  await checkPass("Admin with password_reset -> PASS", { uid: "admin_legacy", token: { role: "admin" } }, requestData);
  assert.equal(dbMockData["admin_permissions/admin_legacy"].permissions["password_reset"], true);
  console.log("ok - password_reset grant honored");

  // Revoked grant is denied even though it previously passed.
  await checkPass("Admin before revoke -> PASS", { uid: "admin_revoke", token: { role: "admin" } }, requestData);
  dbMockData["admin_permissions/admin_revoke"].permissions["password_reset"] = false;
  await checkFail("Admin after revoke -> DENIED", { uid: "admin_revoke", token: { role: "admin" } }, requestData);

  // Temporary-password policy (approved product decision): SIMPLE by design —
  // min 6 chars (Firebase Auth floor), no complexity, because the student
  // must replace it on next login (force_password_change) and all sessions
  // are revoked. The strong policy lives on in changePassword for the
  // student-chosen permanent password. Validation runs before the request
  // lookup, so the reject case uses req-1 with an authorized doctor actor.
  const doctorAuth = { uid: "t1", token: { role: "doctor" } };
  await checkFailCode("5-char temp -> REJECTED", doctorAuth, { requestId: "req-1", newPassword: "a1234" }, "invalid-argument");
  await checkPass("6-char simple temp (letter+digits) -> ACCEPTED", doctorAuth, { requestId: "req-2", newPassword: "a12345" });
  await checkPass("6-digit temp -> ACCEPTED", doctorAuth, { requestId: "req-2", newPassword: "123456" });
  await checkPass("8-char weak temp (no complexity) -> ACCEPTED", doctorAuth, { requestId: "req-2", newPassword: "abcdefgh" });
  await checkPass("8+ strong temp -> ACCEPTED", doctorAuth, { requestId: "req-2", newPassword: "Aa1!bcde" });

  test.cleanup();

  if (process.exitCode === 1) {
    console.error("password_reset tests FAILED");
    process.exit(1);
  }
  console.log(`password_reset.test: PASS - All ${passed} checks passed.`);
}

run();
