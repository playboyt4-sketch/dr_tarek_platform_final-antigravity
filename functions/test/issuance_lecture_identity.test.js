/**
 * Lecture-identity resolution in `generateBunnySignedUrl` (identity fix).
 *
 * Emulator suite: the bunny_video_id selects the VIDEO FILE only. When the
 * client asserts lectureId, authorization (per-lecture access, rolling
 * window, session content) must run on THAT lecture — a duplicated video
 * shared by two lectures must never collapse to limit(1) first-match
 * (fail-open). Legacy callers without lectureId keep working only while
 * the video maps to exactly one live lecture (ambiguity denies).
 *
 * Seed shapes mirror sections_12_13.test.js (same collections/fields).
 */
const test = require("firebase-functions-test")();
const assert = require("node:assert/strict");
const admin = require("firebase-admin");

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = "demo-test";
process.env.BUNNY_PLAYBACK_URL_TEMPLATE = "https://example.com/{video_id}/{quality}";
process.env.BUNNY_TOKEN_KEY = "test_key";

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
  } catch (e) {
    assert.equal(e.code, code, `${name}: expected ${code}, got ${e.code} (${e.message})`);
    console.log(`ok - ${name} (denied ${code})`);
    return;
  }
  assert.fail(`${name}: expected denial ${code}, issuance succeeded`);
}

async function run() {
  console.log("Starting issuance_lecture_identity tests against emulator...");
  let passed = 0;
  const ok = (name) => {
    passed++;
    console.log(`ok - ${name}`);
  };

  const userCenter = "u_ident_center";
  const userGuest = "u_ident_guest";
  const userLegacy = "u_ident_legacy";
  const subj1 = "subj_ident_1";
  const subj2 = "subj_ident_2";
  const dev1 = "ident_device_1_xxxxxxxxxxxxxxxx";
  const devG = "ident_device_guest_xxxxxxxxxxxx";
  const dev2 = "ident_device_2_xxxxxxxxxxxxxxxx";

  // Strict Video-ID contract: fixtures must be bare GUIDs. Semantics
  // preserved exactly: vidX duplicated across A+C, vidY/vidZ/vidF distinct.
  const vidX = "11111111-1111-4111-8111-111111111111";
  const vidY = "22222222-2222-4222-8222-222222222222";
  const vidZ = "33333333-3333-4333-8333-333333333333";
  const vidF = "44444444-4444-4444-8444-444444444444";
  const lecA = "ident_lec_A";
  const lecC = "ident_lec_C";
  const lecD = "ident_lec_D";
  const lecE = "ident_lec_E_nores";
  const lecF = "ident_lec_F_subj2";
  const lecG = "ident_lec_G_unique";

  for (const [uid, type] of [[userCenter, "center_student"], [userGuest, "guest"], [userLegacy, "center_student"]]) {
    await db.collection("users").doc(uid).set({student_type: type, approval_status: "approved"});
  }
  for (const [pid, pkey, ptype] of [["pfree", "free", "center_student"], ["ppro", "pro", "center_student"], ["guest", "guest", "guest"]]) {
    await db.collection("plans").doc(pid).set({student_type: ptype, plan_key: pkey, is_active: true});
  }
  const feat = (id, plan, key, enabled, value) =>
    db.collection("plan_features").doc(id).set(
      Object.assign({plan_id: plan, feature_key: key, enabled}, value === undefined ? {} : {feature_value: value}),
    );
  await feat("if-acc", "pfree", "video.access", true);
  await feat("if-max", "pfree", "video.quality.max", true, "720p");
  await feat("if-rw", "pfree", "video.rolling_window.enabled", true);
  await feat("if-rwh", "pfree", "video.rolling_window.hours", true, 24);
  await feat("if-dev", "pfree", "device.max_count", true, 1);
  await feat("ig-acc", "guest", "video.access", true);
  await feat("ig-max", "guest", "video.quality.max", true, "480p");
  await feat("ig-prev", "guest", "video.preview_duration", true, 7);
  await feat("ig-dev", "guest", "device.max_count", true, 1);

  const assign = (uid, subj) =>
    db.collection("subject_access_assignments").doc(`${uid}_${subj}`).set({
      student_id: uid,
      subject_id: subj,
      is_deleted: false,
      enabled: true,
      subscription_expires_at: ts(Date.now() + 100000000),
      entitlements: {"video.view": true},
    });
  await assign(userCenter, subj1);
  await assign(userGuest, subj1);
  await assign(userLegacy, subj1);
  await db.collection("subscriptions").doc("isub1").set({
    student_id: userCenter, subject_id: subj1, status: "active", plan_id: "pfree",
  });
  await db.collection("subscriptions").doc("isubG").set({
    student_id: userGuest, subject_id: subj1, status: "active", plan_id: "guest",
  });
  await db.collection("subscriptions").doc("isub2").set({
    student_id: userLegacy, subject_id: subj1, status: "active", plan_id: "pfree",
  });

  const lecture = (id, subj, extra) =>
    db.collection("lectures").doc(id).set(Object.assign(
      {subject_id: subj, is_deleted: false, is_visible: true, status: "published"},
      extra || {},
    ));
  await lecture(lecA, subj1);
  await lecture(lecC, subj1);
  await lecture(lecD, subj1);
  await lecture(lecE, subj1);
  await lecture(lecF, subj2);
  await lecture(lecG, subj1, {guest_enabled: true, guest_preview_minutes: 5});

  const res = (id, lec, vid) =>
    db.collection("lecture_resources").doc(id).set({
      lecture_id: lec, bunny_video_id: vid, resource_type: "video",
    });
  // Duplicate video shared by two lectures (the reported live shape).
  await res("iresA", lecA, vidX);
  await res("iresC", lecC, vidX);
  await res("iresD", lecD, vidY);
  await res("iresF", lecF, vidF);
  await res("iresG", lecG, vidZ);

  const call = (uid, body) =>
    generateBunnySignedUrl({data: Object.assign({deviceId: dev1}, body), auth: {uid}});
  const winRef = db.collection("video_watch_windows").doc(userCenter);

  // Window active on A.
  await winRef.set({
    active_lecture_id: lecA,
    window_expires_at: ts(Date.now() + 23 * 3600 * 1000),
    user_id: userCenter,
  });

  // TEST 1a/4: open A with asserted identity -> ALLOW, Full (no preview keys).
  const rA = await call(userCenter, {videoId: vidX, lectureId: lecA, subjectId: subj1});
  assert.ok(rA.url, "A issuance returns a URL");
  assert.equal(rA.previewLimitSeconds, undefined, "Center Free stays Full (no preview keys)");
  assert.equal(rA.previewAudience, undefined, "Center Free carries no audience");
  ok("TEST 1a/4 - open A (asserted) -> ALLOW Full");

  // TEST 1b/9: open C (same file) with asserted identity -> DENY window.
  // Proves C was evaluated as C: an A-row first-match would allow same_video.
  await expectCode(
    call(userCenter, {videoId: vidX, lectureId: lecC, subjectId: subj1}),
    "resource-exhausted",
    "TEST 1b/9 - open C (asserted, dup video) -> DENY window-blocked",
  );
  passed++;

  // TEST 2: different video, window on A -> DENY window-blocked.
  await expectCode(
    call(userCenter, {videoId: vidY, lectureId: lecD, subjectId: subj1}),
    "resource-exhausted",
    "TEST 2 - open D (different video) -> DENY window-blocked",
  );
  passed++;

  // TEST 3: reopen A -> ALLOW same_video.
  await call(userCenter, {videoId: vidX, lectureId: lecA, subjectId: subj1});
  ok("TEST 3 - reopen A (asserted) -> ALLOW same_video");

  // TEST 6: unknown lectureId -> FAIL-CLOSED invalid-argument.
  await expectCode(
    call(userCenter, {videoId: vidX, lectureId: "nope_missing", subjectId: subj1}),
    "invalid-argument",
    "TEST 6 - unknown lectureId -> DENY invalid-argument",
  );
  passed++;

  // TEST 7: lecture from another subject -> FAIL-CLOSED invalid-argument.
  await expectCode(
    call(userCenter, {videoId: vidF, lectureId: lecF, subjectId: subj1}),
    "invalid-argument",
    "TEST 7 - cross-subject lectureId -> DENY invalid-argument",
  );
  passed++;

  // TEST 8: lecture exists but no linked resource -> FAIL-CLOSED.
  await expectCode(
    call(userCenter, {videoId: vidX, lectureId: lecE, subjectId: subj1}),
    "invalid-argument",
    "TEST 8 - lecture without resource row -> DENY invalid-argument",
  );
  passed++;

  // TEST 5: Guest preview behavior unchanged (lecture 5min -> 300s).
  // A guest-plan student BEYOND the 1-device allowance resolves Guest tier
  // (first device would bind Full): pre-occupy the slot, then issue.
  const crypto = require("node:crypto");
  const guestHash = crypto
    .createHash("sha256")
    .update(`${userGuest}|ident_device_g0_xxxxxxxxxxxx`)
    .digest("hex");
  await db
    .collection("subject_device_authorizations")
    .doc(`${userGuest}_${subj1}_${guestHash}`)
    .set({
      student_id: userGuest,
      subject_id: subj1,
      device_hash: guestHash,
      plan_key_at_bind: "guest",
      status: "active",
    });
  const rG = await generateBunnySignedUrl({
    data: {videoId: vidZ, lectureId: lecG, subjectId: subj1, deviceId: devG},
    auth: {uid: userGuest},
  });
  assert.equal(rG.previewLimitSeconds, 300, "guest preview minutes preserved");
  assert.equal(rG.previewAudience, "guest", "guest audience preserved");
  ok("TEST 5 - Guest preview unchanged (300s/guest)");

  // TEST 10: legacy caller without lectureId.
  // Unambiguous single-video lecture still works (backward compatible).
  await db.collection("video_watch_windows").doc(userLegacy).delete().catch(() => {});
  const rL = await generateBunnySignedUrl({
    data: {videoId: vidZ, subjectId: subj1, deviceId: dev2},
    auth: {uid: userLegacy},
  });
  assert.ok(rL.url, "legacy unambiguous issuance returns a URL");
  ok("TEST 10a - legacy no-lectureId single video -> ALLOW");
  // Ambiguous duplicated video without identity -> FAIL-CLOSED.
  await expectCode(
    generateBunnySignedUrl({
      data: {videoId: vidX, subjectId: subj1, deviceId: dev2},
      auth: {uid: userLegacy},
    }),
    "failed-precondition",
    "TEST 10b - legacy no-lectureId dup video -> DENY ambiguous",
  );
  passed++;

  console.log(`issuance_lecture_identity tests passed (${passed}).`);

  // Cleanup: the "guest" plan id is GLOBAL (isGuestPlan pins it) and other
  // suites seed their own plan_features under the same plan_id with
  // first-match-wins reads. Remove our rows so later suites observe no
  // cross-suite footprint (all other fixtures already use prefixed IDs).
  await db.collection("plans").doc("guest").delete();
  for (const suffix of ["acc", "max", "prev", "dev"]) {
    await db.collection("plan_features").doc(`ig-${suffix}`).delete();
  }
  process.exit(0);
}

run().catch((error) => {
  console.error("FAIL", error);
  process.exitCode = 1;
});

