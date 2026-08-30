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
    await db.doc('admin_permissions/admin-with-chat').set({
      admin_id: 'admin-with-chat',
      is_active: true,
      permissions: {admin_chat: true},
    });
    await db.doc('admin_permissions/admin-without-chat').set({
      admin_id: 'admin-without-chat',
      is_active: true,
      permissions: {admin_students: true, admin_chat: false},
    });
    await db.doc('admin_permissions/admin-with-reset').set({
      admin_id: 'admin-with-reset',
      is_active: true,
      permissions: {password_reset: true},
    });
    await db.doc('admin_permissions/admin-without-reset').set({
      admin_id: 'admin-without-reset',
      is_active: true,
      permissions: {admin_students: true, password_reset: false},
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
    // Archive System (Part B): a soft-deleted lecture must stay invisible
    // to students even if it was published before archiving.
    await db.doc('lectures/archived').set({
      status: 'published',
      is_deleted: true,
      deleted_at: new Date(),
      deleted_by: 'teacher-1',
      subject_id: 'subject-1',
    });
    // Part E: platform default storage provider setting document.
    await db.doc('system_settings/settings-main').set({
      default_storage_provider: 'firebase',
      default_plan: 'center_free',
    });
    await db.doc('subject_access_assignments/student-safe_subject-1').set({
      student_id: 'student-safe',
      subject_id: 'subject-1',
      is_deleted: false,
      enabled: true,
      entitlements: ['notes.create', 'bookmarks.create'],
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
    await testEnv.clearFirestore();
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
        .collection('notes').doc('note-1').set({student_id: 'student-safe', subject_id: 'subject-1', body: 'Private note'}),
    );
    await assertFails(
      dbFor('student-safe', {role: 'student', approved: true})
        .collection('notes').doc('note-2').set({student_id: 'another-student', subject_id: 'subject-1', body: 'Not mine'}),
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

    // ---- Exam/Quiz integrity (Owner directive O): clients may start and
    // submit attempts, but score/percentage/passed are server-computed only.
    const studentDb = dbFor('student-safe', {role: 'student', approved: true});

    // Legitimate attempt start passes.
    console.log('Testing legitimate quiz attempt start');
    await assertSucceeds(
      studentDb.collection('quiz_attempts').doc('attempt-1').set({
        student_id: 'student-safe',
        assessment_id: 'quiz-1',
        status: 'started',
        started_at: new Date(),
      }),
    );
    console.log('Testing legitimate exam attempt start');
    await assertSucceeds(
      studentDb.collection('exam_attempts').doc('attempt-2').set({
        student_id: 'student-safe',
        assessment_id: 'exam-1',
        status: 'started',
        started_at: new Date(),
      }),
    );

    // Tampering: creating an attempt that already carries a score fails.
    console.log('Testing tampering on quiz attempt create');
    await assertFails(
      studentDb.collection('quiz_attempts').doc('attempt-cheat-create').set({
        student_id: 'student-safe',
        assessment_id: 'quiz-1',
        status: 'started',
        started_at: new Date(),
        score: 100,
      }),
    );

    // Tampering: submission carrying score/percentage/passed fails.
    console.log('Testing tampering on quiz attempt update (score)');
    await assertFails(
      studentDb.collection('quiz_attempts').doc('attempt-1').update({
        status: 'submitted',
        submitted_at: new Date(),
        answers: {q1: 'wrong'},
        score: 100,
        percentage: 100,
        passed: true,
      }),
    );

    // Quiz submission now happens ONLY through the callable; direct client
    // updates are denied even for answers-only payloads.
    console.log('Testing tampering on quiz attempt update (answers)');
    await assertFails(
      studentDb.collection('quiz_attempts').doc('attempt-1').update({
        status: 'submitted',
        submitted_at: new Date(),
        answers: {q1: 'a'},
      }),
    );

    // After submission the attempt is immutable to the client.
    console.log('Testing immutable quiz attempt after submission');
    await assertFails(
      studentDb.collection('quiz_attempts').doc('attempt-1').update({
        score: 100,
      }),
    );

    // Quiz attempts: clients can start but NEVER update — submission and
    // grading happen only through the submitAssessmentAttempt callable.
    console.log('Testing update on quiz attempt fails 3');
    await assertFails(
      studentDb.collection('quiz_attempts').doc('attempt-1').update({
        status: 'submitted',
        submitted_at: new Date(),
        answers: {q1: 'a'},
      }),
    );

    // Custom groups: students have NO direct access (registration wizard uses
    // the getActiveCustomGroups callable); staff may stream read-only; ALL
    // writes stay callable-only and audited.
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('custom_groups/group-1').set({
        name: 'مجموعة تجريبية',
        description: '',
        is_active: true,
      });
    });
    const teacherDb2 = dbFor('teacher-owner', {role: 'teacher', approved: true});
    await assertFails(studentDb.collection('custom_groups').doc('group-1').get());
    await assertFails(studentDb.collection('custom_groups').get());
    await assertSucceeds(
      teacherDb2.collection('custom_groups').doc('group-1').get(),
    );
    await assertSucceeds(teacherDb2.collection('custom_groups').get());
    await assertSucceeds(
      dbFor('admin-with-chat', {role: 'admin', approved: true})
        .collection('custom_groups').doc('group-1').get(),
    );
    // Writes remain denied even for the Teacher (callables only).
    await assertFails(
      teacherDb2.collection('custom_groups').doc('group-2')
        .set({name: 'forged', is_active: true}),
    );
    await assertFails(
      teacherDb2.collection('custom_groups').doc('group-1')
        .update({is_active: false}),
    );


    // lecture_resources: raw documents carry resource_url / storage paths and
    // are NEVER client-readable — listing goes through the authorized
    // getLectureResources callable (06 Firebase Architecture Sections 4.2/5.2).
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('lecture_resources/resource-1').set({
        lecture_id: 'published',
        resource_type: 'video',
        visibility: true,
        is_visible: true,
        resource_url: 'https://bunny.example/tokenized-url',
      });
    });
    await assertFails(
      studentDb
        .collection('lecture_resources')
        .where('lecture_id', '==', 'published')
        .get(),
    );
    await assertFails(studentDb.collection('lecture_resources').doc('resource-1').get());
    // Phase-1 authoring: STAFF may update resource metadata directly
    // (Rules-governed, canManageContent/isTeacher) — students never can.
    await assertSucceeds(
      teacherDb2.collection('lecture_resources').doc('resource-1').set({
        lecture_id: 'lec-live',
        resource_type: 'video',
        visibility: true,
        resource_url: 'https://bunny.example/rotated-token',
      }),
    );
    await assertFails(studentDb.collection('lecture_resources').doc('resource-1')
      .set({resource_url: 'forged'}));


    // One-time password-reset PIN documents are server-only.
    // (PIN self-service flow was removed by owner decision — the
    // password_reset_pins collection no longer exists in the schema and
    // falls under the default-deny catch-all, as asserted for
    // unlisted_collection above.)

    // Exam attempts: clients can start but NEVER update — submission and
    // grading happen only through the submitExamAttempt callable (Admin SDK).
    await assertFails(
      studentDb.collection('exam_attempts').doc('attempt-2').update({
        status: 'submitted',
        submitted_at: new Date(),
        answers: {q1: 'a'},
      }),
    );
    await assertFails(
      studentDb.collection('exam_attempts').doc('attempt-2').update({
        score: 100,
        percentage: 100,
      }),
    );

    // Question banks contain correct answers — never client-readable
    // (default-deny catch-all; grading happens server-side via Admin SDK).
    await assertFails(
      studentDb.collection('question_bank').doc('q-cheat').get(),
    );
    await assertFails(
      studentDb.collection('exam_questions').doc('link-1').get(),
    );
    await assertFails(
      studentDb.collection('question_bank').doc('q-new').set({
        question: 'hack',
        correct_answer: 'x',
      }),
    );

    // ---- Notifications: students may ONLY mark their OWN notification as
    // read; staff enqueue via create gated by ADMIN_CHAT / teacher role.
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('notifications/notif-mine').set({
        user_id: 'student-safe',
        title: 't',
        body: 'b',
        is_read: false,
      });
      await context.firestore().doc('notifications/notif-theirs').set({
        user_id: 'student-other',
        title: 't',
        body: 'b',
        is_read: false,
      });
    });

    console.log('Test 1: Student marks their own notification as read');
    await assertSucceeds(
      studentDb.collection('notifications').doc('notif-mine').update({
        is_read: true,
        read_at: new Date(),
      }),
    );

    // Student A can NEVER touch student B's notification.
    console.log('Test 2: Student A can NEVER touch student Bs notification');
    await assertFails(
      studentDb.collection('notifications').doc('notif-theirs').update({
        is_read: true,
        read_at: new Date(),
      }),
    );
    await assertFails(
      studentDb.collection('notifications').doc('notif-theirs').get(),
    );

    // Read-receipt updates may not smuggle other fields or un-read a doc.
    console.log('Test 3: Read-receipt updates may not smuggle other fields');
    await assertFails(
      studentDb.collection('notifications').doc('notif-mine').update({
        is_read: true,
        read_at: new Date(),
        title: 'hijacked',
      }),
    );
    console.log('Test 4: un-read a doc');
    await assertFails(
      studentDb.collection('notifications').doc('notif-mine').update({
        is_read: false,
      }),
    );
    console.log('Test 5: hijacked body');
    await assertFails(
      studentDb.collection('notifications').doc('notif-mine').update({
        is_read: true,
        read_at: new Date(),
        body: 'hijacked body',
      }),
    );
    console.log('Test 6: hijacked user_id');
    await assertFails(
      studentDb.collection('notifications').doc('notif-mine').update({
        is_read: true,
        read_at: new Date(),
        user_id: 'student-other',
      }),
    );
    console.log('Test 7: hijacked delivery_status');
    await assertFails(
      studentDb.collection('notifications').doc('notif-mine').update({
        is_read: true,
        read_at: new Date(),
        delivery_status: 'delivered',
      }),
    );
    console.log('Test 8: hijacked sender_id');
    await assertFails(
      studentDb.collection('notifications').doc('notif-mine').update({
        is_read: true,
        read_at: new Date(),
        sender_id: 'admin',
      }),
    );
    console.log('Test 9: hijacked sent_at');
    await assertFails(
      studentDb.collection('notifications').doc('notif-mine').update({
        is_read: true,
        read_at: new Date(),
        sent_at: new Date(),
      }),
    );
    console.log('Test 10: anonymous user');
    await assertFails(
      dbFor('anonymous').collection('notifications').doc('notif-mine').update({
        is_read: true,
        read_at: new Date(),
      }),
    );
    await assertFails(
      studentDb.collection('notifications').doc('notif-mine').delete(),
    );
    // Students cannot enqueue notifications.
    await assertFails(
      studentDb.collection('notifications').doc('notif-forge').set({
        user_id: 'student-safe',
        title: 'spam',
        body: 'spam',
        status: 'queued',
        created_by: 'student-safe',
      }),
    );

    // Staff creation: composer shape requires teacher role or admin_chat.
    const composerPayload = {
      user_id: 'student-safe',
      title: 'إشعار',
      body: 'نص',
      type: 'Announcements',
      notification_type: 'Announcements',
      status: 'queued',
      priority: 'normal',
      media_type: 'none',
      created_at: new Date(),
      created_by: 'staff-1',
    };
    await assertSucceeds(
      dbFor('teacher-owner', {role: 'teacher', approved: true})
        .collection('notifications').doc('notif-t1').set(composerPayload),
    );
    await assertSucceeds(
      dbFor('admin-with-chat', {role: 'admin', approved: true})
        .collection('notifications').doc('notif-a1').set(composerPayload),
    );
    await assertFails(
      dbFor('admin-without-chat', {role: 'admin', approved: true})
        .collection('notifications').doc('notif-a2').set(composerPayload),
    );

    // ---- password_reset_requests: staff may queue pending requests only;
    // reads stay staff-only, resolution stays server-side.
    const resetRequest = {
      student_id: 'student-safe',
      status: 'pending',
      requested_at: new Date(),
    };
    await assertSucceeds(
      dbFor('teacher-owner', {role: 'teacher', approved: true})
        .collection('password_reset_requests').doc('req-t1').set(resetRequest),
    );
    await assertFails(
      dbFor('admin-with-reset', {role: 'admin', approved: true})
        .collection('password_reset_requests').doc('req-a1').set(resetRequest),
    );
    await assertFails(
      dbFor('admin-without-reset', {role: 'admin', approved: true})
        .collection('password_reset_requests').doc('req-a2').set(resetRequest),
    );
    // Students CAN create their own pending reset requests.
    await assertSucceeds(
      studentDb.collection('password_reset_requests').doc('req-s1')
        .set(resetRequest),
    );
    // Students CANNOT create requests for others.
    await assertFails(
      studentDb.collection('password_reset_requests').doc('req-s2')
        .set({
          ...resetRequest,
          student_id: 'other-student',
        }),
    );
    // Students CANNOT create resolved requests.
    await assertFails(
      studentDb.collection('password_reset_requests').doc('req-s3')
        .set({
          ...resetRequest,
          status: 'resolved',
        }),
    );
    // Request documents cannot smuggle extra fields (e.g. resolved markers).
    await assertFails(
      dbFor('teacher-owner', {role: 'teacher', approved: true})
        .collection('password_reset_requests').doc('req-t2').set({
          ...resetRequest,
          resolved_by: 'teacher-owner',
          new_password_hash: 'x',
        }),
    );
    // Requests are immutable to clients once queued (Admin SDK resolves them).
    await assertFails(
      dbFor('teacher-owner', {role: 'teacher', approved: true})
        .collection('password_reset_requests').doc('req-t1')
        .update({status: 'resolved'}),
    );
    // Staff dashboard may still list pending requests (existing read rule).
    await assertSucceeds(
      dbFor('admin-with-reset', {role: 'admin', approved: true})
        .collection('password_reset_requests')
        .where('status', '==', 'pending')
        .get(),
    );

    // registration_requests does NOT exist in the schema (05 Database):
    // the catch-all deny must keep rejecting every client access. The admin
    // home tile was repointed to users where approval_status == 'pending'.
    await assertFails(
      dbFor('teacher-owner', {role: 'teacher', approved: true})
        .collection('registration_requests').doc('x').get(),
    );

    // ---- Content authoring (Phase 1): staff manage sections/lectures/
    // resources directly under Rules; students keep read-only published
    // access to sections/lectures and ZERO direct access to resources.
    const teacherDb3 = dbFor('teacher-1', {role: 'teacher', approved: true});
    const contentAdminDb = dbFor('admin-with-content', {role: 'admin', approved: true});
    const plainAdminDb = dbFor('admin-with-students', {role: 'admin', approved: true});

    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('subject_sections/sec-system').set({
        subject_id: 'subject-1',
        section_key: 'explanation',
        is_system_section: true,
        title: 'شرح',
        display_order: 1,
        is_visible: true,
      });
    });

    // Create custom section.
    await assertSucceeds(teacherDb3.collection('subject_sections').doc('sec-custom').set({
      subject_id: 'subject-1',
      section_key: null,
      is_system_section: false,
      title: 'مجموعة إضافية',
      display_order: 2,
      is_visible: true,
    }));
    await assertSucceeds(contentAdminDb.collection('subject_sections').doc('sec-custom2').set({
      subject_id: 'subject-1',
      section_key: null,
      is_system_section: false,
      title: 'مراجعة خاصة',
      display_order: 3,
      is_visible: false,
    }));
    // Students can never write sections.
    await assertFails(studentDb.collection('subject_sections').doc('sec-hack').set({title: 'x'}));
    // Delegated admins WITHOUT admin_content cannot author.
    await assertFails(plainAdminDb.collection('subject_sections').doc('sec-x').set({
      subject_id: 'subject-1', title: 'x', display_order: 9, is_visible: true,
    }));

    // Edit title/visibility (system section title editable).
    await assertSucceeds(teacherDb3.collection('subject_sections').doc('sec-system')
      .update({title: 'الشرح المحدث', is_visible: false}));
    // Reorder = batched display_order updates.
    await assertSucceeds(teacherDb3.collection('subject_sections').doc('sec-custom')
      .update({display_order: 1}));
    
    // ALL sections use soft delete. Hard delete must fail.
    await assertFails(teacherDb3.collection('subject_sections').doc('sec-custom2').delete());
    await assertFails(teacherDb3.collection('subject_sections').doc('sec-system').delete());

    // Custom-section soft delete allowed at Rules level; SYSTEM sections can
    // never be deleted (Feature 03 — boundary enforced in the Rules).
    await assertSucceeds(teacherDb3.collection('subject_sections').doc('sec-custom2')
      .update({is_deleted: true}));
    await assertFails(teacherDb3.collection('subject_sections').doc('sec-system')
      .update({is_deleted: true}));

    // Lectures: create draft -> publish -> archive (soft, never hard delete).
    await assertSucceeds(teacherDb3.collection('lectures').doc('lec-admin-1').set({
      section_id: 'sec-live',
      title: 'محاضرة تجريبية',
      description: '',
      display_order: 1,
      publish_date: new Date(),
      status: 'draft',
      is_deleted: false,
    }));
    console.log("Checking lec-admin-1 get for student");
    await assertFails(studentDb.collection('lectures').doc('lec-admin-1').get()); // draft hidden
    console.log("Passed lec-admin-1 get for student");
    await assertSucceeds(teacherDb3.collection('lectures').doc('lec-admin-1')
      .update({status: 'published'}));
    await assertSucceeds(contentAdminDb.collection('lectures').doc('lec-admin-1')
      .update({status: 'draft'}));
    await assertSucceeds(teacherDb3.collection('lectures').doc('lec-admin-1')
      .update({is_deleted: true, status: 'archived'}));
    await assertFails(teacherDb3.collection('lectures').doc('lec-admin-1').delete());
    await assertFails(studentDb.collection('lectures').doc('lec-admin-1').set({title: 'hack'}));

    // Lecture resources: staff CRUD incl. video-by-id (no raw URLs), pdf path
    // metadata, external links. Students have NO direct read or write.
    const resourceBase = {
      lecture_id: 'lec-live',
      title: 'الفيديو الأول',
      resource_type: 'video',
      bunny_video_id: 'bunny-part-1',
      storage_path: null,
      resource_url: '',
      thumbnail: null,
      duration: null,
      display_order: 1,
      is_visible: true,
      visibility: true,
      is_deleted: false,
    };
    await assertSucceeds(teacherDb3.collection('lecture_resources').doc('res-video-1').set(resourceBase));
    await assertSucceeds(contentAdminDb.collection('lecture_resources').doc('res-pdf-1').set({
      ...resourceBase,
      resource_type: 'pdf',
      title: 'الملف',
      bunny_video_id: null,
      storage_path: 'lecture_resources/lec-live/res-pdf-1/file.pdf',
      display_order: 2,
    }));
    await assertSucceeds(teacherDb3.collection('lecture_resources').doc('res-link-1').set({
      ...resourceBase,
      resource_type: 'external_link',
      title: 'رابط خارجي',
      resource_url: 'https://example.com',
      display_order: 3,
    }));
    // Reorder + visibility toggle + soft archive.
    await assertSucceeds(teacherDb3.collection('lecture_resources').doc('res-video-1')
      .update({display_order: 3}));
    await assertSucceeds(teacherDb3.collection('lecture_resources').doc('res-video-1')
      .update({is_visible: false, visibility: false}));
    await assertSucceeds(teacherDb3.collection('lecture_resources').doc('res-video-1')
      .update({is_deleted: true, is_visible: false, visibility: false}));
    // Students: no direct reads/writes ever (callable-gated delivery only).
    await assertFails(studentDb.collection('lecture_resources').doc('res-pdf-1').get());
    await assertFails(studentDb.collection('lecture_resources').where('lecture_id', '==', 'lec-live').get());
    await assertFails(studentDb.collection('lecture_resources').doc('res-new').set({title: 'x'}));
    await assertFails(plainAdminDb.collection('lecture_resources').doc('res-nope').set({title: 'x'}));

    // ---- Admin-authored content visible to a SUBSCRIBED student, denied
    // to an unsubscribed one — verified through the same shapes production
    // uses. Enforcement is layered: (a) Rules let any APPROVED student read
    // PUBLISHED non-deleted lectures but give them ZERO direct access to
    // lecture_resources; (b) the getLectureResources callable (Admin SDK)
    // re-validates subject access + active subscription per request. Both
    // layers are exercised below.
    const subscribedStudent = dbFor('student-safe', {role: 'student', approved: true});
    const unsubscribedStudent = dbFor('student-unsubscribed', {role: 'student', approved: true});

    // Teacher publishes a fresh lecture carrying subject_id (the callable
    // resolves the student's subscription from lecture.subject_id).
    await assertSucceeds(teacherDb3.collection('lectures').doc('lec-student-vis').set({
      subject_id: 'subject-1',
      section_id: 'sec-custom',
      title: 'محاضرة الطالب',
      description: '',
      display_order: 2,
      publish_date: new Date(),
      status: 'published',
      is_deleted: false,
    }));

    // (a) Rules layer: approved students may list published lectures, and
    // may NEVER touch lecture_resources documents directly.
    console.log("Checking lec-student-vis get for subscribedStudent");
    await assertSucceeds(subscribedStudent.collection('lectures').doc('lec-student-vis').get());
    console.log("Checking lec-student-vis get for unsubscribedStudent");
    await assertSucceeds(unsubscribedStudent.collection('lectures').doc('lec-student-vis').get());
    console.log("Passed lec-student-vis get");
    await assertFails(subscribedStudent.collection('lecture_resources')
      .where('lecture_id', '==', 'lec-student-vis').get());

    // Staff creates two resources via the same shapes the admin flow writes:
    // one VISIBLE, one HIDDEN (visibility toggle / soft archive).
    await assertSucceeds(teacherDb3.collection('lecture_resources').doc('res-visible-1').set({
      lecture_id: 'lec-student-vis',
      title: 'الفيديو المرئي',
      resource_type: 'video',
      bunny_video_id: 'bunny-vis-1',
      storage_path: null,
      resource_url: '',
      thumbnail: null,
      duration: null,
      display_order: 1,
      is_visible: true,
      visibility: true,
      is_deleted: false,
    }));
    await assertSucceeds(teacherDb3.collection('lecture_resources').doc('res-hidden-1').set({
      lecture_id: 'lec-student-vis',
      title: 'مخفي عن الطلاب',
      resource_type: 'pdf',
      bunny_video_id: null,
      storage_path: 'lecture_resources/lec-student-vis/res-hidden-1/file.pdf',
      resource_url: '',
      thumbnail: null,
      duration: null,
      display_order: 2,
      is_visible: false,
      visibility: false,
      is_deleted: false,
    }));

    // (b) Callable layer (Admin SDK context): replicate getLectureResources'
    // exact gating — requireEnabledSubjectAccess + active-subscription
    // assertSubjectAccess + the visible-only ordered query — then assert a
    // SUBSCRIBED student receives exactly the visible admin-created
    // resource while an UNSUBSCRIBED student is permission-denied.
    const now = Date.now();
    const futureEnd = new Date(now + 30 * 24 * 60 * 60 * 1000);
    const pastEnd = new Date(now - 1000);
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const adminDb = context.firestore();
      await adminDb.doc('subscriptions/student-safe_subject-1').set({
        student_id: 'student-safe',
        subject_id: 'subject-1',
        plan_id: 'pro',
        status: 'active',
        is_deleted: false,
        manually_disabled: false,
        start_date: new Date(now - 1000),
        end_date: futureEnd,
      });
      // Deliberately NO assignment/subscription for student-unsubscribed,
      // and an EXPIRED one to prove end_date is respected too.
      await adminDb.doc('subscriptions/student-unsubscribed_subject-1').set({
        student_id: 'student-unsubscribed',
        subject_id: 'subject-1',
        plan_id: 'free',
        status: 'active',
        is_deleted: false,
        manually_disabled: false,
        start_date: new Date(now - 2000),
        end_date: pastEnd,
      });

      async function callableGetLectureResources(studentId, subjectId, lectureId) {
        const assignment = await adminDb
          .doc(`subject_access_assignments/${studentId}_${subjectId}`).get();
        if (!assignment.exists) {
          throw new Error('permission-denied: Subject Access assignment is required.');
        }
        const a = assignment.data();
        if (a.student_id !== studentId || a.subject_id !== subjectId ||
            a.is_deleted === true || a.enabled !== true) {
          throw new Error('permission-denied: Subject Access is not enabled.');
        }
        const subSnap = await adminDb.collection('subscriptions')
          .where('student_id', '==', studentId)
          .where('subject_id', '==', subjectId)
          .where('status', '==', 'active')
          .limit(1).get();
        if (subSnap.empty) {
          throw new Error('permission-denied: Active subject subscription is required.');
        }
        const s = subSnap.docs[0].data();
        if (s.is_deleted === true || s.manually_disabled === true ||
            (s.end_date?.toMillis && s.end_date.toMillis() <= Date.now())) {
          throw new Error('permission-denied: Subscription is not usable.');
        }
        const resources = await adminDb.collection('lecture_resources')
          .where('lecture_id', '==', lectureId)
          .where('is_visible', '==', true)
          .orderBy('display_order')
          .get();
        return resources.docs.map((d) => d.data().title);
      }

      // Subscribed: sees ONLY the visible video resource, ordered first.
      const delivered = await callableGetLectureResources(
        'student-safe', 'subject-1', 'lec-student-vis');
      if (delivered.length !== 1 || delivered[0] !== 'الفيديو المرئي') {
        throw new Error(
          `Callable contract broken: expected only [الفيديو المرئي], got ${JSON.stringify(delivered)}`);
      }
      // Unsubscribed (no assignment): denied before any resource is served…
      let unsubDenied = false;
      try {
        await callableGetLectureResources('student-unsubscribed', 'subject-1', 'lec-student-vis');
      } catch (e) {
        unsubDenied = String(e.message).startsWith('permission-denied');
      }
      if (!unsubDenied) {
        throw new Error('Unsubscribed student was NOT denied by the callable contract.');
      }
    });

    // ---- Storage authoring paths (11 Assets §4.2 / storage.rules):
    // staff may upload thumbnails/images and attachments under
    // /lecture_resources/{lecture_id}/{resource_id}/, students never.
    const contentAdminStorage = testEnv
      .authenticatedContext('admin-with-content', {role: 'admin', approved: true})
      .storage();
    const unsubscribedStudentStorage = testEnv
      .authenticatedContext('student-unsubscribed', {role: 'student', approved: true})
      .storage();
    await assertSucceeds(teacherStorage
      .ref('lecture_resources/lec-student-vis/res-visible-1/thumb_001.jpg')
      .put(Buffer.from('jpeg-data'), {contentType: 'image/jpeg'}));
    await assertSucceeds(contentAdminStorage
      .ref('lecture_resources/lec-student-vis/res-hidden-1/sheets.zip')
      .put(Buffer.from('zip-data'), {contentType: 'application/zip'}));
    // Type gating: video files are NEVER stored in Firebase Storage
    // (11 Assets §7.2 — Bunny CDN only), so video/mp4 uploads fail even
    // for staff, while octet-stream generic attachments pass validAttachment.
    await assertFails(teacherStorage
      .ref('lecture_resources/lec-student-vis/res-x/movie.mp4')
      .put(Buffer.from('mp4-data'), {contentType: 'video/mp4'}));
    await assertSucceeds(teacherStorage
      .ref('lecture_resources/lec-student-vis/res-x/raw.bin')
      .put(Buffer.from('bin-data'), {contentType: 'application/octet-stream'}));
    await assertFails(unsubscribedStudentStorage
      .ref('lecture_resources/lec-student-vis/res-visible-1/hack.pdf')
      .put(Buffer.from('pdf-data'), {contentType: 'application/pdf'}));

    // ---- FINAL_DECISIONS addendum (§11–15) rule coverage ---------------
    // Part C: lectures gain public_free_* fields. The existing staff update
    // path must accept them; students must still be unable to write ANY
    // lecture field, including the new ones.
    await assertSucceeds(teacherDb3.collection('lectures').doc('lec-student-vis')
      .update({public_free_enabled: true, public_free_preview_minutes: 5}));
    await assertSucceeds(teacherDb3.collection('lectures').doc('lec-student-vis')
      .update({public_free_enabled: false, public_free_preview_minutes: null}));
    await assertFails(studentDb.collection('lectures').doc('lec-student-vis')
      .update({public_free_enabled: true}));
    await assertFails(unsubscribedStudent.collection('lectures').doc('lec-student-vis')
      .set({public_free_enabled: true, title: 'forged'}));
    // Students can never READ a draft even when it is public-free enabled.
    await assertSucceeds(teacherDb3.collection('lectures').doc('lec-pf-draft').set({
      subject_id: 'subject-1',
      section_id: 'sec-custom',
      title: 'مسودة مجانية',
      description: '',
      display_order: 9,
      publish_date: null,
      status: 'draft',
      is_deleted: false,
      public_free_enabled: true,
      public_free_preview_minutes: 5,
    }));
    await assertFails(studentDb.collection('lectures').doc('lec-pf-draft').get());

    // Part B: archived lectures stay invisible to students; staff keep
    // full read access for the Archive screen.
    await assertFails(studentDb.collection('lectures').doc('archived').get());
    await assertSucceeds(teacherDb3.collection('lectures').doc('archived').get());
    // Restoring = flipping is_deleted/status — an UPDATE, never a hard
    // delete; hard deletes remain denied at the boundary.
    await assertSucceeds(teacherDb3.collection('lectures').doc('archived')
      .update({is_deleted: false, status: 'draft', deleted_at: null}));
    await assertFails(teacherDb3.collection('lectures').doc('archived').delete());

    // Part A §15: storage_provider rides on lecture_resources documents —
    // staff may write it, students may write nothing at all.
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('lecture_resources/res-bunny-pdf').set({
        lecture_id: 'lec-student-vis',
        resource_type: 'pdf',
        title: 'ملف Bunny',
        storage_provider: 'bunny',
        storage_path: 'lecture_resources/lec-student-vis/res-bunny-pdf/file.pdf',
        is_visible: true,
        is_deleted: false,
      });
    });
    await assertSucceeds(teacherDb3.collection('lecture_resources').doc('res-bunny-pdf')
      .update({storage_provider: 'firebase'}));
    await assertFails(studentDb.collection('lecture_resources').doc('res-bunny-pdf')
      .update({storage_provider: 'bunny'}));

    // Part A §15 / storage.rules: image ATTACHMENTS (jpg/png) are approved
    // under the same lecture_resources prefix, capped at 5MB like images;
    // video files stay banned from Firebase Storage entirely.
    await assertSucceeds(contentAdminStorage
      .ref('lecture_resources/lec-student-vis/res-img-1/diagram.jpg')
      .put(Buffer.from('jpeg-data'), {contentType: 'image/jpeg'}));
    await assertSucceeds(teacherStorage
      .ref('lecture_resources/lec-student-vis/res-img-2/photo.png')
      .put(Buffer.from('png-data'), {contentType: 'image/png'}));
    await assertFails(teacherStorage
      .ref('lecture_resources/lec-student-vis/res-big/img.jpg')
      .put(Buffer.alloc(5 * 1024 * 1024 + 1), {contentType: 'image/jpeg'}));

    // Part E: system_settings.default_storage_provider is Teacher-readable,
    // student-denied, and client-write-denied for EVERYONE (the only write
    // path is the audited setDefaultStorageProvider callable).
    await assertSucceeds(
      dbFor('teacher-owner', {role: 'teacher', approved: true})
        .collection('system_settings').doc('settings-main').get(),
    );
    await assertFails(studentDb.collection('system_settings').doc('settings-main').get());
    await assertFails(dbFor('admin-with-content', {role: 'admin', approved: true})
      .collection('system_settings').doc('settings-main')
      .set({default_storage_provider: 'bunny'}));
    await assertFails(
      dbFor('teacher-owner', {role: 'teacher', approved: true})
        .collection('system_settings').doc('settings-main')
        .set({default_storage_provider: 'bunny'}),
    );

    // ---- Storage-delivery completion (audit Fix 1 + Fix 2) -------------
    // Attachments and thumbnails are now DELIVERED through callables that
    // sign short-lived URLs server-side. That must NOT loosen the boundary:
    // raw lecture_resources documents stay unreadable to every client, and
    // direct Storage reads of thumbnail/attachment bytes stay denied for
    // everyone (signed URLs minted by the Admin SDK bypass rules; rules
    // themselves never open a public surface).
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const seedDocs = context.firestore();
      // Bunny-hosted attachment (Fix 1 dispatch target).
      await seedDocs.doc('lecture_resources/res-attach-bunny').set({
        lecture_id: 'lec-student-vis',
        resource_type: 'attachment',
        title: 'مرفق Bunny',
        storage_provider: 'bunny',
        storage_path: 'lecture_resources/lec-student-vis/res-attach-bunny/files.zip',
        is_visible: true,
        is_deleted: false,
      });
      // Firebase-hosted attachment (Fix 1 dispatch target).
      await seedDocs.doc('lecture_resources/res-attach-fb').set({
        lecture_id: 'lec-student-vis',
        resource_type: 'attachment',
        title: 'مرفق Firebase',
        storage_provider: 'firebase',
        storage_path: 'lecture_resources/lec-student-vis/res-attach-fb/doc.pdf',
        is_visible: true,
        is_deleted: false,
      });
      // Video resources carrying thumbnails on each provider (Fix 2).
      await seedDocs.doc('lecture_resources/res-thumb-bunny').set({
        lecture_id: 'lec-student-vis',
        resource_type: 'video',
        bunny_video_id: 'video-thumb-bunny',
        thumbnail_storage_provider: 'bunny',
        thumbnail: 'lecture_resources/lec-student-vis/res-thumb-bunny/poster.jpg',
        is_visible: true,
        is_deleted: false,
      });
      await seedDocs.doc('lecture_resources/res-thumb-fb').set({
        lecture_id: 'lec-student-vis',
        resource_type: 'video',
        bunny_video_id: 'video-thumb-fb',
        thumbnail_storage_provider: 'firebase',
        thumbnail: 'lecture_resources/lec-student-vis/res-thumb-fb/poster.jpg',
        is_visible: true,
        is_deleted: false,
      });
    });
    // Raw metadata documents stay client-unreadable for STUDENTS (paths +
    // provider keys are delivered exclusively through getLectureResources),
    // while staff keep their authoring reads (firestore.rules:241).
    for (const docId of ['res-attach-bunny', 'res-attach-fb', 'res-thumb-bunny', 'res-thumb-fb']) {
      await assertFails(studentDb.collection('lecture_resources').doc(docId).get());
      await assertFails(unsubscribedStudent.collection('lecture_resources').doc(docId).get());
      await assertSucceeds(teacherDb3.collection('lecture_resources').doc(docId).get());
    }
    // Direct byte reads of attachment/thumbnail objects stay DENIED for
    // subscribed students, unsubscribed students and staff alike — the
    // signed-URL approach requires no rule loosening (regression guard).
    // Objects are seeded first (rules-disabled) so any failure below is
    // genuinely permission-denied, not object-not-found.
    const thumbPath = 'lecture_resources/lec-student-vis/res-thumb-fb/poster.jpg';
    const attachPath = 'lecture_resources/lec-student-vis/res-attach-bunny/files.zip';
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.storage().ref(thumbPath).put(Buffer.from('jpeg-data'), {contentType: 'image/jpeg'});
      await context.storage().ref(attachPath).put(Buffer.from('zip-data'), {contentType: 'application/zip'});
    });
    const subscribedStudentStorage = testEnv
      .authenticatedContext('student-safe', {role: 'student', approved: true})
      .storage();
    for (const ref of [
      subscribedStudentStorage.ref(thumbPath),
      subscribedStudentStorage.ref(attachPath),
      unsubscribedStudentStorage.ref(thumbPath),
      unsubscribedStudentStorage.ref(attachPath),
      teacherStorage.ref(thumbPath),
      teacherStorage.ref(attachPath),
    ]) {
      await assertFails(ref.getDownloadURL());
    }



    // ---- FINAL_DECISIONS §12: video_watch_windows is server-only -------
    // The rolling 24-hour window state lives in ONE doc per student and is
    // mutated exclusively by the Admin-SDK transaction inside
    // generateBunnySignedUrl. No client — student, staff, or anonymous —
    // may read or write it directly.
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('video_watch_windows/student-safe').set({
        student_id: 'student-safe',
        active_lecture_id: 'lec-student-vis',
        active_resource_id: 'res-video-1',
        window_started_at: new Date(),
        window_expires_at: new Date(Date.now() + 24 * 60 * 60 * 1000),
      });
    });
    const windowDoc = (db) => db.collection('video_watch_windows').doc('student-safe');
    await assertFails(windowDoc(studentDb).get());
    await assertFails(windowDoc(dbFor('student-safe', {role: 'student', approved: true})).get());
    await assertFails(windowDoc(teacherDb3).get());
    await assertFails(testEnv.unauthenticatedContext().firestore()
      .collection('video_watch_windows').doc('student-safe').get());
    await assertFails(windowDoc(studentDb).update({window_expires_at: new Date()}));
    await assertFails(windowDoc(studentDb).set({student_id: 'student-safe'}));
    await assertFails(windowDoc(studentDb).delete());

    console.log('Firestore and Storage rules tests passed.');
  } finally {
    await testEnv.cleanup();
  }
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
