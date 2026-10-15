/**
 * lock_event.test.js — audit-only lock-transition event in recordLoginFailure.
 *
 * Runs against compiled ../lib/index.js with an in-memory Firestore/Auth
 * mock (same pattern as password_reset.test.js). No emulator, no network.
 *
 * Verified behaviors (student-IP scope via verifyPhonePassword):
 *  1. failures 1-4 emit no lock event.
 *  2. 5th failure (fresh lock transition) emits exactly one
 *     auth_security_events doc {event_type login_lock_engaged}.
 *  3. event carries scope/fail_count/lock_minutes, hashed key_hash —
 *     never raw phone/IP/name, never secrets.
 *  4. 6th attempt blocked; no second event (no per-rejection spam).
 *  5. after expiry, next lock transition emits again (bounded, not spammy).
 */
const test = require("firebase-functions-test")({
  projectId: "dr-tarek-platform-functions-test",
});

const assert = require("node:assert/strict");
const crypto = require("node:crypto");

const store = {};
const captured = { securityEvents: [] };

function docRef(collPath, docId) {
  const key = `${collPath}/${docId}`;
  return {
    id: docId,
    get: async () => {
      if (store[key] === undefined) return { exists: false };
      return { exists: true, data: () => store[key] };
    },
    set: async (data, options) => {
      if (collPath === "auth_security_events") captured.securityEvents.push(data);
      if (options && options.merge && store[key] !== undefined) {
        store[key] = { ...store[key], ...data };
      } else {
        store[key] = { ...data };
      }
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
      doc: (docId) => docRef(collPath, docId || `auto-${Math.random()}`),
      add: async (data) => {
        if (collPath === "auth_security_events") captured.securityEvents.push(data);
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

const verifyPhonePassword = test.wrap(functions.verifyPhonePassword);

const IP = "10.9.0.1";

async function attempt(phone) {
  try {
    await verifyPhonePassword({
      data: { phoneNumber: phone, password: "Wrong1!" },
      auth: null,
      rawRequest: { ip: IP },
    });
    return null;
  } catch (err) {
    return err;
  }
}

function lockEvents() {
  return captured.securityEvents.filter((e) => e.event_type === "login_lock_engaged");
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

  const phones = ["01030000001", "01030000002", "01030000003", "01030000004", "01030000005"];

  // 1: first four failures emit no lock event.
  for (let i = 0; i < 4; i++) {
    const err = await attempt(phones[i]);
    if (!err || err.code !== "unauthenticated") {
      fail(`fail${i + 1}`, `unexpected ${err && err.code}`);
    }
  }
  if (lockEvents().length === 0) ok("failures 1-4 emit no lock event");
  else fail("no-early-event", `got ${lockEvents().length}`);

  // 2+3: 5th failure engages the lock and emits exactly one event.
  const err5 = await attempt(phones[4]);
  if (!err5 || err5.code !== "unauthenticated") fail("fail5", `unexpected ${err5 && err5.code}`);
  const events = lockEvents();
  if (events.length !== 1) {
    fail("one-event", `expected 1, got ${events.length}`);
  } else {
    const e = events[0];
    const expectedHash = crypto.createHash("sha256").update(`student_login_ip:${IP}`).digest("hex");
    const serialized = JSON.stringify(e);
    if (
      e.scope === "student_login_ip" &&
      e.key_hash === expectedHash &&
      e.fail_count === 5 &&
      e.lock_minutes === 10 &&
      e.created_by === "system" &&
      !/10\.9\.0\.1/.test(serialized) &&
      !/0103000000/.test(serialized) &&
      !/password|token|secret/i.test(serialized) &&
      e.key_hash !== undefined
    ) {
      ok("lock transition emits one hashed, secret-free event");
    } else {
      fail("event-shape", serialized);
    }
  }

  // 4: blocked 6th attempt adds no second event.
  const err6 = await attempt("01030000006");
  if (!err6 || err6.code !== "resource-exhausted") fail("blocked", `unexpected ${err6 && err6.code}`);
  else if (lockEvents().length === 1) ok("blocked attempt emits no duplicate event");
  else fail("no-dup", `got ${lockEvents().length}`);

  // 5: after expiry, the next transition emits again (bounded).
  const docId = crypto.createHash("sha256").update(`student_login_ip:${IP}`).digest("hex");
  const doc = store[`login_throttle/${docId}`];
  store[`login_throttle/${docId}`] = {
    ...doc,
    locked_until: { toMillis: () => Date.now() - 1000, toDate: () => new Date(Date.now() - 1000) },
  };
  const err7 = await attempt("01030000007");
  if (!err7 || err7.code !== "unauthenticated") fail("post-expiry", `unexpected ${err7 && err7.code}`);
  else if (lockEvents().length === 2) ok("post-expiry transition emits again (bounded)");
  else fail("re-emit", `got ${lockEvents().length}`);

  test.cleanup();

  if (process.exitCode === 1) {
    console.error("lock_event tests FAILED");
    process.exit(1);
  }
  console.log(`lock_event.test: PASS - All ${passed} checks passed.`);
}

run();
