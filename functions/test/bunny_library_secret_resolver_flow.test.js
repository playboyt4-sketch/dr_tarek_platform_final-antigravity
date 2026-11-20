/**
 * ADR-010 Mission 17 — per-library Secret Manager resolver through the REAL
 * callables, against the Firestore emulator.
 *
 * Proves end-to-end (no Bunny network call):
 *   - `bunny_libraries/{id}` is the authoritative catalog the resolver reads.
 *   - Playback signing for Library A uses A's token key ONLY (the emitted
 *     directory token is recomputed here from each candidate key), and the
 *     pull-zone template is A's, never the default library's.
 *   - Library B is equally isolated.
 *   - An allow-listed library with no catalog row fails closed (no fallback).
 *   - Disabled / unverified catalog entries fail closed.
 *   - A catalog row pointing at another library's secret is rejected.
 *   - A missing per-library secret fails closed and is never reported as a
 *     secret problem to the client.
 *
 * Secret VALUES come from env vars named exactly like the Secret Manager
 * entries, which is the resolver's emulator-only source (same pattern as the
 * existing Stream API key fallback). Production reads Secret Manager.
 */
const test = require("firebase-functions-test")();

// Emulator suites must stay offline: any Bunny request fails the suite.
const bunnyGuard =
  require("./bunny_network_guard").installBunnyNetworkGuard();
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const admin = require("firebase-admin");

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = "demo-test";

const LIB_A = "780700";
const LIB_B = "781800";
const LIB_NO_CATALOG = "781900";
const LIB_DISABLED = "781901";
const LIB_CROSS_REF = "781902";
const LIB_MISSING_SECRET = "781903";

process.env.BUNNY_ACTIVE_LIBRARY_IDS = [
  LIB_A,
  LIB_B,
  LIB_NO_CATALOG,
  LIB_DISABLED,
  LIB_CROSS_REF,
  LIB_MISSING_SECRET,
].join(",");
process.env.BUNNY_PLAYBACK_URL_TEMPLATE =
  "https://default.b-cdn.net/{video_id}/{quality}";
process.env.BUNNY_STREAM_LIBRARY_ID = "736742";
process.env.BUNNY_STREAM_API_KEY = "fixture-default-api-key";
process.env.BUNNY_TOKEN_KEY = "fixture-default-token-key";
process.env.BUNNY_780700_PLAYBACK_URL_TEMPLATE =
  "https://a.b-cdn.net/{video_id}/{quality}";
process.env.BUNNY_781800_PLAYBACK_URL_TEMPLATE =
  "https://b.b-cdn.net/{video_id}/{quality}";
process.env.BUNNY_780700_STREAM_API_KEY = "fixture-a-stream-api-key-0001";
process.env.BUNNY_780700_TOKEN_KEY = "fixture-a-token-key-0001";
process.env.BUNNY_781800_STREAM_API_KEY = "fixture-b-stream-api-key-0002";
process.env.BUNNY_781800_TOKEN_KEY = "fixture-b-token-key-0002";

const resolver = require("../lib/core/video/bunny_library_secret_resolver.js");

let functions;
try {
  functions = require("../lib/index.js");
} catch (error) {
  console.error("Failed to load functions:", error);
  process.exit(1);
}

const generateBunnySignedUrl = test.wrap(functions.generateBunnySignedUrl);
const validateBunnyVideoAssociation = test.wrap(
  functions.validateBunnyVideoAssociation,
);
const db = admin.firestore();

const SECRET_VALUES = [
  process.env.BUNNY_TOKEN_KEY,
  process.env.BUNNY_STREAM_API_KEY,
  process.env.BUNNY_780700_TOKEN_KEY,
  process.env.BUNNY_780700_STREAM_API_KEY,
  process.env.BUNNY_781800_TOKEN_KEY,
  process.env.BUNNY_781800_STREAM_API_KEY,
];

function assertNoSecretLeak(payload, label) {
  const serialized = JSON.stringify(payload);
  for (const value of SECRET_VALUES) {
    assert.ok(
      !serialized.includes(value),
      `${label}: response must not expose a secret value`,
    );
  }
  for (const name of [
    "BUNNY_780700_TOKEN_KEY",
    "BUNNY_780700_STREAM_API_KEY",
    "BUNNY_781800_TOKEN_KEY",
    "BUNNY_781800_STREAM_API_KEY",
  ]) {
    assert.ok(
      !serialized.includes(name),
      `${label}: response must not expose a secret name`,
    );
  }
}

function catalogDocument(libraryId, overrides = {}) {
  return {
    library_id: libraryId,
    display_name: `Library ${libraryId}`,
    status: "active",
    pull_zone_id: 123456,
    playback_host: "vz-flow.b-cdn.net",
    source: "manual_registration",
    token_auth_enabled: true,
    token_auth_verified: true,
    credential_refs: {
      stream_api_key: `BUNNY_${libraryId}_STREAM_API_KEY`,
      token_key: `BUNNY_${libraryId}_TOKEN_KEY`,
    },
    ...overrides,
  };
}

// Independent re-implementation of the documented Bunny directory-token
// construction (Mission 13), used only to prove WHICH key signed the URL.
function expectedDirectoryToken(secret, scope, expires) {
  const signature = crypto
    .createHmac("sha256", secret)
    .update(scope)
    .update(String(expires))
    .update(`token_path=${scope}`)
    .digest("base64url");
  return `HS256-${signature}`;
}

function tokenFromUrl(url) {
  const match = /\/bcdn_token=([^&]+)&token_path=([^&]+)&expires=(\d+)\//.exec(url);
  assert.ok(match, "signed URL carries the directory token block");
  return {token: match[1], expires: Number(match[3])};
}

function resolverDeps() {
  return {
    catalog: resolver.firestoreBunnyCatalogSource(db),
    // cacheTtlMs: 0 keeps each assertion independent of earlier reads.
    secrets: resolver.createBunnySecretAccessor({
      isEmulator: true,
      cacheTtlMs: 0,
    }),
    env: process.env,
  };
}

async function run() {
  console.log(
    "Starting bunny_library_secret_resolver_flow tests against emulator...",
  );
  let passed = 0;
  const ok = (name) => {
    passed++;
    console.log(`ok - ${name}`);
  };
  const ts = (ms) => admin.firestore.Timestamp.fromMillis(ms);

  const student = "u_flow_student";
  const doctor = "u_flow_doctor";
  const subj = "subj_flow";
  const device = "flow_device_1_xxxxxxxxxxxxxxx";
  const GUID_A = "7ddd0e6e-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
  const GUID_B = "7ddd0e6e-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
  const GUID_PLAIN = "7ddd0e6e-cccc-4ccc-8ccc-cccccccccccc";
  const lecA = "flow_lec_a";
  const lecB = "flow_lec_b";
  const lecPlain = "flow_lec_plain";

  // --- catalog -----------------------------------------------------------
  await db
    .collection("bunny_libraries")
    .doc(LIB_A)
    .set(catalogDocument(LIB_A));
  await db
    .collection("bunny_libraries")
    .doc(LIB_B)
    .set(catalogDocument(LIB_B));
  await db
    .collection("bunny_libraries")
    .doc(LIB_DISABLED)
    .set(catalogDocument(LIB_DISABLED, {status: "disabled"}));
  await db
    .collection("bunny_libraries")
    .doc(LIB_CROSS_REF)
    .set(
      catalogDocument(LIB_CROSS_REF, {
        credential_refs: {
          stream_api_key: "BUNNY_781800_STREAM_API_KEY",
          token_key: "BUNNY_781800_TOKEN_KEY",
        },
      }),
    );
  await db
    .collection("bunny_libraries")
    .doc(LIB_MISSING_SECRET)
    .set(catalogDocument(LIB_MISSING_SECRET));

  // --- resolver against the emulator catalog -----------------------------
  {
    const deps = resolverDeps();
    const a = await resolver.resolveBunnyPlaybackCredentials({
      libraryId: LIB_A,
      deps,
    });
    assert.equal(a.ok, true, "A playback credentials resolve");
    assert.equal(a.runtime.tokenKey, process.env.BUNNY_780700_TOKEN_KEY);
    assert.equal(
      a.runtime.playbackUrlTemplate,
      process.env.BUNNY_780700_PLAYBACK_URL_TEMPLATE,
    );
    const b = await resolver.resolveBunnyPlaybackCredentials({
      libraryId: LIB_B,
      deps: resolverDeps(),
    });
    assert.equal(b.ok, true, "B playback credentials resolve");
    assert.equal(b.runtime.tokenKey, process.env.BUNNY_781800_TOKEN_KEY);
    assert.notEqual(a.runtime.tokenKey, b.runtime.tokenKey);
    ok("catalog-backed libraries resolve only their own token keys");
  }

  {
    const a = await resolver.resolveBunnyStreamApiCredentials({
      libraryId: LIB_A,
      deps: resolverDeps(),
    });
    const b = await resolver.resolveBunnyStreamApiCredentials({
      libraryId: LIB_B,
      deps: resolverDeps(),
    });
    assert.equal(a.runtime.apiKey, process.env.BUNNY_780700_STREAM_API_KEY);
    assert.equal(b.runtime.apiKey, process.env.BUNNY_781800_STREAM_API_KEY);
    assert.equal(a.runtime.apiLibraryId, LIB_A);
    assert.equal(b.runtime.apiLibraryId, LIB_B);
    assert.notEqual(a.runtime.apiKey, b.runtime.apiKey);
    ok("catalog-backed libraries resolve only their own Stream API keys");
  }

  {
    const result = await resolver.resolveBunnyPlaybackCredentials({
      libraryId: LIB_NO_CATALOG,
      deps: resolverDeps(),
    });
    assert.equal(result.ok, false);
    assert.equal(result.reason, "unknown_library");
    ok("allow-listed library with no catalog row fails closed");
  }

  {
    const disabled = await resolver.resolveBunnyPlaybackCredentials({
      libraryId: LIB_DISABLED,
      deps: resolverDeps(),
    });
    assert.equal(disabled.ok, false);
    assert.equal(disabled.reason, "library_not_activated");

    const crossRef = await resolver.resolveBunnyStreamApiCredentials({
      libraryId: LIB_CROSS_REF,
      deps: resolverDeps(),
    });
    assert.equal(crossRef.ok, false);
    assert.equal(crossRef.reason, "credential_name_mismatch");

    const missing = await resolver.resolveBunnyStreamApiCredentials({
      libraryId: LIB_MISSING_SECRET,
      deps: resolverDeps(),
    });
    assert.equal(missing.ok, false);
    assert.equal(missing.reason, "secret_not_found");
    ok("disabled, cross-referenced and missing-secret entries fail closed");
  }

  // --- callable: playback signing uses the library's own token key --------
  await db.collection("users").doc(student).set({
    student_type: "center_student",
    approval_status: "approved",
  });
  await db.collection("users").doc(doctor).set({
    role: "doctor",
    approval_status: "approved",
  });
  await db.collection("plans").doc("flowfree").set({
    student_type: "center_student",
    plan_key: "free",
    is_active: true,
  });
  const feat = (id, key, enabled, value) =>
    db.collection("plan_features").doc(id).set(
      Object.assign(
        {plan_id: "flowfree", feature_key: key, enabled},
        value === undefined ? {} : {feature_value: value},
      ),
    );
  await feat("flowf-acc", "video.access", true);
  await feat("flowf-max", "video.quality.max", true, "720p");
  await feat("flowf-rw", "video.rolling_window.enabled", true);
  await feat("flowf-rwh", "video.rolling_window.hours", true, 24);
  await feat("flowf-dev", "device.max_count", true, 1);
  await db
    .collection("subject_access_assignments")
    .doc(`${student}_${subj}`)
    .set({
      student_id: student,
      subject_id: subj,
      is_deleted: false,
      enabled: true,
      subscription_expires_at: ts(Date.now() + 100000000),
      entitlements: {"video.view": true},
    });
  await db.collection("subscriptions").doc("flowsub1").set({
    student_id: student,
    subject_id: subj,
    status: "active",
    plan_id: "flowfree",
  });

  for (const id of [lecA, lecB, lecPlain]) {
    await db.collection("lectures").doc(id).set({
      subject_id: subj,
      is_deleted: false,
      is_visible: true,
      status: "published",
    });
  }
  const resource = (id, lectureId, videoId, libraryId) =>
    db.collection("lecture_resources").doc(id).set({
      lecture_id: lectureId,
      bunny_video_id: videoId,
      resource_type: "video",
      bunny_library_id: libraryId,
    });
  await resource("flowresA", lecA, GUID_A, LIB_A);
  await resource("flowresB", lecB, GUID_B, LIB_B);
  await resource("flowresPlain", lecPlain, GUID_PLAIN, LIB_NO_CATALOG);

  const call = (uid, body) =>
    generateBunnySignedUrl({
      data: Object.assign({deviceId: device}, body),
      auth: {uid},
    });
  const resetWindow = () =>
    db.collection("video_watch_windows").doc(student).delete().catch(() => {});

  await resetWindow();
  const a = await call(student, {
    videoId: GUID_A,
    lectureId: lecA,
    subjectId: subj,
  });
  const aToken = tokenFromUrl(a.url);
  assert.ok(
    a.url.startsWith("https://a.b-cdn.net/"),
    "A issues against A's pull zone",
  );
  assert.equal(
    aToken.token,
    expectedDirectoryToken(
      process.env.BUNNY_780700_TOKEN_KEY,
      `/${GUID_A}/`,
      aToken.expires,
    ),
    "A's URL is signed with A's token key",
  );
  for (const otherKey of [
    process.env.BUNNY_781800_TOKEN_KEY,
    process.env.BUNNY_TOKEN_KEY,
  ]) {
    assert.notEqual(
      aToken.token,
      expectedDirectoryToken(otherKey, `/${GUID_A}/`, aToken.expires),
      "A's URL is never signed with another library's token key",
    );
  }
  assertNoSecretLeak(a, "A issuance");
  ok("playback for Library A is signed with A's own token key");

  await resetWindow();
  const b = await call(student, {
    videoId: GUID_B,
    lectureId: lecB,
    subjectId: subj,
  });
  const bToken = tokenFromUrl(b.url);
  assert.ok(
    b.url.startsWith("https://b.b-cdn.net/"),
    "B issues against B's pull zone",
  );
  assert.equal(
    bToken.token,
    expectedDirectoryToken(
      process.env.BUNNY_781800_TOKEN_KEY,
      `/${GUID_B}/`,
      bToken.expires,
    ),
    "B's URL is signed with B's token key",
  );
  assert.notEqual(
    bToken.token,
    expectedDirectoryToken(
      process.env.BUNNY_780700_TOKEN_KEY,
      `/${GUID_B}/`,
      bToken.expires,
    ),
    "B's URL is never signed with A's token key",
  );
  assertNoSecretLeak(b, "B issuance");
  ok("playback for Library B is signed with B's own token key");

  // --- callable: no catalog row means no playback -------------------------
  await resetWindow();
  let failure = null;
  try {
    await call(student, {
      videoId: GUID_PLAIN,
      lectureId: lecPlain,
      subjectId: subj,
    });
  } catch (error) {
    failure = error;
  }
  assert.ok(failure, "uncatalogued library is denied");
  assert.equal(failure.code, "failed-precondition");
  assert.ok(
    failure.message.includes("unknown_library"),
    "denial reason stays registry-style",
  );
  assertNoSecretLeak(failure.message, "uncatalogued denial");
  ok("uncatalogued library never falls back to a global credential");

  // --- callable: validation fails closed without leaking secret state -----
  const doctorAuth = {uid: doctor, token: {role: "doctor"}};
  const disabledValidation = await validateBunnyVideoAssociation({
    data: {videoId: GUID_A, libraryId: LIB_DISABLED},
    auth: doctorAuth,
  });
  assert.equal(disabledValidation.status, "unavailable");
  assert.equal(disabledValidation.reason, "inactive_library");
  assert.equal(disabledValidation.receipt, null);
  assertNoSecretLeak(disabledValidation, "disabled validation");
  ok("disabled library is unavailable, never verified");

  const missingSecretValidation = await validateBunnyVideoAssociation({
    data: {videoId: GUID_A, libraryId: LIB_MISSING_SECRET},
    auth: doctorAuth,
  });
  assert.equal(missingSecretValidation.status, "unavailable");
  assert.equal(
    missingSecretValidation.reason,
    "incomplete_configuration",
    "a missing secret is never reported as a secret problem",
  );
  assert.equal(missingSecretValidation.receipt, null);
  assertNoSecretLeak(missingSecretValidation, "missing-secret validation");
  ok("missing per-library secret fails closed as incomplete_configuration");

  bunnyGuard.assertNoBunnyCalls();
  console.log(
    `bunny_library_secret_resolver_flow tests passed (${passed}).`,
  );
  process.exit(0);
}

run().catch((error) => {
  console.error("FAIL", error);
  process.exitCode = 1;
});
