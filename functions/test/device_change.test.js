/**
 * Device change request workflow tests (ADR-004 rescoped).
 *
 * Approval revokes the old device's Subject-device authorizations (any
 * Subject) so the replacement binds via first-access. Registry rows and the
 * Firebase Auth session are untouched; no re-login is required; no global
 * device pointer is written. Rejection resolves without touching anything.
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

const TEACHER = "tcf11_teacher";
const ADMIN_NODEV = "tcf11_admin_nodev";
const ADMIN_DEV = "tcf11_admin_dev";
const STUDENT = "tcf11_student";
const SUB_1 = "tcf11_sub1";
const SUB_2 = "tcf11_sub2";

const teacherCtx = {uid: TEACHER, token: {role: "teacher"}};
const adminNoDevCtx = {uid: ADMIN_NODEV, token: {role: "admin"}};
const adminDevCtx = {uid: ADMIN_DEV, token: {role: "admin"}};
const studentCtx = {uid: STUDENT, token: {role: "student"}};

async function expectCode(promise, code, label) {
  try {
    await promise;
  } catch (e) {
    assert.equal(
      e.code,
      code,
      `${label}: expected ${code}, got ${e.code} (${e.message})`,
    );
    return;
  }
  throw new Error(`${label}: expected rejection with ${code}, but succeeded`);
}

async function run() {
  console.log("Starting device_change tests against emulator...");
  const db = admin.firestore();
  const auth = admin.auth();

  try {
    await auth.deleteUser(STUDENT);
  } catch (_) {
    // Absent on a fresh emulator — safe to ignore.
  }
  await auth.createUser({uid: STUDENT});

  // Clean slate.
  for (const doc of (
    await db.collection("subject_device_authorizations").where("student_id", "==", STUDENT).get()
  ).docs) {
    await doc.ref.delete();
  }
  for (const doc of (
    await db.collection("devices").where("user_id", "==", STUDENT).get()
  ).docs) {
    await doc.ref.delete();
  }
  for (const doc of (
    await db.collection("device_change_requests").where("student_id", "==", STUDENT).get()
  ).docs) {
    await doc.ref.delete();
  }

  await db.collection("users").doc(STUDENT).set({
    role: "student",
    approval_status: "approved",
  });
  await db.collection("admin_permissions").doc(ADMIN_NODEV).set({
    is_active: true,
    permissions: {admin_students: true},
  });
  await db.collection("admin_permissions").doc(ADMIN_DEV).set({
    is_active: true,
    permissions: {admin_devices: true},
  });

  // Old device holds authorizations on two Subjects; registry row exists.
  // The authorization hash mirrors the server's namespaced hash of the
  // registry device identity (computed here only to seed fixtures).
  const {createHash} = require("node:crypto");
  const oldHash = createHash("sha256").update(`${STUDENT}|tcf11-old`).digest("hex");
  await db.collection("devices").doc("tcf11-old-doc").set({
    user_id: STUDENT,
    device_id: "tcf11-old",
  });
  const now = admin.firestore.FieldValue.serverTimestamp();
  await db.collection("subject_device_authorizations").doc("tcf11-auth-1").set({
    student_id: STUDENT, subject_id: SUB_1, device_hash: oldHash,
    status: "active", is_deleted: false, created_at: now, updated_at: now,
  });
  await db.collection("subject_device_authorizations").doc("tcf11-auth-2").set({
    student_id: STUDENT, subject_id: SUB_2, device_hash: oldHash,
    status: "active", is_deleted: false, created_at: now, updated_at: now,
  });

  const approveDeviceChangeRaw = test.wrap(functions.onDeviceChangeRequest);
  const approveDeviceChange = (payload, ctx) =>
    approveDeviceChangeRaw({...payload, auth: ctx});

  async function seedRequest(id, fields) {
    await db.collection("device_change_requests").doc(id).set({
      student_id: STUDENT,
      status: "pending",
      requested_at: admin.firestore.FieldValue.serverTimestamp(),
      ...fields,
    });
  }
  async function activeAuthzCount() {
    return (await db.collection("subject_device_authorizations")
      .where("student_id", "==", STUDENT).where("status", "==", "active").get()).size;
  }

  // 1. Teacher approval revokes the old device's authorizations everywhere.
  await seedRequest("tcf11-req1", {
    old_device_id: "tcf11-old-doc",
    new_device_id: "tcf11-new",
  });
  const res1 = await approveDeviceChange(
    {data: {requestId: "tcf11-req1", approve: true}},
    teacherCtx,
  );
  assert.equal(res1.approved, true);
  assert.equal(res1.revokedCount, 2, "Both Subject authorizations revoked");
  assert.equal(await activeAuthzCount(), 0);
  const revoked = await db.collection("subject_device_authorizations").doc("tcf11-auth-1").get();
  assert.equal(revoked.data().status, "revoked");
  assert.equal(revoked.data().revoke_reason, "device_change");
  assert.equal(revoked.data().revoked_by, TEACHER);
  const req1 = await db.collection("device_change_requests").doc("tcf11-req1").get();
  assert.equal(req1.data().status, "approved");
  assert.equal(req1.data().resolved_by, TEACHER);
  const audit1 = await db.collection("admin_audit_log").where("target_id", "==", "tcf11-req1").get();
  assert.equal(audit1.size, 1);
  assert.equal(audit1.docs[0].data().action, "device_change_approved");
  assert.equal(audit1.docs[0].data().permission_basis, "teacher");
  const analytics1 = await db.collection("analytics_events").where("reference_id", "==", "tcf11-req1").get();
  assert.ok(
    analytics1.docs.some((d) => d.data().event_type === "Device Replaced"),
    "Device Replaced analytics event must exist",
  );
  // Registry, session, and legacy pointers untouched.
  assert.ok((await db.collection("devices").doc("tcf11-old-doc").get()).exists, "Registry preserved");
  assert.equal((await auth.getUser(STUDENT)).uid, STUDENT, "Auth session intact");
  const studentAfter = await db.collection("users").doc(STUDENT).get();
  assert.ok(!("current_device_id" in studentAfter.data()), "No legacy pointer written");
  console.log("ok - Teacher approval revokes old-device authorizations + audits");

  // 2. Student caller is denied.
  await seedRequest("tcf11-req2", {old_device_id: "tcf11-old-doc", new_device_id: "tcf11-evil"});
  await expectCode(
    approveDeviceChange({data: {requestId: "tcf11-req2", approve: true}}, studentCtx),
    "permission-denied",
    "student approval",
  );
  console.log("ok - Student caller denied");

  // 3a. Admin WITHOUT admin_devices is denied (tightened per ADR-004).
  await expectCode(
    approveDeviceChange({data: {requestId: "tcf11-req2", approve: true}}, adminNoDevCtx),
    "permission-denied",
    "admin without admin_devices",
  );
  console.log("ok - Admin without admin_devices denied");

  // 3b. Delegated admin WITH admin_devices is allowed.
  const res3 = await approveDeviceChange(
    {data: {requestId: "tcf11-req2", approve: true}}, adminDevCtx,
  );
  assert.equal(res3.approved, true);
  const audit3 = await db.collection("admin_audit_log").where("target_id", "==", "tcf11-req2").get();
  assert.equal(audit3.docs[0].data().permission_basis, "delegated:admin_devices");
  console.log("ok - Delegated admin_devices approval allowed");

  // 4. Invalid requests: nonexistent, non-pending, incomplete.
  await expectCode(
    approveDeviceChange({data: {requestId: "tcf11-missing", approve: true}}, teacherCtx),
    "not-found",
    "nonexistent request",
  );
  await expectCode(
    approveDeviceChange({data: {requestId: "tcf11-req1", approve: true}}, teacherCtx),
    "failed-precondition",
    "already-approved request",
  );
  await seedRequest("tcf11-req5", {old_device_id: "tcf11-old-doc"});
  await expectCode(
    approveDeviceChange({data: {requestId: "tcf11-req5", approve: true}}, teacherCtx),
    "failed-precondition",
    "incomplete request",
  );
  console.log("ok - Invalid/nonexistent requests rejected");

  // 5. Reject path resolves without touching authorizations.
  await db.collection("subject_device_authorizations").doc("tcf11-auth-3").set({
    student_id: STUDENT, subject_id: SUB_1, device_hash: "hash-other",
    status: "active", is_deleted: false, created_at: now, updated_at: now,
  });
  await seedRequest("tcf11-req7", {old_device_id: "tcf11-old-doc", new_device_id: "tcf11-new3"});
  const res7 = await approveDeviceChange(
    {data: {requestId: "tcf11-req7", approve: false}}, teacherCtx,
  );
  assert.equal(res7.approved, false);
  const req7 = await db.collection("device_change_requests").doc("tcf11-req7").get();
  assert.equal(req7.data().status, "rejected");
  assert.equal(await activeAuthzCount(), 1, "Reject path revokes nothing");
  console.log("ok - Reject path resolves cleanly");

  test.cleanup();
  console.log("device_change.test: PASS - rescoped workflow verified against emulator");
}

run().catch((e) => {
  console.error("Test failed:", e);
  process.exit(1);
});
