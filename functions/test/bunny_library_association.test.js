// ADR-010 — pure tests for the server-verified association module.
// No Firestore, no Bunny, no network: only the decision table and the
// resource-bound receipt are exercised.
const assert = require("node:assert");
const path = require("node:path");

const lib = require(path.join(__dirname, "..", "lib", "core", "video", "bunny_library_association.js"));

const GUID = "7ddd0e6e-1111-4111-8111-111111111111";
const OTHER_GUID = "8eee0e6e-2222-4222-8222-222222222222";

const ENV = Object.freeze({
  BUNNY_PLAYBACK_URL_TEMPLATE: "https://cdn.example.com/{video_id}/{quality}",
  BUNNY_TOKEN_KEY: "fixture-signing-key",
  BUNNY_STREAM_API_KEY: "fixture-api-key",
  BUNNY_STREAM_LIBRARY_ID: "736742",
});

let passed = 0;
function ok(name, condition) {
  assert.ok(condition, name);
  passed += 1;
  console.log(`ok - ${name}`);
}

function plan(overrides = {}) {
  return lib.planBunnyAssociationWrite(
    {
      resourceType: "video",
      resourceLectureId: "lec-1",
      lectureId: "lec-1",
      resourceSubjectId: "sub-1",
      lectureSubjectId: "sub-1",
      storedVideoId: "",
      requestedVideoId: GUID,
      storedLibraryId: "736742",
      replaceVideo: false,
      ...overrides,
    },
    ENV,
  );
}

function reasonOf(overrides) {
  const result = plan(overrides);
  return result.ok ? "ok" : result.reason;
}

// --- plan -------------------------------------------------------------
ok("accepts a pending video row with the default library", plan().ok === true && plan().libraryId === "736742");
ok("rejects a non-video resource", reasonOf({resourceType: "pdf"}) === "not_video_resource");
ok("rejects a missing lecture id", reasonOf({lectureId: ""}) === "missing_lecture");
ok("rejects a lecture/resource mismatch", reasonOf({resourceLectureId: "lec-2"}) === "lecture_mismatch");
ok("rejects a subject mismatch", reasonOf({lectureSubjectId: "sub-2"}) === "subject_mismatch");
ok("rejects a URL instead of a GUID", reasonOf({requestedVideoId: "https://iframe.mediadelivery.net/embed/1/abc"}) === "invalid_video_id");
ok("rejects a different stored Video ID without replaceVideo", reasonOf({storedVideoId: OTHER_GUID}) === "video_id_mismatch");
ok("accepts a deliberate video replacement", reasonOf({storedVideoId: OTHER_GUID, replaceVideo: true}) === "ok");
ok("accepts the same stored Video ID", reasonOf({storedVideoId: GUID}) === "ok");
ok("rejects an unknown library", reasonOf({storedLibraryId: "999999"}) === "unknown_library");
ok("rejects the inactive library 775315", reasonOf({storedLibraryId: "775315"}) === "inactive_library");
ok("rejects an empty library selection", reasonOf({storedLibraryId: null}) === "unknown_library");
const incompleteEnv = {...ENV};
delete incompleteEnv.BUNNY_STREAM_API_KEY;
const incompleteResult = lib.planBunnyAssociationWrite(
  {
    resourceType: "video",
    resourceLectureId: "lec-1",
    lectureId: "lec-1",
    storedVideoId: "",
    requestedVideoId: GUID,
    storedLibraryId: "736742",
  },
  incompleteEnv,
);
ok("rejects an incomplete Stream configuration", !incompleteResult.ok && incompleteResult.reason === "incomplete_configuration");

// --- cutover / playback gate ------------------------------------------
const cutover = lib.resolveBunnyAssociationCutoverMs({});
ok("cutover defaults to the ADR-010 date", cutover === Date.parse("2026-11-13T00:00:00.000Z"));
ok("cutover honours a valid override", lib.resolveBunnyAssociationCutoverMs({BUNNY_ASSOCIATION_CUTOVER: "2027-01-01T00:00:00.000Z"}) === Date.parse("2027-01-01T00:00:00.000Z"));
ok("cutover ignores a malformed override", lib.resolveBunnyAssociationCutoverMs({BUNNY_ASSOCIATION_CUTOVER: "not-a-date"}) === cutover);
ok("post-cutover rows require an association", lib.isBunnyAssociationRequired(cutover + 1000, cutover) === true);
ok("pre-cutover rows stay legacy", lib.isBunnyAssociationRequired(cutover - 1000, cutover) === false);
ok("a row without created_at is legacy", lib.isBunnyAssociationRequired(null, cutover) === false);
ok("legacy row may resolve the default library", lib.mayResolveBunnyLibraryForPlayback({createdAtMs: cutover - 1000, storedLibraryId: undefined, cutoverMs: cutover}) === true);
ok("verified row may resolve its library", lib.mayResolveBunnyLibraryForPlayback({createdAtMs: cutover + 1000, storedLibraryId: "736742", cutoverMs: cutover}) === true);
ok("pending row may NOT resolve a library", lib.mayResolveBunnyLibraryForPlayback({createdAtMs: cutover + 1000, storedLibraryId: null, cutoverMs: cutover}) === false);

// --- receipts ---------------------------------------------------------
const SECRET = "fixture-signing-key";
const nowSeconds = 1_800_000_000;
const receipt = lib.signBunnyAssociationReceipt({
  secret: SECRET,
  resourceId: "res-1",
  lectureId: "lec-1",
  libraryId: "736742",
  videoId: GUID,
  issuedAtSeconds: nowSeconds,
  ttlSeconds: 600,
});
ok("receipt binds the exact association", receipt.resourceId === "res-1" && receipt.libraryId === "736742" && receipt.expiresAt === nowSeconds + 600);
ok("receipt carries no secret material", !JSON.stringify(receipt).includes(SECRET));

function verify(overrides = {}, now = nowSeconds + 1) {
  return lib.verifyBunnyAssociationReceipt({
    secret: SECRET,
    receipt: "receipt" in overrides ? overrides.receipt : receipt,
    resourceId: overrides.resourceId ?? "res-1",
    lectureId: overrides.lectureId ?? "lec-1",
    libraryId: overrides.libraryId ?? "736742",
    videoId: overrides.videoId ?? GUID,
    nowSeconds: now,
  });
}

ok("valid receipt verifies", verify() === true);
ok("expired receipt is rejected", verify({}, nowSeconds + 601) === false);
ok("wrong resource is rejected", verify({resourceId: "res-2"}) === false);
ok("wrong lecture is rejected", verify({lectureId: "lec-2"}) === false);
ok("wrong library is rejected", verify({libraryId: "775315"}) === false);
ok("wrong video is rejected", verify({videoId: OTHER_GUID}) === false);
ok("tampered signature is rejected", verify({receipt: {...receipt, signature: "AAAA"}}) === false);
ok("foreign-secret receipt is rejected", verify({receipt: lib.signBunnyAssociationReceipt({
  secret: "another-secret",
  resourceId: "res-1",
  lectureId: "lec-1",
  libraryId: "736742",
  videoId: GUID,
  issuedAtSeconds: nowSeconds,
  ttlSeconds: 600,
})}) === false);
ok("malformed receipt is rejected", verify({receipt: {resourceId: "res-1"}}) === false);
ok("null receipt is rejected", verify({receipt: null}) === false);
ok("a receipt cannot be replayed onto another resource (signature check)", verify({
  resourceId: "res-1",
  receipt: lib.signBunnyAssociationReceipt({
    secret: SECRET,
    resourceId: "res-9",
    lectureId: "lec-1",
    libraryId: "736742",
    videoId: GUID,
    issuedAtSeconds: nowSeconds,
    ttlSeconds: 600,
  }),
}) === false);

// --- write fields -----------------------------------------------------
const fields = lib.bunnyAssociationWriteFields("736742", GUID);
ok("write fields are exactly the two association keys", Object.keys(fields).sort().join(",") === "bunny_library_id,bunny_video_id");
ok("write fields carry no template/key/url", Object.values(fields).every((value) => !String(value).includes("http") && !String(value).includes("fixture")));

console.log(`bunny_library_association: ${passed} assertions passed`);
