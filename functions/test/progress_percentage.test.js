const admin = require("firebase-admin");

process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = 'demo-tarek-platform';

// Initialize admin app if not already initialized
if (admin.apps.length === 0) {
  admin.initializeApp({ projectId: "demo-tarek-platform" });
}

async function run() {
    console.log("Starting progress_percentage tests against emulator...");
    const db = admin.firestore();
    const studentId = "student_progress_1";
    const subjectId = "subject_prog_1";
    const sectionId = "section_prog_1";
    const lectureId = "lec_prog_1";
    const progressId = "prog_1";

    // Setup real Firestore data
    await db.collection("subject_sections").doc(sectionId).set({
        subject_id: subjectId,
        title: "Section 1"
    });

    // We create 50 lectures to test Scenario 1
    const batch = db.batch();
    for (let i = 1; i <= 50; i++) {
        // Production lectures always carry the owning subject and a status;
        // `calculateAndSetSubjectProgress` counts only `status == "published"`
        // rows (and resolves the subject through the section). The fixture
        // omitted both, so the trigger correctly counted 0 published lectures.
        batch.set(db.collection("lectures").doc(`lec_prog_${i}`), {
            section_id: sectionId,
            subject_id: subjectId,
            title: `Lecture ${i}`,
            status: "published",
            is_deleted: false
        });
    }
    await batch.commit();

    // Create the document first as false, then update to true to trigger onDocumentUpdated
    await db.collection("lecture_progress").doc(progressId).set({
        student_id: studentId,
        lecture_id: lectureId,
        is_completed: false
    });

    console.log("Updating lecture_progress to trigger function...");
    await db.collection("lecture_progress").doc(progressId).update({
        is_completed: true
    });

    console.log("Waiting for background trigger to finish (up to 120s)...");
    // 120s matches the documented trigger-readiness budget in
    // `test/wait_for_triggers.js`: `emulators:exec` starts this script before
    // Cloud Functions triggers finish registering, and a cold trigger delivery
    // was measured at ~22s. The previous 15s window failed on delivery latency,
    // not on the aggregation (the computed summary is 50/1/2 once delivered).
    // Assertions below are unchanged.
    let summaryDoc;
    for (let i = 0; i < 120; i++) {
        await new Promise(resolve => setTimeout(resolve, 1000));
        summaryDoc = await db.collection("subject_progress_summary").doc(`${studentId}_${subjectId}`).get();
        if (summaryDoc.exists) break;
    }
    
    if (!summaryDoc.exists) {
        throw new Error("Summary doc should be created");
    }
    
    const data = summaryDoc.data();
    if (data.total_lectures !== 50) throw new Error(`Expected 50 total_lectures, got ${data.total_lectures}`);
    if (data.completed_lectures !== 1) throw new Error(`Expected 1 completed_lectures, got ${data.completed_lectures}`);
    if (data.completion_percentage !== 2) throw new Error(`Expected 2 completion_percentage, got ${data.completion_percentage}`);

    console.log("progress_percentage.test: PASS - completion_percentage verified against Firestore Emulator");
}

run().catch(e => {
    console.error("Test failed:", e);
    process.exit(1);
});
