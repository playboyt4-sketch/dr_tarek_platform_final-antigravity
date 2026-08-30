const admin = require('firebase-admin');

// Ensure this matches emulator env
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = 'demo-test'; // For the index.js initializeApp()

// Import the underlying calculation function directly from the built index.js
const { calculateAndSetSubjectProgress } = require('./lib/index.js');

const db = admin.firestore();

async function run() {
  const studentId = 'student_demo_1';
  const subjectId = 'subject_math_101';
  const sectionId = 'section_algebra';

  console.log("Setting up test documents...");

  // 1. Create Subject
  await db.collection('subjects').doc(subjectId).set({
    name: 'Mathematics 101'
  });

  // 2. Create Section
  await db.collection('subject_sections').doc(sectionId).set({
    subject_id: subjectId,
    name: 'Algebra'
  });

  // 3. Create 3 lectures
  for (let i = 1; i <= 3; i++) {
    await db.collection('lectures').doc(`lecture_${i}`).set({
      section_id: sectionId,
      subject_id: subjectId,
      title: `Lecture ${i}`
    });
  }

  // Wait a second for Firestore to settle
  await new Promise(r => setTimeout(r, 1000));

  // 4. Create an initial incomplete lecture_progress
  console.log("Creating lecture_1 progress document...");
  const progressDocId = `${studentId}_lecture_1`;
  await db.collection('lecture_progress').doc(progressDocId).set({
    student_id: studentId,
    lecture_id: 'lecture_1',
    is_completed: false,
    progress_percentage: 50,
    created_at: admin.firestore.FieldValue.serverTimestamp()
  });

  await new Promise(r => setTimeout(r, 1000));

  console.log("Updating lecture_1 to completed...");
  await db.collection('lecture_progress').doc(progressDocId).update({
    is_completed: true,
    progress_percentage: 100,
    updated_at: admin.firestore.FieldValue.serverTimestamp()
  });

  console.log("\nCalling exported calculateAndSetSubjectProgress from index.ts...");
  
  // Call the real logic just like the trigger would
  await calculateAndSetSubjectProgress(db, studentId, 'lecture_1');

  // 6. Check the subject_progress_summary
  const summaryId = `${studentId}_${subjectId}`;
  const summarySnap = await db.collection('subject_progress_summary').doc(summaryId).get();

  console.log("\n=== Resulting subject_progress_summary ===");
  if (summarySnap.exists) {
    console.log(JSON.stringify(summarySnap.data(), null, 2));
  } else {
    console.log(`Document ${summaryId} NOT FOUND.`);
  }
}

run()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error("Test failed:", e);
    process.exit(1);
  });
