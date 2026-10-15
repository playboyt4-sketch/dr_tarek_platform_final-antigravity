/**
 * reset_claim.test.js — single-flight claim for onPasswordResetApproved.
 *
 * Runs against compiled ../lib/index.js with an in-memory Firestore/Auth
 * mock (same pattern as password_reset.test.js). No emulator, no network.
 *
 * Verified behaviors:
 *  1. pending request approved by doctor -> {resolved:true}, ends resolved.
 *  2. second approval by a DIFFERENT actor while processing -> rejected
 *     (failed-precondition), Auth untouched by the contender.
 *  3. same-actor reclaim of a processing request -> proceeds (crash retry).
 *  4. resolved request -> rejected (failed-precondition, not pending).
 *  5. missing request -> not-found.
 *  6. claimed_by/at recorded on claim; preserved after resolve.
 */
const test = require("firebase-functions-test")({
  projectId: "dr-tarek-platform-functions-test",
});

const assert = require("node:assert/strict");

const store = {};
const captured = { updateUser: [], audit: [] };

function docRef(collPath, docId) {
  const key = `${collPath}/${docId}`;
  return {
    id: docId,
    get: async () => {
      if (store[key] === undefined) return { exists: false };
      return { exists: true, data: () => store[key] };
    },
    set: async (data, options) => {
      if (options && options.merge && store[key] !== undefined) {
        store[key] = { ...store[key], ...data };
      } else {
        store[key] = { ...data };
      }
    },
    // Merge into seeded docs only (request status transitions are
    // tracked); writes to unseeded collections (users/user_secrets) are
    // ignored, mirroring password_reset.test.js.
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
      doc: (docId) => docRef(collPath, docId),
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
  FieldValue: { serverTimestamp: () => ({ _ts: true }), delete: () => ({ __delete: true }) },
  Timestamp: {
    now: () => ({ toMillis: () => Date.now() }),
    fromDate: (d) => ({ toMillis: () => d.getTime(), toDate: () => d }),
    fromMillis: (ms) => ({ toMillis: () => ms, toDate: () => new Date(ms) }),
  },
  getAuth: () => ({
    updateUser: async (uid, props) => {
      captured.updateUser.push({ uid, props });
    },
    getUser: async () => ({ customClaims: { role: "student", approved: true } }),
    setCustomUserClaims: async () => {},
    revokeRefreshTokens: async () => {},
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

const onPasswordResetApproved = test.wrap(functions.onPasswordResetApproved);

const doctorA = { uid: "doctor-a", token: { role: "doctor" } };
const doctorB = { uid: "doctor-b", token: { role: "doctor" } };

async function approve(auth, requestId, newPassword) {
  return onPasswordResetApproved({
    data: { requestId, newPassword: newPassword || "Aa1!bcde" },
    auth,
  });
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

  // 1: pending -> approved, ends resolved with claim history.
  // Target-role hardening (item 11): approval requires an existing
  // student-kind target user; fixtures provide student targets.
  store["users/stu-1"] = { role: "student", approval_status: "approved" };
  store["users/stu-2"] = { role: "student", approval_status: "approved" };
  store["password_reset_requests/req-ok"] = { status: "pending", student_id: "stu-1" };
  try {
    const res = await approve(doctorA, "req-ok");
    if (res && res.resolved === true) ok("pending approved -> resolved");
    else fail("approve", JSON.stringify(res));
  } catch (err) {
    fail("approve", `${err.code}: ${err.message}`);
  }
  const done = store["password_reset_requests/req-ok"];
  if (done.status === "resolved" && done.claimed_by === "doctor-a" && done.resolved_by === "doctor-a") {
    ok("claim history preserved (claimed_by/resolved_by)");
  } else {
    fail("history", JSON.stringify(done));
  }

  // 2: contender while processing -> rejected, Auth untouched.
  store["password_reset_requests/req-race"] = { status: "pending", student_id: "stu-2" };
  captured.updateUser.length = 0;
  // Simulate a concurrent claim by doctor-a without resolving: run only the
  // claim by approving... instead directly set processing to model the
  // interleaving (claim is transactional; contender must observe it).
  store["password_reset_requests/req-race"] = {
    status: "processing",
    claimed_by: "doctor-a",
    student_id: "stu-2",
  };
  try {
    await approve(doctorB, "req-race");
    fail("contender", "expected failure, got success");
  } catch (err) {
    if (err.code === "failed-precondition" && /already being processed/.test(err.message)) {
      ok("different-actor contender while processing -> rejected");
    } else {
      fail("contender", `${err.code}: ${err.message}`);
    }
  }
  if (captured.updateUser.length === 0) ok("contender performed zero Auth writes");
  else fail("contender-writes", JSON.stringify(captured.updateUser));

  // 3: same-actor reclaim of processing -> proceeds.
  try {
    const res = await approve(doctorA, "req-race");
    if (res && res.resolved === true) ok("same-actor reclaim proceeds (crash retry)");
    else fail("reclaim", JSON.stringify(res));
  } catch (err) {
    fail("reclaim", `${err.code}: ${err.message}`);
  }

  // 4: resolved -> rejected.
  try {
    await approve(doctorB, "req-ok");
    fail("resolved", "expected failure, got success");
  } catch (err) {
    if (err.code === "failed-precondition") ok("resolved request -> rejected");
    else fail("resolved", `${err.code}: ${err.message}`);
  }

  // 5: missing -> not-found.
  try {
    await approve(doctorA, "req-missing");
    fail("missing", "expected failure, got success");
  } catch (err) {
    if (err.code === "not-found") ok("missing request -> not-found");
    else fail("missing", `${err.code}: ${err.message}`);
  }

  // 6: single audit record per completed approval (no double-audit on
  // rejected contender path above).
  const approvals = captured.audit.filter((a) => a.action === "password_reset_approved");
  if (approvals.length === 2) ok("exactly 2 approval audits for 2 completions");
  else fail("audit-count", `expected 2, got ${approvals.length}`);

  test.cleanup();

  if (process.exitCode === 1) {
    console.error("reset_claim tests FAILED");
    process.exit(1);
  }
  console.log(`reset_claim.test: PASS - All ${passed} checks passed.`);
}

run();
