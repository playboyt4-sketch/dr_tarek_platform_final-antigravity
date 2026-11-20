/**
 * ADR-010 — `listEligibleBunnyLibraries` through the REAL callable.
 *
 * Emulator suite (Firestore + Functions): authorization matrix, eligibility
 * filtering over seeded catalog documents, emergency deny-list behavior, the
 * empty catalog, and the guarantee that the response is the closed projection
 * `{libraries: [{libraryId, displayName}]}` with no credential, host, pull
 * zone or verification field.
 *
 * No Bunny network call is made: the catalog is pure Firestore data.
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

const listLibraries = test.wrap(functions.listEligibleBunnyLibraries);
const db = admin.firestore();

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

function assertClosedProjection(response, label) {
  assert.deepEqual(
    Object.keys(response).sort(),
    ["libraries"],
    `${label}: top-level response shape`,
  );
  for (const item of response.libraries) {
    assert.deepEqual(
      Object.keys(item).sort(),
      ["displayName", "libraryId"],
      `${label}: item projection`,
    );
  }
  const serialized = JSON.stringify(response);
  for (const forbidden of [
    "BUNNY_",
    "tokenKey",
    "apiKey",
    "secret",
    "pull_zone",
    "playback_host",
    "credential_refs",
    "last_verified",
    "vz-",
  ]) {
    assert.ok(
      !serialized.includes(forbidden),
      `${label}: response must not expose ${forbidden}`,
    );
  }
}

// Firestore rejects `undefined` values, so an explicit `undefined` override is
// used by the fixtures to mean "this field is absent".
function writeCatalog(id, overrides = {}) {
  const data = catalogDoc(overrides);
  for (const key of Object.keys(data)) {
    if (data[key] === undefined) delete data[key];
  }
  return db.collection("bunny_libraries").doc(id).set(data);
}

async function clearCatalog() {
  const snapshot = await db.collection("bunny_libraries").get();
  const batch = db.batch();
  for (const doc of snapshot.docs) batch.delete(doc.ref);
  await batch.commit();
}

async function seedCatalog() {
  await clearCatalog();
  await Promise.all([
    writeCatalog("780700"),
    writeCatalog("736742", {
      library_id: "736742",
      display_name: "Production",
      token_auth_verified: false,
      credential_refs: {
        stream_api_key: "BUNNY_736742_STREAM_API_KEY",
        token_key: "BUNNY_736742_TOKEN_KEY",
      },
    }),
    writeCatalog("775315", {
      library_id: "775315",
      display_name: "Inactive",
      status: "disabled",
      credential_refs: {
        stream_api_key: "BUNNY_775315_STREAM_API_KEY",
        token_key: "BUNNY_775315_TOKEN_KEY",
      },
    }),
    writeCatalog("999001", {
      library_id: "999001",
      display_name: "Pending",
      status: "pending_verification",
    }),
    writeCatalog("999002", {
      library_id: "999002",
      display_name: "No credentials",
      credential_refs: undefined,
    }),
    writeCatalog("999003", {
      library_id: "999003",
      display_name: "Bad pull zone",
      pull_zone_id: 0,
    }),
    // Document id / library_id mismatch: must never be eligible.
    writeCatalog("999999", {
      library_id: "999004",
      display_name: "Mismatched id",
    }),
  ]);
}

async function run() {
  console.log("Starting bunny_library_catalog_flow tests against emulator...");
  let passed = 0;
  const ok = (name) => {
    passed++;
    console.log(`ok - ${name}`);
  };

  const doctorAuth = {uid: "u_cat_doctor", token: {role: "doctor"}};
  const adminAllowed = {uid: "u_cat_admin_ok", token: {role: "admin"}};
  const adminDenied = {uid: "u_cat_admin_no", token: {role: "admin"}};
  const adminInactive = {uid: "u_cat_admin_off", token: {role: "admin"}};
  const studentAuth = {uid: "u_cat_student", token: {role: "student"}};

  await db.collection("users").doc("u_cat_doctor").set({
    role: "doctor",
    approval_status: "approved",
  });
  await db.collection("users").doc("u_cat_student").set({
    role: "student",
    student_type: "center_student",
    approval_status: "approved",
  });
  await db.collection("admin_permissions").doc("u_cat_admin_ok").set({
    is_active: true,
    permissions: {admin_content: true},
  });
  await db.collection("admin_permissions").doc("u_cat_admin_no").set({
    is_active: true,
    permissions: {},
  });
  await db.collection("admin_permissions").doc("u_cat_admin_off").set({
    is_active: false,
    permissions: {admin_content: true},
  });

  await seedCatalog();

  // --- authorization matrix ---
  await expectCode(
    listLibraries({data: {}}),
    "unauthenticated",
    "unauthenticated caller is denied",
  );
  passed++;
  await expectCode(
    listLibraries({data: {}, auth: studentAuth}),
    "permission-denied",
    "student caller is denied",
  );
  passed++;
  await expectCode(
    listLibraries({data: {}, auth: adminDenied}),
    "permission-denied",
    "admin without admin_content is denied",
  );
  passed++;
  await expectCode(
    listLibraries({data: {}, auth: adminInactive}),
    "permission-denied",
    "inactive admin with admin_content is denied",
  );
  passed++;

  // --- doctor: only the fully eligible library ---
  const doctorResponse = await listLibraries({data: {}, auth: doctorAuth});
  assert.deepEqual(doctorResponse, {
    libraries: [{libraryId: "780700", displayName: "DrTarek Staging"}],
  });
  assertClosedProjection(doctorResponse, "doctor");
  ok("doctor sees exactly the active + verified library");

  // --- delegated admin with admin_content: same projection ---
  const adminResponse = await listLibraries({data: {}, auth: adminAllowed});
  assert.deepEqual(adminResponse, doctorResponse);
  assertClosedProjection(adminResponse, "admin_content");
  ok("delegated admin_content sees the same closed projection");

  // --- explicit negative cases over the seeded matrix ---
  const ids = doctorResponse.libraries.map((library) => library.libraryId);
  for (const excluded of ["736742", "775315", "999001", "999002", "999003", "999004", "999999"]) {
    assert.ok(!ids.includes(excluded), `excluded library ${excluded} must not appear`);
  }
  ok("unverified/disabled/pending/incomplete/mismatched libraries are excluded");
  assert.ok(!ids.includes("775315"), "library 775315 must stay inactive");
  ok("library 775315 is never listed");

  // --- emergency deny-list ---
  process.env.BUNNY_ACTIVE_LIBRARY_IDS = "780700";
  assert.deepEqual(
    await listLibraries({data: {}, auth: doctorAuth}),
    {libraries: [{libraryId: "780700", displayName: "DrTarek Staging"}]},
  );
  ok("deny-list naming the eligible library keeps it");

  process.env.BUNNY_ACTIVE_LIBRARY_IDS = "736742";
  assert.deepEqual(
    await listLibraries({data: {}, auth: doctorAuth}),
    {libraries: []},
  );
  ok("deny-list cannot resurrect an ineligible library");

  process.env.BUNNY_ACTIVE_LIBRARY_IDS = "780700,775315";
  assert.deepEqual(
    await listLibraries({data: {}, auth: doctorAuth}),
    {libraries: [{libraryId: "780700", displayName: "DrTarek Staging"}]},
  );
  ok("deny-list intersects with the eligibility gate");

  process.env.BUNNY_ACTIVE_LIBRARY_IDS = "not-an-id";
  assert.deepEqual(
    await listLibraries({data: {}, auth: doctorAuth}),
    {libraries: []},
  );
  ok("malformed deny-list fails closed");

  process.env.BUNNY_ACTIVE_LIBRARY_IDS = "   ";
  assert.deepEqual(
    await listLibraries({data: {}, auth: doctorAuth}),
    {libraries: [{libraryId: "780700", displayName: "DrTarek Staging"}]},
  );
  ok("blank deny-list is treated as not engaged");

  delete process.env.BUNNY_ACTIVE_LIBRARY_IDS;
  assert.deepEqual(
    await listLibraries({data: {}, auth: doctorAuth}),
    {libraries: [{libraryId: "780700", displayName: "DrTarek Staging"}]},
  );
  ok("absent deny-list does not reduce eligibility");

  // --- empty catalog ---
  await clearCatalog();
  const empty = await listLibraries({data: {}, auth: doctorAuth});
  assert.deepEqual(empty, {libraries: []});
  assertClosedProjection(empty, "empty catalog");
  ok("empty catalog returns an empty list");

  bunnyGuard.assertNoBunnyCalls();
  console.log(`bunny_library_catalog_flow tests passed (${passed}).`);
  process.exit(0);
}

run().catch((error) => {
  console.error("FAIL", error);
  process.exitCode = 1;
});
