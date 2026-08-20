const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');

const projectId = 'dr-tarek-platform-rules-test';
const root = path.resolve(__dirname, '..');
let testEnv;

function dbFor(uid, token = {}) {
  return testEnv.authenticatedContext(uid, token).firestore();
}

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.doc('users/student-safe').set({
      id: 'student-safe',
      full_name: 'Student Safe',
      role: 'student',
      approval_status: 'approved',
      account_status: 'active',
      is_deleted: false,
    });
    await db.doc('users/student-secret').set({
      id: 'student-secret',
      full_name: 'Student Secret',
      role: 'student',
      approval_status: 'approved',
      account_status: 'active',
      password_hash: 'scrypt:server-only',
    });
    await db.doc('users/pending-student').set({
      id: 'pending-student',
      full_name: 'Pending Student',
      role: 'new_student',
      approval_status: 'pending',
      account_status: 'active',
      is_deleted: false,
    });
    await db.doc('admin_permissions/admin-with-students').set({
      admin_id: 'admin-with-students',
      is_active: true,
      permissions: {admin_students: true},
    });
    await db.doc('admin_permissions/admin-without-students').set({
      admin_id: 'admin-without-students',
      is_active: true,
      permissions: {admin_students: false},
    });
    await db.doc('admin_permissions/admin-with-content').set({
      admin_id: 'admin-with-content',
      is_active: true,
      permissions: {admin_content: true},
    });
    await db.doc('admin_permissions/admin-inactive').set({
      admin_id: 'admin-inactive',
      is_active: false,
      permissions: {admin_students: true, admin_content: true},
    });
    await db.doc('academic_periods/term_1').set({
      id: 'term_1',
      period_type: 'term_1',
      label: 'الترم الأول',
      is_core: true,
      status: 'active',
    });
    await db.doc('platform_features/chat.enabled').set({
      feature_key: 'chat.enabled',
      label: 'المحادثات',
      enabled: true,
    });
    await db.doc('platform_features/exams.enabled').set({
      feature_key: 'exams.enabled',
      label: 'الامتحانات',
      enabled: false,
    });
    await db.doc('lectures/published').set({
      status: 'published',
      is_deleted: false,
      subject_id: 'subject-1',
    });
    await db.doc('lectures/draft').set({
      status: 'draft',
      is_deleted: false,
      subject_id: 'subject-1',
    });
    await db.doc('subject_access_assignments/student-safe_subject-1').set({
      student_id: 'student-safe',
      subject_id: 'subject-1',
      is_deleted: false,
      enabled: true,
    });
    await db.doc('subject_access_assignments/student-safe_subject-2').set({
      student_id: 'student-safe',
      subject_id: 'subject-2',
      is_deleted: true,
      enabled: false,
    });
    await db.doc('subject_access_assignments/student-secret_subject-1').set({
      student_id: 'student-secret',
      subject_id: 'subject-1',
      is_deleted: false,
      enabled: true,
    });
  });
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

  try {
    await seed();

    await assertFails(dbFor('anonymous').collection('users').doc('student-safe').get());
    await assertSucceeds(dbFor('student-safe', {role: 'student', approved: true}).collection('users').doc('student-safe').get());
    await assertFails(dbFor('student-secret', {role: 'student', approved: true}).collection('users').doc('student-secret').get());

    await assertFails(
      dbFor('student-safe', {role: 'student', approved: true})
        .collection('users').doc('student-safe')
        .update({role: 'teacher'}),
    );

    await assertSucceeds(
      dbFor('admin-with-students', {role: 'admin', approved: true})
        .collection('users').doc('pending-student').get(),
    );
    await assertFails(
      dbFor('admin-without-students', {role: 'admin', approved: true})
        .collection('users').doc('pending-student').get(),
    );

    await assertSucceeds(
      dbFor('student-safe', {role: 'student', approved: true})
        .collection('subject_access_assignments')
        .doc('student-safe_subject-1').get(),
    );
    await assertFails(
      dbFor('student-safe', {role: 'student', approved: true})
        .collection('subject_access_assignments')
        .doc('student-secret_subject-1').get(),
    );
    await assertFails(
      dbFor('student-safe', {role: 'student', approved: true})
        .collection('subject_access_assignments')
        .doc('student-safe_subject-2').get(),
    );
    await assertSucceeds(
      dbFor('admin-with-students', {role: 'admin', approved: true})
        .collection('subject_access_assignments')
        .doc('student-secret_subject-1').get(),
    );
    await assertSucceeds(
      dbFor('teacher-1', {role: 'teacher', approved: true})
        .collection('subject_access_assignments')
        .doc('student-secret_subject-1').get(),
    );
    await assertFails(
      dbFor('student-safe', {role: 'student', approved: true})
        .collection('subject_access_assignments')
        .doc('student-safe_subject-3').set({
          student_id: 'student-safe',
          subject_id: 'subject-3',
          is_deleted: false,
          enabled: true,
        }),
    );
    await assertFails(
      dbFor('student-safe', {role: 'student', approved: true})
        .collection('subject_access_assignments')
        .doc('student-safe_subject-1').update({enabled: false}),
    );
    await assertFails(
      dbFor('student-safe', {role: 'student', approved: true})
        .collection('subject_access_assignments')
        .doc('student-safe_subject-1').delete(),
    );

    await assertSucceeds(
      dbFor('student-safe', {role: 'student', approved: true})
        .collection('notes').doc('note-1').set({student_id: 'student-safe', body: 'Private note'}),
    );
    await assertFails(
      dbFor('student-safe', {role: 'student', approved: true})
        .collection('notes').doc('note-2').set({student_id: 'another-student', body: 'Not mine'}),
    );

    await assertSucceeds(
      dbFor('student-safe', {role: 'student', approved: true})
        .collection('lectures').doc('published').get(),
    );
    await assertFails(
      dbFor('student-safe', {role: 'student', approved: true})
        .collection('lectures').doc('draft').get(),
    );
    await assertSucceeds(
      dbFor('teacher-1', {role: 'teacher', approved: true})
        .collection('lectures').doc('draft').get(),
    );

    await assertFails(
      dbFor('student-safe', {role: 'student', approved: true})
        .collection('unlisted_collection').doc('x').get(),
    );

    // academic_periods: readable by any signed-in user, never writable.
    await assertSucceeds(
      dbFor('student-safe', {role: 'student', approved: true})
        .collection('academic_periods').doc('term_1').get(),
    );
    await assertSucceeds(
      dbFor('teacher-1', {role: 'teacher', approved: true})
        .collection('academic_periods').get(),
    );
    await assertFails(
      testEnv.unauthenticatedContext().firestore()
        .collection('academic_periods').doc('term_1').get(),
    );
    await assertFails(
      dbFor('teacher-1', {role: 'teacher', approved: true})
        .collection('academic_periods').doc('term_1').set({status: 'ended'}),
    );
    await assertFails(
      dbFor('admin-with-students', {role: 'admin', approved: true})
        .collection('academic_periods').doc('term_1').update({status: 'ended'}),
    );

    // platform_features: staff read all, students read only enabled, no writes.
    await assertSucceeds(
      dbFor('student-safe', {role: 'student', approved: true})
        .collection('platform_features').doc('chat.enabled').get(),
    );
    await assertFails(
      dbFor('student-safe', {role: 'student', approved: true})
        .collection('platform_features').doc('exams.enabled').get(),
    );
    await assertSucceeds(
      dbFor('teacher-1', {role: 'teacher', approved: true})
        .collection('platform_features').doc('exams.enabled').get(),
    );
    await assertFails(
      dbFor('teacher-1', {role: 'teacher', approved: true})
        .collection('platform_features').doc('chat.enabled').set({enabled: false}),
    );

    // Delegated admin permissions gate real access, not just the UI:
    // admin_content grants subject reads, missing permission denies them.
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('subjects/subject-1').set({
        title: 'Subject 1',
        is_deleted: false,
        is_visible: true,
      });
    });
    await assertSucceeds(
      dbFor('admin-with-content', {role: 'admin', approved: true})
        .collection('subjects').doc('subject-1').get(),
    );
    await assertFails(
      dbFor('admin-with-students', {role: 'admin', approved: true})
        .collection('subjects').doc('subject-1').get(),
    );
    await assertFails(
      dbFor('admin-inactive', {role: 'admin', approved: true})
        .collection('subjects').doc('subject-1').get(),
    );
    // admin_students grants student-record reads; other keys do not.
    await assertSucceeds(
      dbFor('admin-with-students', {role: 'admin', approved: true})
        .collection('users').doc('pending-student').get(),
    );
    await assertFails(
      dbFor('admin-with-content', {role: 'admin', approved: true})
        .collection('users').doc('pending-student').get(),
    );

    const studentStorage = testEnv
      .authenticatedContext('student-safe', {role: 'student', approved: true})
      .storage();
    const otherStudentStorage = testEnv
      .authenticatedContext('student-safe', {role: 'student', approved: true})
      .storage();
    const teacherStorage = testEnv
      .authenticatedContext('teacher-1', {role: 'teacher', approved: true})
      .storage();

    await assertSucceeds(
      studentStorage.ref('profile_photos/student-safe/avatar.png')
        .put(Buffer.from('png-data'), {contentType: 'image/png'}),
    );
    await assertFails(
      otherStudentStorage.ref('profile_photos/another-student/avatar.png')
        .put(Buffer.from('png-data'), {contentType: 'image/png'}),
    );
    await assertFails(
      studentStorage.ref('lecture_resources/lecture-1/resource-1/file.pdf').getDownloadURL(),
    );
    await assertSucceeds(
      teacherStorage.ref('lecture_resources/lecture-1/resource-1/file.pdf')
        .put(Buffer.from('pdf-data'), {contentType: 'application/pdf'}),
    );

    console.log('Firestore and Storage rules tests passed.');
  } finally {
    await testEnv.cleanup();
  }
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
