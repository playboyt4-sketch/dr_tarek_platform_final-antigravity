/**
 * Plan video-quality feature setter (09 §5 backend).
 *
 * Covers the live `setPlanQualityFeature` callable (the legacy generic
 * `setPlanFeature` matrix setter was removed from the backend):
 * doctor/admin success + analytics audit, student/unauthenticated
 * rejection, unknown quality and non-boolean enabled rejection, no
 * mutation on rejected changes, and quality key normalization.
 */
const test = require("firebase-functions-test")({
  projectId: "dr-tarek-platform-functions-test",
});

const assert = require("node:assert/strict");

const writes = [];
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
        set: async () => {},
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

// plan_features doc().set (find-or-create write path) must be observable.
const Module = require("node:module");
const originalRequire = Module.prototype.require;
Module.prototype.require = function (id) {
  if (id === "firebase-admin/firestore") {
    const real = {
      getFirestore: adminMock.getFirestore,
      FieldValue: adminMock.FieldValue,
      Timestamp: adminMock.Timestamp,
    };
    return real;
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

const wrapped = test.wrap(functions.setPlanQualityFeature);

function calls(collection) {
  return writes.filter((w) => w.collection === collection);
}

async function run() {
  let passed = 0;
  async function checkPass(name, req) {
    try {
      const res = await wrapped(req);
      passed++;
      console.log(`ok - ${name}`);
      return res;
    } catch (err) {
      console.error(`FAIL - ${name}: expected success, got ${err.code}: ${err.message}`);
      process.exitCode = 1;
      return null;
    }
  }

  async function checkFail(name, req, code) {
    const before = writes.length;
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
        writes.length,
        before,
        `${name}: rejected change must not mutate the matrix`,
      );
      passed++;
      console.log(`ok - ${name}`);
    }
  }

  const doctorAuth = {uid: "doctor-1", token: {role: "doctor"}};
  const adminAuth = {uid: "admin-1", token: {role: "admin"}};
  const studentAuth = {uid: "student-1", token: {role: "student"}};

  // 1. Doctor success: quality key normalized, analytics audit written.
  const res = await checkPass("Doctor sets 720p quality", {
    data: {planId: "plan-pro", quality: "720p", enabled: true},
    auth: doctorAuth,
  });
  assert.equal(res.ok, true);
  assert.equal(res.planId, "plan-pro");
  assert.equal(res.quality, "720p");
  assert.equal(res.enabled, true);
  const audits = calls("analytics_events");
  assert.equal(audits.length, 1);
  assert.equal(audits[0].data.event_type, "Update Plan Video Quality");
  assert.equal(audits[0].data.reference_id, "plan-pro");
  console.log("ok - Audit written with canonical event type");

  // 2. Admin (staff) success; quality input is case-insensitive.
  const resAdmin = await checkPass("Admin sets 1080P quality (normalized)", {
    data: {planId: "plan-pro", quality: "1080P", enabled: false},
    auth: adminAuth,
  });
  assert.equal(resAdmin.quality, "1080p");
  assert.equal(resAdmin.enabled, false);

  // 3-4. Non-staff rejected.
  await checkFail(
    "Student rejected",
    {data: {planId: "plan-pro", quality: "720p", enabled: true}, auth: studentAuth},
    "permission-denied",
  );
  await checkFail(
    "Unauthenticated rejected",
    {data: {planId: "plan-pro", quality: "720p", enabled: true}},
    "unauthenticated",
  );

  // 5-7. Unknown quality, missing fields and non-boolean enabled rejected.
  await checkFail(
    "Unknown quality rejected",
    {data: {planId: "plan-pro", quality: "999p", enabled: true}, auth: doctorAuth},
    "invalid-argument",
  );
  await checkFail(
    "Missing planId rejected",
    {data: {quality: "720p", enabled: true}, auth: doctorAuth},
    "invalid-argument",
  );
  await checkFail(
    "Non-boolean enabled rejected",
    {data: {planId: "plan-pro", quality: "720p", enabled: "yes"}, auth: doctorAuth},
    "invalid-argument",
  );

  test.cleanup();

  if (process.exitCode === 1) {
    console.error("plan_feature tests FAILED");
    process.exit(1);
  }
  console.log(`plan_feature.test: PASS - All ${passed} checks passed.`);
}

run();
