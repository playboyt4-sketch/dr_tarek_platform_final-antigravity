/**
 * Unit tests for FINAL_DECISIONS §12 (Center Free rolling 24-hour
 * single-video limit) and §13 (grade-based prior-term access) server-side
 * pure policy helpers.
 *
 * The firebase-admin surface is stubbed exactly like the other suites so
 * lib/index.js can be loaded without an emulator or real project.
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
  Timestamp: {
    now: () => ({toMillis: () => Date.now()}),
    fromMillis: (ms) => ({toMillis: () => ms}),
  },
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

const NOW = 1_800_000_000_000; // fixed epoch millis
const HOUR = 60 * 60 * 1000;
const window = (resourceId, expiresInMillis) => ({
  active_resource_id: resourceId,
  window_expires_at: {toMillis: () => NOW + expiresInMillis},
});

// ---- §12: rolling-window decision --------------------------------------
check("no existing window -> allowed (new window starts)", () => {
  assert.deepEqual(
    functions.decideVideoWatchWindow(null, "res-B", NOW),
    {allowed: true, reason: "no_window"},
  );
  assert.deepEqual(
    functions.decideVideoWatchWindow(undefined, "res-B", NOW),
    {allowed: true, reason: "no_window"},
  );
});

check("active window + SAME video -> allowed (resume/replay)", () => {
  assert.deepEqual(
    functions.decideVideoWatchWindow(window("res-A", 5 * HOUR), "res-A", NOW),
    {allowed: true, reason: "same_video"},
  );
});

check("active window + DIFFERENT video -> REJECTED", () => {
  assert.deepEqual(
    functions.decideVideoWatchWindow(window("res-A", 5 * HOUR), "res-B", NOW),
    {allowed: false, reason: "different_video"},
  );
});

check("EXPIRED window -> allowed even for a different video (rolling)", () => {
  // Expired one second ago still counts as expired.
  assert.deepEqual(
    functions.decideVideoWatchWindow(window("res-A", -1), "res-B", NOW),
    {allowed: true, reason: "expired"},
  );
  // Boundary: expires exactly now is expired (current_time < start+24h fails).
  assert.deepEqual(
    functions.decideVideoWatchWindow(window("res-A", 0), "res-B", NOW),
    {allowed: true, reason: "expired"},
  );
});

check("window doc without parsable expiry treated as no window", () => {
  assert.deepEqual(
    functions.decideVideoWatchWindow({active_resource_id: "res-A"}, "res-B", NOW),
    {allowed: true, reason: "expired"},
  );
});

// ---- §12: client-contract sentinel --------------------------------------
check("blocked message sentinel matches the client mapping exactly", () => {
  assert.equal(
    functions.CENTER_FREE_WINDOW_BLOCKED_MESSAGE,
    "A Center Free 24-hour video window is already active for another video.",
  );
});

// ---- §13: grade normalization incl. legacy spellings --------------------
check("normalizeGradeKey accepts canonical and digit forms", () => {
  assert.equal(functions.normalizeGradeKey("grade_one"), "grade_one");
  assert.equal(functions.normalizeGradeKey("grade_3"), "grade_three");
  assert.equal(functions.normalizeGradeKey("Grade 4"), "grade_four");
  assert.equal(functions.normalizeGradeKey("الفرقة الثانية"), "grade_two");
  assert.equal(functions.normalizeGradeKey("nonsense"), null);
  assert.equal(functions.normalizeGradeKey(null), null);
});

check("gradeRank orders grades for prior-term computation", () => {
  assert.equal(functions.gradeRank("grade_one"), 1);
  assert.equal(functions.gradeRank("grade_4"), 4);
  assert.equal(functions.gradeRank("bogus"), null);
});

test.cleanup();
if (process.exitCode === 1) {
  console.error("sections_12_13 tests FAILED");
  process.exit(1);
}
console.log(`sections_12_13 tests passed (${passed}/8 groups).`);
