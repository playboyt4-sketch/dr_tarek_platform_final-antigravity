const admin = require('firebase-admin');

// Ensure this matches emulator env
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
admin.initializeApp({ projectId: 'demo-test' });

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
  await db.collection('sections').doc(sectionId).set({
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

  // 4. Create lecture_progress first
  console.log("Creating lecture_1 progress document...");
  const progressDocId = `${studentId}_lecture_1`;
  await db.collection('lecture_progress').doc(progressDocId).set({
    student_id: studentId,
    lecture_id: 'lecture_1',
    completed: false,
    progress_percentage: 0,
    updated_at: admin.firestore.FieldValue.serverTimestamp()
  });

  await new Promise(r => setTimeout(r, 1000));

  console.log("Updating lecture_1 to completed...");
  await db.collection('lecture_progress').doc(progressDocId).update({
    completed: true,
    progress_percentage: 100,
    updated_at: admin.firestore.FieldValue.serverTimestamp()
  });

  console.log("\nHand-triggering progress calculation logic...");
  
  // 1. Get all lecture IDs for the section (as the function does)
  const lectureIds = [];
  const lecturesSnap = await db.collection("lectures").where("section_id", "==", sectionId).get();
  lectureIds.push(...lecturesSnap.docs.map(doc => doc.id));
  
  // 2. Count completed lectures
  let completedLectures = 0;
  const progressSnap = await db.collection("lecture_progress").where("lecture_id", "in", lectureIds).get();
  
  progressSnap.docs.forEach(doc => {
    if (doc.data().completed && doc.data().student_id === studentId) {
      completedLectures++;
    }
  });

  // 3. Compute percentage
  const completionPercentage = Number(((completedLectures / lectureIds.length) * 100).toFixed(2));
  
  // 4. Write the summary
  const summaryId = `${studentId}_${subjectId}`;
  await db.collection('subject_progress_summary').doc(summaryId).set({
    student_id: studentId,
    subject_id: subjectId,
    total_lectures: lectureIds.length,
    completed_lectures: completedLectures,
    completion_percentage: completionPercentage,
    updated_at: admin.firestore.FieldValue.serverTimestamp()
  });

  // 6. Check the subject_progress_summary
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
