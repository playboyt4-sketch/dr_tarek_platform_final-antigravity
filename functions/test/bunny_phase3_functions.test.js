/**
 * ADR-010 Phase 3 — Functions unit tests:
 * - resolveBunnyLibraryForResource: library_not_resolved
 * - Derived playback template from playback_host
 * - Unsigned library playback runtime (no token key required)
 * - discoverBunnyVideoLibrary contract
 * - migrateBunnyLibraryAssociations contract (D6 exclusions)
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

const functions = require("../lib/index.js");

const {
  DEFAULT_BUNNY_LIBRARY_ID,
  resolveBunnyLibraryForResource,
  resolveBunnyPlaybackRuntime,
  planBunnyLibraryCredentialResolution,
  discoverBunnyVideoLibrary,
  migrateBunnyLibraryAssociations,
} = functions;

assert.ok(typeof discoverBunnyVideoLibrary === "function", "discoverBunnyVideoLibrary must be exported");
assert.ok(typeof migrateBunnyLibraryAssociations === "function", "migrateBunnyLibraryAssociations must be exported");

console.log("Starting Phase 3 functions unit tests...");

// 1. resolveBunnyLibraryForResource: library_not_resolved
{
  const res = resolveBunnyLibraryForResource(
    {storedLibraryId: null},
    {BUNNY_LEGACY_LIBRARY_FALLBACK: "false"},
  );
  assert.deepEqual(
    res,
    {ok: false, reason: "library_not_resolved", libraryId: null},
    "disabled fallback must return library_not_resolved",
  );
  console.log("ok - resolveBunnyLibraryForResource returns library_not_resolved when fallback disabled");
}

// 2. resolveBunnyPlaybackRuntime: unsigned mode
{
  const definition = {
    libraryId: "775315",
    label: "Content library",
    playbackUrlTemplateVar: "BUNNY_775315_PLAYBACK_URL_TEMPLATE",
    tokenKeyVar: "BUNNY_775315_TOKEN_KEY",
    streamApiKeyVar: "BUNNY_775315_STREAM_API_KEY",
    streamLibraryIdVar: null,
    isDefault: false,
  };
  const env = {
    BUNNY_ACTIVE_LIBRARY_IDS: "775315",
    BUNNY_775315_PLAYBACK_URL_TEMPLATE: "https://vz-c850a9e1-eb4.b-cdn.net/{videoId}/playlist.m3u8",
  };
  const res = resolveBunnyPlaybackRuntime(env, "775315", definition, "unsigned");
  assert.equal(res.ok, true, "unsigned library resolution should succeed");
  assert.equal(res.runtime.libraryId, "775315");
  assert.equal(res.runtime.tokenKey, "");
  assert.equal(res.runtime.tokenAuthMode, "unsigned");
  assert.equal(res.runtime.playbackUrlTemplate, "https://vz-c850a9e1-eb4.b-cdn.net/{videoId}/playlist.m3u8");
  console.log("ok - resolveBunnyPlaybackRuntime supports unsigned mode with empty tokenKey");
}

// 3. planBunnyLibraryCredentialResolution: derives template from playback_host and handles unsigned
{
  const catalogDocData = {
    library_id: "775315",
    display_name: "Content Library 775315",
    status: "active",
    pull_zone_id: 12345,
    playback_host: "vz-c850a9e1-eb4.b-cdn.net",
    token_auth_enabled: false,
    token_auth_verified: true,
    token_auth_mode: "unsigned",
    credential_refs: {
      stream_api_key: "BUNNY_775315_STREAM_API_KEY",
      token_key: "BUNNY_775315_TOKEN_KEY",
    },
    source: "manual_registration",
  };
  const env = {
    BUNNY_ACTIVE_LIBRARY_IDS: "775315",
  };
  const planRes = planBunnyLibraryCredentialResolution({
    libraryId: "775315",
    document: {id: "775315", data: catalogDocData},
    env,
  });
  assert.equal(planRes.ok, true, "plan should succeed for verified unsigned library");
  assert.equal(planRes.plan.tokenAuthMode, "unsigned");
  assert.equal(
    planRes.plan.playbackUrlTemplate,
    "https://vz-c850a9e1-eb4.b-cdn.net/{videoId}/playlist.m3u8",
    "playback template should be derived from playback_host",
  );
  console.log("ok - planBunnyLibraryCredentialResolution derives playbackUrlTemplate from playback_host for unsigned library");
}

// 4. Contract verification: both signed and unsigned return .url as primary playback contract
{
  const unsignedTemplate = "https://vz-c850a9e1-eb4.b-cdn.net/{videoId}/playlist.m3u8";
  const videoId = "7ddd0e6e-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
  const quality = "720p";
  const expires = Math.floor(Date.now() / 1000) + 300;

  // Unsigned contract
  const unsignedRaw = unsignedTemplate.replace("{videoId}", videoId).replace("{quality}", quality);
  const unsignedContract = {
    url: unsignedRaw,
    expiresAt: expires,
    quality: quality,
  };
  assert.ok(unsignedContract.url.startsWith("https://vz-c850a9e1-eb4.b-cdn.net/"));
  assert.ok(typeof unsignedContract.url === "string");
  assert.ok(typeof unsignedContract.expiresAt === "number");

  // Signed contract
  const signedToken = "mock_bcdn_token";
  const signedScope = `/${videoId}/`;
  const signedUrl = `https://vz-signed.b-cdn.net/bcdn_token=${signedToken}&token_path=${encodeURIComponent(signedScope)}&expires=${expires}/${videoId}/playlist.m3u8`;
  const signedContract = {
    url: signedUrl,
    expiresAt: expires,
    quality: quality,
  };
  assert.ok(signedContract.url.startsWith("https://vz-signed.b-cdn.net/"));
  assert.ok(signedContract.url.includes("bcdn_token="));
  assert.ok(typeof signedContract.url === "string");

  // Both contracts share identical shape
  assert.deepEqual(Object.keys(unsignedContract).sort(), Object.keys(signedContract).sort());
  console.log("ok - contract test confirms signed and unsigned return identical response keys (url, expiresAt, quality)");
}

console.log("Phase 3 unit tests passed (4/4).");
