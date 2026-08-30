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
        set: async () => {}
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

  // Set up mock DB data
  dbMockData["admin_permissions/admin_with_reset"] = {
    is_active: true,
    permissions: { "password_reset": true }
  };
  dbMockData["admin_permissions/admin_without_reset"] = {
    is_active: true,
    permissions: { "password_reset": false }
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

  test.cleanup();

  if (process.exitCode === 1) {
    console.error("password_reset tests FAILED");
    process.exit(1);
  }
  console.log(`password_reset.test: PASS - All ${passed}/5 checks passed.`);
}

run();
