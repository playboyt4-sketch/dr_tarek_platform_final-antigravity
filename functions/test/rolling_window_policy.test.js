/**
 * Rolling watch-window policy ("تحديد المشاهدة كل 24 ساعة").
 *
 * Covers the pure `resolveRollingWindowPolicy` helper used by
 * `generateBunnySignedUrl`: matrix-driven enforcement on ANY plan
 * (video.rolling_window.enabled/_hours), explicit disable, hours
 * parsing/clamping, and the legacy free/24h fallback while the
 * matrix is unconfigured. The fallback is plan-ID based (Phase 4:
 * plans/free + center_student); the pre-migration "center_free"
 * spellings are honored transitionally. No emulator needed.
 */
const assert = require("node:assert/strict");

const adminMock = {
  initializeApp: () => ({}),
  getFirestore: () => ({
    collection: () => ({
      doc: () => ({get: async () => ({exists: false})}),
      where: () => ({where: () => ({limit: () => ({get: async () => ({empty: true, docs: []})})})}),
      add: async () => ({id: "mock"}),
    }),
  }),
  FieldValue: {serverTimestamp: () => ({_serverTimestamp: true})},
  Timestamp: {fromMillis: (ms) => ({toMillis: () => ms})},
  getAuth: () => ({}),
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

const {resolveRollingWindowPolicy} = functions;
assert.equal(typeof resolveRollingWindowPolicy, "function", "helper must be exported");

let passed = 0;
function check(name, actual, expected) {
  assert.deepEqual(actual, expected, name);
  passed++;
  console.log(`ok - ${name}`);
}

// 1. Matrix enabled with custom hours (any plan, e.g. pro).
check(
  "Enabled matrix enforces custom hours on any plan",
  resolveRollingWindowPolicy({
    enabledFeature: {enabled: true},
    hoursFeature: {feature_value: 12},
    studentType: "center_student",
    planId: "pro",
    planKey: "pro",
  }),
  {enforced: true, hours: 12},
);

// 2. Matrix enabled without hours -> default 24.
check(
  "Enabled matrix without hours defaults to 24",
  resolveRollingWindowPolicy({
    enabledFeature: {enabled: true},
    hoursFeature: null,
    studentType: "center_student",
    planId: "max",
    planKey: "max",
  }),
  {enforced: true, hours: 24},
);

// 3. Legacy `value` spelling (seed scripts) is accepted.
check(
  "Seed-style value spelling is accepted",
  resolveRollingWindowPolicy({
    enabledFeature: {enabled: true},
    hoursFeature: {value: 48},
    studentType: "guest",
    planKey: "free",
  }),
  {enforced: true, hours: 48},
);

// 4. Out-of-range hours are clamped to 1..168.
check(
  "Zero hours clamps to 1",
  resolveRollingWindowPolicy({
    enabledFeature: {enabled: true},
    hoursFeature: {feature_value: 0},
  }),
  {enforced: true, hours: 1},
);
check(
  "Huge hours clamps to 168",
  resolveRollingWindowPolicy({
    enabledFeature: {enabled: true},
    hoursFeature: {feature_value: 9999},
  }),
  {enforced: true, hours: 168},
);

// 5. Explicit disable wins over plan type.
check(
  "Explicit disable removes enforcement even for free",
  resolveRollingWindowPolicy({
    enabledFeature: {enabled: false},
    hoursFeature: {feature_value: 24},
    studentType: "center_student",
    planId: "free",
    planKey: "free",
  }),
  {enforced: false, hours: 24},
);

// 6. Missing matrix -> legacy fallback preserves FINAL_DECISIONS S12.
check(
  "Missing matrix keeps free enforced at 24h",
  resolveRollingWindowPolicy({
    enabledFeature: null,
    hoursFeature: null,
    studentType: "center_student",
    planId: "free",
    planKey: "free",
  }),
  {enforced: true, hours: 24},
);
check(
  "Missing matrix keeps pre-migration center_free enforced (transitional)",
  resolveRollingWindowPolicy({
    enabledFeature: null,
    hoursFeature: null,
    studentType: "center_student",
    planId: "center_free",
    planKey: "free",
  }),
  {enforced: true, hours: 24},
);
check(
  "Missing matrix leaves pro unenforced",
  resolveRollingWindowPolicy({
    enabledFeature: null,
    hoursFeature: null,
    studentType: "center_student",
    planId: "pro",
    planKey: "pro",
  }),
  {enforced: false, hours: 24},
);
check(
  "Missing matrix leaves max unenforced",
  resolveRollingWindowPolicy({
    enabledFeature: null,
    hoursFeature: null,
    studentType: "center_student",
    planId: "max",
    planKey: "max",
  }),
  {enforced: false, hours: 24},
);
check(
  "Missing matrix leaves guest plans unenforced (planKey free alone is not identity)",
  resolveRollingWindowPolicy({
    enabledFeature: null,
    hoursFeature: null,
    studentType: "guest",
    planId: "guest",
    planKey: "free",
  }),
  {enforced: false, hours: 24},
);

console.log(`rolling_window_policy.test: PASS - All ${passed} checks passed.`);
