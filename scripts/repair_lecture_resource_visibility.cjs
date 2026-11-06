/**
 * One-shot, idempotent repair: republishes `lecture_resources` rows that were
 * authored while their lecture was still a draft and later became published
 * without the rows being flipped visible.
 *
 * Why this exists
 * ---------------
 * The student listing/serving gate (`getLectureResources` and the Firestore
 * gate) only returns resources whose `is_visible == true`. Lectures created
 * as drafts store their rows hidden; before the writer fix, publishing the
 * lecture (Dashboard "Publish Now", scheduled auto-publish, or the mobile
 * admin status toggle) changed only `lectures.status`, leaving those rows
 * hidden forever. Students then saw
 * "No published video source found for this lecture".
 *
 * Scope and safety
 * ----------------
 * - Repairs ONLY lectures whose `status == "published"` and
 *   `is_deleted != true` (archived/draft lectures are untouched).
 * - Flips ONLY non-deleted resource rows whose `is_visible != true`, setting
 *   `is_visible` and its legacy mirror `visibility` to true.
 * - Also recomputes `lectures.first_video` with the canonical selector from
 *   `scripts/backfill_first_video.cjs` (same predicate as the Dashboard
 *   writer, backend listing, and client `firstPlayableVideo`).
 * - Deliberate per-resource hiding is not distinguishable from the draft
 *   state in stored data; this script intentionally treats a published
 *   lecture's non-deleted rows as published. Review the dry-run output first.
 * - DRY-RUN by default; writes ONLY with `--apply` (same convention as
 *   `scripts/migrate_public_to_guest.cjs` and `backfill_first_video.cjs`).
 * - Idempotent: reruns converge to zero writes.
 * - Batched writes (400/batch, Firestore limit 500).
 * - Prints IDs/counts only — never secrets, tokens, URLs, or credential data.
 *
 * Usage:
 *   node scripts\repair_lecture_resource_visibility.cjs           (DRY-RUN)
 *   node scripts\repair_lecture_resource_visibility.cjs --apply   (writes)
 *
 * Credentials (pick ONE):
 *   set GOOGLE_APPLICATION_CREDENTIALS=<service-account.json>
 *   (or set FIRESTORE_EMULATOR_HOST to run against the emulator).
 */
const path = require("path");

let admin;
try {
  const {createRequire} = require("module");
  const functionsRequire = createRequire(
    path.join(__dirname, "..", "functions", "package.json"),
  );
  admin = functionsRequire("firebase-admin");
} catch (error) {
  console.error(
    "Could not load firebase-admin from functions/node_modules.\n" +
      'Run "npm install" inside the functions/ folder first.',
  );
  process.exit(1);
}

const {
  selectFirstVideo,
  firstVideoFields,
  sameFirstVideo,
  BATCH_LIMIT,
  EXPECTED_PROJECT_ID,
  normalizeProjectId,
  readCredentialFileProjectId,
  verifyTargetProjectOrExit,
} = require("./backfill_first_video.cjs");

const APPLY = process.argv.includes("--apply");
const DRY_RUN = !APPLY;

function log(message) {
  console.log(message);
}

/**
 * Pure per-lecture plan builder. Kept side-effect-free so the dry-run output
 * and the applied writes are guaranteed to make the same decision.
 *
 * @param {object} lectureData lecture document data
 * @param {Array<{id: string, data: object}>} resources lecture_resources rows
 * @return {{flip: string[], firstVideo: object|null}}
 */
function planLectureRepair(lectureData, resources) {
  const storedFirstVideo =
    lectureData && typeof lectureData.first_video === "object"
      ? lectureData.first_video
      : null;

  const flip = [];
  const publishedRows = [];
  for (const row of resources) {
    const data = row.data && typeof row.data === "object" ? row.data : {};
    if (data.is_deleted === true) continue;
    const needsFlip = data.is_visible !== true;
    if (needsFlip) flip.push(row.id);
    // Union of what the student will see after this repair.
    publishedRows.push({
      id: row.id,
      data: {...data, is_visible: true},
    });
  }

  const winner = selectFirstVideo(publishedRows);
  const computed = winner === null ? null : firstVideoFields(winner);
  return {
    flip,
    firstVideo: computed,
    firstVideoChanged: !sameFirstVideo(storedFirstVideo, computed),
  };
}

async function repairVisibility() {
  log(
    `=== lecture resource visibility repair (${DRY_RUN ? "DRY-RUN" : "APPLY"}) ===`,
  );
  const usingEmulator = !!process.env.FIRESTORE_EMULATOR_HOST;
  if (!usingEmulator && !process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    console.error(
      "ERROR: set GOOGLE_APPLICATION_CREDENTIALS to your service-account " +
        "JSON path first\n(or set FIRESTORE_EMULATOR_HOST to run against " +
        "the emulator).",
    );
    process.exit(1);
  }
  if (admin.apps.length === 0) {
    if (usingEmulator) {
      admin.initializeApp();
    } else {
      admin.initializeApp({projectId: EXPECTED_PROJECT_ID});
    }
  }
  // Strict target-project guard (same as the other migration scripts):
  // unconditional, before any Firestore client/query. Logs only the project.
  {
    const appOptions = (admin.app() && admin.app().options) || {};
    const adminOptionsProjectId = normalizeProjectId(appOptions.projectId);
    let adminCredentialProjectId = null;
    try {
      adminCredentialProjectId = normalizeProjectId(
        appOptions.credential && appOptions.credential.projectId,
      );
    } catch {
      adminCredentialProjectId = null;
    }
    const credentialFileProjectId = readCredentialFileProjectId(
      process.env.GOOGLE_APPLICATION_CREDENTIALS,
    );
    verifyTargetProjectOrExit({
      env: process.env,
      adminOptionsProjectId,
      adminCredentialProjectId,
      credentialFileProjectId,
    });
  }
  const db = admin.firestore();

  const counters = {
    publishedLectures: 0,
    skippedLectures: 0,
    lecturesChanged: 0,
    resourcesFlipped: 0,
    firstVideoAssigned: 0,
    firstVideoCleared: 0,
    errors: 0,
  };
  const failedLectures = [];

  let batch = db.batch();
  let batchOps = 0;
  const commitBatch = async () => {
    if (batchOps === 0) return;
    await batch.commit();
    batch = db.batch();
    batchOps = 0;
  };

  // Small collection in this platform: fetch lectures once and filter in
  // memory (avoids adding a composite index requirement for this one-off).
  const lecturesSnap = await db.collection("lectures").get();
  for (const lectureDoc of lecturesSnap.docs) {
    const lectureId = lectureDoc.id;
    const lectureData = lectureDoc.data() ?? {};
    if (lectureData.status !== "published" || lectureData.is_deleted === true) {
      counters.skippedLectures++;
      continue;
    }
    counters.publishedLectures++;
    try {
      const resourcesSnap = await db
        .collection("lecture_resources")
        .where("lecture_id", "==", lectureId)
        .get();
      const resources = resourcesSnap.docs.map((doc) => ({
        id: doc.id,
        data: doc.data() ?? {},
      }));
      const plan = planLectureRepair(lectureData, resources);

      if (plan.flip.length === 0 && !plan.firstVideoChanged) continue;

      counters.lecturesChanged++;
      counters.resourcesFlipped += plan.flip.length;
      if (plan.firstVideoChanged) {
        if (plan.firstVideo === null) {
          counters.firstVideoCleared++;
        } else {
          counters.firstVideoAssigned++;
        }
      }

      if (DRY_RUN) {
        log(
          `[dry-run] ${lectureId}: flip ${plan.flip.length} resource(s)` +
            (plan.flip.length > 0 ? ` [${plan.flip.join(", ")}]` : "") +
            (plan.firstVideoChanged
              ? `; first_video=${plan.firstVideo === null ? "null" : plan.firstVideo.resource_id}`
              : "; first_video unchanged"),
        );
        continue;
      }

      for (const resourceId of plan.flip) {
        batch.update(
          db.collection("lecture_resources").doc(resourceId),
          {
            is_visible: true,
            visibility: true,
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
            updated_by: "migration_repair_visibility",
          },
        );
        batchOps++;
      }
      if (plan.firstVideoChanged) {
        batch.update(lectureDoc.ref, {first_video: plan.firstVideo});
        batchOps++;
      }
      if (batchOps >= BATCH_LIMIT) {
        await commitBatch();
      }
    } catch (error) {
      counters.errors++;
      failedLectures.push(lectureId);
      console.error(`[error] ${lectureId}: ${error?.message ?? error}`);
    }
  }
  await commitBatch();

  log("=== repair summary ===");
  log(`lectures scanned: ${lecturesSnap.size}`);
  log(`published lectures: ${counters.publishedLectures}`);
  log(`skipped (draft/archived): ${counters.skippedLectures}`);
  log(
    DRY_RUN
      ? `lectures that would change: ${counters.lecturesChanged}`
      : `lectures changed: ${counters.lecturesChanged}`,
  );
  log(
    DRY_RUN
      ? `resources that would be republished: ${counters.resourcesFlipped}`
      : `resources republished: ${counters.resourcesFlipped}`,
  );
  log(`first_video assigned: ${counters.firstVideoAssigned}`);
  log(`first_video cleared: ${counters.firstVideoCleared}`);
  log(`errors: ${counters.errors}`);
  if (failedLectures.length > 0) {
    log(`failed lectures: ${failedLectures.join(", ")}`);
    process.exitCode = 1;
  }
}

module.exports = {
  planLectureRepair,
};

if (require.main === module) {
  repairVisibility().catch((error) => {
    console.error("[Repair] Failed:", error);
    process.exitCode = 1;
  });
}
