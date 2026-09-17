const test = require("firebase-functions-test")({
  projectId: "dr-tarek-platform-functions-test",
});

const assert = require("node:assert/strict");

let dbMockData = {};

const adminMock = {
  initializeApp: () => ({}),
  getFirestore: () => ({
    collection: (collPath) => ({
      doc: (docId) => ({
        get: async () => {
          const docData = dbMockData[`${collPath}/${docId}`];
          if (docData === undefined) return { exists: false };
          return { exists: true, data: () => docData };
        },
        update: async () => {},
        // Honor {merge:true} so permission-key migration is observable;
        // update() stays a no-op so shared fixtures (req-1) remain pending.
        set: async (data, options) => {
          const key = `${collPath}/${docId}`;
          if (options && options.merge && dbMockData[key] !== undefined) {
            dbMockData[key] = {...dbMockData[key], ...data};
          } else {
            dbMockData[key] = data;
          }
        }
      }),
      add: async () => {}
    })
  }),
  FieldValue: {serverTimestamp: () => ({_serverTimestamp: true})},
  Timestamp: {now: () => ({toMillis: () => Date.now()})},
  getAuth: () => ({
    updateUser: async () => {},
    getUser: async () => ({ customClaims: {} }),
    setCustomUserClaims: async () => {}
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

  // Set up mock DB data (canonical key is `password.reset`).
  dbMockData["admin_permissions/admin_with_reset"] = {
    is_active: true,
    permissions: { "password.reset": true }
  };
  dbMockData["admin_permissions/admin_without_reset"] = {
    is_active: true,
    permissions: { "password.reset": false }
  };
  dbMockData["admin_permissions/admin_legacy"] = {
    is_active: true,
    permissions: { "password_reset": true }
  };
  dbMockData["admin_permissions/admin_revoke"] = {
    is_active: true,
    permissions: { "password.reset": true }
  };
  dbMockData["password_reset_requests/req-1"] = {
    status: "pending",
    student_id: "student-123"
  };

  const requestData = { requestId: "req-1", newPassword: "new_password" };

  await checkPass("Teacher reset -> PASS", { uid: "t1", token: { role: "teacher" } }, requestData);
  await checkPass("Admin with password.reset -> PASS", { uid: "admin_with_reset", token: { role: "admin" } }, requestData);
  await checkFail("Admin without password.reset -> DENIED", { uid: "admin_without_reset", token: { role: "admin" } }, requestData);
  await checkFail("Student -> DENIED", { uid: "s1", token: { role: "student" } }, requestData);
  await checkFail("Unauthenticated -> DENIED", null, requestData);

  // Legacy `password_reset` grant is honored once and migrated.
  await checkPass("Admin with legacy key -> PASS (migrated)", { uid: "admin_legacy", token: { role: "admin" } }, requestData);
  assert.equal(dbMockData["admin_permissions/admin_legacy"].permissions["password.reset"], true);
  assert.equal(dbMockData["admin_permissions/admin_legacy"].permissions["password_reset"], false);
  console.log("ok - Legacy key migrated to password.reset");

  // Revoked grant is denied even though it previously passed.
  await checkPass("Admin before revoke -> PASS", { uid: "admin_revoke", token: { role: "admin" } }, requestData);
  dbMockData["admin_permissions/admin_revoke"].permissions["password.reset"] = false;
  await checkFail("Admin after revoke -> DENIED", { uid: "admin_revoke", token: { role: "admin" } }, requestData);

  test.cleanup();

  if (process.exitCode === 1) {
    console.error("password_reset tests FAILED");
    process.exit(1);
  }
  console.log(`password_reset.test: PASS - All ${passed} checks passed.`);
}

run();
