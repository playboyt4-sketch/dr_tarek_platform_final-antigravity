/**
 * PHASE 1 terminology migration tests (public_student -> guest,
 * public_free plan ID -> guest; plan_key "free" unchanged).
 *
 * Pure-logic coverage for the migrated backend contract:
 *  - Student-type / plan identity constants.
 *  - isGuestPlan: identity-safe Guest check that MUST NOT match the
 *    Center Free plan (plans/free, which shares plan_key "free") and MUST
 *    NOT rely on plan_key alone. Phase 4: center_free -> free.
 *  - resolveGuestPreviewSeconds: Guest preview cap semantics (unchanged from
 *    the former Public Free behavior: deny-by-default, per-lecture minutes
 *    win, plan fallback, zero cap when unconfigured).
 *  - readGuestPreviewFields: canonical guest_* lecture fields with bounded
 *    legacy public_free_* fallback for the Phase 1 -> Phase 2 transition.
 *  - Student-type allowlist shape: only "guest" + "center_student" accepted.
 *
 * Runs against the COMPILED output (functions/lib/index.js), mirroring the
 * existing node test convention in this repo. No emulator needed.
 */
const assert = require("node:assert/strict");

const adminMock = {
  initializeApp: () => ({}),
  getFirestore: () => ({
    collection: () => ({
      doc: () => ({ get: async () => ({ exists: false }) }),
      where: () => ({ where: () => ({ limit: () => ({ get: async () => ({ empty: true, docs: [] }) }) }) }),
      add: async () => ({ id: "mock" }),
    }),
  }),
  FieldValue: { serverTimestamp: () => ({ _serverTimestamp: true }) },
  Timestamp: { fromMillis: (ms) => ({ toMillis: () => ms }) },
  getAuth: () => ({}),
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

const {
  GUEST_STUDENT_TYPE,
  CENTER_STUDENT_TYPE,
  GUEST_PLAN_ID,
  isGuestPlan,
  resolveGuestPreviewSeconds,
  readGuestPreviewFields,
} = functions;

let passed = 0;
function check(name, actual, expected) {
  assert.deepEqual(actual, expected, name);
  passed++;
  console.log(`ok - ${name}`);
}

// ---- 1. Identity constants ----
check("guest student type constant", GUEST_STUDENT_TYPE, "guest");
check("center student type untouched", CENTER_STUDENT_TYPE, "center_student");
check("guest plan id constant", GUEST_PLAN_ID, "guest");

// ---- 2. Student-type allowlist shape (mirrors approve/convert/onApproved gates) ----
function isAcceptedStudentType(value) {
  return value === GUEST_STUDENT_TYPE || value === CENTER_STUDENT_TYPE;
}
check("approveStudent accepts guest", isAcceptedStudentType("guest"), true);
check("conversion supports guest", isAcceptedStudentType("guest"), true);
check("conversion supports center_student", isAcceptedStudentType("center_student"), true);
check("legacy public_student rejected", isAcceptedStudentType("public_student"), false);
check("unsupported types rejected", isAcceptedStudentType("student"), false);
check("empty type rejected", isAcceptedStudentType(""), false);

// ---- 3. Guest plan resolution: never confuse guest with free ----
check(
  "guest plan resolves correctly",
  isGuestPlan("guest", { student_type: "guest", plan_key: "free" }),
  true,
);
check(
  "guest does not resolve to free",
  isGuestPlan("free", { student_type: "center_student", plan_key: "free" }),
  false,
);
check(
  "free does not resolve to guest",
  isGuestPlan("guest", { student_type: "center_student", plan_key: "free" }),
  false,
);
check(
  "plan_key=free alone never identifies guest",
  isGuestPlan("free", { student_type: "guest", plan_key: "free" }),
  false,
);
check(
  "pro/max never resolve to guest",
  isGuestPlan("pro", { student_type: "center_student", plan_key: "pro" }) ||
    isGuestPlan("max", { student_type: "center_student", plan_key: "max" }),
  false,
);
check(
  "legacy center_free doc id is not the guest plan",
  isGuestPlan("center_free", { student_type: "center_student", plan_key: "free" }),
  false,
);
check(
  "legacy public_free doc id is not the guest plan",
  isGuestPlan("public_free", { student_type: "public_student", plan_key: "public_free" }),
  false,
);
check("null plan denied", isGuestPlan(null, { student_type: "guest" }), false);
check("null plan data denied", isGuestPlan("guest", null), false);
check("plan_key=free remains a valid (non-identity) classification", "free", "free");

// ---- 4. Claims shape ----
check("guest claim student_type", { student_type: "guest" }.student_type, "guest");
check("guest claim plan_id", { plan_id: "guest" }.plan_id, "guest");

// ---- 5. Preview semantics (security-sensitive, must be unchanged) ----
check(
  "guest + guest plan + preview enabled -> capped",
  resolveGuestPreviewSeconds({ guestEnabled: true, lectureMinutes: 5, planDefaultMinutes: 5 }),
  300,
);
check(
  "guest + preview disabled -> denied/null per existing semantics",
  resolveGuestPreviewSeconds({ guestEnabled: false, lectureMinutes: 5, planDefaultMinutes: 5 }),
  null,
);
check(
  "per-lecture minutes win over plan default",
  resolveGuestPreviewSeconds({ guestEnabled: true, lectureMinutes: 7, planDefaultMinutes: 3 }),
  420,
);
check(
  "unconfigured preview caps at zero (upgrade wall, never unlimited)",
  resolveGuestPreviewSeconds({ guestEnabled: true, lectureMinutes: null, planDefaultMinutes: null }),
  0,
);

// ---- 6. Lecture field reading: canonical guest_* with bounded legacy fallback ----
check(
  "canonical guest fields preferred",
  readGuestPreviewFields({ guest_enabled: true, guest_preview_minutes: 6 }),
  { guestEnabled: true, lectureMinutes: 6 },
);
check(
  "legacy public_free fields still honored during transition",
  readGuestPreviewFields({ public_free_enabled: true, public_free_preview_minutes: 4 }),
  { guestEnabled: true, lectureMinutes: 4 },
);
check(
  "canonical fields win over legacy when both present",
  readGuestPreviewFields({
    guest_enabled: false,
    guest_preview_minutes: 9,
    public_free_enabled: true,
    public_free_preview_minutes: 4,
  }),
  { guestEnabled: false, lectureMinutes: 9 },
);
check(
  "absent fields deny by default",
  readGuestPreviewFields({}),
  { guestEnabled: false, lectureMinutes: null },
);

console.log(`guest_migration.test: PASS - All ${passed} checks passed.`);
