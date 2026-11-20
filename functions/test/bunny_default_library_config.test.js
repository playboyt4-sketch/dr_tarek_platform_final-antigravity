/**
 * ADR-010 — configurable canonical default library.
 *
 * Locks the fix for the staging identity split: the canonical default was a
 * compiled constant while `BUNNY_STREAM_LIBRARY_ID` could point somewhere
 * else, so metadata was read from one library under another library's label.
 *
 * Production behaviour must stay byte-identical: with no override the default
 * is exactly `736742`. Pure module — no emulator, no network.
 */
const assert = require("node:assert/strict");

const registry = require("../lib/core/video/bunny_library_registry.js");

let passed = 0;
function check(name, actual, expected) {
  assert.deepEqual(actual, expected, name);
  passed++;
  console.log(`ok - ${name}`);
}

const {
  DEFAULT_BUNNY_LIBRARY_ID,
  BUNNY_DEFAULT_LIBRARY_VAR,
  resolveDefaultBunnyLibraryId,
  describeBunnyEnvironment,
  findBunnyLibraryDefinition,
  resolveBunnyLibraryForResource,
  resolveBunnyPlaybackRuntime,
  resolveBunnyStreamApiRuntime,
} = registry;

// --- fallback / override ---
check("compiled fallback is the production library", DEFAULT_BUNNY_LIBRARY_ID, "736742");
check("no override resolves the compiled fallback", resolveDefaultBunnyLibraryId({}), "736742");
check(
  "override wins",
  resolveDefaultBunnyLibraryId({[BUNNY_DEFAULT_LIBRARY_VAR]: "780700"}),
  "780700",
);
check(
  "override is trimmed",
  resolveDefaultBunnyLibraryId({[BUNNY_DEFAULT_LIBRARY_VAR]: "  780700  "}),
  "780700",
);
check(
  "non-numeric override is ignored (fails safe to production default)",
  resolveDefaultBunnyLibraryId({[BUNNY_DEFAULT_LIBRARY_VAR]: "staging"}),
  "736742",
);
check(
  "empty override is ignored",
  resolveDefaultBunnyLibraryId({[BUNNY_DEFAULT_LIBRARY_VAR]: "   "}),
  "736742",
);

// --- invariant diagnostic ---
check(
  "matching environment reports no split",
  describeBunnyEnvironment({
    [BUNNY_DEFAULT_LIBRARY_VAR]: "780700",
    BUNNY_STREAM_LIBRARY_ID: "780700",
  }),
  {defaultLibraryId: "780700", streamApiLibraryId: "780700", mismatch: false},
);
check(
  "the historical drift is detected",
  describeBunnyEnvironment({
    [BUNNY_DEFAULT_LIBRARY_VAR]: "736742",
    BUNNY_STREAM_LIBRARY_ID: "780700",
  }),
  {defaultLibraryId: "736742", streamApiLibraryId: "780700", mismatch: true},
);
check(
  "absent stream id falls back to the default",
  describeBunnyEnvironment({}),
  {defaultLibraryId: "736742", streamApiLibraryId: "736742", mismatch: false},
);

// --- production behaviour unchanged ---
const PROD_ENV = {
  BUNNY_PLAYBACK_URL_TEMPLATE: "https://vz-c6abe953-876.b-cdn.net/{video_id}/playlist.m3u8",
  BUNNY_TOKEN_KEY: "fixture-token",
  BUNNY_STREAM_API_KEY: "fixture-api",
  BUNNY_STREAM_LIBRARY_ID: "736742",
};
check(
  "production legacy row still resolves 736742",
  resolveBunnyLibraryForResource({storedLibraryId: null}, PROD_ENV),
  {ok: true, libraryId: "736742", source: "legacy_default"},
);
check(
  "production playback runtime unchanged",
  resolveBunnyPlaybackRuntime(PROD_ENV, DEFAULT_BUNNY_LIBRARY_ID),
  {
    ok: true,
    runtime: {
      libraryId: "736742",
      playbackUrlTemplate: PROD_ENV.BUNNY_PLAYBACK_URL_TEMPLATE,
      tokenKey: "fixture-token",
    },
  },
);
check(
  "production Stream runtime unchanged",
  resolveBunnyStreamApiRuntime(PROD_ENV, DEFAULT_BUNNY_LIBRARY_ID),
  {ok: true, runtime: {libraryId: "736742", apiLibraryId: "736742", apiKey: "fixture-api"}},
);

// --- staging: canonical id follows the override ---
const STAGING_ENV = {
  [BUNNY_DEFAULT_LIBRARY_VAR]: "780700",
  BUNNY_PLAYBACK_URL_TEMPLATE: "https://vz-b5f9cb68-f06.b-cdn.net/{video_id}/playlist.m3u8",
  BUNNY_TOKEN_KEY: "fixture-staging-token",
  BUNNY_STREAM_API_KEY: "fixture-staging-api",
  BUNNY_STREAM_LIBRARY_ID: "780700",
};
check(
  "staging legacy row resolves the staging library",
  resolveBunnyLibraryForResource({storedLibraryId: null}, STAGING_ENV),
  {ok: true, libraryId: "780700", source: "legacy_default"},
);
check(
  "staging playback runtime uses the staging library id",
  resolveBunnyPlaybackRuntime(STAGING_ENV, "780700"),
  {
    ok: true,
    runtime: {
      libraryId: "780700",
      playbackUrlTemplate: STAGING_ENV.BUNNY_PLAYBACK_URL_TEMPLATE,
      tokenKey: "fixture-staging-token",
    },
  },
);
check(
  "staging Stream runtime targets the staging library",
  resolveBunnyStreamApiRuntime(STAGING_ENV, "780700"),
  {ok: true, runtime: {libraryId: "780700", apiLibraryId: "780700", apiKey: "fixture-staging-api"}},
);
check(
  "the overridden default is registry-known and flagged default",
  (() => {
    const definition = findBunnyLibraryDefinition("780700", STAGING_ENV);
    return definition ? {libraryId: definition.libraryId, isDefault: definition.isDefault} : null;
  })(),
  {libraryId: "780700", isDefault: true},
);

// --- non-default libraries still need explicit activation ---
check(
  "a stored non-default library is not activated implicitly",
  resolveBunnyLibraryForResource({storedLibraryId: "780700"}, PROD_ENV),
  {ok: false, reason: "unknown_library", libraryId: "780700"},
);

// --- fail closed ---
check(
  "staging with a missing template fails closed",
  resolveBunnyPlaybackRuntime(
    {[BUNNY_DEFAULT_LIBRARY_VAR]: "780700", BUNNY_TOKEN_KEY: "fixture"},
    "780700",
  ),
  {ok: false, reason: "incomplete_configuration", libraryId: "780700"},
);
check(
  "legacy fallback can still be disabled",
  resolveBunnyLibraryForResource(
    {storedLibraryId: null},
    {...PROD_ENV, BUNNY_LEGACY_LIBRARY_FALLBACK: "false"},
  ),
  {ok: false, reason: "legacy_fallback_disabled", libraryId: "736742"},
);

console.log(`\n${passed} checks passed`);
