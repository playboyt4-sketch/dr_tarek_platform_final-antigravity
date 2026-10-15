/**
 * Guest issuance verdict contract lock (device-blocked wall follow-up).
 *
 * Covers the pure `buildGuestIssuanceVerdict` helper used by
 * `generateBunnySignedUrl`: on Guest tier the response MUST carry
 * `previewLimitSeconds` and `previewAudience` together (never one
 * without the other); on Full tier it MUST carry neither. A numeric
 * cap with a null audience is unclassifiable client-side and degrades
 * to the generic paid wall — an upsell CTA for a device-blocked
 * student. No emulator needed.
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

const {buildGuestIssuanceVerdict} = functions;
assert.equal(typeof buildGuestIssuanceVerdict, "function", "helper must be exported");

let passed = 0;
function check(name, actual, expected) {
  assert.deepEqual(actual, expected, name);
  passed++;
  console.log(`ok - ${name}`);
}

// 1. The reported live case: Center-Free plan (plans/free,
// center_student), device slot held by another device => Guest tier
// with zero playable minutes. Both keys present, audience "center".
check(
  "Guest zero-preview on Center-Free plan carries center audience",
  buildGuestIssuanceVerdict({
    tier: "guest",
    subjectPlanId: "free",
    subjectPlan: {student_type: "center_student"},
    guestPreviewSeconds: 0,
  }),
  {previewLimitSeconds: 0, previewAudience: "center"},
);

// 2. Same branch with positive minutes: still atomic.
check(
  "Guest positive preview on Center-Free plan carries center audience",
  buildGuestIssuanceVerdict({
    tier: "guest",
    subjectPlanId: "pro",
    subjectPlan: {student_type: "center_student"},
    guestPreviewSeconds: 300,
  }),
  {previewLimitSeconds: 300, previewAudience: "center"},
);

// 3. External Guest plan keeps the guest audience.
check(
  "Guest zero-preview on Guest plan carries guest audience",
  buildGuestIssuanceVerdict({
    tier: "guest",
    subjectPlanId: "guest",
    subjectPlan: {student_type: "guest"},
    guestPreviewSeconds: 0,
  }),
  {previewLimitSeconds: 0, previewAudience: "guest"},
);

// 4. Malformed plan identity can never yield a null audience:
// non-Guest plan identity always resolves to "center".
for (const plan of [{}, {student_type: null}, {student_type: "center_student"}, null, undefined]) {
  const verdict = buildGuestIssuanceVerdict({
    tier: "guest",
    subjectPlanId: "free",
    subjectPlan: plan,
    guestPreviewSeconds: 0,
  });
  assert.equal(verdict.previewAudience, "center", `malformed plan ${JSON.stringify(plan)} resolves to center`);
  passed++;
  console.log(`ok - malformed plan ${JSON.stringify(plan)} resolves to center`);
}

// 5. Full tier carries neither key (existing shape preserved).
check(
  "Full tier carries no preview keys",
  buildGuestIssuanceVerdict({
    tier: "full",
    subjectPlanId: "free",
    subjectPlan: {student_type: "center_student"},
    guestPreviewSeconds: null,
  }),
  {},
);

// 6. Full shape has neither key present (explicit `in` guard,
// mirroring the emulator assertion style).
{
  const verdict = buildGuestIssuanceVerdict({
    tier: "full",
    subjectPlanId: "max",
    subjectPlan: {student_type: "center_student"},
    guestPreviewSeconds: null,
  });
  assert.ok(!("previewLimitSeconds" in verdict), "Full carries no previewLimitSeconds key");
  assert.ok(!("previewAudience" in verdict), "Full carries no previewAudience key");
  passed++;
  console.log("ok - Full shape has neither key present");
}

console.log(`guest_issuance_verdict: ${passed} checks passed`);
