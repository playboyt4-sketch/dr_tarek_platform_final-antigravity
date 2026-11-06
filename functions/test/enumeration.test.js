/**
 * enumeration.test.js — account-existence/state oracle resistance.
 *
 * Runs against compiled ../lib/index.js with an in-memory Firestore/Auth
 * mock (same pattern as password_reset.test.js). No emulator, no network.
 *
 * Contract under test (verifyPhonePassword, verify-first ordering):
 *  - unknown phone, wrong password (ANY account state), locked+wrong all
 *    return identical generic `unauthenticated` /
 *    "Invalid phone number or password." — no existence/state signal.
 *  - correct password preserves legitimate state behavior: success for
 *    active approved, approval message for pending/rejected, disabled
 *    message for disabled, lock message while locked.
 *  - submitPasswordResetRequest returns uniform {submitted:true}.
 *  - verifyStaffPassword unknown vs wrong stays identical; ambiguous-name
 *    behavior is documented unchanged (failed-precondition).
 *  - registerNewStudent duplicate-phone behavior is already-exists for every
 *    LIVE account state, while a soft-deleted (deactivated) account releases
 *    its number for reuse (see phone_ownership_lock serialization).
 */
const test = require("firebase-functions-test")({
  projectId: "dr-tarek-platform-functions-test",
});

const assert = require("node:assert/strict");
const crypto = require("node:crypto");

const store = {};
const DELETE = { __delete: true };

function docRef(collPath, docId) {
  const key = `${collPath}/${docId}`;
  return {
    get: async () => {
      if (store[key] === undefined) return { exists: false };
      return { exists: true, data: () => store[key] };
    },
    set: async (data, options) => {
      if (options && options.merge && store[key] !== undefined) {
        const merged = { ...store[key] };
        for (const [k, v] of Object.entries(data)) {
          if (v && v.__delete) delete merged[k];
          else merged[k] = v;
        }
        store[key] = merged;
      } else {
        store[key] = { ...data };
      }
    },
    update: async () => {},
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
        where: usersQuery,
        doc: (docId) => docRef(collPath, docId),
        add: async () => ({}),
      };
    },
    runTransaction: async (fn) =>
      fn({
        get: (ref) => ref.get(),
        set: (ref, data, options) => ref.set(data, options),
      }),
    batch: () => ({ set: () => {}, update: () => {}, delete: () => {}, commit: async () => {} }),
  }),
  FieldValue: { serverTimestamp: () => ({}), delete: () => DELETE },
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
const verifyStaffPassword = test.wrap(functions.verifyStaffPassword);
const registerNewStudent = test.wrap(functions.registerNewStudent);
const submitPasswordResetRequest = test.wrap(functions.submitPasswordResetRequest);

function fixtureHash(password) {
  const salt = Buffer.from("00112233445566778899aabbccddeeff", "hex");
  const derived = crypto.scryptSync(password, salt, 64, { N: 16384, r: 8, p: 1 });
  return `scrypt$${salt.toString("hex")}$${derived.toString("hex")}$16384`;
}

const GENERIC = "Invalid phone number or password.";

async function loginErr(phone, password, ip) {
  try {
    await verifyPhonePassword({
      data: { phoneNumber: phone, password },
      auth: null,
      rawRequest: ip ? { ip } : {},
    });
    return null;
  } catch (err) {
    return err;
  }
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
  const expectGeneric = (err, name) => {
    if (err && err.code === "unauthenticated" && err.message === GENERIC) ok(name);
    else fail(name, `expected generic unauthenticated, got ${err && err.code}: ${err && err.message}`);
  };

  USERS = [
    { id: "active", data: { phone_number: "01001111111", approval_status: "approved", account_status: "active", role: "student", student_type: "center_student", full_name: "Active" } },
    { id: "pending", data: { phone_number: "01002222222", approval_status: "pending", account_status: "active", role: "student", student_type: "center_student", full_name: "Pending" } },
    { id: "rejected", data: { phone_number: "01003333333", approval_status: "rejected", account_status: "active", role: "student", student_type: "center_student", full_name: "Rejected" } },
    { id: "disabled", data: { phone_number: "01004444444", approval_status: "approved", account_status: "disabled", role: "student", student_type: "center_student", full_name: "Disabled" } },
    { id: "locked", data: { phone_number: "01005555555", approval_status: "approved", account_status: "active", role: "student", student_type: "center_student", full_name: "Locked" } },
    // Soft-deleted historical rows: must never shadow a live/reused owner and
    // must never authenticate. "old-deleted" is listed BEFORE "reused-live"
    // on purpose: a naive limit(1) lookup would have resolved the deleted row.
    { id: "deleted-only", data: { phone_number: "01006666666", approval_status: "approved", account_status: "disabled", role: "student", student_type: "center_student", full_name: "Deleted", is_deleted: true } },
    { id: "old-deleted", data: { phone_number: "01007777777", approval_status: "approved", account_status: "disabled", role: "student", student_type: "center_student", full_name: "Old Deleted", is_deleted: true } },
    { id: "reused-live", data: { phone_number: "01007777777", approval_status: "approved", account_status: "active", role: "student", student_type: "center_student", full_name: "Reused Live" } },
    { id: "doc-1", data: { full_name: "Dr Owner", role: "doctor", account_status: "active" } },
    { id: "adm-1", data: { full_name: "Admin One", role: "admin", account_status: "active" } },
    { id: "amb-1", data: { full_name: "Same Name", role: "admin", account_status: "active" } },
    { id: "amb-2", data: { full_name: "Same Name", role: "admin", account_status: "active" } },
  ];
  for (const id of ["active", "pending", "rejected", "disabled", "locked"]) {
    store[`user_secrets/${id}`] = { password_hash: fixtureHash("Correct1!") };
  }
  for (const id of ["deleted-only", "old-deleted", "reused-live"]) {
    store[`user_secrets/${id}`] = { password_hash: fixtureHash("Correct1!") };
  }
  store["user_secrets/locked"] = {
    password_hash: fixtureHash("Correct1!"),
    failed_login_attempts: 5,
    locked_until: { toMillis: () => Date.now() + 10 * 60 * 1000, toDate: () => new Date(Date.now() + 10 * 60 * 1000) },
  };
  store["user_secrets/doc-1"] = { password_hash: fixtureHash("Correct1!") };

  // 1. Unknown phone -> generic.
  expectGeneric(await loginErr("01009999999", "Wrong1!", "10.1.0.1"), "unknown phone -> generic");

  // 2. Active + wrong -> generic, identical to unknown.
  const unknown = await loginErr("01009999998", "Wrong1!", "10.1.0.2");
  const wrong = await loginErr("01001111111", "Wrong1!", "10.1.0.2");
  if (unknown && wrong && unknown.code === wrong.code && unknown.message === wrong.message) {
    ok("unknown == wrong password response");
  } else {
    fail("parity", `unknown=${unknown && unknown.code} wrong=${wrong && wrong.code}`);
  }

  // 3. Active + correct -> success (token), no state leak involved.
  try {
    const res = await verifyPhonePassword({
      data: { phoneNumber: "01001111111", password: "Correct1!" },
      auth: null,
      rawRequest: { ip: "10.1.0.3" },
    });
    if (res && res.token === "mock-token" && res.userId === "active") ok("active + correct -> success");
    else fail("success", JSON.stringify(res));
  } catch (err) {
    fail("success", `${err.code}: ${err.message}`);
  }

  // 4/5/6. Pending/rejected/disabled + WRONG -> generic (no state leak).
  expectGeneric(await loginErr("01002222222", "Wrong1!", "10.1.0.4"), "pending + wrong -> generic");
  expectGeneric(await loginErr("01003333333", "Wrong1!", "10.1.0.4"), "rejected + wrong -> generic");
  expectGeneric(await loginErr("01004444444", "Wrong1!", "10.1.0.4"), "disabled + wrong -> generic");

  // 4b/5b/6b. Correct password preserves legitimate state messages.
  const pendingOk = await loginErr("01002222222", "Correct1!", "10.1.0.5");
  if (pendingOk && pendingOk.code === "permission-denied" && /approval/.test(pendingOk.message)) ok("pending + correct -> approval message");
  else fail("pending-correct", `${pendingOk && pendingOk.code}: ${pendingOk && pendingOk.message}`);
  const rejectedOk = await loginErr("01003333333", "Correct1!", "10.1.0.5");
  if (rejectedOk && rejectedOk.code === "permission-denied" && /approval/.test(rejectedOk.message)) ok("rejected + correct -> approval message");
  else fail("rejected-correct", `${rejectedOk && rejectedOk.code}: ${rejectedOk && rejectedOk.message}`);
  const disabledOk = await loginErr("01004444444", "Correct1!", "10.1.0.5");
  if (disabledOk && disabledOk.code === "permission-denied" && /not active/.test(disabledOk.message)) ok("disabled + correct -> disabled message");
  else fail("disabled-correct", `${disabledOk && disabledOk.code}: ${disabledOk && disabledOk.message}`);

  // 7. Locked + wrong -> generic; locked + correct -> lock enforced.
  expectGeneric(await loginErr("01005555555", "Wrong1!", "10.1.0.6"), "locked + wrong -> generic");
  const lockedOk = await loginErr("01005555555", "Correct1!", "10.1.0.6");
  if (lockedOk && lockedOk.code === "resource-exhausted" && /locked/.test(lockedOk.message)) ok("locked + correct -> lock enforced");
  else fail("locked-correct", `${lockedOk && lockedOk.code}: ${lockedOk && lockedOk.message}`);

  // 8. Duplicate registration: same already-exists for any account state
  // (documents current behavior; product decision pending on silencing).
  async function regErr(phone) {
    try {
      await registerNewStudent({
        data: { fullName: "Test", phoneNumber: phone, grade: "grade_one", password: "Aa1!bcde" },
        auth: null,
      });
      return null;
    } catch (err) {
      return err;
    }
  }
  const dupActive = await regErr("01001111111");
  const dupDisabled = await regErr("01004444444");
  if (dupActive && dupActive.code === "already-exists" && dupDisabled && dupDisabled.code === dupActive.code) {
    ok("duplicate phone -> already-exists regardless of state (unchanged)");
  } else {
    fail("duplicate", `${dupActive && dupActive.code} / ${dupDisabled && dupDisabled.code}`);
  }

  // 8b. Soft-deleted account releases its number: registration succeeds and
  // the cross-instance ownership lock is written in the same transaction.
  const reuseErr = await regErr("01006666666");
  if (
    reuseErr === null &&
    store["users/new-uid"] &&
    store["users/new-uid"].phone_number === "01006666666"
  ) {
    ok("soft-deleted phone released for registration");
  } else {
    fail("phone-reuse", `${reuseErr && reuseErr.code}: ${reuseErr && reuseErr.message}`);
  }
  if (store["system_settings/phone_ownership_lock"]) {
    ok("registration writes phone ownership lock (race serialization)");
  } else {
    fail("phone-lock", "system_settings/phone_ownership_lock was not written");
  }

  // 8c. A deleted-only phone cannot authenticate (uniform generic).
  expectGeneric(
    await loginErr("01006666666", "Correct1!", "10.1.0.9"),
    "soft-deleted-only account -> generic (no access)",
  );

  // 8d. When a deleted historical row and a live row share a phone, the live
  // account wins even though the deleted row is encountered first.
  try {
    const reused = await verifyPhonePassword({
      data: { phoneNumber: "01007777777", password: "Correct1!" },
      auth: null,
      rawRequest: { ip: "10.1.0.10" },
    });
    if (reused && reused.userId === "reused-live") ok("reused phone -> login resolves live owner");
    else fail("reused-login", JSON.stringify(reused));
  } catch (err) {
    fail("reused-login", `${err.code}: ${err.message}`);
  }

  // 9/10. Reset request uniform for unknown and known phones.
  async function resetRes(phone) {
    return submitPasswordResetRequest({ data: { phoneNumber: phone }, auth: null });
  }
  const rUnknown = await resetRes("01008888888");
  const rKnown = await resetRes("01001111111");
  if (rUnknown && rUnknown.submitted === true && rKnown && rKnown.submitted === true) {
    ok("reset unknown == known (uniform submitted:true)");
  } else {
    fail("reset", JSON.stringify({ rUnknown, rKnown }));
  }

  // 11/12. Staff unknown vs wrong identical.
  async function staffErr(name, pw) {
    try {
      await verifyStaffPassword({ data: { displayName: name, password: pw }, auth: null });
      return null;
    } catch (err) {
      return err;
    }
  }
  const sUnknown = await staffErr("Nobody Here", "Wrong1!");
  const sWrong = await staffErr("Dr Owner", "Wrong1!");
  if (sUnknown && sWrong && sUnknown.code === sWrong.code && sUnknown.message === sWrong.message) {
    ok("staff unknown == wrong response");
  } else {
    fail("staff", `${sUnknown && sUnknown.code} / ${sWrong && sWrong.code}`);
  }

  // 13. Ambiguous staff name behavior documented unchanged.
  const amb = await staffErr("Same Name", "Wrong1!");
  if (amb && amb.code === "failed-precondition") ok("ambiguous staff name -> failed-precondition (unchanged)");
  else fail("ambiguous", `${amb && amb.code}: ${amb && amb.message}`);

  test.cleanup();

  if (process.exitCode === 1) {
    console.error("enumeration tests FAILED");
    process.exit(1);
  }
  console.log(`enumeration.test: PASS - All ${passed} checks passed.`);
}

run();
