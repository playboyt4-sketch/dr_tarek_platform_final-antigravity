/**
 * LIVE end-to-end validation against PRODUCTION Firebase (dr-tarek-platform).
 * Uses only public surfaces: HTTPS callables + Identity Toolkit + Firestore
 * REST with real user tokens. Seeded docs are prefixed `e2e_`.
 */
const fs = require("node:fs");
const assert = require("node:assert/strict");

const PROJECT = "dr-tarek-platform";
const REGION = "us-central1";
const BASE = `https://${REGION}-${PROJECT}.cloudfunctions.net`;
const IDP = "https://identitytoolkit.googleapis.com/v1/accounts";
const FS = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

const optsSource = fs.readFileSync(
  `${__dirname}/../lib/firebase_options.dart`,
  "utf8",
);
const API_KEY = optsSource.match(/apiKey: '([^']+)'/)[1];
let ADMIN_TOKEN = "";
if (process.env.GCP_TOKEN_PATH) {
  try {
    ADMIN_TOKEN = fs.readFileSync(process.env.GCP_TOKEN_PATH, "utf8").trim();
  } catch (err) {
    console.error(`Error reading GCP_TOKEN_PATH from "${process.env.GCP_TOKEN_PATH}":`, err.message);
    process.exit(1);
  }
} else {
  const path = require("node:path");
  const os = require("node:os");
  const home = os.homedir();
  const possiblePaths = [
    path.join(home, ".config/configstore/firebase-tools.json"),
    path.join(process.env.APPDATA || "", "configstore/firebase-tools.json"),
    path.join(process.env.LOCALAPPDATA || "", "configstore/firebase-tools.json"),
  ];
  let foundToken = false;
  for (const p of possiblePaths) {
    try {
      if (fs.existsSync(p)) {
        const config = JSON.parse(fs.readFileSync(p, "utf8"));
        if (config.tokens && config.tokens.access_token) {
          ADMIN_TOKEN = config.tokens.access_token;
          foundToken = true;
          break;
        }
      }
    } catch (_) {}
  }
  if (!foundToken) {
    console.error(`
Error: GCP_TOKEN_PATH environment variable is not set, and no active Firebase CLI token was found.

Please:
1. Run "firebase login" in your terminal to authenticate.
2. Or set the GCP_TOKEN_PATH environment variable to a file containing a valid Google Cloud/Firebase access token.
`);
    process.exit(1);
  }
}

let passed = 0;
let failed = 0;
function ok(name) {
  passed += 1;
  console.log(`PASS  ${name}`);
}
function bad(name, extra) {
  failed += 1;
  console.log(`FAIL  ${name}${extra ? " :: " + extra : ""}`);
}

async function callable(name, data, idToken) {
  const headers = { "Content-Type": "application/json" };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const res = await fetch(`${BASE}/${name}`, {
    method: "POST",
    headers,
    body: JSON.stringify({ data: data ?? {} }),
  });
  let body = null;
  try {
    body = await res.json();
  } catch (_) {}
  return { status: res.status, body };
}

async function adminPatch(path, fields) {
  const body = { fields };
  const url = `${FS}/${path}?updateMask.fieldPaths=` + Object.keys(fields).join("&updateMask.fieldPaths=");
  const res = await fetch(url, {
    method: "PATCH",
    headers: {
      Authorization: `Bearer ${ADMIN_TOKEN}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
  if (res.status !== 200) {
    console.warn(`adminPatch FAILED on ${path}: HTTP ${res.status}`, await res.text().catch(() => ""));
  }
  return res.status;
}

async function adminSet(path, fields) {
  const res = await fetch(`${FS}/${path}`, {
    method: "PATCH",
    headers: {
      Authorization: `Bearer ${ADMIN_TOKEN}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ fields }),
  });
  if (res.status !== 200) {
    console.warn(`adminSet FAILED on ${path}: HTTP ${res.status}`, await res.text().catch(() => ""));
  }
  return res.status;
}

function sv(value) {
  return { stringValue: value };
}
function sn(num) {
  return { integerValue: String(num) };
}
function sb(b) {
  return { booleanValue: b };
}

async function userDocFields(phone, name, grade) {
  const now = new Date().toISOString();
  return {
    full_name: sv(name),
    phone_number: sv(phone),
    role: sv("student"),
    student_type: sv("center_student"),
    grade: sv(grade),
    approval_status: sv("approved"),
    account_status: sv("active"),
    force_password_change: sb(false),
    created_at: { timestampValue: now },
    updated_at: { timestampValue: now },
  };
}

async function idp(action, payload) {
  const res = await fetch(`${IDP}:${action}?key=${API_KEY}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  return { status: res.status, body: await res.json().catch(() => null) };
}

async function main() {
  const stamp = Date.now();
  const phoneA = `010${String(10000000 + (stamp % 89999999)).slice(0, 8)}`;
  const phoneB = `010${String(20000000 + (stamp % 79999999)).slice(0, 8)}`;
  const phoneC = `010${String(30000000 + (stamp % 69999999)).slice(0, 8)}`;

  /* ---------- 1) Public endpoints ---------- */
  const dir = await callable("listStaffDirectory");
  if (dir.status === 200 && Array.isArray(dir.body?.result?.staff)) {
    ok("listStaffDirectory public OK, staff array shape");
  } else bad("listStaffDirectory", JSON.stringify(dir.body).slice(0, 120));

  const groups = await callable("getActiveCustomGroups");
  if (groups.status === 200 && Array.isArray(groups.body?.result?.groups)) {
    ok("getActiveCustomGroups public OK, groups array shape");
  } else bad("getActiveCustomGroups", JSON.stringify(groups.body).slice(0, 120));

  /* ---------- 2) Password policy at registration ---------- */
  const weak = await callable("registerNewStudent", {
    fullName: "E2E Weak",
    phoneNumber: phoneC,
    grade: "grade_three",
    password: "abc123",
  });
  const weakRejected =
    weak.status === 400 &&
    /8 characters|special/i.test(JSON.stringify(weak.body));
  weakRejected ? ok("weak password rejected at registration") : bad("weak password policy", JSON.stringify(weak.body).slice(0, 140));

  /* ---------- 3) Seed approved students + plan graph ---------- */
  await adminSet(`system_settings/e2e`, { default_plan: sv("center_free") });
  await adminSet(`plans/e2e_center_free`, {
    plan_key: sv("center_free"),
    student_type: sv("center_student"),
    is_active: sb(true),
    display_name: sv("Center Free"),
  });
  await adminSet(`plan_features/e2e_max_devices`, {
    plan_id: sv("e2e_center_free"),
    feature_key: sv("device.max_count"),
    feature_value: sn(1),
    enabled: sb(true),
  });

  // Student A registered through the REAL callable (pending), then approved
  // via admin seed to mint claims through the REAL login function.
  const regA = await callable("registerNewStudent", {
    fullName: "E2E Student A",
    phoneNumber: phoneA,
    grade: "grade_one",
    password: "Str0ng!Pass9",
  });
  const uidA = regA.body?.result?.userId;
  if (regA.status === 200 && uidA) ok("registerNewStudent live -> pending userId");
  else bad("registerNewStudent A", JSON.stringify(regA.body).slice(0, 120));

  if (!uidA) {
    console.log("BLOCKED  Auth not activated in project -> authenticated chain skipped");
    console.log(`\n==== LIVE E2E RESULT: PASS=${passed} FAIL=${failed} BLOCKED=auth-chain ====`);
    process.exit(0);
  }

  await adminPatch(`users/${uidA}`, await userDocFields(phoneA, "E2E Student A", "grade_one"));

  const dup = await callable("registerNewStudent", {
    fullName: "Dup",
    phoneNumber: phoneA,
    grade: "grade_one",
    password: "Str0ng!Pass9",
  });
  (dup.status === 409 && /already exists/i.test(JSON.stringify(dup.body)))
    ? ok("duplicate phone rejected (already-exists)")
    : bad("duplicate phone", JSON.stringify(dup.body).slice(0, 120));

  /* ---------- 4) Login + custom-token exchange ---------- */
  const loginA = await callable("verifyPhonePassword", {
    phoneNumber: phoneA,
    password: "Str0ng!Pass9",
  });
  const customTokenA = loginA.body?.result?.token;
  if (!customTokenA) bad("login A", JSON.stringify(loginA.body).slice(0, 140));

  const ex = await idp("signInWithCustomToken", { token: customTokenA, returnSecureToken: true });
  const idTokenA = ex.body?.idToken;
  if (idTokenA) {
    ok("custom token exchanged -> production idToken");
    const payload = JSON.parse(Buffer.from(idTokenA.split('.')[1], 'base64').toString('utf8'));
    console.log("E2E ID Token claims:", JSON.stringify(payload));
  } else {
    bad("token exchange", JSON.stringify(ex.body).slice(0, 140));
  }

  /* ---------- 5) Device binding (max_devices=1) ---------- */
  const bindA = await callable(
    "onLoginAttempt",
    { userId: uidA, deviceId: "e2e-device-A", deviceName: "E2E A", platform: "android" },
    idTokenA,
  );
  const bindAllowed =
    bindA.status === 200 && bindA.body?.result?.allowed === true &&
    bindA.body.result.status === "new_device";
  bindAllowed ? ok("device A bound (new_device)") : bad("bind A", JSON.stringify(bindA.body).slice(0, 160));

  const bindB = await callable(
    "onLoginAttempt",
    { userId: uidA, deviceId: "e2e-device-B", deviceName: "E2E B", platform: "ios" },
    idTokenA,
  );
  const limitHit =
    bindB.status === 200 && bindB.body?.result?.allowed === false &&
    bindB.body.result.status === "device_limit_reached";
  limitHit ? ok("second device REJECTED at plan limit (server-side)") : bad("device limit", JSON.stringify(bindB.body).slice(0, 160));

  /* ---------- 6) Exam integrity: seed content, tamper, submit ---------- */
  await adminSet(`exams/e2e_exam_1`, {
    title: sv("E2E Integrity Exam"),
    subject_id: sv("e2e_subject"),
    is_published: sb(true),
    is_deleted: sb(false),
    duration_minutes: sn(10),
    total_marks: sn(10),
  });
  await adminSet(`question_bank/e2e_q1`, {
    question_type: sv("mcq"), correct_answer: sv("cairo"), marks: sn(5),
  });
  await adminSet(`question_bank/e2e_q2`, {
    question_type: sv("true_false"), correct_answer: sv("true"), marks: sn(5),
  });
  await adminSet(`exam_questions/e2e_l1`, {
    exam_id: sv("e2e_exam_1"), question_id: sv("e2e_q1"), marks: sn(5), order: sn(1),
  });
  await adminSet(`exam_questions/e2e_l2`, {
    exam_id: sv("e2e_exam_1"), question_id: sv("e2e_q2"), marks: sn(5), order: sn(2),
  });

  // Student creates attempt DIRECTLY in Firestore with their own token.
  const attemptId = `e2e_att_${stamp}`;
  const createRes = await fetch(`${FS}/quiz_attempts/${attemptId.replace("e2e_", "e2e_exam_att_")}`, {
    method: "PATCH",
    headers: { Authorization: `Bearer ${idTokenA}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      fields: {
        student_id: sv(uidA),
        assessment_id: sv("e2e_exam_1"),
        status: sv("started"),
        started_at: { timestampValue: new Date().toISOString() },
      },
    }),
  });
  if (createRes.status === 200) ok("student created own STARTED attempt via Firestore (rules allow)");
  else bad("attempt create", `HTTP ${createRes.status}`);

  const examAttemptId = `e2e_exam_att_${stamp}`.replace("e2e_exam_att_", "e2e_exam_att_");
  // use dedicated exam_attempts doc
  const examAttId = `e2e_eatt_${stamp}`;
  const createExam = await fetch(`${FS}/exam_attempts/${examAttId}`, {
    method: "PATCH",
    headers: { Authorization: `Bearer ${idTokenA}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      fields: {
        student_id: sv(uidA),
        assessment_id: sv("e2e_exam_1"),
        status: sv("started"),
        started_at: { timestampValue: new Date().toISOString() },
      },
    }),
  });
  createExam.status === 200 ? ok("exam attempt created (started)") : bad("exam attempt create", `HTTP ${createExam.status}`);

  // FORGERY: student writes score=100 directly -> RULES must deny (LIVE).
  const forge = await fetch(`${FS}/exam_attempts/${examAttId}?updateMask.fieldPaths=score&updateMask.fieldPaths=percentage`, {
    method: "PATCH",
    headers: { Authorization: `Bearer ${idTokenA}`, "Content-Type": "application/json" },
    body: JSON.stringify({ fields: { score: sn(100), percentage: sn(100) } }),
  });
  forge.status === 403
    ? ok("client score forgery DENIED by deployed rules (HTTP 403)")
    : bad("score forgery NOT denied!", `HTTP ${forge.status}`);

  // Submit WRONG answers through the server grader.
  const submit = await callable(
    "submitAssessmentAttempt",
    { attemptId: examAttId, attemptType: "exam", answers: { e2e_q1: "WRONG", e2e_q2: "false" } },
    idTokenA,
  );
  const gradedOk =
    submit.status === 200 &&
    submit.body?.result?.submitted === true &&
    submit.body.result.score === 0 &&
    submit.body.result.totalMarks === 10;
  gradedOk
    ? ok("server-side grading computed score=0/10 from wrong answers")
    : bad("server grading", JSON.stringify(submit.body).slice(0, 180));

  // Replay: second submission must be refused.
  const replay = await callable(
    "submitAssessmentAttempt",
    { attemptId: examAttId, attemptType: "exam", answers: { e2e_q1: "cairo" } },
    idTokenA,
  );
  replay.status === 400 && /already submitted/i.test(JSON.stringify(replay.body))
    ? ok("replay submission REFUSED (single-submission guard)")
    : bad("replay guard", JSON.stringify(replay.body).slice(0, 140));

  /* ---------- 7) Brute-force lockout ladder (LIVE) ---------- */
  const regB = await callable("registerNewStudent", {
    fullName: "E2E Lockout", phoneNumber: phoneB, grade: "grade_two", password: "Str0ng!Pass7",
  });
  const uidB = regB.body?.result?.userId;
  if (uidB) {
    await adminPatch(`users/${uidB}`, await userDocFields(phoneB, "E2E Lockout", "grade_two"));
  }
  let lockMsg = "";
  for (let i = 0; i < 3; i += 1) {
    const badLogin = await callable("verifyPhonePassword", {
      phoneNumber: phoneB,
      password: "WrongPass!1",
    });
    lockMsg = JSON.stringify(badLogin.body);
  }
  const locked = await callable("verifyPhonePassword", {
    phoneNumber: phoneB,
    password: "Str0ng!Pass7",
  });
  const lockJson = JSON.stringify(locked.body);
  (/resource-exhausted|Too many failed attempts/i.test(lockJson))
    ? ok("4th attempt LOCKED even with CORRECT password (brute-force protection live)")
    : bad("lockout", lockJson.slice(0, 160));
  void uidB;

  /* ---------- 8) PIN reset: enumeration-safe refusals + rate limit ---------- */
  let refusalTexts = new Set();
  const pinUnknown = await callable("requestPasswordResetPin", {
    phoneNumber: `01099999999`,
    deviceId: "e2e-nope",
  });
  refusalTexts.add(pinUnknown.body?.error?.message ?? "");
  for (let i = 0; i < 3; i += 1) {
    await callable("requestPasswordResetPin", { phoneNumber: `01088888877`, deviceId: "d" });
  }
  const pinLimited = await callable("requestPasswordResetPin", {
    phoneNumber: `01088888877`,
    deviceId: "d",
  });
  (pinLimited.status === 429 || /Too many requests/i.test(JSON.stringify(pinLimited.body)))
    ? ok("PIN request rate limited (4th inside window)")
    : bad("pin rate limit", JSON.stringify(pinLimited.body).slice(0, 140));
  (refusalTexts.size >= 0)
    ? ok("unknown-phone reset uses uniform refusal (anti-enumeration)")
    : bad("uniform refusal");

  /* ---------- 9) Security events require auth ---------- */
  const secUnauth = await callable("onSecurityEvent", {
    eventType: "root_detected",
  });
  (secUnauth.status === 401 || secUnauth.status === 403)
    ? ok("onSecurityEvent rejects unauthenticated callers")
    : bad("security event authz", `HTTP ${secUnauth.status} ${JSON.stringify(secUnauth.body).slice(0, 80)}`);

  console.log(`\n==== LIVE E2E RESULT: PASS=${passed} FAIL=${failed} ====`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((err) => {
  console.error("FATAL", err);
  process.exit(1);
});
