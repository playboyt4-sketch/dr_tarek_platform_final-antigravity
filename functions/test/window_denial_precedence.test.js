/**
 * Window-before-tier denial precedence (Center Free A → Exit → C fix).
 *
 * The rolling-window verdict for the requested lecture is authoritative and
 * must win over the device-tier Guest denial inside `generateBunnySignedUrl`:
 * the Next flow walls from the client-side window snapshot without ever
 * calling issuance, while a direct open after exit calls issuance — a
 * Guest-tier device must still receive the SAME 24-hour restriction
 * (resource-exhausted), never Guest preview, public fallback, or
 * device-unauthorized behavior (Center Free → Guest downgrade).
 *
 * Covers the pure `issuanceDenialPrecedence` helper plus the exact
 * A → Exit → C scenario matrix through `decideVideoWatchWindow`:
 *   - window active for A + request C → blocked → precedence "window"
 *     (issuance throws resource-exhausted BEFORE any tier evaluation);
 *   - reopen A → allowed (same_video) → precedence "tier";
 *   - expired window → allowed → precedence "tier";
 *   - no window → allowed → precedence "tier".
 * No emulator needed.
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

const {issuanceDenialPrecedence, decideVideoWatchWindow} = functions;
for (const [name, fn] of Object.entries({issuanceDenialPrecedence, decideVideoWatchWindow})) {
  assert.equal(typeof fn, "function", `${name} must be exported`);
}

let passed = 0;
function check(name, actual, expected) {
  assert.deepEqual(actual, expected, name);
  passed++;
  console.log(`ok - ${name}`);
}

const ts = (ms) => ({toMillis: () => ms});
const NOW = 1_000_000;
// Window left behind by opening lecture A (active, unexpired).
const windowForA = {active_lecture_id: "lec-A", window_expires_at: ts(NOW + 86_400_000)};

// --- issuanceDenialPrecedence unit contract ---
check(
  "blocked window decision defers to the window (never the tier)",
  issuanceDenialPrecedence({allowed: false, reason: "different_video"}),
  "window",
);
for (const reason of ["no_window", "same_video", "expired"]) {
  check(
    `allowed window decision (${reason}) defers to the tier`,
    issuanceDenialPrecedence({allowed: true, reason}),
    "tier",
  );
}

// --- A → Exit → C end-to-end precedence at the pure level ---
// Direct-open C while A's window is active: blocked → "window", so
// issuance throws resource-exhausted BEFORE any Guest-tier evaluation.
const directOpenC = decideVideoWatchWindow(windowForA, "lec-C", NOW);
check(
  "direct-open C while A's window is active is blocked",
  directOpenC,
  {allowed: false, reason: "different_video"},
);
check(
  "blocked direct-open C resolves to window precedence (same restriction as Next)",
  issuanceDenialPrecedence(directOpenC),
  "window",
);

// Reopening the SAME lecture A stays allowed regardless of tier.
check(
  "reopen A resolves to tier precedence (same_video)",
  issuanceDenialPrecedence(decideVideoWatchWindow(windowForA, "lec-A", NOW)),
  "tier",
);

// Expired windows never block the next open.
const expired = {active_lecture_id: "lec-A", window_expires_at: ts(NOW - 1)};
check(
  "expired window resolves to tier precedence",
  issuanceDenialPrecedence(decideVideoWatchWindow(expired, "lec-C", NOW)),
  "tier",
);

// First open (no window) is unaffected by the pre-check.
check(
  "no window resolves to tier precedence",
  issuanceDenialPrecedence(decideVideoWatchWindow(null, "lec-A", NOW)),
  "tier",
);

console.log(`window_denial_precedence.test: PASS - All ${passed} checks passed.`);
