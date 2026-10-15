/**
 * content_audit.test.js — contentAuditTrigger canonical role attribution.
 *
 * Runs against compiled ../lib/index.js with an in-memory Firestore mock
 * (same pattern as password_reset.test.js). No emulator, no network.
 *
 * Verified behaviors (onSectionWritten as representative trigger):
 *  1. updated_by doctor uid -> actor_role doctor (server-resolved).
 *  2. updated_by admin uid -> actor_role admin.
 *  3. unknown actor (no users doc) -> historical fallback staff_content.
 *  4. created_by used when updated_by absent.
 *  5. neither present -> unknown_staff + staff_content fallback.
 *  6. spoofed role in the doc cannot forge attribution (role comes from
 *     the server-side users doc, never the event payload).
 */
const test = require("firebase-functions-test")({
  projectId: "dr-tarek-platform-functions-test",
});

const assert = require("node:assert/strict");

const store = {};
const captured = { audit: [] };

function docRef(collPath, docId) {
  const key = `${collPath}/${docId}`;
  return {
    id: docId,
    get: async () => {
      if (store[key] === undefined) return { exists: false };
      return { exists: true, data: () => store[key] };
    },
    set: async (data) => {
      store[key] = { ...data };
    },
    update: async (data) => {
      if (store[key] !== undefined) store[key] = { ...store[key], ...data };
    },
  };
}

const adminMock = {
  initializeApp: () => ({}),
  getFirestore: () => ({
    collection: (collPath) => ({
      where: () => ({
        limit: () => ({ get: async () => ({ empty: true, docs: [] }) }),
        get: async () => ({ empty: true, docs: [] }),
      }),
      doc: (docId) => docRef(collPath, docId || "auto"),
      add: async (data) => {
        if (collPath === "admin_audit_log") captured.audit.push(data);
        return { id: "mock-id" };
      },
    }),
    runTransaction: async (fn) =>
      fn({
        get: (ref) => ref.get(),
        update: (ref, data) => ref.update(data),
        set: (ref, data, options) => ref.set(data, options),
      }),
    batch: () => ({ set: () => {}, update: () => {}, delete: () => {}, commit: async () => {} }),
  }),
  FieldValue: { serverTimestamp: () => ({}), delete: () => ({ __delete: true }) },
  Timestamp: {
    now: () => ({ toMillis: () => Date.now() }),
    fromDate: (d) => ({ toMillis: () => d.getTime(), toDate: () => d }),
    fromMillis: (ms) => ({ toMillis: () => ms, toDate: () => new Date(ms) }),
  },
  getAuth: () => ({
    updateUser: async () => {},
    getUser: async () => ({ customClaims: {} }),
    setCustomUserClaims: async () => {},
    createCustomToken: async () => "mock-token",
    createUser: async () => ({ uid: "new-uid" }),
  }),
  getMessaging: () => ({}),
  getStorage: () => ({}),
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
  if (id === "firebase-admin/auth") return { getAuth: adminMock.getAuth };
  if (id === "firebase-admin/messaging") return { getMessaging: adminMock.getMessaging };
  if (id === "firebase-admin/storage") return { getStorage: adminMock.getStorage };
  if (id === "firebase-admin/app") return { initializeApp: adminMock.initializeApp };
  return originalRequire.apply(this, arguments);
};

let functions;
try {
  functions = require("../lib/index.js");
} catch (error) {
  console.error("Failed to load functions:", error);
  process.exit(1);
}

const onSectionWritten = test.wrap(functions.onSectionWritten);

function changeEvent(doc) {
  // Real snapshot objects (encodable by the wrap harness); before is an
  // empty doc so the change reads as an update — attribution assertions
  // are unaffected.
  const before = test.firestore.makeDocumentSnapshot({}, "subject_sections/sec-1");
  const after = test.firestore.makeDocumentSnapshot(doc, "subject_sections/sec-1");
  return {
    data: { before, after },
    params: { docId: "sec-1" },
  };
}

async function run() {
  let passed = 0;
  const ok = (name) => {
    passed++;
    console.log(`ok - ${name}`);
  };
  const fail = (name, detail) => {
    console.error(`FAIL - ${name}: ${detail}`);
    process.exitCode = 1;
  };
  function lastAudit() {
    return captured.audit[captured.audit.length - 1];
  }

  store["users/doctor-1"] = { role: "doctor" };
  store["users/admin-1"] = { role: "admin" };
  store["users/student-1"] = { role: "student" };

  // 1: doctor attribution.
  await onSectionWritten(changeEvent({ updated_by: "doctor-1" }));
  if (lastAudit() && lastAudit().actor_id === "doctor-1" && lastAudit().actor_role === "doctor") {
    ok("doctor writer -> actor_role doctor");
  } else {
    fail("doctor", JSON.stringify(lastAudit()));
  }

  // 2: admin attribution.
  await onSectionWritten(changeEvent({ updated_by: "admin-1" }));
  if (lastAudit() && lastAudit().actor_role === "admin") ok("admin writer -> actor_role admin");
  else fail("admin", JSON.stringify(lastAudit()));

  // 3: unknown actor -> historical fallback.
  await onSectionWritten(changeEvent({ updated_by: "ghost-9" }));
  if (lastAudit() && lastAudit().actor_id === "ghost-9" && lastAudit().actor_role === "staff_content") {
    ok("unknown actor -> staff_content fallback");
  } else {
    fail("fallback", JSON.stringify(lastAudit()));
  }

  // 4: created_by fallback when updated_by absent.
  await onSectionWritten(changeEvent({ created_by: "admin-1" }));
  if (lastAudit() && lastAudit().actor_id === "admin-1" && lastAudit().actor_role === "admin") {
    ok("created_by fallback resolves admin");
  } else {
    fail("created-by", JSON.stringify(lastAudit()));
  }

  // 5: neither field -> unknown_staff + fallback.
  await onSectionWritten(changeEvent({ title: "x" }));
  if (lastAudit() && lastAudit().actor_id === "unknown_staff" && lastAudit().actor_role === "staff_content") {
    ok("missing attribution -> unknown_staff fallback");
  } else {
    fail("missing", JSON.stringify(lastAudit()));
  }

  // 6: role comes from the server-side users doc, not the payload —
  // a student uid in updated_by cannot forge a staff role.
  await onSectionWritten(changeEvent({ updated_by: "student-1" }));
  if (lastAudit() && lastAudit().actor_role === "staff_content") {
    ok("non-staff uid cannot forge staff role");
  } else {
    fail("spoof", JSON.stringify(lastAudit()));
  }

  test.cleanup();

  if (process.exitCode === 1) {
    console.error("content_audit tests FAILED");
    process.exit(1);
  }
  console.log(`content_audit.test: PASS - All ${passed} checks passed.`);
}

run();
