/**
 * ADR-010 — multi-library resolution through the real issuance callable.
 *
 * Emulator suite (Firestore + Functions): proves library resolution happens on
 * the TRUSTED resource record, that legacy rows keep the default library, that
 * unknown/inactive libraries fail closed, that a client hint can never switch
 * credentials, and that entitlement/window behaviour is unchanged.
 *
 * No Bunny network call is made: issuance only signs locally.
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
// Library 775315 must stay INACTIVE for this environment (no allow-list).
delete process.env.BUNNY_ACTIVE_LIBRARY_IDS;

let functions;
try {
  functions = require("../lib/index.js");
} catch (error) {
  console.error("Failed to load functions:", error);
  process.exit(1);
}

const generateBunnySignedUrl = test.wrap(functions.generateBunnySignedUrl);
const db = admin.firestore();
const ts = (ms) => admin.firestore.Timestamp.fromMillis(ms);

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
    return error;
  }
  assert.fail(`${name}: expected denial ${code}, call succeeded`);
}

async function run() {
  console.log("Starting issuance_library_flow tests against emulator...");
  let passed = 0;
  const ok = (name) => {
    passed++;
    console.log(`ok - ${name}`);
  };

  const student = "u_lib_student";
  const outsider = "u_lib_outsider";
  const subj = "subj_lib_1";
  const device = "lib_device_1_xxxxxxxxxxxxxxxx";

  const vidLegacy = "11111111-1111-4111-8111-111111111111";
  const vidDefault = "22222222-2222-4222-8222-222222222222";
  const vidUnknown = "33333333-3333-4333-8333-333333333333";
  const vidInactive = "44444444-4444-4444-8444-444444444444";
  const lecLegacy = "lib_lec_legacy";
  const lecDefault = "lib_lec_default";
  const lecUnknown = "lib_lec_unknown";
  const lecInactive = "lib_lec_inactive";
  const lecOther = "lib_lec_other";

  for (const [uid, type] of [
    [student, "center_student"],
    [outsider, "center_student"],
  ]) {
    await db.collection("users").doc(uid).set({
      student_type: type,
      approval_status: "approved",
    });
  }
  await db.collection("plans").doc("libfree").set({
    student_type: "center_student",
    plan_key: "free",
    is_active: true,
  });
  const feat = (id, key, enabled, value) =>
    db.collection("plan_features").doc(id).set(
      Object.assign(
        {plan_id: "libfree", feature_key: key, enabled},
        value === undefined ? {} : {feature_value: value},
      ),
    );
  await feat("libf-acc", "video.access", true);
  await feat("libf-max", "video.quality.max", true, "720p");
  await feat("libf-rw", "video.rolling_window.enabled", true);
  await feat("libf-rwh", "video.rolling_window.hours", true, 24);
  await feat("libf-dev", "device.max_count", true, 1);

  await db.collection("subject_access_assignments").doc(`${student}_${subj}`).set({
    student_id: student,
    subject_id: subj,
    is_deleted: false,
    enabled: true,
    subscription_expires_at: ts(Date.now() + 100000000),
    entitlements: {"video.view": true},
  });
  await db.collection("subscriptions").doc("libsub1").set({
    student_id: student,
    subject_id: subj,
    status: "active",
    plan_id: "libfree",
  });

  const lecture = (id) =>
    db.collection("lectures").doc(id).set({
      subject_id: subj,
      is_deleted: false,
      is_visible: true,
      status: "published",
    });
  for (const id of [lecLegacy, lecDefault, lecUnknown, lecInactive, lecOther]) {
    await lecture(id);
  }

  const resource = (id, lectureId, videoId, libraryId) =>
    db.collection("lecture_resources").doc(id).set(
      Object.assign(
        {lecture_id: lectureId, bunny_video_id: videoId, resource_type: "video"},
        libraryId === undefined ? {} : {bunny_library_id: libraryId},
      ),
    );
  await resource("libresLegacy", lecLegacy, vidLegacy);
  await resource("libresDefault", lecDefault, vidDefault, "736742");
  await resource("libresUnknown", lecUnknown, vidUnknown, "999999");
  await resource("libresInactive", lecInactive, vidInactive, "775315");

  const call = (uid, body) =>
    generateBunnySignedUrl({
      data: Object.assign({deviceId: device}, body),
      auth: {uid},
    });
  // Each library case must reach library resolution, so the 24h rolling window
  // armed by the previous successful issuance is cleared first. The window
  // behaviour itself is asserted in the final case.
  const resetWindow = () =>
    db.collection("video_watch_windows").doc(student).delete().catch(() => {});

  // --- authentication ---
  await expectCode(
    generateBunnySignedUrl({data: {videoId: vidLegacy, lectureId: lecLegacy, deviceId: device}}),
    "unauthenticated",
    "unauthenticated caller is denied",
  );
  passed++;

  // --- legacy resource: default library, unchanged URL contract ---
  const legacy = await call(student, {videoId: vidLegacy, lectureId: lecLegacy, subjectId: subj});
  assert.ok(typeof legacy.url === "string" && legacy.url.length > 0, "legacy row issues a URL");
  assert.ok(legacy.url.includes(vidLegacy), "URL targets the requested video");
  assert.ok(legacy.url.includes("bcdn_token="), "URL carries the directory token");
  // Mission 13 regression: pull zone 6807898 runs Bunny ADVANCED token auth,
  // so the token must be the path-embedded `HS256-…` directory token together
  // with `token_path` and `expires`. A plain `?token=<sha256>` query token is
  // rejected by the edge with 403 even though the key is correct.
  assert.ok(legacy.url.includes("/bcdn_token=HS256-"), "URL uses the HS256 path token");
  assert.ok(legacy.url.includes("token_path="), "URL scopes the token to the video path");
  assert.ok(/[?&]expires=\d+/.test(legacy.url), "URL carries a numeric expiry in the token block");
  assert.ok(!/[?&]token=/.test(legacy.url), "no legacy query-parameter token is emitted");
  assert.ok(Number.isInteger(legacy.expiresAt), "expiry contract preserved");
  ok("legacy resource (no library id) issues through the default library");

  // --- explicit default association behaves identically ---
  await resetWindow();
  const explicit = await call(student, {videoId: vidDefault, lectureId: lecDefault, subjectId: subj});
  assert.ok(explicit.url.includes(vidDefault), "explicit default library issues the video");
  ok("explicit default-library association issues normally");

  // --- unknown library fails closed, never falls back ---
  await resetWindow();
  const unknownError = await expectCode(
    call(student, {videoId: vidUnknown, lectureId: lecUnknown, subjectId: subj}),
    "failed-precondition",
    "unknown library id fails closed",
  );
  assert.ok(
    String(unknownError.message).includes("unknown_library"),
    `message names the reason (got: ${unknownError.message})`,
  );
  passed++;

  // --- inactive library fails closed ---
  await resetWindow();
  const inactiveError = await expectCode(
    call(student, {videoId: vidInactive, lectureId: lecInactive, subjectId: subj}),
    "failed-precondition",
    "inactive library (775315) fails closed",
  );
  assert.ok(
    String(inactiveError.message).includes("library_not_activated"),
    `message names the reason (got: ${inactiveError.message})`,
  );
  passed++;

  // --- client hint cannot override the trusted record ---
  await resetWindow();
  await expectCode(
    call(student, {
      videoId: vidDefault,
      lectureId: lecDefault,
      subjectId: subj,
      libraryId: "775315",
    }),
    "failed-precondition",
    "client hint disagreeing with the stored library is rejected",
  );
  passed++;
  // A malformed hint on a row WITH a stored library is a mismatch.
  await resetWindow();
  await expectCode(
    call(student, {
      videoId: vidDefault,
      lectureId: lecDefault,
      subjectId: subj,
      libraryId: "abc",
    }),
    "failed-precondition",
    "malformed client hint on an associated row is rejected",
  );
  passed++;
  // On a legacy row a hint is simply IGNORED (it can never pick credentials),
  // so playback keeps working through the default library.
  await resetWindow();
  const legacyHintIgnored = await call(student, {
    videoId: vidLegacy,
    lectureId: lecLegacy,
    subjectId: subj,
    libraryId: "abc",
  });
  assert.ok(
    legacyHintIgnored.url.includes(vidLegacy),
    "legacy row still issues when a stray hint is present",
  );
  ok("hint on a legacy row is ignored, never used for credentials");

  // Matching hint is accepted (hint is allowed, just not authoritative).
  await resetWindow();
  const hinted = await call(student, {
    videoId: vidDefault,
    lectureId: lecDefault,
    subjectId: subj,
    libraryId: "736742",
  });
  assert.ok(hinted.url.includes(vidDefault), "matching hint keeps playback working");
  ok("matching client hint is accepted");

  // --- authorization unchanged: no subscription -> denied before signing ---
  await expectCode(
    call(outsider, {videoId: vidLegacy, lectureId: lecLegacy, subjectId: subj}),
    "permission-denied",
    "subject without entitlement is denied",
  );
  passed++;

  // --- rolling window still enforced across videos ---
  // Armed by the last successful issuance, then a different lecture is blocked.
  await resetWindow();
  await call(student, {videoId: vidLegacy, lectureId: lecLegacy, subjectId: subj});
  await expectCode(
    call(student, {videoId: vidDefault, lectureId: lecDefault, subjectId: subj}),
    "resource-exhausted",
    "rolling window blocks a different lecture (unchanged)",
  );
  passed++;

  bunnyGuard.assertNoBunnyCalls();
  console.log(`issuance_library_flow tests passed (${passed}).`);

  // Cleanup this suite's global-surface rows (plans/plan_features are shared).
  await db.collection("plans").doc("libfree").delete();
  for (const suffix of ["acc", "max", "rw", "rwh", "dev"]) {
    await db.collection("plan_features").doc(`libf-${suffix}`).delete();
  }
  process.exit(0);
}

run().catch((error) => {
  console.error("FAIL", error);
  process.exitCode = 1;
});
