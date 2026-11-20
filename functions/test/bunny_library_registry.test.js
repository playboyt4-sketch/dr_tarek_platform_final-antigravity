/**
 * ADR-010 — pure Bunny library registry contract.
 *
 * Locks the fail-closed behaviour the backend depends on: trusted resource
 * record first, default library only for legacy rows, explicit activation for
 * any additional library, and never a silent fallback to another library's
 * credentials. Also covers the mapping planner used by the dry-run utility.
 * No emulator, no network.
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
  BUNNY_LIBRARIES,
  resolveBunnyLibraryForResource,
  resolveBunnyPlaybackRuntime,
  resolveBunnyStreamApiRuntime,
  planBunnyLibraryBackfill,
  validateBunnyLibraryMapping,
  firstVideoFieldsFromResources,
} = functions;

for (const [name, value] of Object.entries({
  DEFAULT_BUNNY_LIBRARY_ID,
  BUNNY_LIBRARIES,
  resolveBunnyLibraryForResource,
  resolveBunnyPlaybackRuntime,
  resolveBunnyStreamApiRuntime,
  planBunnyLibraryBackfill,
  validateBunnyLibraryMapping,
  firstVideoFieldsFromResources,
})) {
  assert.ok(value !== undefined, `${name} must be exported`);
}

let passed = 0;
function check(name, actual, expected) {
  assert.deepEqual(actual, expected, name);
  passed++;
  console.log(`ok - ${name}`);
}

const DEFAULT_ENV = {
  BUNNY_PLAYBACK_URL_TEMPLATE: "https://vz-default.b-cdn.net/{video_id}/playlist.m3u8",
  BUNNY_TOKEN_KEY: "fixture-token-key",
  BUNNY_STREAM_API_KEY: "fixture-api-key",
  BUNNY_STREAM_LIBRARY_ID: DEFAULT_BUNNY_LIBRARY_ID,
};

const CONTENT_ENV = {
  ...DEFAULT_ENV,
  BUNNY_ACTIVE_LIBRARY_IDS: "775315",
  BUNNY_775315_PLAYBACK_URL_TEMPLATE: "https://vz-content.b-cdn.net/{video_id}/playlist.m3u8",
  BUNNY_775315_TOKEN_KEY: "fixture-775315-token-key",
  BUNNY_775315_STREAM_API_KEY: "fixture-775315-api-key",
};

// --- library resolution: trusted record ---
check(
  "default library stored on the resource resolves as resource-sourced",
  resolveBunnyLibraryForResource({storedLibraryId: DEFAULT_BUNNY_LIBRARY_ID}, DEFAULT_ENV),
  {ok: true, libraryId: DEFAULT_BUNNY_LIBRARY_ID, source: "resource"},
);
check(
  "legacy resource without a library id falls back to the default library",
  resolveBunnyLibraryForResource({storedLibraryId: undefined}, DEFAULT_ENV),
  {ok: true, libraryId: DEFAULT_BUNNY_LIBRARY_ID, source: "legacy_default"},
);
check(
  "null library id is legacy",
  resolveBunnyLibraryForResource({storedLibraryId: null}, DEFAULT_ENV),
  {ok: true, libraryId: DEFAULT_BUNNY_LIBRARY_ID, source: "legacy_default"},
);
check(
  "empty/whitespace library id is legacy",
  resolveBunnyLibraryForResource({storedLibraryId: "   "}, DEFAULT_ENV),
  {ok: true, libraryId: DEFAULT_BUNNY_LIBRARY_ID, source: "legacy_default"},
);
check(
  "unknown library id fails closed",
  resolveBunnyLibraryForResource({storedLibraryId: "999999"}, DEFAULT_ENV),
  {ok: false, reason: "unknown_library", libraryId: "999999"},
);
check(
  "non-numeric library id fails closed as unknown",
  resolveBunnyLibraryForResource({storedLibraryId: "library-a"}, DEFAULT_ENV),
  {ok: false, reason: "unknown_library", libraryId: "library-a"},
);

// --- second library: defined but NOT activated ---
check(
  "second library is not activated without an allow-list entry",
  resolveBunnyLibraryForResource({storedLibraryId: "775315"}, DEFAULT_ENV),
  {ok: false, reason: "library_not_activated", libraryId: "775315"},
);
check(
  "second library resolves once explicitly activated",
  resolveBunnyLibraryForResource({storedLibraryId: "775315"}, CONTENT_ENV),
  {ok: true, libraryId: "775315", source: "resource"},
);

// --- client hint: validated, never authoritative ---
check(
  "matching client hint keeps the trusted library",
  resolveBunnyLibraryForResource(
    {storedLibraryId: DEFAULT_BUNNY_LIBRARY_ID, clientLibraryHintId: DEFAULT_BUNNY_LIBRARY_ID},
    DEFAULT_ENV,
  ),
  {ok: true, libraryId: DEFAULT_BUNNY_LIBRARY_ID, source: "resource"},
);
check(
  "hint disagreeing with the stored library fails closed (no credential switch)",
  resolveBunnyLibraryForResource(
    {storedLibraryId: DEFAULT_BUNNY_LIBRARY_ID, clientLibraryHintId: "775315"},
    CONTENT_ENV,
  ),
  {ok: false, reason: "library_mismatch", libraryId: DEFAULT_BUNNY_LIBRARY_ID},
);
check(
  "hint on a legacy row is ignored (never selects credentials)",
  resolveBunnyLibraryForResource(
    {storedLibraryId: null, clientLibraryHintId: "775315"},
    CONTENT_ENV,
  ),
  {ok: true, libraryId: DEFAULT_BUNNY_LIBRARY_ID, source: "legacy_default"},
);
check(
  "legacy fallback can be disabled post-migration",
  resolveBunnyLibraryForResource(
    {storedLibraryId: null},
    {...DEFAULT_ENV, BUNNY_LEGACY_LIBRARY_FALLBACK: "false"},
  ),
  {ok: false, reason: "library_not_resolved", libraryId: null},
);

// --- playback runtime: per-library template + key ---
check(
  "default playback runtime uses the existing production env names",
  resolveBunnyPlaybackRuntime(DEFAULT_ENV, DEFAULT_BUNNY_LIBRARY_ID),
  {
    ok: true,
    runtime: {
      libraryId: DEFAULT_BUNNY_LIBRARY_ID,
      playbackUrlTemplate: DEFAULT_ENV.BUNNY_PLAYBACK_URL_TEMPLATE,
      tokenKey: DEFAULT_ENV.BUNNY_TOKEN_KEY,
    },
  },
);
check(
  "activated second library signs with ITS OWN zone and key",
  resolveBunnyPlaybackRuntime(CONTENT_ENV, "775315"),
  {
    ok: true,
    runtime: {
      libraryId: "775315",
      playbackUrlTemplate: CONTENT_ENV.BUNNY_775315_PLAYBACK_URL_TEMPLATE,
      tokenKey: CONTENT_ENV.BUNNY_775315_TOKEN_KEY,
    },
  },
);
check(
  "missing configuration fails closed (no template)",
  resolveBunnyPlaybackRuntime({BUNNY_TOKEN_KEY: "k"}, DEFAULT_BUNNY_LIBRARY_ID),
  {ok: false, reason: "incomplete_configuration", libraryId: DEFAULT_BUNNY_LIBRARY_ID},
);
check(
  "missing configuration fails closed (blank key)",
  resolveBunnyPlaybackRuntime(
    {...DEFAULT_ENV, BUNNY_TOKEN_KEY: "   "},
    DEFAULT_BUNNY_LIBRARY_ID,
  ),
  {ok: false, reason: "incomplete_configuration", libraryId: DEFAULT_BUNNY_LIBRARY_ID},
);
check(
  "unactivated library playback runtime fails closed",
  resolveBunnyPlaybackRuntime(DEFAULT_ENV, "775315"),
  {ok: false, reason: "library_not_activated", libraryId: "775315"},
);
check(
  "unknown library playback runtime fails closed",
  resolveBunnyPlaybackRuntime(DEFAULT_ENV, "12345"),
  {ok: false, reason: "unknown_library", libraryId: "12345"},
);

// --- Stream API (metadata) runtime ---
check(
  "default Stream API runtime keeps the env library id override",
  resolveBunnyStreamApiRuntime(DEFAULT_ENV, DEFAULT_BUNNY_LIBRARY_ID),
  {
    ok: true,
    runtime: {
      libraryId: DEFAULT_BUNNY_LIBRARY_ID,
      apiLibraryId: DEFAULT_BUNNY_LIBRARY_ID,
      apiKey: DEFAULT_ENV.BUNNY_STREAM_API_KEY,
    },
  },
);
check(
  "Stream API metadata is best-effort when unconfigured",
  resolveBunnyStreamApiRuntime({}, DEFAULT_BUNNY_LIBRARY_ID),
  {ok: false, reason: "incomplete_configuration", libraryId: DEFAULT_BUNNY_LIBRARY_ID},
);
check(
  "second library Stream API uses its canonical id",
  resolveBunnyStreamApiRuntime(CONTENT_ENV, "775315"),
  {
    ok: true,
    runtime: {libraryId: "775315", apiLibraryId: "775315", apiKey: "fixture-775315-api-key"},
  },
);

// --- wrong library/video association (as far as data permits) ---
const mapping = [
  {videoId: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", libraryId: "775315"},
  {videoId: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", libraryId: DEFAULT_BUNNY_LIBRARY_ID},
];
check(
  "mapping to an unactivated library is rejected",
  validateBunnyLibraryMapping(mapping, DEFAULT_ENV).length,
  1,
);
check(
  "mapping validates against an activated library",
  validateBunnyLibraryMapping(mapping, CONTENT_ENV),
  [],
);
check(
  "duplicate video id mapped to two libraries is rejected",
  validateBunnyLibraryMapping(
    [
      {videoId: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", libraryId: "775315"},
      {videoId: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", libraryId: DEFAULT_BUNNY_LIBRARY_ID},
    ],
    CONTENT_ENV,
  ),
  ["video aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa is mapped to two libraries (775315, 736742)"],
);

// --- backfill planner ---
const rows = [
  {resourceId: "r-content", bunnyVideoId: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", bunnyLibraryId: null},
  {resourceId: "r-default", bunnyVideoId: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", bunnyLibraryId: null},
  {resourceId: "r-already", bunnyVideoId: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", bunnyLibraryId: DEFAULT_BUNNY_LIBRARY_ID},
  {resourceId: "r-placeholder", bunnyVideoId: "", bunnyLibraryId: null},
  {resourceId: "r-unmapped", bunnyVideoId: "cccccccc-cccc-cccc-cccc-cccccccccccc", bunnyLibraryId: null},
];
const plan = planBunnyLibraryBackfill(rows, mapping, CONTENT_ENV);
check(
  "planner sets only mapped rows and never guesses",
  plan.decisions.map((decision) => [decision.resourceId, decision.action]),
  [
    ["r-content", "set"],
    ["r-default", "set"],
    ["r-already", "unchanged"],
    ["r-placeholder", "skipped_no_video_id"],
    ["r-unmapped", "conflict"],
  ],
);
check("planner summary counts", plan.summary, {
  total: 5,
  set: 2,
  unchanged: 1,
  skippedNoVideoId: 1,
  skippedNotVideo: 0,
  conflict: 1,
  manualReview: 1,
});
const secondRun = planBunnyLibraryBackfill(
  rows.map((row) => ({
    ...row,
    bunnyLibraryId: row.bunnyLibraryId ??
      mapping.find((entry) => entry.videoId === row.bunnyVideoId)?.libraryId ?? null,
  })),
  mapping,
  CONTENT_ENV,
);
check(
  "planner is idempotent after a successful apply",
  secondRun.summary,
  {
    total: 5,
    set: 0,
    unchanged: 3,
    skippedNoVideoId: 1,
    skippedNotVideo: 0,
    conflict: 1,
    manualReview: 1,
  },
);
check(
  "stored library disagreeing with the mapping is a conflict, never overwritten",
  planBunnyLibraryBackfill(
    [{resourceId: "r", bunnyVideoId: mapping[0].videoId, bunnyLibraryId: DEFAULT_BUNNY_LIBRARY_ID}],
    mapping,
    CONTENT_ENV,
  ).decisions[0].action,
  "conflict",
);

// --- first_video projection carries the library additively ---
const projection = firstVideoFieldsFromResources([
  {
    id: "res-1",
    data: {
      resource_type: "video",
      is_visible: true,
      is_deleted: false,
      bunny_video_id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
      bunny_library_id: "775315",
      title: "Lecture",
      display_order: 1,
    },
  },
]);
check("first_video projection exposes bunny_library_id", projection.bunny_library_id, "775315");
check(
  "legacy first_video projection keeps a null library",
  firstVideoFieldsFromResources([
    {
      id: "res-2",
      data: {
        resource_type: "video",
        is_visible: true,
        bunny_video_id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
        display_order: 2,
      },
    },
  ]).bunny_library_id,
  null,
);

// --- Mission 19: a foreign environment's compiled default is not a library ---
{
  const {
    findBunnyLibraryDefinition,
    isBunnyLibraryActive,
  } = require("../lib/core/video/bunny_library_registry.js");
  const STAGING_ENV = {
    ...DEFAULT_ENV,
    BUNNY_DEFAULT_LIBRARY_ID: "780700",
    BUNNY_STREAM_LIBRARY_ID: "780700",
  };
  check(
    "the overridden default is the only default in its environment",
    (() => {
      const definition = findBunnyLibraryDefinition("780700", STAGING_ENV);
      return definition ? {libraryId: definition.libraryId, isDefault: definition.isDefault} : null;
    })(),
    {libraryId: "780700", isDefault: true},
  );
  check(
    "the compiled production default is unknown in staging",
    findBunnyLibraryDefinition(DEFAULT_BUNNY_LIBRARY_ID, STAGING_ENV),
    null,
  );
  check(
    "staging explicit 736742 fails closed",
    resolveBunnyLibraryForResource({storedLibraryId: DEFAULT_BUNNY_LIBRARY_ID}, STAGING_ENV),
    {ok: false, reason: "unknown_library", libraryId: DEFAULT_BUNNY_LIBRARY_ID},
  );
  check(
    "the compiled default slot is not active for a foreign id",
    isBunnyLibraryActive(BUNNY_LIBRARIES.find((entry) => entry.isDefault), STAGING_ENV),
    false,
  );
  check(
    "staging explicit 780700 is accepted as the exact default",
    resolveBunnyLibraryForResource({storedLibraryId: "780700"}, STAGING_ENV),
    {ok: true, libraryId: "780700", source: "resource"},
  );
}

console.log(`bunny_library_registry tests passed (${passed}).`);

// Mission 12 — Secret Manager precedence for the Stream API key.
// The mounted secret always wins; the plain env var is only honoured under
// the Functions emulator, so production can never silently read a stale or
// foreign key (an empty result fails closed as incomplete_configuration).
{
  const {resolveBunnyStreamApiKey} = require("../lib/core/video/bunny_library_registry.js");
  assert.equal(
      resolveBunnyStreamApiKey({secretValue: "  from-secret  ", env: {}, isEmulator: false}),
      "from-secret");
  assert.equal(
      resolveBunnyStreamApiKey({secretValue: "", env: {}, isEmulator: false}),
      "");
  assert.equal(
      resolveBunnyStreamApiKey({
        secretValue: null,
        env: {BUNNY_STREAM_API_KEY: "env-key"},
        isEmulator: false,
      }),
      "",
      "production must not fall back to the plain env var");
  assert.equal(
      resolveBunnyStreamApiKey({
        secretValue: "",
        env: {BUNNY_STREAM_API_KEY: "env-key"},
        isEmulator: true,
      }),
      "env-key",
      "emulator fixtures still resolve");
  assert.equal(
      resolveBunnyStreamApiKey({
        secretValue: "secret-key",
        env: {BUNNY_STREAM_API_KEY: "env-key"},
        isEmulator: true,
      }),
      "secret-key",
      "mounted secret outranks env");
  console.log("PASS stream api key resolution (secret first, no silent env fallback)");
}
