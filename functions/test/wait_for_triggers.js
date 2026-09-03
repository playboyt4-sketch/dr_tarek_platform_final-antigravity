/**
 * Readiness gate for emulator-backed suites.
 *
 * `firebase emulators:exec` starts the test command as soon as the emulator
 * HUB is up, but Cloud Functions triggers (e.g. recalculateSubjectProgress)
 * may still be deploying. A test that writes before its trigger is
 * registered loses the event permanently, so suites must not start writing
 * until trigger delivery is proven end-to-end.
 *
 * This probe writes a minimal canary chain (section -> lecture ->
 * lecture_progress false->true) and polls for the summary doc that ONLY the
 * real recalculateSubjectProgress trigger can create. It never fabricates
 * the summary itself. Canary docs are deleted before exit so suites observe
 * a clean database.
 *
 * Exit 0 when delivery is proven, exit 1 on timeout.
 */
const admin = require("firebase-admin");

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
const projectId = process.env.GCLOUD_PROJECT || "demo-tarek-platform";
process.env.GCLOUD_PROJECT = projectId;

if (admin.apps.length === 0) {
  admin.initializeApp({projectId});
}

const PROBE = "__trigger_probe__";
const TIMEOUT_MS = 120000;
const POLL_MS = 1000;

async function run() {
  const db = admin.firestore();
  const sectionId = `${PROBE}_section`;
  const lectureId = `${PROBE}_lecture`;
  const progressId = `${PROBE}_progress`;
  const studentId = `${PROBE}_student`;
  const subjectId = `${PROBE}_subject`;
  const summaryId = `${studentId}_${subjectId}`;

  await db.collection("subject_sections").doc(sectionId).set({
    subject_id: subjectId,
    title: "Trigger readiness probe",
  });
  await db.collection("lectures").doc(lectureId).set({
    section_id: sectionId,
    title: "Trigger readiness probe",
  });
  await db.collection("lecture_progress").doc(progressId).set({
    student_id: studentId,
    lecture_id: lectureId,
    is_completed: false,
  });
  await db.collection("lecture_progress").doc(progressId).update({
    is_completed: true,
  });

  const deadline = Date.now() + TIMEOUT_MS;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const snap = await db
      .collection("subject_progress_summary")
      .doc(summaryId)
      .get();
    if (snap.exists) break;
    if (Date.now() > deadline) {
      throw new Error(
        "Trigger readiness probe timed out: recalculateSubjectProgress " +
          "did not deliver within 120s. Functions emulator triggers are " +
          "not ready.",
      );
    }
    await new Promise((resolve) => setTimeout(resolve, POLL_MS));
  }

  // Leave a clean database for the real suites.
  await db.collection("lecture_progress").doc(progressId).delete();
  await db.collection("lectures").doc(lectureId).delete();
  await db.collection("subject_sections").doc(sectionId).delete();
  await db.collection("subject_progress_summary").doc(summaryId).delete();

  console.log(
    "wait_for_triggers: PASS - recalculateSubjectProgress delivery proven.",
  );
}

run().catch((e) => {
  console.error("wait_for_triggers failed:", e);
  process.exit(1);
});
