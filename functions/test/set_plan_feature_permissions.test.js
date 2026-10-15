/**
 * setPlanFeature authorization tiers (rolling-window hardening).
 *
 * - video.rolling_window.enabled/_hours are SENSITIVE: Doctor only.
 *   Admin/Student/unauthenticated are rejected with permission-denied/
 *   unauthenticated and must not mutate the matrix or audit log.
 * - Ordinary keys (e.g. video.pip) stay Admin-or-Doctor, Student and
 *   unauthenticated rejected.
 * - Missing planId/featureKey and non-boolean enabled are invalid-argument.
 *
 * Offline mock harness (same pattern as plan_feature.test.js): no emulator.
 */
const test = require("firebase-functions-test")({
  projectId: "dr-tarek-platform-functions-test",
});

const assert = require("node:assert/strict");

const writes = [];
const sets = [];
const dbData = {
  "plans/plan-pro": {is_active: true, plan_key: "pro"},
};

const adminMock = {
  initializeApp: () => ({}),
  getFirestore: () => ({
    collection: (collPath) => ({
      doc: (docId) => ({
        id: docId,
        get: async () => {
          const docData = dbData[`${collPath}/${docId}`];
          if (docData === undefined) return {exists: false};
          return {exists: true, data: () => docData};
        },
        update: async () => {},
        set: async (data) => {
          sets.push({collection: collPath, id: docId, data});
        },
        ref: {id: docId},
      }),
      where: () => ({
        where: () => ({
          limit: () => ({get: async () => ({empty: true, docs: []})}),
        }),
        limit: () => ({get: async () => ({empty: true, docs: []})}),
      }),
      add: async (data) => {
        const id = `${collPath}-doc-${writes.length}`;
        writes.push({collection: collPath, id, data});
        return {id};
      },
    }),
  }),
  FieldValue: {serverTimestamp: () => ({_serverTimestamp: true})},
  Timestamp: {now: () => ({toMillis: () => Date.now()})},
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

const wrapped = test.wrap(functions.setPlanFeature);

function mutationCount() {
  return writes.length + sets.length;
}

async function run() {
  let passed = 0;

  async function checkPass(name, req, verify) {
    try {
      const res = await wrapped(req);
      if (verify) verify(res);
      passed++;
      console.log(`ok - ${name}`);
    } catch (err) {
      console.error(`FAIL - ${name}: expected success, got ${err.code}: ${err.message}`);
      process.exitCode = 1;
    }
  }

  async function checkFail(name, req, code) {
    const before = mutationCount();
    try {
      await wrapped(req);
      console.error(`FAIL - ${name}: expected failure, got success`);
      process.exitCode = 1;
    } catch (err) {
      if (code && err.code !== code) {
        console.error(`FAIL - ${name}: expected ${code}, got ${err.code}`);
        process.exitCode = 1;
        return;
      }
      assert.equal(
        mutationCount(),
        before,
        `${name}: rejected change must not mutate matrix or audit`,
      );
      passed++;
      console.log(`ok - ${name}`);
    }
  }

  const doctorAuth = {uid: "doctor-1", token: {role: "doctor"}};
  const adminAuth = {uid: "admin-1", token: {role: "admin"}};
  const studentAuth = {uid: "student-1", token: {role: "student"}};

  // 1. Doctor sets a sensitive key.
  await checkPass(
    "Doctor sets video.rolling_window.enabled",
    {
      data: {
        planId: "plan-pro",
        featureKey: "video.rolling_window.enabled",
        enabled: true,
      },
      auth: doctorAuth,
    },
    (res) => {
      assert.equal(res.ok, true);
      assert.equal(res.featureKey, "video.rolling_window.enabled");
    },
  );

  // 2. Doctor sets sensitive hours with a value.
  await checkPass(
    "Doctor sets video.rolling_window.hours=12",
    {
      data: {
        planId: "plan-pro",
        featureKey: "video.rolling_window.hours",
        enabled: true,
        value: 12,
        valueType: "number",
      },
      auth: doctorAuth,
    },
    (res) => assert.equal(res.value, 12),
  );

  // 3-4. Delegated Admin is rejected on BOTH sensitive keys.
  await checkFail(
    "Admin rejected on rolling_window.enabled",
    {
      data: {
        planId: "plan-pro",
        featureKey: "video.rolling_window.enabled",
        enabled: true,
      },
      auth: adminAuth,
    },
    "permission-denied",
  );
  await checkFail(
    "Admin rejected on rolling_window.hours",
    {
      data: {
        planId: "plan-pro",
        featureKey: "video.rolling_window.hours",
        enabled: true,
        value: 48,
      },
      auth: adminAuth,
    },
    "permission-denied",
  );

  // 5. Admin still allowed on ordinary keys (quality-matrix precedent).
  await checkPass(
    "Admin sets ordinary key video.pip",
    {
      data: {planId: "plan-pro", featureKey: "video.pip", enabled: true},
      auth: adminAuth,
    },
    (res) => assert.equal(res.ok, true),
  );

  // 6-7. Student / unauthenticated rejected everywhere.
  await checkFail(
    "Student rejected on ordinary key",
    {
      data: {planId: "plan-pro", featureKey: "video.pip", enabled: true},
      auth: studentAuth,
    },
    "permission-denied",
  );
  await checkFail(
    "Unauthenticated rejected",
    {
      data: {planId: "plan-pro", featureKey: "video.pip", enabled: true},
    },
    "unauthenticated",
  );

  // 8-9. Validation: missing fields + non-boolean enabled.
  await checkFail(
    "Missing featureKey rejected",
    {data: {planId: "plan-pro", enabled: true}, auth: doctorAuth},
    "invalid-argument",
  );
  await checkFail(
    "Non-boolean enabled rejected",
    {
      data: {planId: "plan-pro", featureKey: "video.pip", enabled: "yes"},
      auth: doctorAuth,
    },
    "invalid-argument",
  );

  test.cleanup();

  if (process.exitCode === 1) {
    console.error("set_plan_feature_permissions tests FAILED");
    process.exit(1);
  }
  console.log(`set_plan_feature_permissions.test: PASS - All ${passed} checks passed.`);
}

run();
