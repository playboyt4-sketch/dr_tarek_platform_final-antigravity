/**
 * Subject-Level Device Authorization backend tests (ADR-004).
 *
 * Covers first-access transactional binding, Guest tier resolution,
 * per-Subject isolation, deny composition, concurrency, reset/unbind,
 * and registry independence — all against the Firestore emulator.
 *
 * Runs inside `firebase emulators:exec` (firestore + functions + auth).
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

const STUDENT = "sauth_student";
const TEACHER = "sauth_teacher";
const ADMIN_DEV = "sauth_admin_dev";
const ADMIN_NODEV = "sauth_admin_nodev";

const SUB_A = "sauth_subA"; // Free (allowance 1)
const SUB_B = "sauth_subB"; // Pro (allowance 1)
const SUB_C = "sauth_subC"; // Max (allowance 2)
const SUB_D = "sauth_subD"; // Free, used for race test
const SUB_E = "sauth_subE"; // Max, used for last-slot race test

const studentCtx = {uid: STUDENT, token: {role: "student", approved: true}};
const teacherCtx = {uid: TEACHER, token: {role: "teacher"}};
const adminDevCtx = {uid: ADMIN_DEV, token: {role: "admin"}};
const adminNoDevCtx = {uid: ADMIN_NODEV, token: {role: "admin"}};

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
  console.log("Starting subject_authorization tests against emulator...");
  const db = admin.firestore();
  const auth = admin.auth();
  const resolveTierRaw = test.wrap(functions.resolveSubjectTier);
  const resolve = (payload, ctx) => resolveTierRaw({...payload, auth: ctx || studentCtx});
  const resetRaw = test.wrap(functions.resetStudentDevices);
  const reset = (payload, ctx) => resetRaw({...payload, auth: ctx});
  const unbindRaw = test.wrap(functions.unbindSubjectDevice);
  const unbind = (payload, ctx) => unbindRaw({...payload, auth: ctx});
  const loginRaw = test.wrap(functions.onLoginAttempt);
  const login = (payload, ctx) => loginRaw({...payload, auth: ctx});

  // ---- Seed identity -------------------------------------------------
  try {
    await auth.deleteUser(STUDENT);
  } catch (_) {
    // Fresh emulator — safe to ignore.
  }
  await auth.createUser({uid: STUDENT});
  await db.collection("users").doc(STUDENT).set({
    role: "student",
    student_type: "center_student",
    approval_status: "approved",
    account_status: "active",
  });
  await db.collection("users").doc(TEACHER).set({role: "teacher"});
  await db.collection("admin_permissions").doc(ADMIN_DEV).set({
    is_active: true,
    permissions: {admin_devices: true},
  });
  await db.collection("admin_permissions").doc(ADMIN_NODEV).set({
    is_active: true,
    permissions: {admin_students: true},
  });

  // ---- Seed plans + allowances ---------------------------------------
  const plans = {free: "sauth_plan_free", pro: "sauth_plan_pro", max: "sauth_plan_max"};
  await db.collection("plans").doc(plans.free).set({plan_key: "center_free", student_type: "center_student", is_active: true});
  await db.collection("plans").doc(plans.pro).set({plan_key: "center_pro", student_type: "center_student", is_active: true});
  await db.collection("plans").doc(plans.max).set({plan_key: "center_max", student_type: "center_student", is_active: true});
  await db.collection("plan_features").doc("sauth_feat_free").set({plan_id: plans.free, feature_key: "device.max_count", feature_value: 1, enabled: true});
  await db.collection("plan_features").doc("sauth_feat_pro").set({plan_id: plans.pro, feature_key: "device.max_count", feature_value: 1, enabled: true});
  await db.collection("plan_features").doc("sauth_feat_max").set({plan_id: plans.max, feature_key: "device.max_count", feature_value: 2, enabled: true});

  // ---- Seed subjects, assignments, subscriptions ----------------------
  const subjectPlan = {[SUB_A]: plans.free, [SUB_B]: plans.pro, [SUB_C]: plans.max, [SUB_D]: plans.free, [SUB_E]: plans.max};
  for (const [subjectId, planId] of Object.entries(subjectPlan)) {
    await db.collection("subjects").doc(subjectId).set({title: subjectId});
    await db.collection("subject_access_assignments").doc(`${STUDENT}_${subjectId}`).set({
      student_id: STUDENT,
      subject_id: subjectId,
      enabled: true,
      is_deleted: false,
    });
    await db.collection("subscriptions").doc(`sauth_sub_${subjectId}`).set({
      student_id: STUDENT,
      subject_id: subjectId,
      plan_id: planId,
      status: "active",
    });
  }

  // Clean slate for authorization + registry collections.
  for (const collection of ["subject_device_authorizations", "devices", "analytics_events", "admin_audit_log", "notifications"]) {
    const snap = await db.collection(collection).where(
      collection === "devices" || collection === "analytics_events" ? "user_id" : "student_id",
      "==", STUDENT,
    ).get().catch(() => ({docs: []}));
    for (const doc of snap.docs) await doc.ref.delete();
  }

  const tier = (studentId, subjectId, deviceId) =>
    resolve({data: {studentId, subjectId, deviceId, platform: "android"}});
  async function authzCount(subjectId, onlyActive = true) {
    let query = db.collection("subject_device_authorizations")
      .where("student_id", "==", STUDENT)
      .where("subject_id", "==", subjectId);
    if (onlyActive) query = query.where("status", "==", "active");
    return (await query.get()).size;
  }
  // 1. Free first device -> Full.
  const r1 = await tier(STUDENT, SUB_A, "sauth-dev1");
  assert.equal(r1.tier, "full");
  assert.equal(r1.allowance, 1);
  assert.ok(r1.authorizationId, "Full must return an authorization id");
  console.log("ok 1 - Free first device Full");

  // 2. Free second device -> Guest, no record.
  const before2 = await authzCount(SUB_A, false);
  const r2 = await tier(STUDENT, SUB_A, "sauth-dev2");
  assert.equal(r2.tier, "guest");
  assert.equal(r2.authorizationId, null);
  assert.equal(await authzCount(SUB_A, false), before2, "Guest must not create a record");
  console.log("ok 2 - Free second device Guest, no record");

  // 3/4. Pro first -> Full; second -> Guest.
  assert.equal((await tier(STUDENT, SUB_B, "sauth-dev1")).tier, "full");
  assert.equal((await tier(STUDENT, SUB_B, "sauth-dev2")).tier, "guest");
  console.log("ok 3/4 - Pro first Full, second Guest");

  // 5/6/7. Max first + second -> Full; third -> Guest.
  assert.equal((await tier(STUDENT, SUB_C, "sauth-dev1")).tier, "full");
  assert.equal((await tier(STUDENT, SUB_C, "sauth-dev2")).tier, "full");
  const r7 = await tier(STUDENT, SUB_C, "sauth-dev3");
  assert.equal(r7.tier, "guest");
  assert.equal(r7.allowance, 2);
  assert.equal(await authzCount(SUB_C), 2);
  console.log("ok 5/6/7 - Max two Full, third Guest");

  // 8. Repeat access stays Full without duplicates.
  const before8 = await authzCount(SUB_A);
  assert.equal((await tier(STUDENT, SUB_A, "sauth-dev1")).tier, "full");
  assert.equal(await authzCount(SUB_A), before8);
  console.log("ok 8 - Repeat access idempotent");

  // 9. No cross-Subject leakage: A and B authorizations are distinct
  // records, and Guest activity on one Subject writes nothing anywhere.
  const aIds = (await db.collection("subject_device_authorizations")
    .where("student_id", "==", STUDENT).where("subject_id", "==", SUB_A).get()).docs.map((d) => d.id);
  const bIds = (await db.collection("subject_device_authorizations")
    .where("student_id", "==", STUDENT).where("subject_id", "==", SUB_B).get()).docs.map((d) => d.id);
  assert.ok(aIds.length > 0 && bIds.length > 0, "Precondition: both Subjects hold authorizations");
  assert.ok(!aIds.some((id) => bIds.includes(id)), "Authorization records are Subject-scoped");
  const bBefore = await authzCount(SUB_B, false);
  const aBefore = await authzCount(SUB_A, false);
  // B slots are full (dev1 bound), so dev9 is Guest there.
  assert.equal((await tier(STUDENT, SUB_B, "sauth-dev9")).tier, "guest");
  assert.equal(await authzCount(SUB_A, false), aBefore, "B activity created nothing for A");
  assert.equal(await authzCount(SUB_B, false), bBefore, "Guest created nothing for B");
  console.log("ok 9 - No cross-Subject authorization leakage");

  // 10. Highest plan does not uplift: dev3 on Free subject A stays Guest
  // despite Max on C.
  assert.equal((await tier(STUDENT, SUB_A, "sauth-dev3")).tier, "guest");
  console.log("ok 10 - Max on C does not uplift A");

  // 11. Disabled assignment -> deny, no binding.
  await db.collection("subject_access_assignments").doc(`${STUDENT}_${SUB_B}`).update({enabled: false});
  const bCountBefore = await authzCount(SUB_B, false);
  await expectCode(tier(STUDENT, SUB_B, "sauth-dev-fresh"), "permission-denied", "disabled assignment");
  assert.equal(await authzCount(SUB_B, false), bCountBefore);
  await db.collection("subject_access_assignments").doc(`${STUDENT}_${SUB_B}`).update({enabled: true});
  console.log("ok 11 - Disabled assignment denies without binding");

  // 12. Inactive subscription -> deny, no binding.
  await db.collection("subscriptions").doc(`sauth_sub_${SUB_B}`).update({status: "expired"});
  await expectCode(tier(STUDENT, SUB_B, "sauth-dev-fresh"), "permission-denied", "expired subscription");
  await db.collection("subscriptions").doc(`sauth_sub_${SUB_B}`).update({status: "active"});
  console.log("ok 12 - Inactive subscription denies without binding");

  // 13. Explicit lecture deny is untouched by tier resolution.
  await db.collection("lecture_access_grants").doc(`sauth-lec1_${STUDENT}`).set({
    lecture_id: "sauth-lec1",
    student_id: STUDENT,
    allowed: false,
    is_deleted: false,
  });
  const r13 = await tier(STUDENT, SUB_A, "sauth-dev1");
  assert.equal(r13.tier, "full");
  const grantAfter = await db.collection("lecture_access_grants").doc(`sauth-lec1_${STUDENT}`).get();
  assert.equal(grantAfter.data().allowed, false, "Tier resolution must not alter explicit deny");
  console.log("ok 13 - Explicit deny preserved");

  // 14. Simultaneous Free first-access -> exactly one authorization.
  const [r14a, r14b] = await Promise.all([
    tier(STUDENT, SUB_D, "sauth-race1"),
    tier(STUDENT, SUB_D, "sauth-race2"),
  ]);
  const fulls14 = [r14a, r14b].filter((r) => r.tier === "full").length;
  assert.equal(fulls14, 1, "Exactly one racer wins the Free slot");
  assert.equal(await authzCount(SUB_D), 1);
  console.log("ok 14 - Free race yields exactly one authorization");

  // 15. Simultaneous Max last-slot race -> exactly one wins.
  await tier(STUDENT, SUB_E, "sauth-max1");
  const [r15a, r15b] = await Promise.all([
    tier(STUDENT, SUB_E, "sauth-max2"),
    tier(STUDENT, SUB_E, "sauth-max3"),
  ]);
  assert.equal([r15a, r15b].filter((r) => r.tier === "full").length, 1);
  assert.equal(await authzCount(SUB_E), 2);
  console.log("ok 15 - Max last-slot race yields exactly one winner");

  // 16. Guest creates no record (explicit total check).
  const totalBefore = (await db.collection("subject_device_authorizations")
    .where("student_id", "==", STUDENT).get()).size;
  await tier(STUDENT, SUB_C, "sauth-dev3");
  await tier(STUDENT, SUB_A, "sauth-dev2");
  assert.equal(
    (await db.collection("subject_device_authorizations").where("student_id", "==", STUDENT).get()).size,
    totalBefore,
    "Guest resolutions must not write records",
  );
  console.log("ok 16 - Guest writes nothing");

  // 17. Global reset revokes every active authorization.
  const activeBefore = (await db.collection("subject_device_authorizations")
    .where("student_id", "==", STUDENT).where("status", "==", "active").get()).size;
  assert.ok(activeBefore > 0, "Precondition: active authorizations exist");
  const resetRes = await reset({data: {studentId: STUDENT, reason: "test-reset"}}, teacherCtx);
  assert.equal(resetRes.revokedCount, activeBefore);
  assert.equal(
    (await db.collection("subject_device_authorizations")
      .where("student_id", "==", STUDENT).where("status", "==", "active").get()).size,
    0,
  );
  const revokedSample = await db.collection("subject_device_authorizations")
    .where("student_id", "==", STUDENT).where("status", "==", "revoked").limit(1).get();
  assert.equal(revokedSample.docs[0].data().revoke_reason, "reset");
  assert.equal(revokedSample.docs[0].data().revoked_by, TEACHER);
  const resetAudit = await db.collection("admin_audit_log")
    .where("target_id", "==", STUDENT).get();
  assert.ok(resetAudit.docs.some((d) => d.data().action === "subject_device_reset"), "Reset audit required");
  console.log("ok 17 - Global reset revokes all with audit");

  // 18. Per-Subject unbind affects only that Subject.
  await tier(STUDENT, SUB_A, "sauth-dev1");
  await tier(STUDENT, SUB_B, "sauth-dev1");
  const unRes = await unbind(
    {data: {studentId: STUDENT, subjectId: SUB_A, deviceId: "sauth-dev1", reason: "test-unbind"}},
    teacherCtx,
  );
  assert.equal(unRes.revoked, true);
  assert.equal(await authzCount(SUB_A), 0);
  assert.equal(await authzCount(SUB_B), 1, "Other Subject untouched");
  await expectCode(
    unbind({data: {studentId: STUDENT, subjectId: SUB_A, deviceId: "sauth-dev1"}}, teacherCtx),
    "not-found",
    "double unbind",
  );
  // Delegated admin_devices may unbind; admin without it may not.
  await expectCode(
    unbind({data: {studentId: STUDENT, subjectId: SUB_B, deviceId: "sauth-dev1"}}, adminNoDevCtx),
    "permission-denied",
    "admin without admin_devices",
  );
  const unRes2 = await unbind(
    {data: {studentId: STUDENT, subjectId: SUB_B, deviceId: "sauth-dev1"}}, adminDevCtx,
  );
  assert.equal(unRes2.revoked, true);
  console.log("ok 18 - Per-Subject unbind isolated + permission-gated");

  // 19. Reset does not log the student out: auth user intact, registry
  // intact, users doc untouched by authorization, rebinding works.
  await tier(STUDENT, SUB_A, "sauth-dev1");
  await reset({data: {studentId: STUDENT}}, teacherCtx);
  const stillUser = await auth.getUser(STUDENT);
  assert.equal(stillUser.uid, STUDENT, "Auth session identity intact after reset");
  const usersDoc = await db.collection("users").doc(STUDENT).get();
  assert.ok(!("current_device_id" in usersDoc.data()), "Reset writes no legacy device pointer");
  assert.equal((await tier(STUDENT, SUB_A, "sauth-dev1")).tier, "full", "Rebinding from scratch works");
  console.log("ok 19 - Reset preserves session, allows rebinding");

  // 20. Registry independent from authorization.
  const regSnap = await db.collection("devices").where("user_id", "==", STUDENT).get();
  assert.ok(regSnap.size > 0, "Registry rows exist");
  assert.ok(regSnap.docs.every((d) => !("active_device" in d.data())), "Registry carries no authorization flag");
  await login({data: {userId: STUDENT, deviceId: "sauth-brand-new", platform: "web"}}, studentCtx);
  const freshReg = await db.collection("devices")
    .where("user_id", "==", STUDENT).where("device_id", "==", "sauth-brand-new").get();
  assert.equal(freshReg.size, 1, "Unknown device auto-registers on tier path/login");
  assert.equal(
    (await db.collection("subject_device_authorizations")
      .where("student_id", "==", STUDENT).where("status", "==", "active").get()).size,
    1,
    "Registration alone authorizes nothing (only the SUB_A rebind from step 19)",
  );
  console.log("ok 20 - Registry independent from authorization");

  test.cleanup();
  console.log("subject_authorization.test: PASS - all 20 scenarios verified against Firestore Emulator");
}

run().catch((e) => {
  console.error("Test failed:", e);
  process.exit(1);
});
