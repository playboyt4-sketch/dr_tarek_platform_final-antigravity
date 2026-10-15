/**
 * staff_lock_stretch.test.js — Staff/Doctor/Admin per-name lockout must not
 * stretch while the lock is active (lockout-DoS hardening).
 *
 * Approved decision: once a staff identity is already inside an active
 * lockout period, additional wrong-password attempts must NOT increment its
 * failure counter, extend the existing lockout, or create a new lockout
 * period. The existing lock remains valid until its original locked_until
 * expires; after expiry, normal failure counting resumes per existing
 * policy. Scope is staff_login ONLY: IP throttles, student login,
 * registration, change-password, enumeration, thresholds, durations, the
 * response contract, and all other behavior are unchanged.
 *
 * Runs against compiled ../lib/index.js with an in-memory Firestore/Auth
 * mock (same pattern as staff_login_throttle.test.js). No emulator, no
 * network.
 *
 * Verified behaviors:
 *  1.  existing failure sequence unchanged (fails 1-2 -> unauthenticated,
 *      no lock; fail 3 -> unauthenticated + lock at existing threshold).
 *  2.  lock created at existing threshold with existing ladder duration
 *      (3 fails -> ~5 minutes).
 *  3.  wrong password while locked does NOT increment fail_count.
 *  4.  wrong password while locked does NOT extend locked_until (exact ms).
 *  5.  multiple wrong attempts while locked keep the original expiry.
 *  6.  a concurrent attempt that passed the pre-check before the lock
 *      committed is a no-op (fail_count and locked_until untouched) and
 *      still returns the generic unauthenticated response.
 *  7.  after lock expiry, failure counting resumes normally (fail 4 +
 *      fresh ladder lock).
 *  8.  IP throttle unchanged (5 distributed fails -> unauthenticated;
 *      6th -> resource-exhausted; ~10min ladder).
 *  9.  student authentication + enumeration unchanged.
 *  10. ambiguous-name behavior unchanged.
 */
const test = require("firebase-functions-test")({
  projectId: "dr-tarek-platform-functions-test",
});

const assert = require("node:assert/strict");
const crypto = require("node:crypto");

const store = {};

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
    update: async (data) => {
      if (store[key] !== undefined) store[key] = { ...store[key], ...data };
    },
    delete: async () => {
      delete store[key];
    },
  };
}

let USERS = [];

function usersQuery(field, op, value) {
  const docs = USERS.filter((u) => {
    if (op === "==") return u.data[field] === value;
    if (op === "in") return Array.isArray(value) && value.includes(u.data[field]);
    return false;
  }).map((u) => ({ id: u.id, data: () => u.data, ref: docRef("users", u.id) }));
  return {
    limit: () => ({ get: async () => ({ empty: docs.length === 0, docs }) }),
    get: async () => ({ empty: docs.length === 0, docs }),
  };
}

const adminMock = {
  initializeApp: () => ({}),
  getFirestore: () => ({
    collection: (collPath) => {
      if (collPath === "users") return { where: usersQuery, doc: (id) => docRef(collPath, id), add: async () => ({}) };
      return {
        where: () => ({
          limit: () => ({ get: async () => ({ empty: true, docs: [] }) }),
          get: async () => ({ empty: true, docs: [] }),
        }),
        doc: (docId) => docRef(collPath, docId),
        add: async () => ({}),
      };
    },
    runTransaction: async (fn) =>
      fn({
        get: (ref) => ref.get(),
        update: (ref, data) => ref.update(data),
        set: (ref, data, options) => ref.set(data, options),
      }),
    batch: () => ({ set: () => {}, update: () => {}, delete: () => {}, commit: async () => {} }),
  }),
  FieldValue: { serverTimestamp: () => ({}), delete: () => ({ __delete: true }) },
  Timestamp: class MockTimestamp {
    constructor(ms) {
      this.ms = ms;
    }
    toMillis() {
      return this.ms;
    }
    toDate() {
      return new Date(this.ms);
    }
    static now() {
      return new MockTimestamp(Date.now());
    }
    static fromDate(d) {
      return new MockTimestamp(d.getTime());
    }
    static fromMillis(ms) {
      return new MockTimestamp(ms);
    }
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

const verifyStaffPassword = test.wrap(functions.verifyStaffPassword);
const verifyPhonePassword = test.wrap(functions.verifyPhonePassword);

function fixtureHash(password) {
  const salt = Buffer.from("00112233445566778899aabbccddeeff", "hex");
  const derived = crypto.scryptSync(password, salt, 64, { N: 16384, r: 8, p: 1 });
  return `scrypt$${salt.toString("hex")}$${derived.toString("hex")}$16384`;
}

function throttleDocId(scope, key) {
  return crypto.createHash("sha256").update(`${scope}:${key}`).digest("hex");
}

function staffDoc(name) {
  return store[`login_throttle/${throttleDocId("staff_login", name.toLowerCase())}`];
}

async function staffAttempt(name, password, ip) {
  try {
    await verifyStaffPassword({
      data: { displayName: name, password },
      auth: null,
      rawRequest: ip ? { ip } : {},
    });
    return null;
  } catch (err) {
    return err;
  }
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

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

  USERS = [
    { id: "doc-1", data: { full_name: "Dr Owner", role: "doctor", account_status: "active" } },
    { id: "race-1", data: { full_name: "Race User", role: "admin", account_status: "active" } },
  ];
  store["user_secrets/doc-1"] = { password_hash: fixtureHash("OwnerPass1!") };
  store["user_secrets/race-1"] = { password_hash: fixtureHash("RacePass1!") };

  // 1: existing failure sequence unchanged (fails 1-2, no lock yet).
  for (let i = 1; i <= 2; i++) {
    const err = await staffAttempt("Dr Owner", "Wrong1!");
    if (!err || err.code !== "unauthenticated") fail(`seq-fail${i}`, `expected unauthenticated, got ${err && err.code}`);
    const doc = staffDoc("Dr Owner");
    if (!doc || doc.fail_count !== i) fail(`seq-count${i}`, `expected fail_count ${i}, got ${doc && doc.fail_count}`);
    if (doc && doc.locked_until !== undefined) fail(`seq-nolock${i}`, "lock created before threshold");
  }
  ok("fails 1-2 -> unauthenticated, fail_count 1-2, no lock (unchanged)");

  // 2: lock created at the existing threshold with the existing duration.
  const err3 = await staffAttempt("Dr Owner", "Wrong1!");
  if (!err3 || err3.code !== "unauthenticated") fail("threshold", `expected unauthenticated, got ${err3 && err3.code}`);
  const lockedDoc = staffDoc("Dr Owner");
  if (!lockedDoc || lockedDoc.fail_count !== 3) fail("threshold-count", `expected fail_count 3, got ${lockedDoc && lockedDoc.fail_count}`);
  const remainingMs = lockedDoc.locked_until.toMillis() - Date.now();
  if (!(remainingMs > 4 * 60 * 1000 && remainingMs <= 5 * 60 * 1000)) {
    fail("threshold-duration", `expected ~5min ladder, got ${remainingMs}ms`);
  }
  ok(`lock created at existing threshold (fail 3, ~5min ladder, ${Math.round(remainingMs / 1000)}s remaining)`);
  const originalExpiryMs = lockedDoc.locked_until.toMillis();

  // 3-5: wrong passwords while locked change nothing.
  for (let i = 4; i <= 6; i++) {
    const err = await staffAttempt("Dr Owner", "Wrong1!");
    if (!err || err.code !== "resource-exhausted") fail(`locked-attempt${i}`, `expected resource-exhausted, got ${err && err.code}`);
    const doc = staffDoc("Dr Owner");
    if (doc.fail_count !== 3) fail(`locked-count${i}`, `fail_count stretched to ${doc.fail_count}`);
    if (doc.locked_until.toMillis() !== originalExpiryMs) {
      fail(`locked-expiry${i}`, `locked_until moved by ${doc.locked_until.toMillis() - originalExpiryMs}ms`);
    }
  }
  ok("attempts 4-6 while locked -> resource-exhausted, fail_count stays 3, original expiry kept (exact ms)");

  // 6: concurrent attempt that passed the pre-check before the lock
  // committed is a no-op inside recordLoginFailure.
  await staffAttempt("Race User", "Wrong1!");
  await staffAttempt("Race User", "Wrong1!");
  if (staffDoc("Race User").fail_count !== 2) fail("race-setup", "expected primed fail_count 2");
  const pending = staffAttempt("Race User", "Wrong1!");
  // Yield macrotasks so the attempt passes the lock pre-check and the
  // users/secret reads and is inside password verification; the mock
  // scrypt takes orders of magnitude longer, so it cannot have recorded yet.
  await sleep(0);
  await sleep(0);
  // Simulate the concurrent committer: exactly what a committed 3rd failure
  // writes (fail_count 3 + 5-minute ladder lock).
  const raceExpiryMs = Date.now() + 5 * 60 * 1000;
  const raceKey = `login_throttle/${throttleDocId("staff_login", "race user")}`;
  store[raceKey] = {
    ...store[raceKey],
    fail_count: 3,
    locked_until: new adminMock.Timestamp(raceExpiryMs),
  };
  const raceErr = await pending;
  let racePass = true;
  if (!raceErr || raceErr.code !== "unauthenticated") {
    fail("race-contract", `expected generic unauthenticated, got ${raceErr && raceErr.code}`);
    racePass = false;
  }
  const raceDoc = staffDoc("Race User");
  if (raceDoc.fail_count !== 3) {
    fail("race-count", `concurrent failure incremented to ${raceDoc.fail_count}`);
    racePass = false;
  }
  if (raceDoc.locked_until.toMillis() !== raceExpiryMs) {
    fail("race-expiry", `concurrent failure moved locked_until by ${raceDoc.locked_until.toMillis() - raceExpiryMs}ms`);
    racePass = false;
  }
  if (racePass) ok("in-flight concurrent failure while locked is a no-op (count + expiry untouched, generic response)");

  // 7: after lock expiry, normal failure counting resumes.
  store[`login_throttle/${throttleDocId("staff_login", "dr owner")}`] = {
    ...staffDoc("Dr Owner"),
    locked_until: new adminMock.Timestamp(Date.now() - 1000),
  };
  const errAfter = await staffAttempt("Dr Owner", "Wrong1!");
  if (!errAfter || errAfter.code !== "unauthenticated") fail("expiry", `expected unauthenticated, got ${errAfter && errAfter.code}`);
  const resumed = staffDoc("Dr Owner");
  if (resumed.fail_count !== 4) fail("expiry-count", `expected resumed fail_count 4, got ${resumed.fail_count}`);
  const resumedMs = resumed.locked_until.toMillis() - Date.now();
  if (!(resumedMs > 4 * 60 * 1000 && resumedMs <= 5 * 60 * 1000)) {
    fail("expiry-lock", `expected fresh ~5min ladder lock, got ${resumedMs}ms`);
  }
  ok("after expiry, counting resumes (fail 4 + fresh ladder lock)");

  // 8: IP throttle unchanged.
  const IP = "10.40.0.1";
  const names = ["Nobody A", "Nobody B", "Nobody C", "Nobody D", "Nobody E", "Nobody F"];
  for (let i = 0; i < 5; i++) {
    const err = await staffAttempt(names[i], "Wrong1!", IP);
    if (!err || err.code !== "unauthenticated") fail(`ip-fail${i + 1}`, `expected unauthenticated, got ${err && err.code}`);
  }
  const err6 = await staffAttempt(names[5], "Wrong1!", IP);
  if (!err6 || err6.code !== "resource-exhausted") fail("ip-lock", `expected resource-exhausted, got ${err6 && err6.code}`);
  const ipDoc = store[`login_throttle/${throttleDocId("staff_login_ip", IP)}`];
  const ipMs = ipDoc.locked_until.toMillis() - Date.now();
  if (!(ipMs > 9 * 60 * 1000 && ipMs <= 10 * 60 * 1000)) fail("ip-duration", `expected ~10min, got ${ipMs}ms`);
  ok("IP throttle unchanged (5 fails -> unauthenticated, 6th throttled, ~10min)");

  // 9: student authentication + enumeration unchanged.
  try {
    await verifyPhonePassword({
      data: { phoneNumber: "01009999999", password: "Wrong1!" },
      auth: null,
      rawRequest: {},
    });
    fail("student-unknown", "expected failure, got success");
  } catch (err) {
    if (err.code === "unauthenticated") ok("student unknown-phone still generic unauthenticated");
    else fail("student-unknown", `unexpected ${err.code}`);
  }
  const errUnknownStaff = await staffAttempt("Ghost Person", "Wrong1!");
  if (errUnknownStaff && errUnknownStaff.code === "unauthenticated") ok("unknown staff name still generic unauthenticated");
  else fail("staff-unknown", `unexpected ${errUnknownStaff && errUnknownStaff.code}`);

  // 10: ambiguous-name behavior unchanged.
  USERS.push({ id: "amb-1", data: { full_name: "Same Name", role: "admin", account_status: "active" } });
  USERS.push({ id: "amb-2", data: { full_name: "Same Name", role: "admin", account_status: "active" } });
  const errAmb = await staffAttempt("Same Name", "Wrong1!", "10.40.0.9");
  if (errAmb && errAmb.code === "failed-precondition") ok("ambiguous-name still failed-precondition");
  else fail("ambiguous", `unexpected ${errAmb && errAmb.code}`);

  test.cleanup();

  if (process.exitCode === 1) {
    console.error("staff_lock_stretch tests FAILED");
    process.exit(1);
  }
  console.log(`staff_lock_stretch.test: PASS - All ${passed} checks passed.`);
}

run();
