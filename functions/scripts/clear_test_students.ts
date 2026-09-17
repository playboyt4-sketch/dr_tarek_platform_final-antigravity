import { initializeApp, getApps } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

/**
 * One-shot cleanup: removes every TEST student from the LIVE database.
 *
 * Keeps (untouched):
 *  - the teacher account  (users doc id 2B1pvLZ0p5W3hwoXlBi1rUtp0Iy2,
 *    phone 01115800180) with all of its data and secrets;
 *  - reference collections: plans, plan_features, academic_periods,
 *    platform_features, subjects (and everything else not listed below).
 *
 * Deletes:
 *  - every other `users` document (any role / any approval state);
 *  - everything owned by those deleted uids in:
 *    subscriptions, subject_access_assignments, devices, notifications,
 *    exam_attempts, quiz_attempts, lecture_progress, learning_progress,
 *    payment_logs, user_secrets.
 *
 * Auth accounts are NOT touched by this script.
 *
 * Usage (from functions/):
 *   node scripts/clear_test_students.ts            # dry run (default)
 *   node scripts/clear_test_students.ts --live     # real deletion
 *
 * Auth: Application Default Credentials
 * (gcloud auth application-default login) + project dr-tarek-platform.
 */

const PROJECT_ID =
  process.env.GOOGLE_CLOUD_PROJECT ?? "dr-tarek-platform";
const KEEP_PHONE = "01115800180";
const TEACHER_UID = "2B1pvLZ0p5W3hwoXlBi1rUtp0Iy2";
const LIVE = process.argv.includes("--live");
const BATCH_LIMIT = 400;
const IN_CHUNK = 30;

if (getApps().length === 0) {
  initializeApp({ projectId: PROJECT_ID });
}
const db = getFirestore();

interface PerCollectionPlan {
  collection: string;
  field: string | null; // null => document id IS the uid
}

const RELATED: PerCollectionPlan[] = [
  { collection: "subscriptions", field: "student_id" },
  { collection: "subject_access_assignments", field: "student_id" },
  { collection: "devices", field: "user_id" },
  { collection: "notifications", field: "user_id" },
  { collection: "exam_attempts", field: "student_id" },
  { collection: "quiz_attempts", field: "student_id" },
  { collection: "lecture_progress", field: "student_id" },
  { collection: "learning_progress", field: "student_id" },
  { collection: "payment_logs", field: "student_id" },
  { collection: "user_secrets", field: null },
];

function chunk<T>(items: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) {
    out.push(items.slice(i, i + size));
  }
  return out;
}

async function countOwned(
  collection: string,
  field: string | null,
  uids: string[],
): Promise<number> {
  if (uids.length === 0) return 0;
  if (field === null) {
    const refs = uids.map((uid) => db.collection(collection).doc(uid));
    const snaps = await db.getAll(...refs);
    return snaps.filter((s) => s.exists).length;
  }
  let total = 0;
  for (const part of chunk(uids, IN_CHUNK)) {
    const snap = await db
      .collection(collection)
      .where(field, "in", part)
      .get();
    total += snap.size;
  }
  return total;
}

async function deleteOwned(
  collection: string,
  field: string | null,
  uids: string[],
  counters: Record<string, number>,
): Promise<void> {
  if (uids.length === 0) return;
  let batch = db.batch();
  let pending = 0;
  const flush = async () => {
    if (pending === 0) return;
    await batch.commit();
    batch = db.batch();
    pending = 0;
  };
  const erase = async (ref: FirebaseFirestore.DocumentReference) => {
    batch.delete(ref);
    pending += 1;
    counters[collection] = (counters[collection] ?? 0) + 1;
    if (pending >= BATCH_LIMIT) await flush();
  };
  if (field === null) {
    for (const uid of uids) {
      const snap = await db.collection(collection).doc(uid).get();
      if (snap.exists) await erase(snap.ref);
    }
  } else {
    for (const part of chunk(uids, IN_CHUNK)) {
      const snap = await db
        .collection(collection)
        .where(field, "in", part)
        .get();
      for (const doc of snap.docs) await erase(doc.ref);
    }
  }
  await flush();
}

async function main(): Promise<void> {
  console.log(`Project: ${PROJECT_ID} | mode: ${LIVE ? "LIVE" : "DRY-RUN"}`);

  const usersSnap = await db.collection("users").get();
  const keep: string[] = [];
  const drop: { uid: string; name: string; phone: string; role: string }[] =
    [];
  for (const doc of usersSnap.docs) {
    const data = doc.data() as Record<string, unknown>;
    const phone =
      typeof data.phone_number === "string" ? data.phone_number : "";
    if (doc.id === TEACHER_UID || phone === KEEP_PHONE) {
      keep.push(`${doc.id} (phone=${phone || "?"})`);
    } else {
      drop.push({
        uid: doc.id,
        name:
          typeof data.full_name === "string" ? data.full_name : "",
        phone,
        role: typeof data.role === "string" ? data.role : "",
      });
    }
  }

  const teacherPresent = usersSnap.docs.some((d) => d.id === TEACHER_UID);
  console.log(`users total: ${usersSnap.size}`);
  console.log(`KEEP (${keep.length}):`);
  for (const entry of keep) console.log(`  + ${entry}`);
  if (!teacherPresent) {
    throw new Error(
      `SAFETY ABORT: teacher doc ${TEACHER_UID} not found. ` +
        "Refusing to delete anything.",
    );
  }

  const dropUids = drop.map((d) => d.uid);
  console.log(`DELETE users docs (${dropUids.length}):`);
  for (const d of drop.slice(0, 50)) {
    console.log(`  - ${d.uid} name=${d.name} phone=${d.phone} role=${d.role}`);
  }
  if (drop.length > 50) console.log(`  ... and ${drop.length - 50} more`);

  console.log("Related-collection impact per deleted uid set:");
  for (const rel of RELATED) {
    const n = await countOwned(rel.collection, rel.field, dropUids);
    const by = rel.field === null ? "doc-id" : rel.field;
    console.log(`  ${rel.collection} (by ${by}): ${n} docs`);
  }

  if (!LIVE) {
    console.log("DRY-RUN complete — nothing was deleted. Re-run with --live.");
    return;
  }

  const counters: Record<string, number> = {};
  let batch = db.batch();
  let pending = 0;
  for (const uid of dropUids) {
    batch.delete(db.collection("users").doc(uid));
    pending += 1;
    counters["users"] = (counters["users"] ?? 0) + 1;
    if (pending >= BATCH_LIMIT) {
      await batch.commit();
      batch = db.batch();
      pending = 0;
    }
  }
  if (pending > 0) await batch.commit();

  for (const rel of RELATED) {
    await deleteOwned(rel.collection, rel.field, dropUids, counters);
  }

  console.log("Deleted per collection:");
  for (const [collection, n] of Object.entries(counters)) {
    console.log(`  ${collection}: ${n}`);
  }

  const verifyUsers = await db.collection("users").get();
  console.log(`users remaining: ${verifyUsers.size} (expected ${keep.length})`);
  for (const rel of RELATED) {
    const left = await countOwned(rel.collection, rel.field, dropUids);
    console.log(`  ${rel.collection} leftovers for deleted uids: ${left}`);
  }
  console.log("Cleanup complete.");
}

main().catch((err) => {
  console.error("FAILED:", err);
  process.exitCode = 1;
});
