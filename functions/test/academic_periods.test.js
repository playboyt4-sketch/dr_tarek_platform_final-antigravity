/**
 * Unit tests for the academic-period lifecycle Cloud Functions.
 *
 * Covers the mandatory cases from the Phase-1 brief:
 *  - setAcademicPeriodStatus / setSubscriptionDisciplinaryStatus reject any
 *    caller that is not the Teacher (Platform Owner).
 *  - Starting a period stamps started_at; ending it stamps ended_at and
 *    automatically expires every subscription bound to the period with
 *    end_date = ended_at in the same batch.
 *  - createExceptionalAcademicPeriod creates is_core=false periods.
 */
const test = require("firebase-functions-test")({
  projectId: "dr-tarek-platform-functions-test",
});

const assert = require("node:assert/strict");

const firestoreState = new Map();
const auditLog = [];

function makeDocRef(path) {
  return {
    id: path.split("/").pop(),
    path,
    get: async () => {
      const data = firestoreState.get(path);
      return {
        exists: data !== undefined,
        data: () => data,
      };
    },
    set: async (data, options) => {
      if (options && options.merge && firestoreState.has(path)) {
        firestoreState.set(path, {...firestoreState.get(path), ...data});
      } else {
        firestoreState.set(path, data);
      }
    },
    update: async (data) => {
      firestoreState.set(path, {...(firestoreState.get(path) ?? {}), ...data});
    },
  };
}

function makeQuery(name, filters = []) {
  return {
    where: (field, op, value) => makeQuery(name, [...filters, {field, op, value}]),
    limit: () => makeQuery(name, filters),
    get: async () => {
      const docs = [];
      for (const [path, data] of firestoreState.entries()) {
        if (!path.startsWith(`${name}/`)) continue;
        const matches = filters.every(({field, value}) => data[field] === value);
        if (matches) {
          docs.push({
            id: path.split("/").pop(),
            data: () => data,
            ref: makeDocRef(path),
          });
        }
      }
      return {empty: docs.length === 0, docs};
    },
  };
}

function makeCollection(name) {
  return {
    doc: (id) => makeDocRef(`${name}/${id ?? `auto_${Math.random().toString(36).slice(2)}`}`),
    where: (field, op, value) => makeQuery(name, [{field, op, value}]),
    add: async (data) => {
      auditLog.push({collection: name, data});
      return makeDocRef(`${name}/auto_${auditLog.length}`);
    },
  };
}

// Minimal firebase-admin mock surface used by the functions under test.
const adminMock = {
  initializeApp: () => ({}),
  getFirestore: () => ({
    collection: makeCollection,
    batch: () => {
      const ops = [];
      return {
        update: (ref, data) => ops.push(() => ref.update(data)),
        set: (ref, data) => ops.push(() => ref.set(data)),
        commit: async () => Promise.all(ops.map((op) => op())),
      };
    },
    runTransaction: async (callback) =>
      callback({
        get: (ref) => ref.get(),
        update: (ref, data) => ref.update(data),
        set: (ref, data, options) => {
          if (ref.path && ref.path.startsWith("admin_audit_log")) {
            auditLog.push({collection: "admin_audit_log", data});
          }
          return ref.set(data, options);
        },
      }),
  }),
  getAuth: () => ({
    setCustomUserClaims: async () => {},
  }),
  getMessaging: () => ({}),
  getStorage: () => ({}),
  FieldValue: {
    serverTimestamp: () => ({_serverTimestamp: true}),
  },
  Timestamp: {
    now: () => ({toMillis: () => Date.now()}),
  },
};

const Module = require("node:module");
const originalRequire = Module.prototype.require;
Module.prototype.require = function (id) {
  if (id === "firebase-admin/firestore") {
    return {
      getFirestore: adminMock.getFirestore,
      FieldValue: adminMock.FieldValue,
      Timestamp: adminMock.Timestamp,
    };
  }
  if (id === "firebase-admin/auth") return {getAuth: adminMock.getAuth};
  if (id === "firebase-admin/messaging") {
    return {getMessaging: adminMock.getMessaging};
  }
  if (id === "firebase-admin/storage") return {getStorage: adminMock.getStorage};
  if (id === "firebase-admin/app") return {initializeApp: adminMock.initializeApp};
  return originalRequire.apply(this, arguments);
};

let functions;
try {
  functions = require("../lib/index.js");
} catch (error) {
  console.error("Failed to load functions:", error);
  process.exit(1);
} finally {
  Module.prototype.require = originalRequire;
}

function teacherRequest(data) {
  return {auth: {uid: "teacher-1", token: {role: "teacher"}}, data};
}

function adminRequest(data) {
  return {auth: {uid: "admin-1", token: {role: "admin"}}, data};
}

function studentRequest(data) {
  return {auth: {uid: "student-1", token: {role: "student"}}, data};
}

async function expectPermissionDenied(promise, label) {
  try {
    await promise;
    assert.fail(`${label}: expected rejection but call succeeded`);
  } catch (error) {
    // requireTeacher rejects unauthenticated callers with "unauthenticated"
    // and authenticated non-teacher callers with "permission-denied".
    assert.ok(
      ["permission-denied", "unauthenticated"].includes(error.code),
      `${label}: unexpected error code ${error.code}`,
    );
  }
}

async function run() {
  // 1) Teacher-only guards.
  await expectPermissionDenied(
    functions.setAcademicPeriodStatus.run(
      adminRequest({periodId: "term_1", status: "active"}),
    ),
    "setAcademicPeriodStatus(admin)",
  );
  await expectPermissionDenied(
    functions.setAcademicPeriodStatus.run(
      studentRequest({periodId: "term_1", status: "active"}),
    ),
    "setAcademicPeriodStatus(student)",
  );
  await expectPermissionDenied(
    functions.setAcademicPeriodStatus.run(
      {data: {periodId: "term_1", status: "active"}},
    ),
    "setAcademicPeriodStatus(anonymous)",
  );
  await expectPermissionDenied(
    functions.setSubscriptionDisciplinaryStatus.run(
      adminRequest({subscriptionId: "sub-1", disabled: true}),
    ),
    "setSubscriptionDisciplinaryStatus(admin)",
  );
  await expectPermissionDenied(
    functions.createExceptionalAcademicPeriod.run(
      adminRequest({label: "تدريب فردي"}),
    ),
    "createExceptionalAcademicPeriod(admin)",
  );

  // 2) Lifecycle: start then end, with automatic subscription expiry.
  firestoreState.set("academic_periods/term_1", {
    id: "term_1",
    period_type: "term_1",
    label: "الترم الأول",
    is_core: true,
    status: "ended",
    is_deleted: false,
  });

  await functions.setAcademicPeriodStatus.run(
    teacherRequest({periodId: "term_1", status: "active"}),
  );
  const started = firestoreState.get("academic_periods/term_1");
  assert.equal(started.status, "active");
  assert.ok(started.started_at, "started_at must be stamped on activation");
  assert.equal(started.ended_at, null);

  // Ending the period expires bound subscriptions with end_date = ended_at.
  firestoreState.set("subscriptions/sub-1", {
    student_id: "student-1",
    subject_id: "subject-1",
    academic_period_id: "term_1",
    status: "active",
  });

  await functions.setAcademicPeriodStatus.run(
    teacherRequest({periodId: "term_1", status: "ended"}),
  );
  const ended = firestoreState.get("academic_periods/term_1");
  assert.equal(ended.status, "ended");
  assert.ok(ended.ended_at, "ended_at must be stamped on termination");

  // The subscription bound to the ended period must be expired with
  // end_date equal to the period ended_at (same batch semantics).
  const expiredSubscription = firestoreState.get("subscriptions/sub-1");
  assert.equal(expiredSubscription.status, "expired");
  assert.equal(
    expiredSubscription.end_date,
    ended.ended_at,
    "subscription end_date must equal the period ended_at",
  );

  // 3) Exceptional period creation writes the approved schema.
  const result = await functions.createExceptionalAcademicPeriod.run(
    teacherRequest({label: "تدريب فردي"}),
  );
  assert.equal(result.success, true);
  const created = firestoreState.get(`academic_periods/${result.periodId}`);
  assert.equal(created.is_core, false);
  assert.equal(created.label, "تدريب فردي");
  assert.equal(created.status, "ended");
  assert.equal(created.created_by, "teacher-1");

  // 4) Audit log entries were recorded for lifecycle changes.
  const periodAudits = auditLog.filter(
    (entry) => entry.collection === "admin_audit_log" &&
      entry.data.target_type === "academic_period",
  );
  assert.ok(periodAudits.length >= 3, "audit log must record period changes");

  console.log("Academic period function tests passed.");
}

run()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(() => test.cleanup());
