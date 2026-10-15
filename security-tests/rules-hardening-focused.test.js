/**
 * rules-hardening-focused.test.js — residual items 4 (Firestore) + 5 (Storage).
 *
 * Focused emulator suite for the purely-internal rule hardening:
 *  - device_change_requests create: pending-only + hasOnly allowlist.
 *  - lecture_progress / learning_progress create+update: playback-shape
 *    hasOnly allowlist (ownership semantics unchanged).
 *  - storage.rules lecture_resources: explicit video/* denied even for
 *    staff; octet-stream/images still allowed; students still denied.
 *
 * Run: firebase emulators:exec --only firestore,storage
 *        --project dr-tarek-platform-emulator "node rules-hardening-focused.test.js"
 * from security-tests/. No production, no network beyond localhost.
 */
const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');

const projectId = 'dr-tarek-platform-hardening-test';
const root = path.resolve(__dirname, '..');
let testEnv;

function dbFor(uid, token = {}) {
  return testEnv.authenticatedContext(uid, token).firestore();
}
function storageFor(uid, token = {}) {
  return testEnv.authenticatedContext(uid, token).storage();
}

async function run() {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8'),
    },
    storage: {
      rules: fs.readFileSync(path.join(root, 'storage.rules'), 'utf8'),
    },
  });
  let passed = 0;
  const ok = (name) => {
    passed++;
    console.log(`ok - ${name}`);
  };

  try {
    await testEnv.clearFirestore();
    await testEnv.clearStorage();

    const student = dbFor('student-1', { role: 'student', approved: true });
    const doctorStorage = storageFor('doctor-1', { role: 'doctor', approved: true });
    const studentStorage = storageFor('student-1', { role: 'student', approved: true });

    // ---- item 4a: device_change_requests create hardening ----
    await assertSucceeds(student.collection('device_change_requests').doc('req-ok').set({
      student_id: 'student-1',
      status: 'pending',
      requested_at: new Date(),
      old_device_id: 'old-1',
      new_device_id: 'new-1',
    }));
    ok('device request: pending self-request with server shape -> allowed');

    await assertFails(student.collection('device_change_requests').doc('req-approved').set({
      student_id: 'student-1',
      status: 'approved',
      requested_at: new Date(),
      new_device_id: 'new-1',
    }));
    ok('device request: client-chosen status approved -> denied');

    await assertFails(student.collection('device_change_requests').doc('req-smuggle').set({
      student_id: 'student-1',
      status: 'pending',
      requested_at: new Date(),
      new_device_id: 'new-1',
      decided_by: 'student-1',
      resolved_at: new Date(),
    }));
    ok('device request: smuggled decision fields -> denied');

    await assertFails(student.collection('device_change_requests').doc('req-other').set({
      student_id: 'another-student',
      status: 'pending',
      requested_at: new Date(),
      new_device_id: 'new-1',
    }));
    ok('device request: another student id -> denied');

    // ---- item 4b: lecture_progress playback-shape allowlist ----
    const legitProgress = {
      student_id: 'student-1',
      lecture_id: 'lec-1',
      subject_id: 'subject-1',
      section_id: 'sec-1',
      lecture_title: 'Intro',
      thumbnail_url: 'https://cdn.example/t.jpg',
      position_seconds: 12.5,
      duration_seconds: 600,
      progress_percent: 2.08,
      completed: false,
      is_completed: false,
      completed_at: null,
      pdf_last_page: 3,
      pdf_total_pages: 10,
      updated_at: new Date(),
    };
    await assertSucceeds(student.collection('lecture_progress').doc('student-1_lec-1').set(legitProgress));
    ok('lecture_progress: legit playback shape -> allowed');

    await assertFails(student.collection('lecture_progress').doc('student-1_lec-2').set({
      ...legitProgress,
      lecture_id: 'lec-2',
      forged_score: 100,
    }));
    ok('lecture_progress: arbitrary extra field -> denied');

    await assertSucceeds(
      student.collection('lecture_progress').doc('student-1_lec-1').update({ position_seconds: 42 }),
    );
    ok('lecture_progress: legit merge update -> allowed');

    await assertFails(
      student.collection('lecture_progress').doc('student-1_lec-1').update({ injected_admin: true }),
    );
    ok('lecture_progress: merge update with junk key -> denied');

    // ---- item 4b: learning_progress symmetric allowlist ----
    await assertSucceeds(student.collection('learning_progress').doc('lp-ok').set({
      student_id: 'student-1',
      lecture_id: 'lec-1',
      position_seconds: 5,
      updated_at: new Date(),
    }));
    ok('learning_progress: known-shape create -> allowed');

    await assertFails(student.collection('learning_progress').doc('lp-bad').set({
      student_id: 'student-1',
      lecture_id: 'lec-1',
      forged_completion: true,
    }));
    ok('learning_progress: arbitrary extra field -> denied');

    // ---- item 5: storage MIME gate (video never in Firebase Storage) ----
    await assertFails(doctorStorage
      .ref('lecture_resources/lec-1/res-x/movie.mp4')
      .put(Buffer.from('mp4-data'), { contentType: 'video/mp4' }));
    ok('storage: staff video/mp4 upload -> denied');

    await assertSucceeds(doctorStorage
      .ref('lecture_resources/lec-1/res-x/raw.bin')
      .put(Buffer.from('bin-data'), { contentType: 'application/octet-stream' }));
    ok('storage: staff octet-stream attachment -> allowed');

    await assertSucceeds(doctorStorage
      .ref('lecture_resources/lec-1/res-x/thumb.jpg')
      .put(Buffer.from('jpeg-data'), { contentType: 'image/jpeg' }));
    ok('storage: staff jpeg thumbnail -> allowed');

    await assertFails(studentStorage
      .ref('lecture_resources/lec-1/res-x/hack.pdf')
      .put(Buffer.from('pdf-data'), { contentType: 'application/pdf' }));
    ok('storage: student upload -> denied');
  } finally {
    await testEnv.cleanup();
  }

  console.log(`rules-hardening-focused.test: PASS - All ${passed} checks passed.`);
}

run().catch((err) => {
  console.error(`rules-hardening-focused tests FAILED: ${err && err.message}`);
  process.exit(1);
});
