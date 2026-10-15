/**
 * Max playback session tests (ADR-004 follow-up step).
 *
 * One live session per Student + Subject, server-owned tokens and leases,
 * takeover by transaction, resume from `lecture_progress`, fail-closed
 * validation. Guest/revoked/expired/disabled callers are denied.
 *
 * Runs inside `firebase emulators:exec` (firestore + auth).
 */
const test = require("firebase-functions-test")();
const assert = require("node:assert/strict");
const admin = require("firebase-admin");

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || "demo-test";
process.env.BUNNY_PLAYBACK_URL_TEMPLATE =
  "https://cdn.example.com/{video_id}/{quality}/stream.m3u8";
process.env.BUNNY_TOKEN_KEY = "test-secret-key";

let functions;
try {
  functions = require("../lib/index.js");
} catch (error) {
  console.error("Failed to load functions:", error);
  process.exit(1);
}

const STUDENT = "pbs_student";
const DOCTOR = "pbs_doctor";
const ADMIN_DEV = "pbs_admin_dev";
const SUB_A = "pbs_maxA";
const SUB_B = "pbs_maxB";
const LEC_A = "pbs_lecA";
const LEC_B = "pbs_lecB";

const studentCtx = {uid: STUDENT, token: {role: "student", approved: true}};
const doctorCtx = {uid: DOCTOR, token: {role: "doctor"}};
const adminDevCtx = {uid: ADMIN_DEV, token: {role: "admin"}};

function expectCode(promise, code, label) {
  return promise.then(
    () => {
      throw new Error(`${label}: expected rejection with ${code}, but succeeded`);
    },
    (e) => {
      assert.equal(e.code, code, `${label}: expected ${code}, got ${e.code} (${e.message})`);
    },
  );
}

async function run() {
  console.log("Starting playback_session tests against emulator...");
  const db = admin.firestore();
  const beginRaw = test.wrap(functions.beginOrTakeoverPlayback);
  const begin = (payload) => beginRaw({data: payload, auth: studentCtx});
  const beatRaw = test.wrap(functions.heartbeatPlayback);
  const beat = (payload) => beatRaw({data: payload, auth: studentCtx});
  const resetRaw = test.wrap(functions.resetStudentDevices);
  const unbindRaw = test.wrap(functions.unbindSubjectDevice);
  const videoRaw = test.wrap(functions.generateBunnySignedUrl);
  const videoUrl = (payload) => videoRaw({data: payload, auth: studentCtx});

  await db.collection("users").doc(STUDENT).set({
    role: "student", student_type: "center_student",
    approval_status: "approved", account_status: "active",
  });
  await db.collection("admin_permissions").doc(ADMIN_DEV).set({
    is_active: true, permissions: {admin_devices: true},
  });
  await db.collection("plans").doc("pbs_plan_max").set({
    plan_key: "center_max", student_type: "center_student", is_active: true,
  });
  for (const [key, value] of [
    ["device.max_count", 2], ["video.access", true], ["video.quality.720p", true],
  ]) {
    await db.collection("plan_features").doc(`pbs_feat_${key}`).set({
      plan_id: "pbs_plan_max", feature_key: key, feature_value: value, enabled: true,
    });
  }
  for (const [subjectId, lectureId] of [[SUB_A, LEC_A], [SUB_B, LEC_B]]) {
    await db.collection("subjects").doc(subjectId).set({title: subjectId});
    await db.collection("subject_sections").doc(`pbs_sec_${subjectId}`).set({subject_id: subjectId});
    await db.collection("subject_access_assignments").doc(`${STUDENT}_${subjectId}`).set({
      student_id: STUDENT, subject_id: subjectId, enabled: true, is_deleted: false,
    });
    await db.collection("subscriptions").doc(`pbs_sub_${subjectId}`).set({
      student_id: STUDENT, subject_id: subjectId, plan_id: "pbs_plan_max", status: "active",
    });
    await db.collection("lectures").doc(lectureId).set({
      subject_id: subjectId, section_id: `pbs_sec_${subjectId}`,
      status: "published", is_deleted: false,
    });
  }
  await db.collection("lecture_resources").doc("pbs_vidA").set({
    lecture_id: LEC_A, resource_type: "video", bunny_video_id: "pbs-vid-A",
    is_visible: true, display_order: 1,
  });
  await db.collection("lecture_progress").doc("pbs_progA").set({
    student_id: STUDENT, lecture_id: LEC_A, video_position_seconds: 123, is_completed: false,
  });
  for (const collection of ["playback_sessions", "subject_device_authorizations", "devices"]) {
    const key = collection === "devices" ? "user_id" : "student_id";
    const snap = await db.collection(collection).where(key, "==", STUDENT).get()
      .catch(() => ({docs: []}));
    for (const doc of snap.docs) await doc.ref.delete();
  }

  const beginPayload = (subjectId, deviceId, lectureId) =>
    ({studentId: STUDENT, subjectId, deviceId, lectureId, platform: "android"});
  async function sessionDoc(subjectId) {
    return db.collection("playback_sessions").doc(`${STUDENT}_${subjectId}`).get();
  }

  // 1. Device A starts -> A active, resumes persisted position.
  const s1 = await begin(beginPayload(SUB_A, "pbs-playback-device-A", LEC_A));
  assert.ok(s1.sessionToken && s1.sessionToken.length >= 32, "Opaque server token issued");
  assert.equal(s1.positionSeconds, 123, "Resume comes from persisted progress");
  assert.equal(s1.takeover, false);
  console.log("ok 1 - A starts, resumes persisted position");

  // 2. Device B starts -> B active, A superseded.
  const s2 = await begin(beginPayload(SUB_A, "pbs-playback-device-B", LEC_A));
  assert.equal(s2.takeover, true);
  assert.notEqual(s2.sessionToken, s1.sessionToken, "Takeover rotates the token");
  await expectCode(
    beat({studentId: STUDENT, subjectId: SUB_A, deviceId: "pbs-playback-device-A", sessionToken: s1.sessionToken}),
    "permission-denied", "superseded heartbeat",
  );
  console.log("ok 2 - B takes over, A heartbeat rejected");

  // 3. A starts again -> A active, B superseded (symmetric).
  const s3 = await begin(beginPayload(SUB_A, "pbs-playback-device-A", LEC_A));
  assert.equal(s3.takeover, true);
  await expectCode(
    beat({studentId: STUDENT, subjectId: SUB_A, deviceId: "pbs-playback-device-B", sessionToken: s2.sessionToken}),
    "permission-denied", "superseded heartbeat",
  );
  console.log("ok 3 - Symmetric takeover back to A");

  // 4. Simultaneous takeover -> exactly one live session, one valid token.
  const [r4a, r4b] = await Promise.all([
    begin(beginPayload(SUB_B, "pbs-playback-device-A", LEC_B)),
    begin(beginPayload(SUB_B, "pbs-playback-device-B", LEC_B)),
  ]);
  assert.notEqual(r4a.sessionToken, r4b.sessionToken, "Concurrent begins mint distinct tokens");
  const results4 = await Promise.allSettled([
    beat({studentId: STUDENT, subjectId: SUB_B, deviceId: "pbs-playback-device-A", sessionToken: r4a.sessionToken}),
    beat({studentId: STUDENT, subjectId: SUB_B, deviceId: "pbs-playback-device-B", sessionToken: r4b.sessionToken}),
  ]);
  assert.equal(
    results4.filter((r) => r.status === "fulfilled").length, 1,
    "Exactly one concurrent token stays live",
  );
  console.log("ok 4 - Simultaneous takeover yields one live session");

  // 5. Covered above (old-device heartbeat rejected after takeover).

  // 6. Active heartbeat accepted: lease extended, position advanced.
  const s6 = await begin(beginPayload(SUB_A, "pbs-playback-device-A", LEC_A));
  const before6 = (await sessionDoc(SUB_A)).data().lease_expires_at.toMillis();
  const h6 = await beat({studentId: STUDENT, subjectId: SUB_A, deviceId: "pbs-playback-device-A",
    sessionToken: s6.sessionToken, positionSeconds: 200});
  assert.equal(h6.positionSeconds, 200);
  assert.ok(h6.leaseExpiresAtMs >= before6, "Lease extended by heartbeat");
  console.log("ok 6 - Active heartbeat accepted with position update");

  // 7. Expired session cannot remain authoritative: force-expiry, then the
  // old token is rejected while a fresh begin succeeds.
  await db.collection("playback_sessions").doc(`${STUDENT}_${SUB_A}`).update({
    lease_expires_at: admin.firestore.Timestamp.fromMillis(Date.now() - 1000),
  });
  await expectCode(
    beat({studentId: STUDENT, subjectId: SUB_A, deviceId: "pbs-playback-device-A", sessionToken: s6.sessionToken}),
    "permission-denied", "stale heartbeat",
  );
  const s7 = await begin(beginPayload(SUB_A, "pbs-playback-device-A", LEC_A));
  assert.notEqual(s7.sessionToken, s6.sessionToken, "Expired session rotates token on re-begin");
  console.log("ok 7 - Stale session rejected, re-begin works");

  // 8. Two begins for the same device -> one session doc, same token.
  const s8a = await begin(beginPayload(SUB_A, "pbs-playback-device-A", LEC_A));
  const s8b = await begin(beginPayload(SUB_A, "pbs-playback-device-A", LEC_A));
  assert.equal(s8a.sessionToken, s8b.sessionToken, "Refresh keeps the token");
  console.log("ok 8 - Same-device begins converge on one session");

  // 9. Subject isolation: SUB_B session untouched by SUB_A activity.
  const liveTokenB = (await sessionDoc(SUB_B)).data().session_token;
  const winnerB = [r4a, r4b].find((r) => r.sessionToken === liveTokenB);
  assert.ok(winnerB, "Live token belongs to one of the racers");
  const winnerDeviceB = winnerB === r4a ? "pbs-playback-device-A" : "pbs-playback-device-B";
  const h9 = await beat({studentId: STUDENT, subjectId: SUB_B, deviceId: winnerDeviceB,
    sessionToken: winnerB.sessionToken});
  assert.ok(h9.positionSeconds >= 0, "Other Subject session still live");
  console.log("ok 9 - Subject sessions isolated");

  // 10. Guest device cannot begin: fill SUB_A slots (devA active) — devC
  // Guest after devB binds the second slot via tier path.
  await begin(beginPayload(SUB_A, "pbs-playback-device-B", LEC_A));
  await expectCode(
    begin(beginPayload(SUB_A, "pbs-playback-device-C", LEC_A)),
    "permission-denied", "guest begin",
  );
  assert.equal(
    (await db.collection("playback_sessions").where("student_id", "==", STUDENT).get()).size,
    2,
    "Denied begin creates no extra session docs",
  );
  console.log("ok 10 - Guest cannot start Full playback");

  // 11/13. Unknown subject / disabled assignment -> denied, no session.
  await expectCode(begin(beginPayload("pbs_nope", "pbs-playback-device-A", LEC_A)), "permission-denied", "unknown subject");
  await db.collection("subject_access_assignments").doc(`${STUDENT}_${SUB_A}`).update({enabled: false});
  await expectCode(begin(beginPayload(SUB_A, "pbs-playback-device-A", LEC_A)), "permission-denied", "disabled assignment");
  await db.collection("subject_access_assignments").doc(`${STUDENT}_${SUB_A}`).update({enabled: true});
  assert.ok(!(await db.collection("playback_sessions").doc(`${STUDENT}_pbs_nope`).get()).exists);
  console.log("ok 11/13 - Missing/disabled assignment denied without session");

  // 12. Inactive subscription -> denied.
  await db.collection("subscriptions").doc(`pbs_sub_${SUB_A}`).update({status: "expired"});
  await expectCode(begin(beginPayload(SUB_A, "pbs-playback-device-A", LEC_A)), "permission-denied", "expired subscription");
  await db.collection("subscriptions").doc(`pbs_sub_${SUB_A}`).update({status: "active"});
  console.log("ok 12 - Inactive subscription denied");

  // 14. Takeover returns the latest persisted progress.
  await db.collection("lecture_progress").doc("pbs_progA").update({video_position_seconds: 456});
  const s14 = await begin(beginPayload(SUB_A, "pbs-playback-device-B", LEC_A));
  assert.equal(s14.positionSeconds, 456, "Takeover resumes latest persisted position");
  console.log("ok 14 - Latest persisted progress returned");

  // 15. Reset invalidates the live session on next validation; rebinding works.
  await resetRaw({data: {studentId: STUDENT, reason: "pbs-test15"}, auth: doctorCtx});
  await expectCode(
    beat({studentId: STUDENT, subjectId: SUB_A, deviceId: "pbs-playback-device-B", sessionToken: s14.sessionToken}),
    "permission-denied", "post-reset heartbeat",
  );
  const s15 = await begin(beginPayload(SUB_A, "pbs-playback-device-B", LEC_A));
  assert.ok(s15.sessionToken, "Rebind after reset starts a fresh session");
  console.log("ok 15 - Reset invalidates session, rebind works");

  // 16. Revocation invalidates playback authority.
  await unbindRaw({data: {studentId: STUDENT, subjectId: SUB_A, deviceId: "pbs-playback-device-B"},
    auth: adminDevCtx});
  await expectCode(
    beat({studentId: STUDENT, subjectId: SUB_A, deviceId: "pbs-playback-device-B", sessionToken: s15.sessionToken}),
    "permission-denied", "post-revocation heartbeat",
  );
  console.log("ok 16 - Revocation invalidates playback authority");

  // 17/18. Forged token and forged device identity rejected.
  const s17 = await begin(beginPayload(SUB_A, "pbs-playback-device-A", LEC_A));
  await expectCode(
    beat({studentId: STUDENT, subjectId: SUB_A, deviceId: "pbs-playback-device-A", sessionToken: "deadbeef"}),
    "permission-denied", "forged token",
  );
  await expectCode(
    beat({studentId: STUDENT, subjectId: SUB_A, deviceId: "pbs-playback-device-B", sessionToken: s17.sessionToken}),
    "permission-denied", "foreign device with live token",
  );
  console.log("ok 17/18 - Forged token and device identity rejected");

  // 19/20. Issuance wiring: Full Max URL carries session fields; a second
  // device's issuance takes over and kills the first token.
  const v19 = await videoUrl({videoId: "pbs-vid-A", deviceId: "pbs-playback-device-A"});
  assert.ok(v19.sessionToken && typeof v19.positionSeconds === "number", "Issuance returns session state");
  const h19 = await beat({studentId: STUDENT, subjectId: SUB_A, deviceId: "pbs-playback-device-A",
    sessionToken: v19.sessionToken});
  assert.ok(h19.positionSeconds >= 0, "Issued token is live");
  const v20 = await videoUrl({videoId: "pbs-vid-A", deviceId: "pbs-playback-device-B"});
  assert.equal(v20.takeover, true, "Second issuance takes over");
  await expectCode(
    beat({studentId: STUDENT, subjectId: SUB_A, deviceId: "pbs-playback-device-A", sessionToken: v19.sessionToken}),
    "permission-denied", "first token dead after issuance takeover",
  );
  console.log("ok 19/20 - Issuance integrated with sessions");

  test.cleanup();
  console.log("playback_session.test: PASS - all 18 scenarios verified against Firestore Emulator");
}

run().catch((e) => {
  console.error("Test failed:", e);
  process.exit(1);
});
