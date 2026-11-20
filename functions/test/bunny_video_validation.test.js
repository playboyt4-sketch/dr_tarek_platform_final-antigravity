/**
 * ADR-010 — pre-write library/video validation contract (pure).
 *
 * Locks the decision table the doctor-facing callable relies on: format and
 * library gates first, then the Stream API verdict, then the signed receipt.
 * `unavailable` is never success, and no branch substitutes another library.
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
  planBunnyVideoValidation,
  interpretBunnyMetadataResponse,
  interpretBunnyMetadataError,
  signBunnyValidationReceipt,
  verifyBunnyValidationReceipt,
} = functions;

for (const [name, value] of Object.entries({
  planBunnyVideoValidation,
  interpretBunnyMetadataResponse,
  interpretBunnyMetadataError,
  signBunnyValidationReceipt,
  verifyBunnyValidationReceipt,
})) {
  assert.equal(typeof value, "function", `${name} must be exported`);
}

let passed = 0;
function check(name, actual, expected) {
  assert.deepEqual(actual, expected, name);
  passed++;
  console.log(`ok - ${name}`);
}

const GUID = "7ddd0e6e-1111-4111-8111-111111111111";
const OTHER_LIBRARY = "775315";
const PROD_ENV = {
  BUNNY_STREAM_API_KEY: "fixture-api-key",
  BUNNY_STREAM_LIBRARY_ID: DEFAULT_BUNNY_LIBRARY_ID,
};
const CONTENT_ENV = {
  BUNNY_ACTIVE_LIBRARY_IDS: OTHER_LIBRARY,
  BUNNY_775315_STREAM_API_KEY: "fixture-775315-api-key",
};

// --- planning: format and library gates ---
check(
  "valid request plans a library-scoped metadata probe",
  planBunnyVideoValidation({libraryId: DEFAULT_BUNNY_LIBRARY_ID, videoId: GUID}, PROD_ENV),
  {
    ok: true,
    request: {
      libraryId: DEFAULT_BUNNY_LIBRARY_ID,
      apiLibraryId: DEFAULT_BUNNY_LIBRARY_ID,
      apiKey: "fixture-api-key",
      videoId: GUID,
    },
  },
);
check(
  "a URL is not a Video ID",
  planBunnyVideoValidation({libraryId: DEFAULT_BUNNY_LIBRARY_ID, videoId: "https://x/" + GUID}, PROD_ENV).result,
  {status: "rejected", reason: "invalid_video_id", libraryId: DEFAULT_BUNNY_LIBRARY_ID, videoId: "https://x/" + GUID},
);
check(
  "empty library id is rejected",
  planBunnyVideoValidation({libraryId: "  ", videoId: GUID}, PROD_ENV).result.reason,
  "unknown_library",
);
check(
  "unknown library is rejected",
  planBunnyVideoValidation({libraryId: "999999", videoId: GUID}, PROD_ENV),
  {
    ok: false,
    result: {status: "unavailable", reason: "unknown_library", libraryId: "999999", videoId: GUID},
  },
);
check(
  "inactive library is unavailable (never falls back to the default)",
  planBunnyVideoValidation({libraryId: OTHER_LIBRARY, videoId: GUID}, PROD_ENV),
  {
    ok: false,
    result: {status: "unavailable", reason: "inactive_library", libraryId: OTHER_LIBRARY, videoId: GUID},
  },
);
check(
  "activated but unconfigured library reports incomplete configuration",
  planBunnyVideoValidation({libraryId: OTHER_LIBRARY, videoId: GUID}, {
    ...CONTENT_ENV,
    BUNNY_775315_STREAM_API_KEY: "",
  }).result.reason,
  "incomplete_configuration",
);
check(
  "default library without credentials reports incomplete configuration",
  planBunnyVideoValidation({libraryId: DEFAULT_BUNNY_LIBRARY_ID, videoId: GUID}, {}),
  {
    ok: false,
    result: {
      status: "unavailable",
      reason: "incomplete_configuration",
      libraryId: DEFAULT_BUNNY_LIBRARY_ID,
      videoId: GUID,
    },
  },
);
check(
  "activated library plans against its own configuration",
  planBunnyVideoValidation({libraryId: OTHER_LIBRARY, videoId: GUID}, CONTENT_ENV).request,
  {
    libraryId: OTHER_LIBRARY,
    apiLibraryId: OTHER_LIBRARY,
    apiKey: "fixture-775315-api-key",
    videoId: GUID,
  },
);

// --- response interpretation ---
const probe = {libraryId: DEFAULT_BUNNY_LIBRARY_ID, apiLibraryId: DEFAULT_BUNNY_LIBRARY_ID, videoId: GUID};
check(
  "200 with matching guid is verified",
  interpretBunnyMetadataResponse({status: 200, body: {guid: GUID, videoLibraryId: Number(DEFAULT_BUNNY_LIBRARY_ID)}}, probe),
  {status: "verified", reason: "ok", libraryId: DEFAULT_BUNNY_LIBRARY_ID, videoId: GUID},
);
check(
  "200 naming a different video is a mismatch",
  interpretBunnyMetadataResponse({status: 200, body: {guid: "94710db9-2222-4222-8222-222222222222"}}, probe).reason,
  "video_mismatch",
);
check(
  "200 naming a different library is a mismatch",
  interpretBunnyMetadataResponse({status: 200, body: {guid: GUID, videoLibraryId: Number(OTHER_LIBRARY)}}, probe),
  {status: "mismatch", reason: "library_mismatch", libraryId: DEFAULT_BUNNY_LIBRARY_ID, videoId: GUID},
);
check(
  "404 means the video is not in the selected library",
  interpretBunnyMetadataResponse({status: 404}, probe),
  {status: "mismatch", reason: "not_found_in_library", libraryId: DEFAULT_BUNNY_LIBRARY_ID, videoId: GUID},
);
check(
  "401/403 is unavailable (credentials), never a verdict on the video",
  interpretBunnyMetadataResponse({status: 401}, probe).reason,
  "api_unauthorized",
);
check(
  "5xx is unavailable",
  interpretBunnyMetadataResponse({status: 503}, probe),
  {status: "unavailable", reason: "metadata_unavailable", libraryId: DEFAULT_BUNNY_LIBRARY_ID, videoId: GUID},
);
check(
  "200 with an unparseable body is unavailable, not verified",
  interpretBunnyMetadataResponse({status: 200, body: null}, probe).status,
  "unavailable",
);
check(
  "timeout is unavailable",
  interpretBunnyMetadataError(Object.assign(new Error("aborted"), {name: "AbortError"}), probe),
  {status: "unavailable", reason: "api_timeout", libraryId: DEFAULT_BUNNY_LIBRARY_ID, videoId: GUID},
);
check(
  "other transport failure is unavailable",
  interpretBunnyMetadataError(new Error("socket"), probe).reason,
  "metadata_unavailable",
);

// --- receipts ---
const secret = "fixture-receipt-secret";
const receipt = signBunnyValidationReceipt({
  secret,
  libraryId: DEFAULT_BUNNY_LIBRARY_ID,
  videoId: GUID,
  issuedAtSeconds: 1000,
  ttlSeconds: 600,
});
check("receipt binds library/video/expiry", [
  receipt.libraryId,
  receipt.videoId,
  receipt.expiresAt,
], [DEFAULT_BUNNY_LIBRARY_ID, GUID, 1600]);
check("receipt carries no secret", Object.keys(receipt).sort(),
  ["expiresAt", "libraryId", "signature", "videoId"]);
check(
  "valid receipt verifies",
  verifyBunnyValidationReceipt({
    secret, receipt, libraryId: DEFAULT_BUNNY_LIBRARY_ID, videoId: GUID, nowSeconds: 1500,
  }),
  true,
);
check(
  "receipt is rejected for another library",
  verifyBunnyValidationReceipt({
    secret, receipt, libraryId: OTHER_LIBRARY, videoId: GUID, nowSeconds: 1500,
  }),
  false,
);
check(
  "receipt is rejected for another video",
  verifyBunnyValidationReceipt({
    secret, receipt, libraryId: DEFAULT_BUNNY_LIBRARY_ID, videoId: "84710db9-2222-4222-8222-222222222222", nowSeconds: 1500,
  }),
  false,
);
check(
  "expired receipt is rejected",
  verifyBunnyValidationReceipt({
    secret, receipt, libraryId: DEFAULT_BUNNY_LIBRARY_ID, videoId: GUID, nowSeconds: 1601,
  }),
  false,
);
check(
  "tampered signature is rejected",
  verifyBunnyValidationReceipt({
    secret,
    receipt: {...receipt, signature: receipt.signature.slice(0, -2) + "AA"},
    libraryId: DEFAULT_BUNNY_LIBRARY_ID,
    videoId: GUID,
    nowSeconds: 1500,
  }),
  false,
);
check(
  "receipt signed with another secret is rejected",
  verifyBunnyValidationReceipt({
    secret: "other-secret", receipt, libraryId: DEFAULT_BUNNY_LIBRARY_ID, videoId: GUID, nowSeconds: 1500,
  }),
  false,
);
check(
  "malformed receipt is rejected without throwing",
  verifyBunnyValidationReceipt({
    secret, receipt: "nope", libraryId: DEFAULT_BUNNY_LIBRARY_ID, videoId: GUID, nowSeconds: 1500,
  }),
  false,
);

console.log(`bunny_video_validation tests passed (${passed}).`);
