const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');

const projectId = 'dr-tarek-platform';
const root = path.resolve(__dirname, '..');
let testEnv;

function dbFor(uid, token = {}) {
  return testEnv.authenticatedContext(uid, token).firestore();
}

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    
    // Seed subjects and lectures
    await db.doc('subjects/subject-test').set({
      id: 'subject-test',
      is_deleted: false,
      is_visible: true,
      status: 'published'
    });
    
    await db.doc('lectures/lecture-test').set({
      id: 'lecture-test',
      subject_id: 'subject-test',
      is_deleted: false,
      status: 'published'
    });

    await db.doc('lecture_resources/resource-test').set({
      id: 'resource-test',
      lecture_id: 'lecture-test',
      subject_id: 'subject-test',
      is_deleted: false,
      status: 'published'
    });

    // Seed students
    await db.doc('users/student-with-notes').set({
      id: 'student-with-notes',
      role: 'student',
      approval_status: 'approved',
      student_type: 'center_student'
    });
    
    await db.doc('users/student-without-notes').set({
      id: 'student-without-notes',
      role: 'student',
      approval_status: 'approved'
    });

    await db.doc('users/student-expired').set({
      id: 'student-expired',
      role: 'student',
      approval_status: 'approved'
    });
    
    await db.doc('users/student-no-access').set({
      id: 'student-no-access',
      role: 'student',
      approval_status: 'approved'
    });

    // Seed access assignments
    await db.doc('subject_access_assignments/student-with-notes_subject-test').set({
      student_id: 'student-with-notes',
      subject_id: 'subject-test',
      enabled: true,
      is_deleted: false,
      entitlements: ['notes.create', 'bookmarks.create'],
      // expiry in future
      subscription_expires_at: new Date(Date.now() + 1000 * 60 * 60 * 24 * 30)
    });

    await db.doc('subject_access_assignments/student-without-notes_subject-test').set({
      student_id: 'student-without-notes',
      subject_id: 'subject-test',
      enabled: true,
      is_deleted: false,
      entitlements: [],
      subscription_expires_at: new Date(Date.now() + 1000 * 60 * 60 * 24 * 30)
    });

    await db.doc('subject_access_assignments/student-expired_subject-test').set({
      student_id: 'student-expired',
      subject_id: 'subject-test',
      enabled: true,
      is_deleted: false,
      entitlements: ['notes.create', 'bookmarks.create'],
      // expiry in past
      subscription_expires_at: new Date(Date.now() - 1000)
    });

    // Seed notes and bookmarks
    await db.doc('notes/note-1').set({
      student_id: 'student-with-notes',
      subject_id: 'subject-test'
    });
    
    await db.doc('bookmarks/bookmark-1').set({
      student_id: 'student-with-notes',
      subject_id: 'subject-test'
    });
  });
}

async function run() {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8'),
    }
  });
  
  process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";

  try {
    await seed();

    console.log("=== Running Entitlements Tests ===");

    // Test 1: Protected Content Access
    console.log("Test: Protected content (lecture_resources) access");
    // With access
    await assertSucceeds(dbFor('student-with-notes', {role: 'student', approved: true}).doc('lecture_resources/resource-test').get());
    // Without access (no assignment doc)
    await assertFails(dbFor('student-no-access', {role: 'student', approved: true}).doc('lecture_resources/resource-test').get());

    // Test 2: Teacher reads remain unaffected
    console.log("Test: Teacher/Admin reads unaffected");
    await assertSucceeds(dbFor('teacher-1', {role: 'teacher'}).doc('lecture_resources/resource-test').get());

    // Test 3: Notes & Bookmarks (entitlement + ownership)
    console.log("Test: Notes & Bookmarks access (entitlement + ownership)");
    // Student with notes.create entitlement can read/create their own notes
    await assertSucceeds(dbFor('student-with-notes', {role: 'student', approved: true}).doc('notes/note-1').get());
    await assertSucceeds(dbFor('student-with-notes', {role: 'student', approved: true}).collection('notes').add({
      student_id: 'student-with-notes',
      subject_id: 'subject-test'
    }));
    
    // Cannot read another student's notes
    await assertFails(dbFor('student-without-notes', {role: 'student', approved: true}).doc('notes/note-1').get());

    // Seed their own note first to test they cannot read THEIR OWN note without the entitlement
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('notes/note-without-notes-user').set({
        student_id: 'student-without-notes',
        subject_id: 'subject-test'
      });
    });

    // Student WITHOUT entitlement cannot read their own existing notes even for their subject
    await assertFails(dbFor('student-without-notes', {role: 'student', approved: true}).doc('notes/note-without-notes-user').get());

    // Student WITHOUT entitlement cannot create notes even for their subject
    await assertFails(dbFor('student-without-notes', {role: 'student', approved: true}).collection('notes').add({
      student_id: 'student-without-notes',
      subject_id: 'subject-test'
    }));

    // Test 4: Expiry Bounds
    console.log("Test: Expiry Bounds");
    // Seed their own note first
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('notes/note-expired-user').set({
        student_id: 'student-expired',
        subject_id: 'subject-test'
      });
    });

    // Student with expired subscription is denied read access to their existing note despite having entitlement array
    await assertFails(dbFor('student-expired', {role: 'student', approved: true}).doc('notes/note-expired-user').get());

    // Student with expired subscription is denied create access
    await assertFails(dbFor('student-expired', {role: 'student', approved: true}).doc('notes/new-note').set({
      student_id: 'student-expired',
      subject_id: 'subject-test'
    }));

    // Test 5: Fan-out Trigger
    console.log("Test: Fan-out Trigger (simulate plan_features update)");
    
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const adminDb = context.firestore();
      // Seed a plan and subscription for the fan-out test
      await adminDb.doc('plan_features/feature-notes').set({
        plan_id: 'plan-1',
        feature_key: 'notes.create',
        enabled: false,
        feature_value: false
      });
      
      await adminDb.doc('subscriptions/sub-1').set({
        student_id: 'fanout-student',
        subject_id: 'subject-test',
        plan_id: 'plan-1',
        status: 'active'
      });
      
      await adminDb.doc('subject_access_assignments/fanout-student_subject-test').set({
        student_id: 'fanout-student',
        subject_id: 'subject-test',
        enabled: true,
        entitlements: ['old.entitlement']
      });

      // Trigger fan-out by updating the feature to enabled: true
      await adminDb.doc('plan_features/feature-notes').update({
        enabled: true
      });

      // Wait for cloud function to execute (poll up to 45 seconds)
      console.log("Waiting up to 45 seconds for fan-out trigger (emulator cold starts can be slow)...");
      let entitlements = [];
      const maxRetries = 90; // 90 * 500ms = 45 seconds
      let success = false;
      
      for (let i = 0; i < maxRetries; i++) {
        await new Promise(r => setTimeout(r, 500));
        const updatedAssignment = await adminDb.doc('subject_access_assignments/fanout-student_subject-test').get();
        entitlements = updatedAssignment.data().entitlements;
        
        if (entitlements && entitlements.includes('notes.create')) {
          success = true;
          break;
        }
      }
      
      if (success) {
        console.log("Fan-out test passed: entitlements updated!");
      } else {
        console.error("Fan-out test failed: entitlements not updated within 20 seconds. Current array:", entitlements);
        process.exit(1);
      }
    });

    console.log("=== All Entitlements Tests Passed ===");

  } catch (error) {
    console.error("Test failed:", error);
    process.exit(1);
  } finally {
    await testEnv.cleanup();
  }
}

run();
