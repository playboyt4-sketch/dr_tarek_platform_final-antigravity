/**
 * Unit tests for buildBunnyFileUrl:
 * Ensures buildBunnyFileUrl returns an unsigned direct URL for libraries configured with tokenAuthMode: 'unsigned'
 * and returns a token-signed URL with bcdn_token for libraries configured with tokenAuthMode: 'signed'.
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
  console.error("Failed to load functions/lib/index.js:", error);
  process.exit(1);
}

const { buildBunnyFileUrl } = functions;

function doc(libraryId, overrides = {}) {
  return {
    id: libraryId,
    data: {
      library_id: libraryId,
      display_name: `Library ${libraryId}`,
      status: "active",
      pull_zone_id: 123456,
      playback_host: "vz-test.b-cdn.net",
      source: "manual_registration",
      token_auth_enabled: true,
      token_auth_verified: true,
      credential_refs: {
        stream_api_key: `BUNNY_${libraryId}_STREAM_API_KEY`,
        token_key: `BUNNY_${libraryId}_TOKEN_KEY`,
      },
      ...overrides,
    },
  };
}

const LIB_UNSIGNED = "780701";
const LIB_SIGNED = "780702";

const deps = {
  catalog: {
    get: async (id) => {
      if (id === LIB_UNSIGNED) {
        return doc(LIB_UNSIGNED, {
          token_auth_enabled: false,
          token_auth_verified: true,
          token_auth_mode: "unsigned",
        });
      }
      if (id === LIB_SIGNED) {
        return doc(LIB_SIGNED, {
          token_auth_enabled: true,
          token_auth_verified: true,
          token_auth_mode: "signed",
        });
      }
      return null;
    },
  },
  secrets: {
    readSecret: async () => "secret-token-signing-key-12345",
  },
  env: {
    BUNNY_ACTIVE_LIBRARY_IDS: `${LIB_UNSIGNED},${LIB_SIGNED}`,
    [`BUNNY_${LIB_UNSIGNED}_PLAYBACK_URL_TEMPLATE`]: "https://vz-unsigned.b-cdn.net/{video_id}/playlist.m3u8",
    [`BUNNY_${LIB_SIGNED}_PLAYBACK_URL_TEMPLATE`]: "https://vz-signed.b-cdn.net/{video_id}/playlist.m3u8",
  },
};

async function run() {
  console.log("Starting buildBunnyFileUrl unit tests...");

  // 1. Unsigned library returns direct URL without bcdn_token
  const unsignedUrl = await buildBunnyFileUrl("vid-abc-123", "thumbnail.jpg", 3600, LIB_UNSIGNED, deps);
  assert.equal(
    unsignedUrl,
    "https://vz-unsigned.b-cdn.net/vid-abc-123/thumbnail.jpg",
    "Unsigned library URL must match direct origin/videoId/fileName shape",
  );
  assert.ok(
    !unsignedUrl.includes("bcdn_token="),
    "Unsigned library URL must NOT contain bcdn_token parameter",
  );
  assert.ok(
    !unsignedUrl.includes("token_path="),
    "Unsigned library URL must NOT contain token_path parameter",
  );
  console.log("ok - buildBunnyFileUrl returns plain unsigned URL for unsigned library");

  // 2. Signed library returns signed URL with bcdn_token, token_path, and expires
  const signedUrl = await buildBunnyFileUrl("vid-abc-123", "thumbnail.jpg", 3600, LIB_SIGNED, deps);
  assert.ok(
    signedUrl.startsWith("https://vz-signed.b-cdn.net/bcdn_token="),
    "Signed library URL must start with bcdn_token segment",
  );
  assert.ok(
    signedUrl.includes("token_path=%2Fvid-abc-123%2F"),
    "Signed library URL must include encoded token_path",
  );
  assert.ok(
    signedUrl.includes("&expires="),
    "Signed library URL must include expires parameter",
  );
  assert.ok(
    signedUrl.endsWith("/vid-abc-123/thumbnail.jpg"),
    "Signed library URL must end with /videoId/fileName path",
  );
  console.log("ok - buildBunnyFileUrl returns signed tokenized URL for signed library");

  console.log("All buildBunnyFileUrl unit tests passed successfully.");
}

run().catch((err) => {
  console.error("buildBunnyFileUrl test failed:", err);
  process.exit(1);
});
