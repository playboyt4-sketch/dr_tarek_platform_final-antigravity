/**
 * Unit tests for V1 Individual Per-Lecture Student Access (approved).
 *
 * Covers the exported pure grant helpers enforced by every
 * protected-content callable (getLectureResources, generateBunnySignedUrl,
 * resolveDocumentAccess for PDF/attachment delivery):
 *  - lectureAccessGrantId: deterministic {lectureId}_{studentId} identity
 *    (duplicates structurally impossible).
 *  - isLectureAccessDenied: ONLY an explicit stored allowed === false
 *    denies; missing/malformed grants and allowed === true defer to the
 *    normal eligibility model (override, never a security bypass).
 *  - LECTURE_ACCESS_DENIED_MESSAGE: defined denial sentinel.
 *
 * The firebase-admin surface is stubbed exactly like
 * resource_delivery.test.js so lib/index.js loads without an emulator.
 */
const test = require("firebase-functions-test")({
  projectId: "dr-tarek-platform-functions-test",
});

const assert = require("node:assert/strict");

const adminMock = {
  initializeApp: () => ({}),
  getFirestore: () => ({collection: () => { throw new Error("not used"); }}),
  getAuth: () => ({}),
  getMessaging: () => ({}),
  getStorage: () => ({}),
  FieldValue: {serverTimestamp: () => ({_serverTimestamp: true})},
  Timestamp: {now: () => ({toMillis: () => Date.now()})},
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
  if (id === "firebase-admin/messaging") {
    return {getMessaging: adminMock.getMessaging};
  }
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

let passed = 0;
function check(name, fn) {
  try {
    fn();
    passed += 1;
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`FAIL - ${name}`);
    console.error(error);
    process.exitCode = 1;
  }
}

// ---- Grant identity ---------------------------------------------------
check("lectureAccessGrantId is deterministic lectureId_studentId", () => {
  assert.equal(
    functions.lectureAccessGrantId("lecture123", "student456"),
    "lecture123_student456",
  );
});
check("same pair always maps to the same id (no duplicates)", () => {
  assert.equal(
    functions.lectureAccessGrantId("lec1", "stu9"),
    functions.lectureAccessGrantId("lec1", "stu9"),
  );
});
check("different students yield different ids", () => {
  assert.notEqual(
    functions.lectureAccessGrantId("lec1", "stu1"),
    functions.lectureAccessGrantId("lec1", "stu2"),
  );
});

// ---- Explicit-deny predicate ------------------------------------------
check("explicit allowed=false denies", () => {
  assert.equal(functions.isLectureAccessDenied({allowed: false}), true);
});
check("allowed=true does not deny (other checks still apply)", () => {
  assert.equal(functions.isLectureAccessDenied({allowed: true}), false);
});
check("missing grant defers to normal eligibility (no deny)", () => {
  assert.equal(functions.isLectureAccessDenied(null), false);
  assert.equal(functions.isLectureAccessDenied(undefined), false);
});
check("malformed grant never denies", () => {
  assert.equal(functions.isLectureAccessDenied({}), false);
  assert.equal(functions.isLectureAccessDenied({allowed: "false"}), false);
  assert.equal(functions.isLectureAccessDenied({allowed: 0}), false);
  assert.equal(functions.isLectureAccessDenied("no"), false);
});
check("soft-deleted grant carries no override (treated as missing)", () => {
  assert.equal(
    functions.isLectureAccessDenied({allowed: false, is_deleted: true}),
    false,
  );
  assert.equal(
    functions.isLectureAccessDenied({allowed: true, is_deleted: true}),
    false,
  );
});

// ---- Denial sentinel ----------------------------------------------------
check("LECTURE_ACCESS_DENIED_MESSAGE is defined", () => {
  assert.equal(typeof functions.LECTURE_ACCESS_DENIED_MESSAGE, "string");
  assert.ok(functions.LECTURE_ACCESS_DENIED_MESSAGE.length > 0);
});

test.cleanup();
if (process.exitCode === 1) {
  console.error("lecture_access tests FAILED");
  process.exit(1);
}
console.log(`lecture_access tests passed (${passed}/9 groups).`);
