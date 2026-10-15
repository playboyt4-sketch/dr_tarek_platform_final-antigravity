/**
 * Lecture-identity resolution contract for `generateBunnySignedUrl`.
 *
 * Covers the pure `matchIssuanceResource` helper (identity fix): the
 * bunny_video_id selects the VIDEO FILE only, never the lecture. When the
 * client asserts a lecture only that lecture's row may resolve (anything
 * else is a mismatch); legacy lookups resolve a single live row, report
 * missing on zero rows, and report ambiguous — never limit(1) first-match —
 * on duplicated videos. Also locks the rolling-window and Guest-preview
 * pure contracts the identity fix relies on. No emulator needed.
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

const {
  matchIssuanceResource,
  decideVideoWatchWindow,
  resolveRollingWindowPolicy,
  resolveGuestPreviewSeconds,
} = functions;
for (const [name, fn] of Object.entries({
  matchIssuanceResource,
  decideVideoWatchWindow,
  resolveRollingWindowPolicy,
  resolveGuestPreviewSeconds,
})) {
  assert.equal(typeof fn, "function", `${name} must be exported`);
}

let passed = 0;
function check(name, actual, expected) {
  assert.deepEqual(actual, expected, name);
  passed++;
  console.log(`ok - ${name}`);
}

const row = (id, lectureId, deleted = false) => ({id, lectureId, deleted});

// --- matchIssuanceResource: asserted identity (TEST 9) ---
check(
  "requested lecture resolves its own row among duplicates",
  matchIssuanceResource(
    [row("resA", "lecA"), row("resC", "lecC")],
    {requestedLectureId: "lecC"},
  ),
  {kind: "resolved", resourceId: "resC"},
);
check(
  "requested lecture with no linking row is a mismatch (TEST 8 shape)",
  matchIssuanceResource([row("resA", "lecA")], {requestedLectureId: "lecE"}),
  {kind: "mismatch"},
);
check(
  "requested lecture with zero rows is a mismatch",
  matchIssuanceResource([], {requestedLectureId: "lecE"}),
  {kind: "mismatch"},
);
check(
  "requested lecture ignores soft-deleted rows",
  matchIssuanceResource(
    [row("resOld", "lecC", true), row("resC", "lecC")],
    {requestedLectureId: "lecC"},
  ),
  {kind: "resolved", resourceId: "resC"},
);

// --- matchIssuanceResource: legacy path (TEST 10) ---
check(
  "legacy single live row resolves (backward compatible)",
  matchIssuanceResource([row("resA", "lecA")], {requestedLectureId: null}),
  {kind: "resolved", resourceId: "resA"},
);
check(
  "legacy zero rows is missing (legacy not-found preserved)",
  matchIssuanceResource([], {requestedLectureId: null}),
  {kind: "missing"},
);
check(
  "legacy duplicated video is ambiguous, never first-match (TEST 1 shape)",
  matchIssuanceResource(
    [row("resA", "lecA"), row("resC", "lecC")],
    {requestedLectureId: null},
  ),
  {kind: "ambiguous"},
);
check(
  "legacy duplicate with one deleted row resolves the live one",
  matchIssuanceResource(
    [row("resOld", "lecA", true), row("resA", "lecA")],
    {requestedLectureId: null},
  ),
  {kind: "resolved", resourceId: "resA"},
);
check(
  "legacy all-deleted rows is missing",
  matchIssuanceResource(
    [row("resOld", "lecA", true)],
    {requestedLectureId: null},
  ),
  {kind: "missing"},
);

// --- decideVideoWatchWindow regression (rolling window untouched) ---
const ts = (ms) => ({toMillis: () => ms});
const NOW = 1_000_000;
check(
  "window: no window -> allowed",
  decideVideoWatchWindow(null, "lecC", NOW),
  {allowed: true, reason: "no_window"},
);
check(
  "window: same lecture reopen -> allowed (TEST 3 shape)",
  decideVideoWatchWindow(
    {active_lecture_id: "lecA", window_expires_at: ts(NOW + 1000)},
    "lecA",
    NOW,
  ),
  {allowed: true, reason: "same_video"},
);
check(
  "window: different lecture while active -> denied (TEST 1/2 shape)",
  decideVideoWatchWindow(
    {active_lecture_id: "lecA", window_expires_at: ts(NOW + 1000)},
    "lecC",
    NOW,
  ),
  {allowed: false, reason: "different_video"},
);
check(
  "window: expired -> allowed",
  decideVideoWatchWindow(
    {active_lecture_id: "lecA", window_expires_at: ts(NOW - 1)},
    "lecC",
    NOW,
  ),
  {allowed: true, reason: "expired"},
);

// --- resolveRollingWindowPolicy regression ---
check(
  "policy: Center Free matrix enabled -> enforced 24h",
  resolveRollingWindowPolicy({
    enabledFeature: {enabled: true},
    hoursFeature: {feature_value: 24},
    studentType: "center_student",
    planKey: "free",
    planId: "free",
  }),
  {enforced: true, hours: 24},
);
check(
  "policy: Pro matrix disabled -> not enforced",
  resolveRollingWindowPolicy({
    enabledFeature: {enabled: false},
    hoursFeature: {feature_value: 24},
    studentType: "center_student",
    planKey: "pro",
    planId: "pro",
  }),
  {enforced: false, hours: 24},
);
check(
  "policy: legacy Center Free fallback still enforced",
  resolveRollingWindowPolicy({
    enabledFeature: null,
    hoursFeature: null,
    studentType: "center_student",
    planKey: "free",
    planId: "free",
  }),
  {enforced: true, hours: 24},
);

// --- resolveGuestPreviewSeconds: the observed 420 source ---
check(
  "preview: lecture 7 minutes -> 420s (observed live value source)",
  resolveGuestPreviewSeconds({
    guestEnabled: true,
    lectureMinutes: 7,
    planDefaultMinutes: null,
  }),
  420,
);
check(
  "preview: disabled gate -> null (issuance throws, unchanged)",
  resolveGuestPreviewSeconds({
    guestEnabled: false,
    lectureMinutes: 7,
    planDefaultMinutes: 7,
  }),
  null,
);

console.log(`issuance_lecture_matcher tests passed (${passed}).`);
