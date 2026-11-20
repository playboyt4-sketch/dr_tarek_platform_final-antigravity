/**
 * ADR-010 Option C — Bunny library lifecycle through the REAL callables.
 *
 * Emulator suite (Firestore + Functions). Proves:
 *  - only a Doctor may register, deactivate, reactivate, verify or read health;
 *  - registration always lands in `pending_verification` with both token flags
 *    false, and derives credential names from the library id;
 *  - a duplicate registration is rejected without overwriting;
 *  - deactivation always wins, reactivation never returns straight to `active`;
 *  - verification fails closed when the library's credentials are absent and
 *    never reports `active`;
 *  - every lifecycle action writes an audit record with no credential material;
 *  - the health projection never exposes host, pull zone or credential names.
 *
 * No Bunny network call is made: the verification probe cannot obtain a secret
 * in the emulator, so it must fail closed before any HTTP request.
 */
const test = require("firebase-functions-test")();

// Emulator suites must stay offline: any Bunny request fails the suite.
const bunnyGuard =
  require("./bunny_network_guard").installBunnyNetworkGuard();
const assert = require("node:assert/strict");
const admin = require("firebase-admin");

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = "demo-test";
process.env.BUNNY_PLAYBACK_URL_TEMPLATE = "https://example.com/{video_id}/{quality}";
process.env.BUNNY_TOKEN_KEY = "fixture-signing-key";
process.env.BUNNY_STREAM_API_KEY = "fixture-api-key";
process.env.BUNNY_STREAM_LIBRARY_ID = "736742";
delete process.env.BUNNY_ACTIVE_LIBRARY_IDS;
delete process.env.BUNNY_ASSOCIATION_RECEIPT_KEY;

let functions;
try {
  functions = require("../lib/index.js");
} catch (error) {
  console.error("Failed to load functions:", error);
  process.exit(1);
}

const register = test.wrap(functions.registerBunnyLibrary);
const deactivate = test.wrap(functions.deactivateBunnyLibrary);
const reactivate = test.wrap(functions.reactivateBunnyLibrary);
const verify = test.wrap(functions.verifyBunnyLibrary);
const health = test.wrap(functions.listBunnyLibraryHealth);

const db = admin.firestore();

const DOCTOR = {uid: "u_lifecycle_doctor", token: {role: "doctor"}};
const ADMIN = {uid: "u_lifecycle_admin", token: {role: "admin"}};
const STUDENT = {uid: "u_lifecycle_student", token: {role: "student"}};

const LIB = "990001";
const LIB_DUP = "990002";
const FORBIDDEN_HEALTH_KEYS = [
  "playbackHost",
  "playback_host",
  "pullZoneId",
  "pull_zone_id",
  "credentialRefs",
  "credential_refs",
  "tokenKey",
  "streamApiKey",
];

let passed = 0;
function ok(name, condition) {
  assert.ok(condition, name);
  passed += 1;
  console.log(`ok - ${name}`);
}

async function expectCode(promise, code, name) {
  try {
    await promise;
  } catch (error) {
    assert.equal(
      error.code,
      code,
      `${name}: expected ${code}, got ${error.code} (${error.message})`,
    );
    console.log(`ok - ${name} (denied ${code})`);
    passed += 1;
    return error;
  }
  assert.fail(`${name}: expected denial ${code}, call succeeded`);
}

function registration(overrides = {}) {
  return {
    libraryId: LIB,
    displayName: "Lifecycle Test Library",
    pullZoneId: 424242,
    playbackHost: "vz-lifecycle-test.b-cdn.net",
    ...overrides,
  };
}

async function auditFor(libraryId) {
  const snapshot = await db
    .collection("admin_audit_log")
    .where("target_id", "==", libraryId)
    .get();
  return snapshot.docs.map((doc) => doc.data());
}

async function cleanup() {
  for (const id of [LIB, LIB_DUP]) {
    await db.collection("bunny_libraries").doc(id).delete().catch(() => {});
    const audit = await db
      .collection("admin_audit_log")
      .where("target_id", "==", id)
      .get();
    for (const doc of audit.docs) await doc.ref.delete().catch(() => {});
  }
}

async function run() {
  await cleanup();

  // --- authorization: nobody but a Doctor may touch the lifecycle ------
  await expectCode(
    register({data: registration(), auth: undefined}),
    "unauthenticated",
    "unauthenticated register",
  );
  await expectCode(
    register({data: registration(), auth: ADMIN}),
    "permission-denied",
    "admin register",
  );
  await expectCode(
    register({data: registration(), auth: STUDENT}),
    "permission-denied",
    "student register",
  );
  await expectCode(
    deactivate({data: {libraryId: LIB}, auth: ADMIN}),
    "permission-denied",
    "admin deactivate",
  );
  await expectCode(
    reactivate({data: {libraryId: LIB}, auth: ADMIN}),
    "permission-denied",
    "admin reactivate",
  );
  await expectCode(
    verify({data: {libraryId: LIB}, auth: ADMIN}),
    "permission-denied",
    "admin verify",
  );
  await expectCode(
    health({data: {}, auth: ADMIN}),
    "permission-denied",
    "admin health",
  );

  // --- registration ----------------------------------------------------
  await expectCode(
    register({data: registration({libraryId: "not-a-number"}), auth: DOCTOR}),
    "invalid-argument",
    "non-numeric library id",
  );
  await expectCode(
    register({data: registration({displayName: "   "}), auth: DOCTOR}),
    "invalid-argument",
    "blank display name",
  );
  await expectCode(
    register({data: registration({playbackHost: "https://evil.example.com"}), auth: DOCTOR}),
    "invalid-argument",
    "non-Bunny playback host",
  );

  const created = await register({data: registration(), auth: DOCTOR});
  ok("registration succeeds for a Doctor", created.registered === true);
  ok("registration returns the library id", created.libraryId === LIB);
  ok("registration is never active", created.status === "pending_verification");

  const doc = await db.collection("bunny_libraries").doc(LIB).get();
  ok("catalog document is created", doc.exists === true);
  const data = doc.data();
  ok("catalog status is pending_verification", data.status === "pending_verification");
  ok("catalog token auth starts disabled", data.token_auth_enabled === false);
  ok("catalog token auth starts unverified", data.token_auth_verified === false);
  ok("catalog has no verification timestamp", data.last_verified_at === null);
  ok("catalog has no error code", data.last_error_code === null);
  ok(
    "credential names are derived from the id",
    data.credential_refs.stream_api_key === `BUNNY_${LIB}_STREAM_API_KEY` &&
      data.credential_refs.token_key === `BUNNY_${LIB}_TOKEN_KEY`,
  );
  ok(
    "catalog document stores no secret value",
    Object.values(data.credential_refs).every((name) => /^BUNNY_[0-9]+_[A-Z_]+$/.test(name)),
  );

  const registrationAudit = await auditFor(LIB);
  const registerEntry = registrationAudit.find(
    (entry) => entry.action === "bunny_library_register",
  );
  ok("registration writes an audit record", Boolean(registerEntry));
  ok("registration audit names the new status", registerEntry.new_status === "pending_verification");
  ok(
    "registration audit carries no credential material",
    !JSON.stringify(registerEntry).includes("BUNNY_") &&
      !JSON.stringify(registerEntry).includes("b-cdn.net"),
  );

  await expectCode(
    register({data: registration({libraryId: LIB, displayName: "Overwrite"}), auth: DOCTOR}),
    "already-exists",
    "duplicate registration",
  );
  const afterDuplicate = await db.collection("bunny_libraries").doc(LIB).get();
  ok("duplicate registration does not overwrite", afterDuplicate.data().display_name === "Lifecycle Test Library");

  // --- deactivate / reactivate ----------------------------------------
  await expectCode(
    deactivate({data: {libraryId: "999999"}, auth: DOCTOR}),
    "not-found",
    "deactivate unknown library",
  );
  const deactivated = await deactivate({data: {libraryId: LIB, reason: "test"}, auth: DOCTOR});
  ok("deactivation returns disabled", deactivated.status === "disabled");
  const deactivatedDoc = await db.collection("bunny_libraries").doc(LIB).get();
  ok("deactivation persists disabled", deactivatedDoc.data().status === "disabled");
  const deactivateAudit = (await auditFor(LIB)).find(
    (entry) => entry.action === "bunny_library_deactivate",
  );
  ok("deactivation is audited", deactivateAudit.previous_status === "pending_verification" && deactivateAudit.new_status === "disabled");
  ok("deactivation audit records the operator reason", deactivateAudit.reason === "test");

  await expectCode(
    deactivate({data: {libraryId: LIB}, auth: DOCTOR}),
    "failed-precondition",
    "deactivate twice",
  );

  const reactivated = await reactivate({data: {libraryId: LIB}, auth: DOCTOR});
  ok("reactivation returns to pending_verification", reactivated.status === "pending_verification");
  ok("reactivation never returns active", reactivated.status !== "active");
  const reactivateAudit = (await auditFor(LIB)).find(
    (entry) => entry.action === "bunny_library_reactivate",
  );
  ok("reactivation is audited", reactivateAudit.previous_status === "disabled" && reactivateAudit.new_status === "pending_verification");

  await expectCode(
    reactivate({data: {libraryId: LIB}, auth: DOCTOR}),
    "failed-precondition",
    "reactivate while not disabled",
  );

  // --- verification fails closed without credentials -------------------
  const verified = await verify({data: {libraryId: LIB}, auth: DOCTOR});
  ok("verification never activates without credentials", verified.status !== "active");
  ok("verification reports unverified token auth", verified.tokenAuthVerified === false);
  ok("verification returns a typed error code", typeof verified.errorCode === "string" && verified.errorCode.length > 0);
  ok(
    "verification response leaks no credential material",
    !JSON.stringify(verified).includes("BUNNY_") &&
      !JSON.stringify(verified).includes("b-cdn.net"),
  );
  const verifiedDoc = await db.collection("bunny_libraries").doc(LIB).get();
  ok("verification persists a non-active status", verifiedDoc.data().status !== "active");
  ok("verification keeps token auth unverified", verifiedDoc.data().token_auth_verified === false);
  ok("verification records the typed code", verifiedDoc.data().last_error_code === verified.errorCode);
  const verifyAudit = (await auditFor(LIB)).find(
    (entry) => entry.action === "bunny_library_verify",
  );
  ok("verification is audited", Boolean(verifyAudit));
  ok(
    "verification audit carries no credential material",
    !JSON.stringify(verifyAudit).includes("BUNNY_") &&
      !JSON.stringify(verifyAudit).includes("b-cdn.net"),
  );

  // --- health projection ----------------------------------------------
  const healthView = await health({data: {}, auth: DOCTOR});
  const entry = healthView.libraries.find((item) => item.libraryId === LIB);
  ok("health lists the registered library", Boolean(entry));
  ok("health reports the current status", entry.status === "pending_verification");
  ok(
    "health exposes no host, pull zone or credential name",
    Boolean(entry) && FORBIDDEN_HEALTH_KEYS.every((key) => !(key in entry)),
  );
  ok(
    "health payload contains no credential material",
    !JSON.stringify(healthView).includes("BUNNY_") &&
      !JSON.stringify(healthView).includes("b-cdn.net"),
  );

  await cleanup();
  bunnyGuard.assertNoBunnyCalls();
  console.log(`bunny_library_lifecycle_flow tests passed (${passed}).`);
  process.exit(0);
}

run().catch(async (error) => {
  console.error("FAIL", error);
  await cleanup().catch(() => {});
  process.exitCode = 1;
});
