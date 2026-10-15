/**
 * Bunny video identifier strict Video-ID contract (security regression suite).
 *
 * Approved contract (Platform Owner):
 *   Dashboard/content storage: bare Bunny Video ID (GUID) only.
 *   CASE 1: bare GUID -> ACCEPT.
 *   CASE 2: Bunny URL containing a GUID -> REJECT (never extracted).
 *   CASE 3: arbitrary non-GUID string -> REJECT.
 *   CASE 4: null/missing -> REJECT.
 *
 * This suite pins the strict contract on the exported pure helpers
 * `normalizeBunnyVideoIdForLookup` (trim-only, no URL extraction) and
 * `isValidBunnyVideoId` (bare-GUID regex only):
 *  - bare Bunny GUID passes through unchanged and validates;
 *  - a Bunny player/share URL is preserved verbatim by normalize and
 *    FAILS validation (must never yield its embedded GUID);
 *  - invalid/malformed identifiers pass through unchanged and FAIL validation;
 *  - empty/null/undefined normalize to null and FAIL validation;
 *  - exact-match lookup semantics: a GUID-stored row is reachable by its
 *    GUID only, never by a URL containing that GUID.
 *
 * Pure unit tests only: the firebase-admin surface is stubbed exactly like
 * resource_delivery.test.js so lib/index.js loads without an emulator or a
 * real project. No Firestore, no network, no writes.
 *
 *   node test/bunny_video_id_lookup.test.js   (cwd = functions/)
 */
const test = require("firebase-functions-test")({
  projectId: "dr-tarek-platform-functions-test",
});

const assert = require("node:assert/strict");

const adminMock = {
  initializeApp: () => ({}),
  getFirestore: () => ({collection: () => { throw new Error("not used"); }}),
  getAuth: () => ({}),
  getMessaging: () => ({}),
  getStorage: () => ({}),
  FieldValue: {serverTimestamp: () => ({_serverTimestamp: true})},
  Timestamp: {now: () => ({toMillis: () => Date.now()})},
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
  if (id === "firebase-admin/messaging") {
    return {getMessaging: adminMock.getMessaging};
  }
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

const normalize = functions.normalizeBunnyVideoIdForLookup;
const isValid = functions.isValidBunnyVideoId;

let passed = 0;
function check(name, fn) {
  try {
    fn();
    passed += 1;
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`FAIL - ${name}`);
    console.error(error);
    process.exitCode = 1;
  }
}

const GUID = "6ffb23ad-f073-480d-9a68-43baaf9803d5";
const PLAYER_URL =
  "https://player.mediadelivery.net/play/736742/6ffb23ad-f073-480d-9a68-43baaf9803d5";

check("helpers are exported", () => {
  assert.equal(typeof normalize, "function");
  assert.equal(typeof isValid, "function");
});

check("CASE 1 - valid bare GUID is accepted", () => {
  assert.equal(normalize(GUID), GUID);
  assert.equal(normalize(`  ${GUID}  `), GUID);
  assert.equal(isValid(GUID), true);
  assert.equal(isValid(`  ${GUID}  `), true);
});

check("CASE 2 - Bunny URL containing a GUID is rejected (never extracted)", () => {
  // normalize MUST NOT convert URL -> GUID (strict trim-only).
  assert.equal(normalize(PLAYER_URL), PLAYER_URL);
  // validation MUST reject the URL even though it embeds a GUID.
  assert.equal(isValid(PLAYER_URL), false);
});

check("CASE 3 - arbitrary non-GUID strings are rejected", () => {
  assert.equal(normalize("not-a-guid"), "not-a-guid");
  assert.equal(isValid("not-a-guid"), false);
  assert.equal(normalize("https://example.com/no-guid-here"), "https://example.com/no-guid-here");
  assert.equal(isValid("https://example.com/no-guid-here"), false);
});

check("CASE 4 - empty/null/missing are rejected", () => {
  assert.equal(normalize(""), null);
  assert.equal(isValid(""), false);
  assert.equal(normalize(null), null);
  assert.equal(isValid(null), false);
  assert.equal(normalize(undefined), null);
  assert.equal(isValid(undefined), false);
});

// Strict VIDEO-ID-ONLY lookup semantics: exact trimmed match only.
// Mirrors the backend implementation without touching Firestore.
function lookupInStore(store, videoId) {
  const key = normalize(videoId);
  if (key == null) return null;
  if (!isValid(videoId)) return null;
  return store.get(key) ?? null;
}

check("GUID-stored row reachable by GUID only, never by URL", () => {
  const store = new Map([[GUID, {id: "res-guid"}]]);
  assert.equal(lookupInStore(store, GUID).id, "res-guid");
  assert.equal(lookupInStore(store, PLAYER_URL), null);
});

check("URL input never resolves a GUID row (no silent extraction)", () => {
  const store = new Map([[GUID, {id: "res-guid"}]]);
  assert.equal(lookupInStore(store, PLAYER_URL), null);
  assert.equal(isValid(PLAYER_URL), false);
});

check("unknown GUID identifiers resolve to nothing", () => {
  const store = new Map([[GUID, {id: "res-guid"}]]);
  assert.equal(lookupInStore(store, "00000000-0000-0000-0000-000000000000"), null);
});

console.log(`bunny_video_id_lookup tests passed (${passed} groups).`);
