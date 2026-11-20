/**
 * ADR-010 — migration dry-run tooling safety contract.
 *
 * Proves the backfill tooling cannot write, refuses ambiguous input, is
 * idempotent, detects stale snapshots, and produces usable backup/rollback
 * metadata. Pure — no emulator, no Firestore, no network.
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
  DEFAULT_BUNNY_LIBRARY_ID,
  bunnyPosterCacheKey,
  validateBunnyLibraryMapping,
  planBunnyLibraryBackfill,
  resolveBunnyLibraryBackfillMode,
  evaluateBunnyLibraryBackfillWrite,
  buildBunnyLibraryBackfillBackup,
  BUNNY_LIBRARY_MAPPING_FIELDS,
} = functions;

let passed = 0;
function check(name, actual, expected) {
  assert.deepEqual(actual, expected, name);
  passed++;
  console.log(`ok - ${name}`);
}

const CONTENT_ENV = {
  BUNNY_ACTIVE_LIBRARY_IDS: "775315",
  BUNNY_775315_PLAYBACK_URL_TEMPLATE: "https://vz-content.b-cdn.net/{video_id}/playlist.m3u8",
  BUNNY_775315_TOKEN_KEY: "fixture-775315-token-key",
  BUNNY_775315_STREAM_API_KEY: "fixture-775315-api-key",
};

const VIDEO_A = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
const VIDEO_B = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";

// --- execution mode: writes are structurally unavailable ---
check(
  "default mode is dry-run",
  resolveBunnyLibraryBackfillMode({}),
  {mode: "dry-run", reason: null},
);
check(
  "apply mode is refused",
  resolveBunnyLibraryBackfillMode({apply: true}).mode,
  "blocked_apply",
);
check(
  "apply refusal explains why",
  resolveBunnyLibraryBackfillMode({apply: true}).reason.includes("disabled in this build"),
  true,
);
check(
  "mapping field allow-list is explicit",
  BUNNY_LIBRARY_MAPPING_FIELDS.slice().sort(),
  ["lectureId", "libraryId", "resourceId", "subjectId", "videoId"],
);

// --- poster cache isolation between libraries ---
check(
  "cache keys isolate the same video id across libraries",
  bunnyPosterCacheKey("775315", VIDEO_A) === bunnyPosterCacheKey(DEFAULT_BUNNY_LIBRARY_ID, VIDEO_A),
  false,
);
check(
  "cache key is stable within a library",
  bunnyPosterCacheKey(DEFAULT_BUNNY_LIBRARY_ID, VIDEO_A),
  `${DEFAULT_BUNNY_LIBRARY_ID}:${VIDEO_A}`,
);

// --- mapping validation ---
const validMapping = [
  {videoId: VIDEO_A, libraryId: "775315", resourceId: "res-a", lectureId: "lec-1", subjectId: "sub-1"},
  {videoId: VIDEO_B, libraryId: "775315"},
];
check(
  "well-formed mapping validates",
  validateBunnyLibraryMapping(validMapping, CONTENT_ENV),
  [],
);
check(
  "unexpected field is rejected",
  validateBunnyLibraryMapping([{videoId: VIDEO_A, libraryId: "775315", libaryId: "typo"}], CONTENT_ENV),
  ["mapping[0] has unexpected field \"libaryId\""],
);
check(
  "unknown library is rejected",
  validateBunnyLibraryMapping([{videoId: VIDEO_A, libraryId: "999999"}], CONTENT_ENV),
  ["mapping[0] (aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa) references unknown library 999999"],
);
check(
  "unactivated library is rejected",
  validateBunnyLibraryMapping([{videoId: VIDEO_A, libraryId: "775315"}], {}),
  ["mapping[0] (aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa) references library 775315 that is not configured"],
);
check(
  "duplicate video id is rejected",
  validateBunnyLibraryMapping(
    [
      {videoId: VIDEO_A, libraryId: "775315"},
      {videoId: VIDEO_A, libraryId: "775315"},
    ],
    CONTENT_ENV,
  ),
  [`video ${VIDEO_A} is mapped more than once`],
);
check(
  "duplicate resource assignment is rejected",
  validateBunnyLibraryMapping(
    [
      {videoId: VIDEO_A, libraryId: "775315", resourceId: "res-a"},
      {videoId: VIDEO_B, libraryId: "775315", resourceId: "res-a"},
    ],
    CONTENT_ENV,
  ),
  ["resource res-a is mapped more than once"],
);
check(
  "empty video id is rejected",
  validateBunnyLibraryMapping([{videoId: "  ", libraryId: "775315"}], CONTENT_ENV),
  ["mapping[0] has an empty videoId"],
);

// --- planner ---
const rows = [
  {resourceId: "res-a", bunnyVideoId: VIDEO_A, bunnyLibraryId: null, resourceType: "video", lectureId: "lec-1", subjectId: "sub-1", updateTime: "2026-11-12T00:00:00.000Z"},
  {resourceId: "res-b", bunnyVideoId: VIDEO_B, bunnyLibraryId: "775315", resourceType: "video", lectureId: "lec-2", subjectId: "sub-1", updateTime: "2026-11-12T01:00:00.000Z"},
];
const plan = planBunnyLibraryBackfill(rows, validMapping, CONTENT_ENV);
check(
  "planner writes only the resource missing an association",
  plan.decisions.map((decision) => [decision.resourceId, decision.action]),
  [["res-a", "set"], ["res-b", "unchanged"]],
);
check("clean plan is writable", plan.writable, true);
check("clean plan summary", plan.summary, {
  total: 2, set: 1, unchanged: 1, skippedNoVideoId: 0, skippedNotVideo: 0, conflict: 0, manualReview: 0,
});

check(
  "non-video resources are skipped, never written",
  planBunnyLibraryBackfill(
    [{resourceId: "res-pdf", bunnyVideoId: null, bunnyLibraryId: null, resourceType: "pdf"}],
    validMapping,
    CONTENT_ENV,
  ).decisions[0].action,
  "skipped_not_video",
);
check(
  "placeholder rows (no video id) are skipped",
  planBunnyLibraryBackfill(
    [{resourceId: "res-empty", bunnyVideoId: "", bunnyLibraryId: null, resourceType: "video"}],
    validMapping,
    CONTENT_ENV,
  ).decisions[0].action,
  "skipped_no_video_id",
);
check(
  "unmapped video id is a conflict, never a guess",
  planBunnyLibraryBackfill(
    [{resourceId: "res-x", bunnyVideoId: "cccccccc-cccc-cccc-cccc-cccccccccccc", bunnyLibraryId: null, resourceType: "video"}],
    validMapping,
    CONTENT_ENV,
  ).decisions[0].action,
  "conflict",
);
check(
  "mapping scoped to another resource is a conflict",
  planBunnyLibraryBackfill(
    [{resourceId: "res-other", bunnyVideoId: VIDEO_A, bunnyLibraryId: null, resourceType: "video"}],
    validMapping,
    CONTENT_ENV,
  ).decisions[0].reason,
  "mapping is scoped to resource res-a",
);
check(
  "lecture mismatch is a conflict",
  planBunnyLibraryBackfill(
    [{resourceId: "res-a", bunnyVideoId: VIDEO_A, bunnyLibraryId: null, resourceType: "video", lectureId: "lec-9", subjectId: "sub-1"}],
    validMapping,
    CONTENT_ENV,
  ).decisions[0].action,
  "conflict",
);
check(
  "missing lecture identity cannot be silently accepted",
  planBunnyLibraryBackfill(
    [{resourceId: "res-a", bunnyVideoId: VIDEO_A, bunnyLibraryId: null, resourceType: "video"}],
    validMapping,
    CONTENT_ENV,
  ).decisions[0].reason,
  "cannot verify lectureId (missing on the resource)",
);
check(
  "already-correct association is idempotent",
  planBunnyLibraryBackfill(
    [{resourceId: "res-a", bunnyVideoId: VIDEO_A, bunnyLibraryId: "775315", resourceType: "video", lectureId: "lec-1", subjectId: "sub-1"}],
    validMapping,
    CONTENT_ENV,
  ).decisions[0].action,
  "unchanged",
);
check(
  "conflicting stored library is never overwritten",
  planBunnyLibraryBackfill(
    [{resourceId: "res-a", bunnyVideoId: VIDEO_A, bunnyLibraryId: DEFAULT_BUNNY_LIBRARY_ID, resourceType: "video", lectureId: "lec-1", subjectId: "sub-1"}],
    validMapping,
    CONTENT_ENV,
  ).decisions[0].action,
  "conflict",
);
check(
  "mapping entry pointing at a missing resource is reported",
  planBunnyLibraryBackfill([], validMapping, CONTENT_ENV).unresolvedMappings,
  [{resourceId: "res-a", videoId: VIDEO_A, reason: "mapping targets a resource that is not in the snapshot"}],
);
check(
  "plan with unresolved mappings is not writable",
  planBunnyLibraryBackfill([], validMapping, CONTENT_ENV).writable,
  false,
);
check(
  "invalid mapping blocks the whole plan",
  planBunnyLibraryBackfill(rows, [{videoId: VIDEO_A, libraryId: "999999"}], CONTENT_ENV).writable,
  false,
);

// --- concurrency / write evaluation (mocked, no writes) ---
const setDecision = plan.decisions.find((decision) => decision.resourceId === "res-a");
check(
  "writes are disabled unless explicitly enabled",
  evaluateBunnyLibraryBackfillWrite(setDecision, rows[0], {}),
  {allowed: false, reason: "writes_disabled"},
);
check(
  "explicit enablement + matching snapshot allows a future write",
  evaluateBunnyLibraryBackfillWrite(setDecision, rows[0], {
    writesEnabled: true,
    expectedUpdateTime: "2026-11-12T00:00:00.000Z",
  }),
  {allowed: true, reason: "ok"},
);
check(
  "stale snapshot is detected",
  evaluateBunnyLibraryBackfillWrite(setDecision, rows[0], {
    writesEnabled: true,
    expectedUpdateTime: "2026-11-12T05:00:00.000Z",
  }),
  {allowed: false, reason: "stale_snapshot"},
);
check(
  "unchanged decisions are not writes",
  evaluateBunnyLibraryBackfillWrite(
    plan.decisions.find((decision) => decision.resourceId === "res-b"),
    rows[1],
    {writesEnabled: true},
  ).reason,
  "not_a_write",
);
check(
  "missing snapshot row is refused",
  evaluateBunnyLibraryBackfillWrite(setDecision, null, {writesEnabled: true}).reason,
  "resource_missing",
);

// --- backup / rollback metadata ---
const backup = buildBunnyLibraryBackfillBackup(plan, rows, "2026-11-12T00:00:00.000Z");
check("backup covers exactly the planned writes", backup.entries.length, 1);
check("backup records previous and next values", backup.entries[0], {
  resourceId: "res-a",
  videoId: VIDEO_A,
  previousLibraryId: null,
  nextLibraryId: "775315",
  lectureId: "lec-1",
  subjectId: "sub-1",
  updateTime: "2026-11-12T00:00:00.000Z",
});
check("backup is timestamped", backup.createdAt, "2026-11-12T00:00:00.000Z");
check("backup documents the rollback path", backup.rollback.includes("previousLibraryId"), true);

// --- re-plan after an applied result is fully idempotent ---
const afterRows = rows.map((row) => ({...row, bunnyLibraryId: row.bunnyLibraryId ?? "775315"}));
check(
  "re-plan after apply has nothing to write",
  planBunnyLibraryBackfill(afterRows, validMapping, CONTENT_ENV).summary.set,
  0,
);

console.log(`bunny_library_migration tests passed (${passed}).`);
