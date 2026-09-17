const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');
const assert = require('node:assert/strict');

const projectId = 'dr-tarek-platform-result-release-test';
const root = path.resolve(__dirname, '..');
let testEnv;

function dbFor(uid, token = {}) {
  return testEnv.authenticatedContext(uid, token).firestore();
}

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    // Scheduled attempt whose result is withheld (score absent).
    await db.doc('quiz_attempts/rr-pending').set({
      student_id: 'student-rr',
      assessment_id: 'quiz-rr',
      status: 'submitted',
      score: null,
      percentage: null,
      graded: false,
    });
    // Released attempt carrying a final score.
    await db.doc('exam_attempts/rr-released').set({
      student_id: 'student-rr',
      assessment_id: 'exam-rr',
      status: 'submitted',
      score: 8,
      percentage: 80,
      graded: true,
    });
  });
}

async function run() {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8'),
    },
  });

  try {
    await testEnv.clearFirestore();
    await seed();
    const student = () =>
      dbFor('student-rr', {role: 'student', approved: true});

    // Student may read the attempt shell but the withheld result stays null.
    const pendingSnap = await assertSucceeds(
      student().collection('quiz_attempts').doc('rr-pending').get(),
    );
    assert.equal(pendingSnap.data().score, null);
    assert.equal(pendingSnap.data().percentage, null);
    console.log('ok - Withheld result reads as null, never leaked');

    // Released results remain readable by their owner.
    const releasedSnap = await assertSucceeds(
      student().collection('exam_attempts').doc('rr-released').get(),
    );
    assert.equal(releasedSnap.data().score, 8);
    console.log('ok - Released result readable by owner');

    // Students cannot forge scores through creates or updates.
    await assertFails(
      student().collection('quiz_attempts').doc('rr-forge').set({
        student_id: 'student-rr',
        assessment_id: 'quiz-rr',
        status: 'started',
        score: 10,
      }),
    );
    await assertFails(
      student().collection('quiz_attempts').doc('rr-pending').update({
        score: 10,
      }),
    );
    await assertFails(
      student().collection('quiz_attempts').doc('rr-pending').delete(),
    );
    console.log('ok - Score forgery and deletion denied');

    // Strangers and anonymous users see nothing.
    await assertFails(
      dbFor('student-other', {role: 'student', approved: true})
        .collection('quiz_attempts')
        .doc('rr-pending')
        .get(),
    );
    await assertFails(
      testEnv.unauthenticatedContext().firestore()
        .collection('quiz_attempts')
        .doc('rr-pending')
        .get(),
    );
    console.log('ok - Cross-user and anonymous reads denied');

    // Staff retains read access for support/analytics.
    await assertSucceeds(
      dbFor('teacher-1', {role: 'teacher'})
        .collection('quiz_attempts')
        .doc('rr-pending')
        .get(),
    );
    console.log('ok - Staff read preserved');
  } finally {
    await testEnv.cleanup();
  }
  console.log('result_release rules: PASS');
}

run().catch((e) => {
  console.error('result_release rules FAILED:', e);
  process.exit(1);
});
