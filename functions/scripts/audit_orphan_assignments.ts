import { initializeApp, getApps } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

/**
 * One-time READ-ONLY audit: lists every `subject_access_assignments` row
 * where access is enabled but no active `subscriptions` document backs the
 * same (student_id, subject_id) pair.
 *
 * These are the "no-plan" rows left behind by the pre-fix partial-save bug
 * (assignment written by `setSubjectAccess`, subscription rejected or never
 * attempted): they render as "بدون خطة نشطة" in the Subjects tab and must
 * be repaired manually per row via the Repair action — this script NEVER
 * modifies data, it only lists candidates for review.
 *
 * Usage (from functions/):
 *   npx ts-node scripts/audit_orphan_assignments.ts
 *
 * Optional filters:
 *   npx ts-node scripts/audit_orphan_assignments.ts --student=<uid>
 *
 * Auth: Application Default Credentials
 * (gcloud auth application-default login) + project dr-tarek-platform.
 */

const PROJECT_ID =
  process.env.GOOGLE_CLOUD_PROJECT ?? "dr-tarek-platform";
const ONLY_STUDENT = (() => {
  const arg = process.argv.find((a) => a.startsWith("--student="));
  return arg ? arg.slice("--student=".length) : null;
})();

if (getApps().length === 0) {
  initializeApp({ projectId: PROJECT_ID });
}
const db = getFirestore();

interface OrphanRow {
  assignmentId: string;
  studentId: string;
  studentName: string | null;
  studentGrade: string | null;
  subjectId: string;
  subjectTitle: string | null;
}

async function main(): Promise<void> {
  const assignmentsSnap = ONLY_STUDENT
    ? await db.collection("subject_access_assignments").where("student_id", "==", ONLY_STUDENT).get()
    : await db.collection("subject_access_assignments").get();

  const orphans: OrphanRow[] = [];
  let scanned = 0;
  for (const doc of assignmentsSnap.docs) {
    const data = doc.data() ?? {};
    if (data.is_deleted === true || data.enabled !== true) continue;
    const studentId = typeof data.student_id === "string" ? data.student_id : null;
    const subjectId = typeof data.subject_id === "string" ? data.subject_id : null;
    if (!studentId || !subjectId) continue;
    scanned += 1;

    const subsSnap = await db.collection("subscriptions")
      .where("student_id", "==", studentId)
      .where("subject_id", "==", subjectId)
      .where("status", "==", "active")
      .limit(1)
      .get();
    const backed = subsSnap.docs.some((s) => (s.data() ?? {}).is_deleted !== true);
    if (backed) continue;

    const [studentSnap, subjectSnap] = await Promise.all([
      db.collection("users").doc(studentId).get(),
      db.collection("subjects").doc(subjectId).get(),
    ]);
    orphans.push({
      assignmentId: doc.id,
      studentId,
      studentName: studentSnap.exists
        ? (typeof studentSnap.data()?.full_name === "string" ? studentSnap.data()?.full_name : null)
        : null,
      studentGrade: studentSnap.exists
        ? (typeof studentSnap.data()?.grade === "string" ? studentSnap.data()?.grade : null)
        : null,
      subjectId,
      subjectTitle: subjectSnap.exists
        ? (typeof subjectSnap.data()?.title === "string" ? subjectSnap.data()?.title : doc.id)
        : null,
    });
  }

  // eslint-disable-next-line no-console
  console.log(`Scanned ${scanned} enabled, non-deleted assignment(s).`);
  if (orphans.length === 0) {
    // eslint-disable-next-line no-console
    console.log("No orphan rows found — every enabled assignment has an active subscription.");
    return;
  }
  // eslint-disable-next-line no-console
  console.log(`Found ${orphans.length} orphan row(s) (LIST ONLY — nothing was modified):`);
  for (const row of orphans) {
    // eslint-disable-next-line no-console
    console.log(
      `- ${row.assignmentId} | student=${row.studentName ?? row.studentId} ` +
      `(${row.studentGrade ?? "grade?"}) | subject=${row.subjectTitle ?? row.subjectId}`,
    );
  }
  // eslint-disable-next-line no-console
  console.log("Repair: open each student in the Dashboard → Subjects tab → Repair.");
}

main().catch((error) => {
  // eslint-disable-next-line no-console
  console.error("Audit failed:", error);
  process.exit(1);
});
