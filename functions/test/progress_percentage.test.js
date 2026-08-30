const test = require("firebase-functions-test")();
const assert = require("node:assert/strict");
const admin = require("firebase-admin");

let functions;
try {
  functions = require("../lib/index.js");
} catch (error) {
  console.error("Failed to load functions:", error);
  process.exit(1);
}

const wrapped = test.wrap(functions.recalculateSubjectProgress);

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
        batch.set(db.collection("lectures").doc(`lec_prog_${i}`), {
            section_id: sectionId,
            title: `Lecture ${i}`
        });
    }
    await batch.commit();

    const beforeSnap = test.firestore.makeDocumentSnapshot({
        student_id: studentId,
        lecture_id: lectureId,
        is_completed: false
    }, `lecture_progress/${progressId}`);

    const afterSnap = test.firestore.makeDocumentSnapshot({
        student_id: studentId,
        lecture_id: lectureId,
        is_completed: true
    }, `lecture_progress/${progressId}`);

    const change = test.makeChange(beforeSnap, afterSnap);

    // Run the trigger
    await wrapped(change, { params: { progressId } });

    // Verify the summary was updated
    const summaryDoc = await db.collection("subject_progress_summary").doc(`${studentId}_${subjectId}`).get();
    assert.ok(summaryDoc.exists, "Summary doc should be created");
    
    const data = summaryDoc.data();
    assert.strictEqual(data.total_lectures, 50, "Total lectures should be 50");
    assert.strictEqual(data.completed_lectures, 1, "Completed lectures should be 1");
    assert.strictEqual(data.completion_percentage, 2, "Percentage should be 2");

    test.cleanup();
    console.log("progress_percentage.test: PASS - completion_percentage verified against Firestore Emulator");
}

run().catch(e => {
    console.error("Test failed:", e);
    process.exit(1);
});
