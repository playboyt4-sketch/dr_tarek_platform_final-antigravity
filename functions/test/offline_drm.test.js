/**
 * Subject-partitioned offline DRM authorization tests (ADR-004 DRM step).
 *
 * `revalidateOfflineAccess` resolves per (student, subject, device):
 * Full devices keep offline authority (subject to the existing
 * offline.mode feature); Guest, revoked, expired, and disabled states
 * resolve to wipe — scoped to the affected Subject only.
 *
 * Runs inside `firebase emulators:exec` (firestore + auth).
 */
const test = require("firebase-functions-test")();
const assert = require("node:assert/strict");
const admin = require("firebase-admin");

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || "demo-test";

let functions;
try {
  functions = require("../lib/index.js");
} catch (error) {
  console.error("Failed to load functions:", error);
  process.exit(1);
}

const STUDENT = "drm_student";
const SUB_A = "drm_subA"; // Free (allowance 1)
const SUB_B = "drm_subB"; // Pro (allowance 1)
const SUB_C = "drm_subC"; // Max (allowance 2)
const DEV_A = "drm-test-device-A";
const DEV_B = "drm-test-device-B";
const DEV_C = "drm-test-device-C";

const studentCtx = {uid: STUDENT, token: {role: "student", approved: true}};
const doctorCtx = {uid: "drm_doctor", token: {role: "doctor"}};

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
  console.log("Starting offline_drm tests against emulator...");
  const db = admin.firestore();
  const auth = admin.auth();
  const revalRaw = test.wrap(functions.revalidateOfflineAccess);
  const reval = (deviceId, subjectIds) =>
    revalRaw({data: {deviceId, subjectIds}, auth: studentCtx});
  const resetRaw = test.wrap(functions.resetStudentDevices);
  const unbindRaw = test.wrap(functions.unbindSubjectDevice);

  try {
    await auth.deleteUser(STUDENT);
  } catch (_) {
    // Fresh emulator — safe to ignore.
  }
  await auth.createUser({uid: STUDENT});
  await db.collection("users").doc(STUDENT).set({
    role: "student", student_type: "center_student",
    approval_status: "approved", account_status: "active",
  });

  const plans = {free: "drm_plan_free", pro: "drm_plan_pro", max: "drm_plan_max"};
  await db.collection("plans").doc(plans.free).set({plan_key: "center_free", student_type: "center_student", is_active: true});
  await db.collection("plans").doc(plans.pro).set({plan_key: "center_pro", student_type: "center_student", is_active: true});
  await db.collection("plans").doc(plans.max).set({plan_key: "center_max", student_type: "center_student", is_active: true});
  for (const [planId, key, value] of [
    [plans.free, "device.max_count", 1], [plans.pro, "device.max_count", 1], [plans.max, "device.max_count", 2],
    [plans.free, "offline.mode", true], [plans.pro, "offline.mode", true], [plans.max, "offline.mode", true],
  ]) {
    await db.collection("plan_features").doc(`drm_feat_${planId}_${key}`).set({
      plan_id: planId, feature_key: key, feature_value: value, enabled: true,
    });
  }
  const subjectPlan = {[SUB_A]: plans.free, [SUB_B]: plans.pro, [SUB_C]: plans.max};
  for (const [subjectId, planId] of Object.entries(subjectPlan)) {
    await db.collection("subjects").doc(subjectId).set({title: subjectId});
    await db.collection("subject_access_assignments").doc(`${STUDENT}_${subjectId}`).set({
      student_id: STUDENT, subject_id: subjectId, enabled: true, is_deleted: false,
    });
    await db.collection("subscriptions").doc(`drm_sub_${subjectId}`).set({
      student_id: STUDENT, subject_id: subjectId, plan_id: planId, status: "active",
    });
  }
  for (const collection of ["subject_device_authorizations", "devices"]) {
    const key = collection === "devices" ? "user_id" : "student_id";
    const snap = await db.collection(collection).where(key, "==", STUDENT).get()
      .catch(() => ({docs: []}));
    for (const doc of snap.docs) await doc.ref.delete();
  }

  const resultFor = (res, subjectId) => res.results.find((r) => r.subjectId === subjectId);
  async function authzCount() {
    return (await db.collection("subject_device_authorizations")
      .where("student_id", "==", STUDENT).where("status", "==", "active").get()).size;
  }

  // Revalidation is read-only (it never claims slots), so bind the
  // Full devices first through the real first-access path — mirroring
  // production, where content access precedes offline sync.
  const tierRaw = test.wrap(functions.resolveSubjectTier);
  const bind = (subjectId, deviceId) =>
    tierRaw({data: {studentId: STUDENT, subjectId, deviceId}, auth: studentCtx});
  await bind(SUB_A, DEV_A);
  await bind(SUB_B, DEV_A);
  await bind(SUB_C, DEV_A);
  await bind(SUB_C, DEV_B);

  // 1. Full authorized Free device keeps offline authority.
  let res = await reval(DEV_A, [SUB_A]);
  assert.equal(resultFor(res, SUB_A).allowed, true);
  assert.equal(resultFor(res, SUB_A).wipeRequired, false);
  console.log("ok 1 - Full Free keeps offline authority");

  // 2. Guest cannot obtain offline authority (wipe, no fallback key).
  res = await reval(DEV_B, [SUB_A]);
  assert.equal(resultFor(res, SUB_A).allowed, false);
  assert.equal(resultFor(res, SUB_A).wipeRequired, true);
  assert.equal(resultFor(res, SUB_A).reason, "guest_tier");
  console.log("ok 2 - Guest resolves to wipe");

  // 3. Full Pro keeps offline authority.
  res = await reval(DEV_A, [SUB_B]);
  assert.equal(resultFor(res, SUB_B).allowed, true);
  console.log("ok 3 - Full Pro keeps offline authority");

  // 4/5. Max devices 1+2 keep offline authority.
  res = await reval(DEV_A, [SUB_C]);
  assert.equal(resultFor(res, SUB_C).allowed, true);
  res = await reval(DEV_B, [SUB_C]);
  assert.equal(resultFor(res, SUB_C).allowed, true);
  console.log("ok 4/5 - Max devices 1 and 2 keep offline authority");

  // 6. Max third device wipes.
  res = await reval(DEV_C, [SUB_C]);
  assert.equal(resultFor(res, SUB_C).allowed, false);
  assert.equal(resultFor(res, SUB_C).wipeRequired, true);
  console.log("ok 6 - Max third device wipes");

  // 7/8. Cross-Subject isolation: DEV_B is Full on C but Guest on A.
  res = await reval(DEV_B, [SUB_A, SUB_C]);
  assert.equal(resultFor(res, SUB_A).allowed, false, "Guest on A");
  assert.equal(resultFor(res, SUB_C).allowed, true, "Full on C unaffected");
  console.log("ok 7/8 - Cross-Subject isolation holds");

  // 9/10. Subject A expiry blocks A only; B unaffected.
  await db.collection("subscriptions").doc(`drm_sub_${SUB_A}`).update({status: "expired"});
  res = await reval(DEV_A, [SUB_A, SUB_B]);
  assert.equal(resultFor(res, SUB_A).allowed, false);
  assert.equal(resultFor(res, SUB_A).wipeRequired, true);
  assert.equal(resultFor(res, SUB_B).allowed, true, "B unaffected by A expiry");
  await db.collection("subscriptions").doc(`drm_sub_${SUB_A}`).update({status: "active"});
  console.log("ok 9/10 - Expiry scoped to its Subject");

  // 11/12. Per-Subject revoke blocks that Subject only.
  await unbindRaw({data: {studentId: STUDENT, subjectId: SUB_A, deviceId: DEV_A},
    auth: doctorCtx});
  res = await reval(DEV_A, [SUB_A, SUB_B]);
  assert.equal(resultFor(res, SUB_A).allowed, false, "Revoked device wipes on A");
  assert.equal(resultFor(res, SUB_B).allowed, true, "B unaffected by A revoke");
  console.log("ok 11/12 - Revoke scoped to its Subject");

  // 13/14. Global reset invalidates authority; authentication intact.
  await resetRaw({data: {studentId: STUDENT, reason: "drm-test13"}, auth: doctorCtx});
  res = await reval(DEV_A, [SUB_A, SUB_B, SUB_C]);
  assert.ok(res.results.every((r) => r.allowed === false && r.wipeRequired === true),
    "All Subjects wipe after reset");
  assert.equal((await auth.getUser(STUDENT)).uid, STUDENT, "Auth session intact");
  console.log("ok 13/14 - Reset invalidates authority, session intact");

  // 15. No Full fallback: Guest responses carry no keys or artifacts.
  res = await reval(DEV_B, [SUB_C]);
  const guest = resultFor(res, SUB_C);
  assert.equal(guest.allowed, false);
  assert.ok(!("url" in guest) && !("key" in guest) && !("license" in guest),
    "Guest response carries no key material");
  console.log("ok 15 - Guest never receives fallback material");

  // 16/17/18. Forged client tier/plan/device-authorization ignored.
  const forged = await revalRaw({data: {deviceId: DEV_B, subjectIds: [SUB_A],
    tier: "full", plan_id: plans.max, max_devices: 99,
    subscription_status: "active", authorized: true}, auth: studentCtx});
  assert.equal(resultFor(forged, SUB_A).allowed, false, "Forged flags cannot mint authority");
  console.log("ok 16/17/18 - Forged client claims ignored");

  // 19. Lecture deny layering: an explicit grant-deny does not change
  // revalidate (deny is enforced at content issuance, already covered).
  // Rebind DEV_A on SUB_A first (reset in test 13 cleared all slots).
  await bind(SUB_A, DEV_A);
  await db.collection("lecture_access_grants").doc(`drm-lec1_${STUDENT}`).set({
    lecture_id: "drm-lec1", student_id: STUDENT, allowed: false, is_deleted: false,
  });
  res = await reval(DEV_A, [SUB_A]);
  assert.equal(resultFor(res, SUB_A).allowed, true, "Deny lives at issuance, not revalidation");
  const grant = await db.collection("lecture_access_grants").doc(`drm-lec1_${STUDENT}`).get();
  assert.equal(grant.data().allowed, false, "Grant untouched");
  console.log("ok 19 - Lecture-deny layering preserved");

  // 20/21. Results are partitioned per Subject in one call.
  res = await reval(DEV_A, [SUB_A, SUB_B, SUB_C]);
  assert.equal(res.results.length, 3);
  assert.deepEqual(
    res.results.map((r) => r.subjectId).sort(), [SUB_A, SUB_B, SUB_C].sort(),
  );
  console.log("ok 20/21 - Per-Subject partitioned results");

  // 22. Offline revalidation never creates authorizations.
  const countBefore = await authzCount();
  await reval(DEV_C, [SUB_A, SUB_B, SUB_C]);
  assert.equal(await authzCount(), countBefore, "Revalidation binds nothing");
  console.log("ok 22 - Revalidation creates no authorization");

  // 23/24. No global binding recreated; no second subscription source.
  const regRows = (await db.collection("devices").where("user_id", "==", STUDENT).get()).docs;
  assert.ok(regRows.every((d) => !("active_device" in d.data())), "No authorization flags in registry");
  const subsBefore = (await db.collection("subscriptions").where("student_id", "==", STUDENT).get())
    .docs.map((d) => ({id: d.id, ...d.data()}));
  await reval(DEV_A, [SUB_A]);
  const subsAfter = (await db.collection("subscriptions").where("student_id", "==", STUDENT).get())
    .docs.map((d) => ({id: d.id, ...d.data()}));
  assert.deepEqual(subsAfter, subsBefore, "Subscriptions untouched");
  console.log("ok 23/24 - No global binding, no second subscription source");

  // Fail-closed: missing deviceId.
  await expectCode(revalRaw({data: {subjectIds: [SUB_A]}, auth: studentCtx}),
    "invalid-argument", "missing deviceId");

  test.cleanup();
  console.log("offline_drm.test: PASS - Subject-partitioned offline authority verified");
}

run().catch((e) => {
  console.error("Test failed:", e);
  process.exit(1);
});
