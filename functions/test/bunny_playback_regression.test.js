/**
 * ADR-010 — playback/listing regression guards.
 *
 * Proves the additive library work did not alter the existing contracts:
 * default-library configuration names, no cross-library credential borrowing,
 * first-video eligibility/order, served-resource predicate, VIDEO-ID-ONLY
 * validation, per-lecture deny semantics, document feature keys, and the
 * window/tier denial precedence. Pure — no emulator.
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
  if (firebaseAdminStorage(id)) return {getStorage: adminMock.getStorage};
  if (id === "firebase-admin/app") return {initializeApp: adminMock.initializeApp};
  return originalRequire.apply(this, arguments);
};
function firebaseAdminStorage(id) {
  return id === "firebase-admin/storage";
}

let functions;
try {
  functions = require("../lib/index.js");
} catch (error) {
  console.error("Failed to load functions:", error);
  process.exit(1);
}

const {
  DEFAULT_BUNNY_LIBRARY_ID,
  resolveBunnyLibraryForResource,
  resolveBunnyPlaybackRuntime,
  resolveBunnyStreamApiRuntime,
  firstVideoFieldsFromResources,
  isServedLectureResource,
  isValidBunnyVideoId,
  normalizeBunnyVideoIdForLookup,
  isLectureAccessDenied,
  lectureAccessGrantId,
  documentFeatureKeys,
  isDocumentResourceType,
  issuanceDenialPrecedence,
} = functions;

let passed = 0;
function check(name, actual, expected) {
  assert.deepEqual(actual, expected, name);
  passed++;
  console.log(`ok - ${name}`);
}

const GUID = "7ddd0e6e-1111-4111-8111-111111111111";

// --- default library configuration is unchanged ---
const PROD_ENV = {
  BUNNY_PLAYBACK_URL_TEMPLATE: "https://vz-default.b-cdn.net/{video_id}/playlist.m3u8",
  BUNNY_TOKEN_KEY: "fixture-token-key",
  BUNNY_STREAM_API_KEY: "fixture-api-key",
  BUNNY_STREAM_LIBRARY_ID: DEFAULT_BUNNY_LIBRARY_ID,
};
check(
  "legacy resource resolves the default library (production behaviour)",
  resolveBunnyLibraryForResource({storedLibraryId: null}, PROD_ENV),
  {ok: true, libraryId: DEFAULT_BUNNY_LIBRARY_ID, source: "legacy_default"},
);
check(
  "default playback runtime reads the historical env names",
  resolveBunnyPlaybackRuntime(PROD_ENV, DEFAULT_BUNNY_LIBRARY_ID).runtime,
  {
    libraryId: DEFAULT_BUNNY_LIBRARY_ID,
    playbackUrlTemplate: PROD_ENV.BUNNY_PLAYBACK_URL_TEMPLATE,
    tokenKey: PROD_ENV.BUNNY_TOKEN_KEY,
  },
);
check(
  "default metadata runtime reads the historical env names",
  resolveBunnyStreamApiRuntime(PROD_ENV, DEFAULT_BUNNY_LIBRARY_ID).runtime,
  {
    libraryId: DEFAULT_BUNNY_LIBRARY_ID,
    apiLibraryId: DEFAULT_BUNNY_LIBRARY_ID,
    apiKey: PROD_ENV.BUNNY_STREAM_API_KEY,
  },
);

// --- no cross-library credential borrowing ---
const ONLY_SECOND_LIBRARY = {
  BUNNY_775315_PLAYBACK_URL_TEMPLATE: "https://vz-content.b-cdn.net/{video_id}/playlist.m3u8",
  BUNNY_775315_TOKEN_KEY: "fixture-775315-token-key",
  BUNNY_775315_STREAM_API_KEY: "fixture-775315-api-key",
};
check(
  "default library never borrows another library's signing config",
  resolveBunnyPlaybackRuntime(ONLY_SECOND_LIBRARY, DEFAULT_BUNNY_LIBRARY_ID),
  {ok: false, reason: "incomplete_configuration", libraryId: DEFAULT_BUNNY_LIBRARY_ID},
);
check(
  "default library never borrows another library's API key",
  resolveBunnyStreamApiRuntime(ONLY_SECOND_LIBRARY, DEFAULT_BUNNY_LIBRARY_ID),
  {ok: false, reason: "incomplete_configuration", libraryId: DEFAULT_BUNNY_LIBRARY_ID},
);
check(
  "inactive library cannot be reached even with full credentials present",
  resolveBunnyPlaybackRuntime(ONLY_SECOND_LIBRARY, "775315").reason,
  "library_not_activated",
);

// --- first-video projection: eligibility, order, additive library ---
const videoRow = (id, order, overrides = {}) => ({
  id,
  data: {
    resource_type: "video",
    is_visible: true,
    is_deleted: false,
    bunny_video_id: GUID,
    display_order: order,
    title: id,
    ...overrides,
  },
});
check(
  "first video: lowest display order wins",
  firstVideoFieldsFromResources([videoRow("b", 5), videoRow("a", 2)]).resource_id,
  "a",
);
check(
  "first video: document id breaks ties",
  firstVideoFieldsFromResources([videoRow("b", 3), videoRow("a", 3)]).resource_id,
  "a",
);
check(
  "first video: invisible rows are ignored",
  firstVideoFieldsFromResources([videoRow("hidden", 0, {is_visible: false}), videoRow("v", 4)]).resource_id,
  "v",
);
check(
  "first video: soft-deleted rows are ignored",
  firstVideoFieldsFromResources([videoRow("del", 0, {is_deleted: true}), videoRow("v", 4)]).resource_id,
  "v",
);
check(
  "first video: empty video id is ignored",
  firstVideoFieldsFromResources([videoRow("noid", 0, {bunny_video_id: "  "}), videoRow("v", 4)]).resource_id,
  "v",
);
check(
  "first video: non-video rows are ignored",
  firstVideoFieldsFromResources([
    videoRow("pdf", 0, {resource_type: "pdf"}),
    videoRow("v", 4),
  ]).resource_id,
  "v",
);
check(
  "first video: none eligible yields null",
  firstVideoFieldsFromResources([videoRow("del", 0, {is_deleted: true})]),
  null,
);
check(
  "first video: projection keys remain the published contract",
  Object.keys(firstVideoFieldsFromResources([videoRow("v", 1)])).sort(),
  [
    "bunny_library_id",
    "bunny_video_id",
    "display_order",
    "resource_id",
    "thumbnail_path",
    "thumbnail_storage_provider",
    "title",
  ].sort(),
);

// --- serving + identifier validation ---
check("listing: soft-deleted resource is not served", isServedLectureResource({is_deleted: true}), false);
check("listing: live resource is served", isServedLectureResource({is_deleted: false}), true);
check("listing: missing flag is served (legacy rows)", isServedLectureResource({}), true);
check("listing: null resource is served by legacy predicate", isServedLectureResource(null), true);
check("video id: bare GUID accepted", isValidBunnyVideoId(GUID), true);
check("video id: embed URL rejected", isValidBunnyVideoId("https://iframe.mediadelivery.net/embed/775315/" + GUID), false);
check("video id: empty rejected", isValidBunnyVideoId("   "), false);
check(
  "lookup: raw value is trimmed, never extracted from a URL",
  normalizeBunnyVideoIdForLookup("  " + GUID + " "),
  GUID,
);
check(
  "lookup: URL is not normalized into a GUID",
  normalizeBunnyVideoIdForLookup("https://x/" + GUID),
  "https://x/" + GUID,
);

// --- per-lecture deny + document feature keys (entitlement regressions) ---
check("deny: explicit deny wins", isLectureAccessDenied({allowed: false}), true);
check("deny: allow defers", isLectureAccessDenied({allowed: true}), false);
check("deny: missing grant defers", isLectureAccessDenied(undefined), false);
check("deny: soft-deleted grant defers", isLectureAccessDenied({allowed: false, is_deleted: true}), false);
check("deny: non-object input defers", isLectureAccessDenied("deny"), false);
check("grant id is deterministic", lectureAccessGrantId("lec", "stu"), "lec_stu");
check("document feature keys: pdf", documentFeatureKeys("pdf"), {view: "pdf.access", download: "pdf.download"});
check("document type: pdf/attachment only", [
  isDocumentResourceType("pdf"),
  isDocumentResourceType("attachment"),
  isDocumentResourceType("video"),
  isDocumentResourceType("external_link"),
], [true, true, false, false]);

// --- window/tier precedence (unchanged) ---
check("precedence: blocked window wins over tier", issuanceDenialPrecedence({allowed: false}), "window");
check("precedence: allowed window defers to tier", issuanceDenialPrecedence({allowed: true}), "tier");

console.log(`bunny_playback_regression tests passed (${passed}).`);
