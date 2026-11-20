/**
 * ADR-010 — pure contract of the Firestore-backed catalog read path.
 *
 * Locks the eligibility filtering, the emergency deny-list (Mission 8 §F.3.7),
 * the document-id integrity check, the deterministic ordering and the closed
 * client projection. No emulator, no network, no Firestore.
 */
const assert = require("node:assert/strict");
const reader = require("../lib/core/video/bunny_library_catalog_reader.js");

let passed = 0;
function check(name, actual, expected) {
  assert.deepEqual(actual, expected, name);
  passed++;
  console.log(`ok - ${name}`);
}

function catalogDoc(overrides = {}) {
  return {
    library_id: "780700",
    display_name: "DrTarek Staging",
    status: "active",
    pull_zone_id: 6807898,
    playback_host: "vz-b5f9cb68-f06.b-cdn.net",
    token_auth_enabled: true,
    token_auth_verified: true,
    credential_refs: {
      stream_api_key: "BUNNY_780700_STREAM_API_KEY",
      token_key: "BUNNY_780700_TOKEN_KEY",
    },
    source: "manual_registration",
    last_error_code: null,
    ...overrides,
  };
}

const doc = (id, data) => ({id, data});
const eligible = (id, name = `Library ${id}`) => ({
  libraryId: id,
  displayName: name,
});

// --- single-document eligibility ---
check(
  "active + verified library is eligible",
  reader.selectEligibleBunnyLibraries(
    [doc("780700", catalogDoc())],
    {},
  ),
  [eligible("780700", "DrTarek Staging")],
);

check(
  "disabled library is excluded",
  reader.selectEligibleBunnyLibraries(
    [doc("775315", catalogDoc({library_id: "775315", status: "disabled"}))],
    {},
  ),
  [],
);

check(
  "pending_verification library is excluded",
  reader.selectEligibleBunnyLibraries(
    [doc("999001", catalogDoc({
      library_id: "999001",
      status: "pending_verification",
    }))],
    {},
  ),
  [],
);

check(
  "error library is excluded",
  reader.selectEligibleBunnyLibraries(
    [doc("999005", catalogDoc({library_id: "999005", status: "error"}))],
    {},
  ),
  [],
);

check(
  "token auth disabled is excluded",
  reader.selectEligibleBunnyLibraries(
    [doc("999006", catalogDoc({
      library_id: "999006",
      token_auth_enabled: false,
    }))],
    {},
  ),
  [],
);

check(
  "token auth unverified is excluded",
  reader.selectEligibleBunnyLibraries(
    [doc("999007", catalogDoc({
      library_id: "999007",
      token_auth_verified: false,
    }))],
    {},
  ),
  [],
);

// --- missing / invalid metadata fails closed ---
check(
  "missing display name is excluded",
  reader.selectEligibleBunnyLibraries(
    [doc("999008", catalogDoc({library_id: "999008", display_name: "  "}))],
    {},
  ),
  [],
);

check(
  "missing pull zone is excluded",
  reader.selectEligibleBunnyLibraries(
    [doc("999009", catalogDoc({library_id: "999009", pull_zone_id: 0}))],
    {},
  ),
  [],
);

check(
  "missing playback host is excluded",
  reader.selectEligibleBunnyLibraries(
    [doc("999010", catalogDoc({library_id: "999010", playback_host: ""}))],
    {},
  ),
  [],
);

check(
  "missing credentials are excluded",
  reader.selectEligibleBunnyLibraries(
    [doc("999011", catalogDoc({
      library_id: "999011",
      credential_refs: undefined,
    }))],
    {},
  ),
  [],
);

check(
  "credential VALUE masquerading as a name is excluded",
  reader.selectEligibleBunnyLibraries(
    [doc("999012", catalogDoc({
      library_id: "999012",
      credential_refs: {
        stream_api_key: "a".repeat(40),
        token_key: "BUNNY_999012_TOKEN_KEY",
      },
    }))],
    {},
  ),
  [],
);

check(
  "invalid library id is excluded",
  reader.selectEligibleBunnyLibraries(
    [doc("vz-123", catalogDoc({library_id: "vz-123"}))],
    {},
  ),
  [],
);

check(
  "document id / library_id mismatch is excluded",
  reader.selectEligibleBunnyLibraries(
    [doc("999999", catalogDoc({library_id: "999013"}))],
    {},
  ),
  [],
);

check(
  "null document is excluded",
  reader.selectEligibleBunnyLibraries([doc("999014", null)], {}),
  [],
);

// --- emergency deny-list (Mission 8 §F.3.7) ---
const twoEligible = [
  doc("736742", catalogDoc({
    library_id: "736742",
    display_name: "Production",
    credential_refs: {
      stream_api_key: "BUNNY_736742_STREAM_API_KEY",
      token_key: "BUNNY_736742_TOKEN_KEY",
    },
  })),
  doc("780700", catalogDoc()),
];

check(
  "no deny-list keeps every eligible library",
  reader.selectEligibleBunnyLibraries(twoEligible, {}),
  [eligible("736742", "Production"), eligible("780700", "DrTarek Staging")],
);

check(
  "deny-list reduces to the listed library",
  reader.selectEligibleBunnyLibraries(twoEligible, {
    BUNNY_ACTIVE_LIBRARY_IDS: "780700",
  }),
  [eligible("780700", "DrTarek Staging")],
);

check(
  "deny-list can reduce to an empty list",
  reader.selectEligibleBunnyLibraries(twoEligible, {
    BUNNY_ACTIVE_LIBRARY_IDS: "775315",
  }),
  [],
);

check(
  "deny-list never expands eligibility",
  reader.selectEligibleBunnyLibraries(
    [doc("775315", catalogDoc({library_id: "775315", status: "disabled"}))],
    {BUNNY_ACTIVE_LIBRARY_IDS: "775315"},
  ),
  [],
);

check(
  "blank deny-list is treated as not engaged",
  reader.selectEligibleBunnyLibraries(twoEligible, {
    BUNNY_ACTIVE_LIBRARY_IDS: "   ",
  }),
  [eligible("736742", "Production"), eligible("780700", "DrTarek Staging")],
);

check(
  "malformed deny-list fails closed (deny all)",
  reader.selectEligibleBunnyLibraries(twoEligible, {
    BUNNY_ACTIVE_LIBRARY_IDS: "not-an-id",
  }),
  [],
);

// --- ordering, duplicates, empty catalog, mixed states ---
check(
  "empty catalog returns an empty list",
  reader.selectEligibleBunnyLibraries([], {}),
  [],
);

check(
  "multiple libraries keep only eligible ones, in numeric order",
  reader.selectEligibleBunnyLibraries(
    [
      doc("999003", catalogDoc({library_id: "999003", display_name: "Bad zone", pull_zone_id: 0})),
      doc("780700", catalogDoc()),
      doc("775315", catalogDoc({library_id: "775315", display_name: "Inactive", status: "disabled"})),
      doc("999002", catalogDoc({library_id: "999002", display_name: "No creds", credential_refs: undefined})),
      doc("736742", catalogDoc({
        library_id: "736742",
        display_name: "Production",
        credential_refs: {
          stream_api_key: "BUNNY_736742_STREAM_API_KEY",
          token_key: "BUNNY_736742_TOKEN_KEY",
        },
      })),
    ],
    {},
  ),
  [eligible("736742", "Production"), eligible("780700", "DrTarek Staging")],
);

check(
  "numeric ordering is length-aware (9 before 10)",
  reader.selectEligibleBunnyLibraries(
    [
      doc("10", catalogDoc({library_id: "10", display_name: "Ten", credential_refs: {stream_api_key: "BUNNY_10_STREAM_API_KEY", token_key: "BUNNY_10_TOKEN_KEY"}})),
      doc("9", catalogDoc({library_id: "9", display_name: "Nine", credential_refs: {stream_api_key: "BUNNY_9_STREAM_API_KEY", token_key: "BUNNY_9_TOKEN_KEY"}})),
    ],
    {},
  ),
  [eligible("9", "Nine"), eligible("10", "Ten")],
);

check(
  "duplicate documents are de-duplicated",
  reader.selectEligibleBunnyLibraries(
    [doc("780700", catalogDoc()), doc("780700", catalogDoc())],
    {},
  ),
  [eligible("780700", "DrTarek Staging")],
);

// --- projection is closed ---
const projection = reader.selectEligibleBunnyLibraries(
  [doc("780700", catalogDoc())],
  {},
);
check(
  "projection exposes only libraryId and displayName",
  Object.keys(projection[0]).sort(),
  ["displayName", "libraryId"],
);
assert.ok(
  !JSON.stringify(projection).includes("BUNNY_"),
  "projection must not contain credential names",
);
passed++;
console.log("ok - projection contains no credential references");
assert.ok(
  !JSON.stringify(projection).includes("vz-"),
  "projection must not contain the playback host",
);
passed++;
console.log("ok - projection contains no playback host");
assert.ok(
  !JSON.stringify(projection).includes("pull_zone"),
  "projection must not contain the pull zone id",
);
passed++;
console.log("ok - projection contains no pull zone id");

// --- Firestore adapter (fake store, still no emulator) ---
(async () => {
  const store = {
    collection(name) {
      assert.equal(name, "bunny_libraries", "adapter reads bunny_libraries");
      return {
        get: async () => ({
          docs: [
            {id: "780700", data: () => catalogDoc()},
            {id: "775315", data: () => catalogDoc({library_id: "775315", status: "disabled"})},
          ],
        }),
      };
    },
  };
  const loaded = await reader.loadEligibleBunnyLibraries(store, {});
  check(
    "Firestore adapter maps docs and applies the same gate",
    loaded,
    [eligible("780700", "DrTarek Staging")],
  );

  const failingStore = {
    collection() {
      return {
        get: async () => {
          throw new Error("simulated catalog outage");
        },
      };
    },
  };
  let threw = false;
  try {
    await reader.loadEligibleBunnyLibraries(failingStore, {});
  } catch (error) {
    threw = error instanceof Error;
  }
  assert.equal(threw, true, "adapter must surface read failures");
  passed++;
  console.log("ok - adapter surfaces read failures instead of an empty success");

  console.log(`\n${passed} checks passed`);
})().catch((error) => {
  console.error("FAIL", error);
  process.exitCode = 1;
});
