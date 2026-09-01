import * as admin from "firebase-admin";

admin.initializeApp();
const db = admin.firestore();

async function backfillTotalLectures() {
  console.log("Starting backfill for total_lectures...");

  const subjectsSnap = await db.collection("subjects").get();
  console.log(`Found ${subjectsSnap.size} subjects. Processing...`);

  const batchSize = 100;
  let currentBatch = db.batch();
  let operationsCount = 0;

  async function commitBatch() {
    if (operationsCount > 0) {
      await currentBatch.commit();
      currentBatch = db.batch();
      operationsCount = 0;
    }
  }

  for (const subjectDoc of subjectsSnap.docs) {
    const subjectId = subjectDoc.id;

    // Count published lectures
    const lecturesSnap = await db.collection("lectures")
      .where("subject_id", "==", subjectId)
      .where("status", "==", "published")
      .get();

    // Also count legacy published lectures
    const legacySnap = await db.collection("lectures")
      .where("subject_id", "==", subjectId)
      .where("is_published", "==", true)
      .get();

    const uniqueLectures = new Set<string>();
    for (const doc of lecturesSnap.docs) uniqueLectures.add(doc.id);
    for (const doc of legacySnap.docs) uniqueLectures.add(doc.id);

    const publishedCount = uniqueLectures.size;

    console.log(`Subject ${subjectId}: found ${publishedCount} published lectures.`);

    // Update subject document
    currentBatch.update(subjectDoc.ref, {total_lectures: publishedCount});
    operationsCount++;
    if (operationsCount >= batchSize) await commitBatch();

    // Find and update all progress summaries for this subject
    const summariesSnap = await db.collection("subject_progress_summary")
      .where("subject_id", "==", subjectId)
      .get();

    for (const summaryDoc of summariesSnap.docs) {
      const data = summaryDoc.data();
      const currentCompleted = data.completed_lectures ?? 0;
      const totalLectures = publishedCount || 1; // avoid div by zero if 0
      const completionPercentage = Number(((currentCompleted / totalLectures) * 100).toFixed(2));

      currentBatch.update(summaryDoc.ref, {
        total_lectures: publishedCount,
        completion_percentage: completionPercentage,
      });
      operationsCount++;
      if (operationsCount >= batchSize) await commitBatch();
    }
  }

  await commitBatch();
  console.log("Backfill completed successfully!");
}

backfillTotalLectures().catch(console.error);
