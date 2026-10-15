/**
 * changeStudentGrade backend tests (grade-normalization guard fix).
 *
 * - A student whose stored grade is a non-canonical alias (registration
 *   stores the grade verbatim) must NOT be falsely rejected by the
 *   optimistic-concurrency guard: both sides of the comparison are
 *   normalized, so the change succeeds and the stored value converges
 *   to the canonical key.
 * - A genuine mid-flight grade change (two concurrent grade mutations)
 *   must still be rejected with failed-precondition + the "in flight"
 *   message, and the losing transaction must roll back.
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

const STUDENT = "cgrade_student";
const DOCTOR = "cgrade_doctor";
const SUB_OLD = "cgrade_old_subject";

const doctorCtx = {uid: DOCTOR, token: {role: "doctor"}};

async function run() {
  console.log("Starting change_student_grade tests against emulator...");
  const db = admin.firestore();
  const changeRaw = test.wrap(functions.changeStudentGrade);
  const change = (payload) => changeRaw({data: payload, auth: doctorCtx});

  // ---- Seed ----------------------------------------------------------
  await db.collection("users").doc(DOCTOR).set({role: "doctor"});
  await db.collection("users").doc(STUDENT).set({
    role: "student",
    approval_status: "approved",
    student_type: "center_student",
    grade: "grade_1", // Non-canonical alias, as registerNewStudent stores verbatim.
  });
  await db.collection("subjects").doc(SUB_OLD).set({
    title: "Old subject",
    grade: "Grade 1", // Alias spelling: read-side normalization must still match it.
    is_deleted: false,
  });
  await db.collection("subject_access_assignments").doc(`${STUDENT}_${SUB_OLD}`).set({
    student_id: STUDENT,
    subject_id: SUB_OLD,
    enabled: true,
    is_deleted: false,
  });

  // ---- 1. Alias stored grade: change must succeed, not falsely reject.
  const res = await change({studentId: STUDENT, grade: "grade_two"});
  assert.equal(res.success, true, "alias change succeeds");
  assert.equal(res.changed, true, "alias change reports changed");
  assert.equal(res.previousGrade, "grade_one", "previous grade normalizes to canonical");
  const afterAlias = await db.collection("users").doc(STUDENT).get();
  assert.equal(afterAlias.data().grade, "grade_two", "stored grade converges to canonical");
  const archived = await db
    .collection("subject_access_assignments")
    .doc(`${STUDENT}_${SUB_OLD}`)
    .get();
  assert.equal(archived.data().is_deleted, true, "old-grade assignment archived");
  assert.equal(archived.data().enabled, false, "old-grade assignment disabled");
  console.log("ok 1 - alias stored grade changes successfully (no false guard trip)");

  // ---- 2. No-op on identical grade.
  const noop = await change({studentId: STUDENT, grade: "grade_two"});
  assert.equal(noop.changed, false, "identical grade is a no-op");
  console.log("ok 2 - identical grade returns changed:false");

  // ---- 3. Genuine race: two concurrent grade mutations, one must lose
  // with the guard message; the loser rolls back (grade stays the winner's).
  await db.collection("users").doc(STUDENT).update({grade: "grade_one"});
  const attempts = await Promise.allSettled([
    change({studentId: STUDENT, grade: "grade_two"}),
    change({studentId: STUDENT, grade: "grade_three"}),
  ]);
  const fulfilled = attempts.filter((a) => a.status === "fulfilled");
  const rejected = attempts.filter((a) => a.status === "rejected");
  assert.equal(fulfilled.length, 1, "exactly one racer wins");
  assert.equal(rejected.length, 1, "exactly one racer loses");
  assert.equal(rejected[0].reason.code, "failed-precondition", "loser gets failed-precondition");
  assert.match(
    rejected[0].reason.message,
    /in flight/,
    "loser gets the guard message",
  );
  const finalSnap = await db.collection("users").doc(STUDENT).get();
  assert.ok(
    ["grade_two", "grade_three"].includes(finalSnap.data().grade),
    `final grade is the winner's (${finalSnap.data().grade})`,
  );
  console.log("ok 3 - genuine concurrent change rejected with guard message");

  // ---- 4. Audit + analytics trail for the winning change.
  const audits = await db
    .collection("admin_audit_log")
    .where("target_id", "==", STUDENT)
    .where("action", "==", "change_student_grade")
    .get();
  assert.ok(audits.size >= 2, `audit entries exist (found ${audits.size})`);
  const events = await db
    .collection("analytics_events")
    .where("user_id", "==", STUDENT)
    .where("event_type", "==", "Student Grade Changed")
    .get();
  assert.ok(events.size >= 2, `analytics entries exist (found ${events.size})`);
  console.log("ok 4 - audit and analytics trail recorded");

  console.log("All change_student_grade tests passed!");
}

run().catch((error) => {
  console.error("change_student_grade tests FAILED:", error);
  process.exit(1);
});
