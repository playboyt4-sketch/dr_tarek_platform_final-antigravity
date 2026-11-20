/**
 * ADR-010 — Firestore Rules enforcement of the server-owned association.
 *
 * Proves the client-side half of the security model:
 *  - `bunny_library_id` can never be created, changed or removed by a client
 *    (including a content manager with valid `admin_content` delegation),
 *  - `created_at` is mandatory on create and immutable on update (the issuance
 *    gate relies on it to distinguish a pending row from a genuine legacy row),
 *  - a VERIFIED row's `bunny_video_id` is immutable to clients, while a
 *    PENDING/legacy row may still be authored,
 *  - unrelated permitted updates and PDF rows are unchanged, and
 *  - the trusted server (Admin SDK) can write the association.
 */
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

const GUID_A = '11111111-aaaa-4aaa-8aaa-000000000001';
const GUID_B = '22222222-bbbb-4bbb-8bbb-000000000002';

function contentManagerDb() {
  return testEnv.authenticatedContext('admin-content', {
    role: 'admin',
    approved: true,
  }).firestore();
}

function plainAdminDb() {
  return testEnv.authenticatedContext('admin-plain', {
    role: 'admin',
    approved: true,
  }).firestore();
}

const baseRow = {
  lecture_id: 'lec-1',
  subject_id: 'sub-1',
  resource_type: 'video',
  title: 'Video',
  display_order: 1,
  bunny_video_id: null,
  is_visible: true,
  is_deleted: false,
};

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.doc('admin_permissions/admin-content').set({
      admin_id: 'admin-content',
      is_active: true,
      permissions: {admin_content: true},
    });
    await db.doc('admin_permissions/admin-plain').set({
      admin_id: 'admin-plain',
      is_active: true,
      permissions: {admin_students: true},
    });
    await db.doc('lectures/lec-1').set({
      subject_id: 'sub-1',
      section_id: 'sec-1',
      title: 'Lecture',
      status: 'published',
      is_deleted: false,
    });
    // Verified row: server-written association.
    await db.doc('lecture_resources/res-verified').set({
      ...baseRow,
      bunny_video_id: GUID_A,
      bunny_library_id: '736742',
      created_at: new Date('2026-12-01T00:00:00Z'),
    });
    // Pending row: created after the cutover, no association yet.
    await db.doc('lecture_resources/res-pending').set({
      ...baseRow,
      created_at: new Date('2026-12-01T00:00:00Z'),
    });
    await db.doc('lecture_resources/res-pdf').set({
      ...baseRow,
      resource_type: 'pdf',
      bunny_video_id: null,
      created_at: new Date('2026-12-01T00:00:00Z'),
    });
  });
}

let passed = 0;
async function ok(name, promise) {
  await promise;
  passed += 1;
  console.log(`ok - ${name}`);
}

async function denied(name, promise) {
  await assertFails(promise);
  passed += 1;
  console.log(`ok - ${name}`);
}

async function run() {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {rules: fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8')},
  });
  await testEnv.clearFirestore();
  await seed();

  const admin = contentManagerDb();
  const {serverTimestamp, deleteField} = require('firebase/firestore');

  // --- create -----------------------------------------------------------
  await ok('content manager creates a pending video row (no association)',
    assertSucceeds(admin.collection('lecture_resources').doc('res-new').set({
      ...baseRow,
      created_at: serverTimestamp(),
    })));

  await denied('client cannot create a row WITH bunny_library_id',
    admin.collection('lecture_resources').doc('res-lib').set({
      ...baseRow,
      bunny_library_id: '736742',
      created_at: serverTimestamp(),
    }));

  await denied('client cannot create a row without created_at',
    admin.collection('lecture_resources').doc('res-nostamp').set({
      ...baseRow,
    }));

  await denied('client cannot forge an old created_at to look legacy',
    admin.collection('lecture_resources').doc('res-forged-legacy').set({
      ...baseRow,
      created_at: new Date('2020-01-01T00:00:00Z'),
    }));

  await denied('admin without admin_content cannot create resources',
    plainAdminDb().collection('lecture_resources').doc('res-plain').set({
      ...baseRow,
      created_at: serverTimestamp(),
    }));

  // --- update: association is immutable to clients ----------------------
  await denied('client cannot ADD bunny_library_id to a pending row',
    admin.collection('lecture_resources').doc('res-pending').update({
      bunny_library_id: '736742',
      bunny_video_id: GUID_A,
    }));

  await denied('client cannot CHANGE a stored bunny_library_id',
    admin.collection('lecture_resources').doc('res-verified').update({
      bunny_library_id: '775315',
    }));

  await denied('client cannot REMOVE a stored bunny_library_id',
    admin.collection('lecture_resources').doc('res-verified').update({
      bunny_library_id: null,
    }));

  await denied('client cannot swap the Video ID under a verified association',
    admin.collection('lecture_resources').doc('res-verified').update({
      bunny_video_id: GUID_B,
    }));

  await denied('client cannot change resource_type',
    admin.collection('lecture_resources').doc('res-pdf').update({
      resource_type: 'video',
      bunny_video_id: GUID_A,
    }));

  // --- update: created_at is immutable (Mission 6) ----------------------
  await denied('client cannot BACKDATE created_at on an existing row',
    admin.collection('lecture_resources').doc('res-pending').update({
      created_at: new Date('2020-01-01T00:00:00Z'),
    }));

  await denied('client cannot NULLIFY created_at',
    admin.collection('lecture_resources').doc('res-pending').update({
      created_at: null,
    }));

  await denied('client cannot DELETE created_at with deleteField()',
    admin.collection('lecture_resources').doc('res-pending').update({
      created_at: deleteField(),
    }));

  await ok('update that leaves created_at unchanged is still allowed',
    assertSucceeds(admin.collection('lecture_resources').doc('res-pending').update({
      title: 'Still pending',
    })));

  await denied('admin without admin_content cannot update resources',
    plainAdminDb().collection('lecture_resources').doc('res-pending').update({
      title: 'Unauthorized rename',
    }));

  await ok('content manager can still create with serverTimestamp()',
    assertSucceeds(admin.collection('lecture_resources').doc('res-new-2').set({
      ...baseRow,
      created_at: serverTimestamp(),
    })));

  // --- update: permitted operations still work -------------------------
  await ok('unrelated update on a verified row still works',
    assertSucceeds(admin.collection('lecture_resources').doc('res-verified').update({
      title: 'Renamed',
      display_order: 2,
    })));

  await ok('pending row may still have its Video ID authored',
    assertSucceeds(admin.collection('lecture_resources').doc('res-pending').update({
      bunny_video_id: GUID_A,
    })));

  await ok('PDF row keeps working without any association',
    assertSucceeds(admin.collection('lecture_resources').doc('res-pdf').update({
      title: 'Handout',
      resource_url: 'https://example.com/file.pdf',
    })));

  // --- trusted server write --------------------------------------------
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await ok('trusted server persists the association',
      db.doc('lecture_resources/res-pending').update({
        bunny_video_id: GUID_A,
        bunny_library_id: '736742',
      }));
  });

  // --- reads unchanged --------------------------------------------------
  await ok('staff can still read lecture resources',
    assertSucceeds(admin.collection('lecture_resources').doc('res-verified').get()));

  console.log(`adr010_association_rules: ${passed} assertions passed`);
  await testEnv.cleanup();
}

run().catch(async (error) => {
  console.error('Rules test failed:', error);
  if (testEnv) await testEnv.cleanup();
  process.exit(1);
});
