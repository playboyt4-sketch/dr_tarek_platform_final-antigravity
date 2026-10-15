/**
 * migrate_teacher_to_doctor operator tests (ADR-005).
 *
 * Offline harness with fake Firestore/Auth deps injected into
 * scripts/migrate_teacher_to_doctor.cjs runOperator(). NEVER touches
 * production, the emulator, or real credentials: no initializeApp, no
 * network, no GOOGLE_APPLICATION_CREDENTIALS.
 */
const assert = require("node:assert/strict");

const op = require("../../scripts/migrate_teacher_to_doctor.cjs");

const OWNER = "2B1pvLZ0p5W3hwoXlBi1rUtp0Iy2";

function ownerDoc(role) {
  return {
    id: OWNER,
    full_name: "Owner Name",
    display_handle: "Dr/owner",
    profile_photo: "",
    phone_number: "01000000000",
    role,
    student_type: null,
    approval_status: "approved",
    account_status: "active",
    is_active: true,
    force_password_change: false,
    created_at: "2026-01-01",
    updated_at: "2026-01-02",
    created_by: "bootstrap",
    updated_by: "bootstrap",
  };
}

function makeFakes({doc, teacherIds, claims, markers}) {
  const calls = {updates: [], claimsWrites: [], audits: [], collections: []};
  let stored = doc === undefined ? undefined : JSON.parse(JSON.stringify(doc));
  const markerDocs = (markers || []).map((m, i) => ({id: `marker-${i}`, ...m}));
  const db = {
    collection: (name) => {
      calls.collections.push(name);
      if (name === "users") {
        return {
          doc: (id) => ({
            get: async () => (stored === undefined
              ? {exists: false}
              : {exists: true, id, data: () => JSON.parse(JSON.stringify(stored))}),
            update: async (patch) => {
              calls.updates.push({id, patch});
              stored = {...stored, ...patch};
            },
          }),
          where: (field) => ({
            get: async () => {
              if (field === "migration_id") {
                throw new Error("users has no migration_id query");
              }
              return {docs: teacherIds.map((id) => ({id}))};
            },
          }),
        };
      }
      if (name === "admin_audit_log") {
        return {
          where: () => ({
            get: async () => ({
              docs: markerDocs.map((m) => ({id: m.id, data: () => ({...m})})),
            }),
          }),
          add: async (entry) => {
            calls.audits.push(entry);
            markerDocs.push({id: `marker-${markerDocs.length}`, ...entry});
            return {id: "marker-1"};
          },
        };
      }
      throw new Error(`unexpected collection access: ${name}`);
    },
  };
  const auth = {
    getUser: async (uid) => ({uid, customClaims: {...claims}}),
    setCustomUserClaims: async (uid, next) => {
      calls.claimsWrites.push({uid, next});
    },
  };
  const fieldValue = {serverTimestamp: () => "TS"};
  const logs = [];
  const log = (...a) => logs.push(a.join(" "));
  return {db, auth, fieldValue, calls, logs, log};
}

const baseClaims = {role: "teacher", approved: true, max_devices: 5};

async function expectAbort(deps, opts, fragment) {
  let error = null;
  try {
    await op.runOperator(deps, opts, deps.log);
  } catch (err) {
    error = err;
  }
  assert.ok(error, `expected abort for ${fragment}`);
  assert.match(error.message, /ABORT/);
  assert.equal(deps.calls.updates.length, 0, "no doc writes on abort");
  assert.equal(deps.calls.claimsWrites.length, 0, "no claims writes on abort");
  assert.equal(deps.calls.audits.length, 0, "no audit writes on abort");
  console.log(`ok - abort: ${fragment}`);
}

async function run() {
  // ---- Dry run: teacher owner reports migration, zero writes ----
  {
    const f = makeFakes({doc: ownerDoc("teacher"), teacherIds: [OWNER], claims: baseClaims});
    const res = await op.runOperator(f, {dryRun: true}, f.log);
    assert.equal(res.state, "MIGRATE");
    assert.equal(res.wrote, false);
    assert.equal(f.calls.updates.length, 0);
    assert.equal(f.calls.claimsWrites.length, 0);
    assert.equal(f.calls.audits.length, 0);
    assert.ok(!f.calls.collections.includes("user_secrets"), "secrets collection never touched");
    console.log("ok - dry-run: teacher owner reports migration with zero writes");
  }

  // ---- Dry-run aborts ----
  {
    const f = makeFakes({doc: ownerDoc("teacher"), teacherIds: [OWNER], claims: baseClaims});
    await expectAbort(f, {dryRun: true, uid: "someone-else"}, "wrong UID");
  }
  {
    const f = makeFakes({doc: ownerDoc("teacher"), teacherIds: [OWNER], claims: baseClaims});
    await expectAbort(f, {dryRun: true, project: "wrong-project"}, "wrong project");
  }
  {
    const f = makeFakes({doc: undefined, teacherIds: [], claims: {}});
    await expectAbort(f, {dryRun: true}, "missing user");
  }
  {
    const f = makeFakes({doc: ownerDoc("admin"), teacherIds: [], claims: {role: "admin"}});
    await expectAbort(f, {dryRun: true}, "unexpected role admin");
  }
  {
    const f = makeFakes({doc: ownerDoc("teacher"), teacherIds: [OWNER, "second-owner"], claims: baseClaims});
    await expectAbort(f, {dryRun: true}, "second teacher candidate");
  }

  // ---- Idempotency: doctor owner with marker present, no write ----
  {
    const f = makeFakes({
      doc: ownerDoc("doctor"),
      teacherIds: [],
      claims: {role: "doctor", approved: true, max_devices: 5},
      markers: [{target_uid: OWNER, action: "role_migrated_teacher_to_doctor"}],
    });
    const res = await op.runOperator(f, {confirm: true}, f.log);
    assert.equal(res.state, "ALREADY_MIGRATED");
    assert.equal(res.wrote, false);
    assert.equal(f.calls.updates.length, 0);
    assert.equal(f.calls.claimsWrites.length, 0);
    assert.equal(f.calls.audits.length, 0);
    console.log("ok - idempotent: migrated owner with marker performs zero writes");
  }

  // ---- Recovery: doctor owner WITHOUT marker records exactly the marker ----
  {
    const f = makeFakes({
      doc: ownerDoc("doctor"),
      teacherIds: [],
      claims: {role: "doctor", approved: true, max_devices: 5},
      markers: [],
    });
    const res = await op.runOperator(f, {confirm: true}, f.log);
    assert.equal(res.state, "ALREADY_MIGRATED");
    assert.equal(res.wrote, true);
    assert.equal(f.calls.updates.length, 0, "role never rewritten");
    assert.equal(f.calls.claimsWrites.length, 0, "claims never written");
    assert.equal(f.calls.audits.length, 1);
    assert.equal(f.calls.audits[0].action, "role_migrated_teacher_to_doctor");
    assert.equal(f.calls.audits[0].actor_role, "doctor");
    // Second run is now a pure no-op: no duplicate marker.
    const f2 = makeFakes({
      doc: ownerDoc("doctor"),
      teacherIds: [],
      claims: {role: "doctor", approved: true, max_devices: 5},
      markers: [{target_uid: OWNER, action: "role_migrated_teacher_to_doctor"}],
    });
    const res2 = await op.runOperator(f2, {confirm: true}, f2.log);
    assert.equal(res2.wrote, false);
    console.log("ok - recovery: missing marker recorded once, never duplicated");
  }

  // ---- Migration: teacher -> doctor, role-only write, claims untouched ----
  {
    const f = makeFakes({doc: ownerDoc("teacher"), teacherIds: [OWNER], claims: baseClaims});
    const res = await op.runOperator(f, {confirm: true}, f.log);
    assert.equal(res.state, "MIGRATE");
    assert.equal(res.wrote, true);
    assert.equal(f.calls.updates.length, 1);
    assert.equal(f.calls.updates[0].id, OWNER);
    assert.deepEqual(f.calls.updates[0].patch, {role: "doctor"});
    assert.equal(f.calls.claimsWrites.length, 0, "no manual claims write; login flow mints claims");
    assert.equal(f.calls.audits.length, 1);
    assert.equal(f.calls.audits[0].action, "role_migrated_teacher_to_doctor");
    assert.equal(f.calls.audits[0].actor_role, "doctor");
    assert.equal(f.calls.audits[0].previous_role, "teacher");
    assert.ok(!f.calls.collections.includes("user_secrets"), "secrets collection never touched");
    console.log("ok - migration: role-only teacher -> doctor, claims untouched, marker recorded");
  }

  // ---- Rollback: doctor -> teacher, UID-gated, role-only ----
  {
    const f = makeFakes({
      doc: ownerDoc("doctor"),
      teacherIds: [],
      claims: {role: "doctor", approved: true, max_devices: 5},
    });
    const res = await op.runOperator(f, {rollback: true, confirm: true}, f.log);
    assert.equal(res.state, "ROLLBACK");
    assert.equal(res.wrote, true);
    assert.deepEqual(f.calls.updates[0].patch, {role: "teacher"});
    assert.equal(f.calls.claimsWrites.length, 0, "no manual claims write on rollback either");
    assert.equal(f.calls.audits[0].action, "role_migrated_doctor_to_teacher_rollback");
    console.log("ok - rollback: role-only doctor -> teacher for expected UID");
  }
  {
    const f = makeFakes({
      doc: ownerDoc("doctor"),
      teacherIds: [],
      claims: {role: "doctor"},
    });
    await expectAbort(f, {rollback: true, confirm: true, uid: "someone-else"}, "rollback wrong UID");
  }
  {
    // Rollback without --confirm performs zero writes.
    const f = makeFakes({
      doc: ownerDoc("doctor"),
      teacherIds: [],
      claims: {role: "doctor"},
    });
    await expectAbort(f, {rollback: true}, "rollback without confirm");
  }

  // ---- Pure helpers ----
  {
    const before = {role: "teacher", name: "x", n: 1};
    assert.deepEqual(op.preservedFieldDiff(before, {...before, role: "doctor"}), []);
    assert.deepEqual(
      op.preservedFieldDiff(before, {...before, role: "doctor", name: "y"}),
      ["name"],
    );
    assert.equal(op.decideState({docExists: true, role: "teacher"}).valueOf(), "MIGRATE");
    assert.equal(op.decideState({docExists: true, role: "doctor"}).valueOf(), "ALREADY_MIGRATED");
    console.log("ok - pure helpers: field diff, state machine");
  }

  console.log("migrate_teacher_to_doctor.test: PASS");
}

run().catch((error) => {
  console.error(`FAIL: ${error.message}`);
  process.exit(1);
});
