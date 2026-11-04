/**
 * student_claims_sync.test.js — login-time repair of student identity
 * custom claims in verifyPhonePassword.
 *
 * Runs against compiled ../lib/index.js with an in-memory Firestore/Auth
 * mock (same pattern as student_login_throttle.test.js). No emulator, no
 * network.
 *
 * Regression context: `onStudentApproved` is a Firestore trigger and can
 * fail (or never have run for accounts approved before it was deployed).
 * The user record then stays `approved` while Firebase Auth keeps no stored
 * claims. `getIdTokenResult(true)` drops the one-time custom-token claims,
 * so `onLoginAttempt` sees `token.role === undefined` and rejects device
 * binding — a correct password cannot complete login.
 *
 * Verified behaviors:
 *  1. Drifted student claims are restored at login (role/student_type/
 *     approved/force_password_change) while preserving existing keys.
 *  2. Plan/subscription claims are preserved, never recomputed at login.
 *  3. A healthy student claim set is left untouched (no redundant write,
 *     so no refresh-token revocation on every login).
 *  4. Staff (doctor) claim sync behavior is unchanged.
 */
const test = require("firebase-functions-test")({
  projectId: "dr-tarek-platform-functions-test",
});

const assert = require("node:assert/strict");
const crypto = require("node:crypto");

const store = {};
let USERS = [];

// Stored custom claims per uid, mutable by the Auth mock.
const CLAIMS = {};
const writes = [];
const customTokens = [];

function docRef(collPath, docId) {
  const key = `${collPath}/${docId}`;
  return {
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
  };
}

function matchesFilter(data, field, op, value) {
  if (op === "==") return data[field] === value;
  if (op === "in") return Array.isArray(value) && value.includes(data[field]);
  return false;
}

function usersQuery(field, op, value) {
  const docs = USERS.filter((u) => matchesFilter(u.data, field, op, value)).map(
    (u) => ({ id: u.id, data: () => u.data }),
  );
  return {
    limit: () => ({ get: async () => ({ empty: docs.length === 0, docs }) }),
    get: async () => ({ empty: docs.length === 0, docs }),
  };
}

const adminMock = {
  initializeApp: () => ({}),
  getFirestore: () => ({
    collection: (collPath) => {
      if (collPath === "users") {
        return {
          where: usersQuery,
          doc: (id) => docRef(collPath, id),
          add: async () => ({}),
        };
      }
      return {
        where: () => ({
          limit: () => ({ get: async () => ({ empty: true, docs: [] }) }),
          get: async () => ({ empty: true, docs: [] }),
        }),
        doc: (docId) => docRef(collPath, docId),
        add: async () => ({ id: "analytics-event" }),
      };
    },
    runTransaction: async (fn) =>
      fn({
        get: (ref) => ref.get(),
        set: (ref, data, options) => ref.set(data, options),
        update: (ref, data) => ref.update(data),
      }),
    batch: () => ({
      set: () => {},
      update: () => {},
      delete: () => {},
      commit: async () => {},
    }),
  }),
  FieldValue: { serverTimestamp: () => ({}), delete: () => ({ __delete: true }) },
  Timestamp: {
    now: () => ({ toMillis: () => Date.now() }),
    fromDate: (d) => ({ toMillis: () => d.getTime(), toDate: () => d }),
    fromMillis: (ms) => ({ toMillis: () => ms, toDate: () => new Date(ms) }),
  },
  getAuth: () => ({
    updateUser: async () => {},
    getUser: async (uid) => ({ customClaims: { ...(CLAIMS[uid] || {}) } }),
    setCustomUserClaims: async (uid, claims) => {
      writes.push({ uid, claims });
      CLAIMS[uid] = { ...claims };
    },
    createCustomToken: async (uid, claims) => {
      customTokens.push({ uid, claims });
      return "mock-token";
    },
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

function fixtureHash(password) {
  const salt = Buffer.from("00112233445566778899aabbccddeeff", "hex");
  const derived = crypto.scryptSync(password, salt, 64, { N: 16384, r: 8, p: 1 });
  return `scrypt$${salt.toString("hex")}$${derived.toString("hex")}$16384`;
}

const PASSWORD = "Correct1!";

async function login(phone) {
  return verifyPhonePassword({
    data: { phoneNumber: phone, password: PASSWORD },
    auth: null,
    rawRequest: {},
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

  USERS = [
    {
      id: "drifted-student",
      data: {
        phone_number: "01000000001",
        approval_status: "approved",
        account_status: "active",
        role: "student",
        student_type: "center_student",
        force_password_change: true,
      },
    },
    {
      id: "healthy-student",
      data: {
        phone_number: "01000000002",
        approval_status: "approved",
        account_status: "active",
        role: "student",
        student_type: "guest",
        force_password_change: false,
      },
    },
    {
      id: "partial-student",
      data: {
        phone_number: "01000000003",
        approval_status: "approved",
        account_status: "active",
        role: "student",
        student_type: "center_student",
        force_password_change: false,
      },
    },
    {
      id: "doctor-1",
      data: {
        phone_number: "01000000004",
        approval_status: "approved",
        account_status: "active",
        role: "doctor",
        force_password_change: false,
      },
    },
  ];
  for (const user of USERS) {
    store[`user_secrets/${user.id}`] = { password_hash: fixtureHash(PASSWORD) };
  }

  // 1: drifted student (the production symptom: only force_password_change).
  CLAIMS["drifted-student"] = { force_password_change: true };
  try {
    const res = await login("01000000001");
    if (res && res.token === "mock-token") ok("drifted student logs in");
    else fail("drifted-login", JSON.stringify(res));
  } catch (err) {
    fail("drifted-login", `${err.code}: ${err.message}`);
  }
  const repaired = CLAIMS["drifted-student"] || {};
  if (
    repaired.role === "student" &&
    repaired.student_type === "center_student" &&
    repaired.approved === true &&
    repaired.force_password_change === true
  ) {
    ok("drifted claims restored at login");
  } else {
    fail("drifted-claims", JSON.stringify(repaired));
  }
  const driftedWrite = writes.find((w) => w.uid === "drifted-student");
  if (driftedWrite && driftedWrite.claims.role === "student") {
    ok("restored claims are persisted via setCustomUserClaims");
  } else {
    fail("drifted-persist", JSON.stringify(driftedWrite));
  }
  const driftedToken = customTokens.find((t) => t.uid === "drifted-student");
  if (driftedToken && driftedToken.claims.role === "student") {
    ok("custom token still carries role=student");
  } else {
    fail("drifted-token", JSON.stringify(driftedToken));
  }

  // 2: healthy student -> no write (avoids needless token revocation).
  CLAIMS["healthy-student"] = {
    role: "student",
    student_type: "guest",
    plan_id: "guest",
    max_devices: 1,
    approved: true,
    subscription_status: "active",
    force_password_change: false,
  };
  const beforeHealthy = writes.length;
  try {
    await login("01000000002");
    ok("healthy student logs in");
  } catch (err) {
    fail("healthy-login", `${err.code}: ${err.message}`);
  }
  if (writes.length === beforeHealthy) ok("healthy claims untouched (no write)");
  else fail("healthy-write", JSON.stringify(writes.slice(beforeHealthy)));

  // 3: partial drift with plan claims -> identity restored, plan preserved.
  CLAIMS["partial-student"] = {
    plan_id: "free",
    max_devices: 2,
    subscription_status: "active",
    force_password_change: false,
  };
  try {
    await login("01000000003");
    ok("partial-drift student logs in");
  } catch (err) {
    fail("partial-login", `${err.code}: ${err.message}`);
  }
  const partial = CLAIMS["partial-student"] || {};
  if (partial.role === "student" && partial.approved === true) {
    ok("partial drift: identity claims restored");
  } else {
    fail("partial-identity", JSON.stringify(partial));
  }
  if (
    partial.plan_id === "free" &&
    partial.max_devices === 2 &&
    partial.subscription_status === "active"
  ) {
    ok("partial drift: plan/subscription claims preserved");
  } else {
    fail("partial-plan", JSON.stringify(partial));
  }

  // 4: staff branch unchanged — doctor claims synced as doctor, no student_type.
  CLAIMS["doctor-1"] = {};
  try {
    await login("01000000004");
    ok("doctor logs in");
  } catch (err) {
    fail("doctor-login", `${err.code}: ${err.message}`);
  }
  const doctor = CLAIMS["doctor-1"] || {};
  if (doctor.role === "doctor" && doctor.approved === true && doctor.student_type === undefined) {
    ok("doctor claims synced without student identity");
  } else {
    fail("doctor-claims", JSON.stringify(doctor));
  }

  test.cleanup();

  if (process.exitCode === 1) {
    console.error("student_claims_sync tests FAILED");
    process.exit(1);
  }
  console.log(`student_claims_sync.test: PASS - All ${passed} checks passed.`);
}

run();
