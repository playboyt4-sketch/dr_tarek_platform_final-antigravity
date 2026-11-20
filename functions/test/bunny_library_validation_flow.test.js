/**
 * ADR-010 — pre-write library/video validation through the real callable.
 *
 * Emulator suite (Firestore + Functions): doctor-only authorization, format and
 * library gates, and the guarantee that a validation response never contains
 * credentials and never reports `verified` when metadata could not be checked.
 *
 * The cases here are deliberately chosen so NO Bunny network call is possible
 * (invalid id / unknown library / inactive library), keeping the suite
 * deterministic and offline.
 */
const test = require("firebase-functions-test")();

// Emulator suites must stay offline: any Bunny request fails the suite.
const bunnyGuard =
  require("./bunny_network_guard").installBunnyNetworkGuard();
const assert = require("node:assert/strict");
const admin = require("firebase-admin");

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = "demo-test";
process.env.BUNNY_TOKEN_KEY = "fixture-signing-key";
delete process.env.BUNNY_ACTIVE_LIBRARY_IDS;

let functions;
try {
  functions = require("../lib/index.js");
} catch (error) {
  console.error("Failed to load functions:", error);
  process.exit(1);
}

const validate = test.wrap(functions.validateBunnyVideoAssociation);
const db = admin.firestore();

async function expectCode(promise, code, name) {
  try {
    await promise;
  } catch (error) {
    assert.equal(error.code, code, `${name}: expected ${code}, got ${error.code}`);
    console.log(`ok - ${name} (denied ${code})`);
    return;
  }
  assert.fail(`${name}: expected denial ${code}, call succeeded`);
}

function assertNoSecrets(payload, label) {
  const serialized = JSON.stringify(payload);
  for (const forbidden of ["apiKey", "AccessKey", "tokenKey", "secret"]) {
    assert.ok(
      !serialized.includes(forbidden),
      `${label}: response must not expose ${forbidden}`,
    );
  }
}

async function run() {
  console.log("Starting bunny_library_validation_flow tests against emulator...");
  let passed = 0;
  const ok = (name) => {
    passed++;
    console.log(`ok - ${name}`);
  };
  const GUID = "7ddd0e6e-1111-4111-8111-111111111111";

  await db.collection("users").doc("u_val_doctor").set({
    role: "doctor",
    approval_status: "approved",
  });
  await db.collection("users").doc("u_val_student").set({
    role: "student",
    student_type: "center_student",
    approval_status: "approved",
  });

  const doctorAuth = {uid: "u_val_doctor", token: {role: "doctor"}};
  const studentAuth = {uid: "u_val_student", token: {role: "student"}};

  // --- authentication / authorization ---
  await expectCode(
    validate({data: {videoId: GUID, libraryId: "736742"}}),
    "unauthenticated",
    "unauthenticated caller is denied",
  );
  passed++;
  await expectCode(
    validate({data: {videoId: GUID, libraryId: "736742"}, auth: studentAuth}),
    "permission-denied",
    "non-doctor caller is denied",
  );
  passed++;

  // --- format gate ---
  const invalid = await validate({
    data: {videoId: "https://iframe.mediadelivery.net/embed/775315/" + GUID, libraryId: "736742"},
    auth: doctorAuth,
  });
  assert.equal(invalid.status, "rejected");
  assert.equal(invalid.reason, "invalid_video_id");
  assert.equal(invalid.receipt, null);
  assertNoSecrets(invalid, "invalid id");
  ok("embed URL is rejected as an invalid Video ID");

  // --- unknown library ---
  const unknown = await validate({
    data: {videoId: GUID, libraryId: "999999"},
    auth: doctorAuth,
  });
  assert.equal(unknown.status, "unavailable");
  assert.equal(unknown.reason, "unknown_library");
  assert.equal(unknown.receipt, null);
  assertNoSecrets(unknown, "unknown library");
  ok("unknown library is unavailable, not verified");

  // --- inactive library (775315 must stay inactive) ---
  const inactive = await validate({
    data: {videoId: GUID, libraryId: "775315"},
    auth: doctorAuth,
  });
  assert.equal(inactive.status, "unavailable");
  assert.equal(inactive.reason, "inactive_library");
  assert.equal(inactive.receipt, null);
  assertNoSecrets(inactive, "inactive library");
  ok("inactive library 775315 is unavailable, not verified");

  // --- empty library id ---
  const missingLibrary = await validate({
    data: {videoId: GUID, libraryId: "   "},
    auth: doctorAuth,
  });
  assert.equal(missingLibrary.reason, "unknown_library");
  ok("empty library id is rejected");

  // --- response shape is closed (no extra keys that could leak) ---
  assert.deepEqual(
    Object.keys(missingLibrary).sort(),
    ["libraryId", "reason", "receipt", "status", "videoId"],
    "validation response exposes only the verdict",
  );
  ok("validation response shape is closed");

  bunnyGuard.assertNoBunnyCalls();
  console.log(`bunny_library_validation_flow tests passed (${passed}).`);
  process.exit(0);
}

run().catch((error) => {
  console.error("FAIL", error);
  process.exitCode = 1;
});
