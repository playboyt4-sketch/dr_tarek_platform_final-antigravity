/**
 * Read-only production inventory for the pre-onboarding student cleanup.
 *
 * Safety:
 * - Refuses any project other than dr-tarek-platform.
 * - Performs NO writes to Firestore, Auth, Storage, or Secret Manager.
 * - Prints only masked identifiers and aggregate counts.
 * - Writes full backup-quality JSON under a caller-supplied local folder
 *   (never inside the repository) for audit/recovery.
 *
 * Usage:
 *   $env:GOOGLE_APPLICATION_CREDENTIALS = '<service-account.json>'
 *   node scripts\production_inventory.cjs --out "D:\Temp\dr_tarek_inventory_<ts>"
 */
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const {createRequire} = require("node:module");

const EXPECTED_PROJECT_ID = "dr-tarek-platform";
const repoRoot = path.join(__dirname, "..");
const functionsRequire = createRequire(path.join(repoRoot, "functions", "package.json"));
const admin = functionsRequire("firebase-admin");

function argValue(flag) {
  const index = process.argv.indexOf(flag);
  return index >= 0 ? (process.argv[index + 1] ?? "").trim() : "";
}

function fail(message) {
  console.error(`ERROR: ${message}`);
  process.exit(1);
}

function mask(value) {
  const text = typeof value === "string" ? value.trim() : "";
  if (!text) return null;
  if (text.length <= 6) return "***";
  return `${text.slice(0, 3)}***${text.slice(-2)}`;
}

function sha256(text) {
  return crypto.createHash("sha256").update(text).digest("hex");
}

function writeJson(dir, name, value) {
  const file = path.join(dir, name);
  const text = JSON.stringify(value, null, 2);
  fs.writeFileSync(file, text, "utf8");
  return {file: name, bytes: Buffer.byteLength(text), sha256: sha256(text)};
}

function credentialProjectId() {
  const file = (process.env.GOOGLE_APPLICATION_CREDENTIALS ?? "").trim();
  if (!file) return null;
  try {
    const parsed = JSON.parse(fs.readFileSync(file, "utf8"));
    return typeof parsed.project_id === "string" ? parsed.project_id : null;
  } catch {
    return null;
  }
}

function normalizeRole(value) {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

async function countCollection(db, name) {
  try {
    const snap = await db.collection(name).count().get();
    return snap.data().count;
  } catch {
    return null;
  }
}

const LINKED_COLLECTIONS = [
  {collection: "devices", field: "user_id"},
  {collection: "notifications", field: "user_id"},
  {collection: "analytics_events", field: "user_id"},
  {collection: "security_events", field: "user_id"},
  {collection: "notes", field: "student_id"},
  {collection: "bookmarks", field: "student_id"},
  {collection: "learning_progress", field: "student_id"},
  {collection: "lecture_progress", field: "student_id"},
  {collection: "subject_progress_summary", field: "student_id"},
  {collection: "subscriptions", field: "student_id"},
  {collection: "subject_access_assignments", field: "student_id"},
  {collection: "quiz_attempts", field: "student_id"},
  {collection: "exam_attempts", field: "student_id"},
  {collection: "password_reset_requests", field: "student_id"},
  {collection: "student_questions", field: "student_id"},
  {collection: "chat_rooms", field: "student_id"},
  {collection: "subject_device_authorizations", field: "student_id"},
  {collection: "playback_sessions", field: "student_id"},
  {collection: "student_subject_pricing", field: "student_id"},
  {collection: "video_watch_windows", field: "user_id"},
  {collection: "device_change_requests", field: "student_id"},
  {collection: "payment_logs", field: "student_id"},
  {collection: "lecture_access_grants", field: "student_id"},
  {collection: "registration_requests", field: "student_id"},
];

function chunk(values, size) {
  const out = [];
  for (let i = 0; i < values.length; i += size) out.push(values.slice(i, i + size));
  return out;
}

async function linkedCounts(db, studentIds) {
  const byCollection = {};
  for (const {collection, field} of LINKED_COLLECTIONS) {
    const perStudent = {};
    let total = 0;
    try {
      for (const ids of chunk(studentIds, 10)) {
        if (ids.length === 0) break;
        const snap = await db
          .collection(collection)
          .where(field, "in", ids)
          .select(field, "is_deleted", "status", "enabled")
          .get();
        for (const doc of snap.docs) {
          const data = doc.data() ?? {};
          const owner = typeof data[field] === "string" ? data[field] : null;
          if (!owner) continue;
          perStudent[owner] = (perStudent[owner] ?? 0) + 1;
          total += 1;
        }
      }
      byCollection[collection] = {field, total, perStudent};
    } catch (error) {
      byCollection[collection] = {
        field,
        total: null,
        perStudent: {},
        error: error?.message ?? String(error),
      };
    }
  }

  // Derived child rows: replies are keyed by question_id, messages by room_id.
  const derived = {};
  try {
    const questions = await db
      .collection("student_questions")
      .where("student_id", "in", studentIds.slice(0, 10))
      .select("student_id")
      .get();
    const questionOwner = new Map();
    for (const doc of questions.docs) {
      const owner = (doc.data() ?? {}).student_id;
      if (typeof owner === "string") questionOwner.set(doc.id, owner);
    }
    let replies = 0;
    for (const ids of chunk([...questionOwner.keys()], 10)) {
      if (ids.length === 0) break;
      const snap = await db
        .collection("student_question_replies")
        .where("question_id", "in", ids)
        .select("question_id")
        .get();
      replies += snap.size;
    }
    derived.student_question_replies = replies;
  } catch (error) {
    derived.student_question_replies = {error: error?.message ?? String(error)};
  }

  try {
    const rooms = await db
      .collection("chat_rooms")
      .where("student_id", "in", studentIds.slice(0, 10))
      .select("student_id")
      .get();
    const roomOwner = new Map();
    for (const doc of rooms.docs) {
      const owner = (doc.data() ?? {}).student_id;
      if (typeof owner === "string") roomOwner.set(doc.id, owner);
    }
    let messages = 0;
    for (const ids of chunk([...roomOwner.keys()], 10)) {
      if (ids.length === 0) break;
      const snap = await db
        .collection("chat_messages")
        .where("room_id", "in", ids)
        .select("room_id")
        .get();
      messages += snap.size;
    }
    derived.chat_messages = messages;
  } catch (error) {
    derived.chat_messages = {error: error?.message ?? String(error)};
  }

  return {byCollection, derived};
}

async function main() {
  const outDir = argValue("--out");
  if (!outDir) fail("--out <local backup directory> is required.");
  if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    fail("GOOGLE_APPLICATION_CREDENTIALS is not set.");
  }
  const credProject = credentialProjectId();
  if (credProject !== EXPECTED_PROJECT_ID) {
    fail(`Refusing to run: credential project is ${credProject ?? "<unknown>"}, expected ${EXPECTED_PROJECT_ID}.`);
  }
  if (admin.apps.length === 0) {
    admin.initializeApp({projectId: EXPECTED_PROJECT_ID});
  }
  if ((admin.app().options.projectId ?? "") !== EXPECTED_PROJECT_ID) {
    fail(`Refusing to run: Admin SDK project is ${admin.app().options.projectId}.`);
  }

  fs.mkdirSync(outDir, {recursive: true});
  const db = admin.firestore();
  const auth = admin.auth();
  const manifest = [];

  console.log(`=== production inventory (READ-ONLY) ===`);
  console.log(`project: ${EXPECTED_PROJECT_ID}`);
  console.log(`backup directory: ${outDir}`);

  // Root collections + documented counts.
  const rootCollections = (await db.listCollections()).map((c) => c.id).sort();
  const collectionCounts = {};
  for (const name of rootCollections) {
    collectionCounts[name] = await countCollection(db, name);
  }

  // Auth users (full backup).
  const authUsers = [];
  let pageToken;
  do {
    const page = await auth.listUsers(1000, pageToken);
    for (const user of page.users) authUsers.push(user.toJSON());
    pageToken = page.pageToken;
  } while (pageToken);

  // Firestore users (full backup).
  const usersSnap = await db.collection("users").get();
  const users = usersSnap.docs.map((doc) => ({id: doc.id, data: doc.data() ?? {}}));

  const usersById = new Map(users.map((entry) => [entry.id, entry.data]));
  const authById = new Map(authUsers.map((entry) => [entry.uid, entry]));
  const allIds = new Set([...usersById.keys(), ...authById.keys()]);

  const entries = [...allIds].map((uid) => {
    const user = usersById.get(uid) ?? {};
    const authUser = authById.get(uid) ?? null;
    const claims = authUser?.customClaims ?? {};
    const firestoreRole = normalizeRole(user.role);
    const claimRole = normalizeRole(claims.role);
    const role = firestoreRole || claimRole || "unknown";
    const isStudentRole = role === "student" || role === "new_student";
    return {
      uid,
      role,
      firestoreRole: firestoreRole || null,
      claimRole: claimRole || null,
      approvedClaim: claims.approved === true,
      authDisabled: authUser?.disabled === true,
      hasAuth: authUser !== null,
      hasFirestoreUser: usersById.has(uid),
      phoneMasked: mask(user.phone_number ?? authUser?.phoneNumber),
      phoneNumber: user.phone_number ?? authUser?.phoneNumber ?? null,
      fullName: user.full_name ?? authUser?.displayName ?? "",
      accountStatus: user.account_status ?? null,
      approvalStatus: user.approval_status ?? null,
      isDeleted: user.is_deleted === true,
      createdAt: user.created_at ?? null,
      lastSignIn: authUser?.metadata?.lastSignInTime ?? null,
      isStudentRole,
    };
  });

  const roleCounts = entries.reduce((acc, entry) => {
    acc[entry.role] = (acc[entry.role] ?? 0) + 1;
    return acc;
  }, {});
  const doctorCandidates = entries.filter(
    (entry) => entry.role === "doctor" || entry.role === "teacher",
  );
  const adminCandidates = entries.filter((entry) => entry.role === "admin");
  const studentCandidates = entries.filter((entry) => entry.isStudentRole);
  const studentIds = studentCandidates.map((entry) => entry.uid);

  // Phone duplicates among non-deleted, non-disabled accounts.
  const phoneGroups = new Map();
  for (const entry of entries) {
    const phone = typeof entry.phoneNumber === "string" ? entry.phoneNumber.trim() : "";
    if (!phone) continue;
    if (entry.isDeleted || entry.authDisabled) continue;
    const group = phoneGroups.get(phone) ?? [];
    group.push(entry.uid);
    phoneGroups.set(phone, group);
  }
  const duplicateActivePhones = [...phoneGroups.entries()]
    .filter(([, uids]) => uids.length > 1)
    .map(([phone, uids]) => ({phoneMasked: mask(phone), uids}));

  const linked = await linkedCounts(db, studentIds);
  const linkedTotals = Object.fromEntries(
    Object.entries(linked.byCollection).map(([name, info]) => [
      name,
      info.total,
    ]),
  );
  linkedTotals.student_question_replies = linked.derived.student_question_replies;
  linkedTotals.chat_messages = linked.derived.chat_messages;

  const inventory = {
    generatedAt: new Date().toISOString(),
    project: EXPECTED_PROJECT_ID,
    rootCollections,
    collectionCounts,
    auth: {
      total: authUsers.length,
      disabled: authUsers.filter((u) => u.disabled === true).length,
    },
    firestoreUsers: {
      total: users.length,
      softDeleted: users.filter((u) => u.data.is_deleted === true).length,
    },
    roleCounts,
    doctorCandidates: doctorCandidates.map((entry) => ({
      uid: entry.uid,
      role: entry.role,
      phoneMasked: entry.phoneMasked,
      fullName: entry.fullName,
      hasAuth: entry.hasAuth,
      authDisabled: entry.authDisabled,
      approvedClaim: entry.approvedClaim,
      accountStatus: entry.accountStatus,
      isDeleted: entry.isDeleted,
    })),
    adminCandidates: adminCandidates.map((entry) => ({
      uid: entry.uid,
      phoneMasked: entry.phoneMasked,
      fullName: entry.fullName,
      hasAuth: entry.hasAuth,
      authDisabled: entry.authDisabled,
      approvedClaim: entry.approvedClaim,
      accountStatus: entry.accountStatus,
      isDeleted: entry.isDeleted,
    })),
    students: {
      total: studentCandidates.length,
      withAuth: studentCandidates.filter((entry) => entry.hasAuth).length,
      withFirestoreUser: studentCandidates.filter((entry) => entry.hasFirestoreUser).length,
      alreadyDisabledAuth: studentCandidates.filter((entry) => entry.authDisabled).length,
      alreadySoftDeleted: studentCandidates.filter((entry) => entry.isDeleted).length,
      pendingApproval: studentCandidates.filter((entry) => entry.approvalStatus === "pending").length,
      approved: studentCandidates.filter((entry) => entry.approvalStatus === "approved").length,
      list: studentCandidates.map((entry) => ({
        uid: entry.uid,
        role: entry.role,
        phoneMasked: entry.phoneMasked,
        fullName: entry.fullName,
        hasAuth: entry.hasAuth,
        authDisabled: entry.authDisabled,
        hasFirestoreUser: entry.hasFirestoreUser,
        accountStatus: entry.accountStatus,
        approvalStatus: entry.approvalStatus,
        isDeleted: entry.isDeleted,
        lastSignIn: entry.lastSignIn,
      })),
    },
    duplicateActivePhones,
    linkedTotals,
    linkedPerStudent: Object.fromEntries(
      Object.entries(linked.byCollection).map(([name, info]) => [
        name,
        info.perStudent,
      ]),
    ),
    unknownCollections: rootCollections.filter(
      (name) =>
        ![
          "users",
          "user_secrets",
          "devices",
          "notifications",
          "analytics_events",
          "security_events",
          "notes",
          "bookmarks",
          "learning_progress",
          "lecture_progress",
          "subject_progress_summary",
          "subscriptions",
          "subject_access_assignments",
          "quiz_attempts",
          "exam_attempts",
          "password_reset_requests",
          "student_questions",
          "student_question_replies",
          "chat_rooms",
          "chat_messages",
          "subject_device_authorizations",
          "playback_sessions",
          "student_subject_pricing",
          "student_financial_accounts",
          "video_watch_windows",
          "device_change_requests",
          "payment_logs",
          "lecture_access_grants",
          "registration_requests",
          "subjects",
          "subject_sections",
          "lectures",
          "lecture_resources",
          "plans",
          "plan_features",
          "platform_features",
          "system_settings",
          "admin_audit_log",
          "admin_permissions",
          "auth_security_events",
          "login_throttle",
          "video_rate_limits",
          "custom_groups",
          "academic_periods",
          "timeline_quizzes",
          "question_bank",
          "exams",
          "exam_questions",
          "notification_dlq",
          "retries",
        ].includes(name),
    ),
  };

  manifest.push(writeJson(outDir, "auth_users.json", authUsers));
  manifest.push(writeJson(outDir, "users.json", users));
  manifest.push(writeJson(outDir, "inventory.json", inventory));
  manifest.push(
    writeJson(outDir, "manifest.json", {
      generatedAt: inventory.generatedAt,
      project: EXPECTED_PROJECT_ID,
      files: manifest,
    }),
  );

  console.log(`root collections: ${rootCollections.length}`);
  console.log(`auth users: ${inventory.auth.total} (disabled ${inventory.auth.disabled})`);
  console.log(`firestore users: ${inventory.firestoreUsers.total} (soft-deleted ${inventory.firestoreUsers.softDeleted})`);
  console.log(`role counts: ${JSON.stringify(roleCounts)}`);
  console.log(`doctor candidates: ${doctorCandidates.length}`);
  for (const entry of inventory.doctorCandidates) {
    console.log(`  - ${entry.uid} role=${entry.role} disabled=${entry.authDisabled} deleted=${entry.isDeleted} name=${entry.fullName}`);
  }
  console.log(`admin candidates: ${adminCandidates.length}`);
  for (const entry of inventory.adminCandidates) {
    console.log(`  - ${entry.uid} disabled=${entry.authDisabled} deleted=${entry.isDeleted} name=${entry.fullName}`);
  }
  console.log(`students: ${inventory.students.total} (auth ${inventory.students.withAuth}, firestore ${inventory.students.withFirestoreUser}, already disabled ${inventory.students.alreadyDisabledAuth}, already soft-deleted ${inventory.students.alreadySoftDeleted})`);
  console.log(`duplicate active phones: ${duplicateActivePhones.length}`);
  console.log(`linked totals: ${JSON.stringify(linkedTotals)}`);
  if (inventory.unknownCollections.length > 0) {
    console.log(`unknown root collections: ${inventory.unknownCollections.join(", ")}`);
  }
  console.log(`wrote: ${manifest.map((m) => m.file).join(", ")}`);
}

main().catch((error) => {
  console.error(`ERROR: ${error?.message ?? error}`);
  process.exitCode = 1;
});
