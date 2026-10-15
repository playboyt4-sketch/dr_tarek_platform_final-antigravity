/**
 * One-shot, idempotent backfill: populates `lectures/{lectureId}.first_video`
 * for existing lectures using the canonical Phase 2/3 first-video semantics.
 *
 * Canonical eligibility (MUST match dashboard `selectFirstVideoCandidate`,
 * backend listing order + `isServedLectureResource`, and client
 * `firstPlayableVideo`):
 *   resource_type == "video" && is_visible == true && is_deleted != true
 *   && bunny_video_id non-empty after trimming.
 * Winner: lowest display_order, document ID ascending as tiebreak.
 *
 * Result shape (identity + display metadata ONLY — never signed URLs,
 * secrets, storage URLs, or per-student authorization state):
 *   first_video: {resource_id, bunny_video_id, title?, display_order,
 *                 thumbnail_path?, thumbnail_storage_provider?} | null
 * Thumbnail keys are written only when the resource row already carries
 * authoritative values; otherwise explicit nulls (same as Dashboard).
 *
 * Boundary note (why script-local helpers): this plain-node migration
 * cannot import the Flutter/Dart selector or the TypeScript sources
 * without build coupling across packages. The predicates below reproduce
 * the exact Phase 2/3 semantics and are unit-tested in
 * functions/test/first_video_backfill.test.js alongside an emulator
 * end-to-end run of this script.
 *
 * Safety:
 * - DRY-RUN by default (read-only); writes ONLY with --apply
 *   (same convention as scripts/migrate_public_to_guest.cjs).
 * - Recomputes EVERY lecture (never blind-skips existing first_video),
 *   but writes only when the recomputed value differs (idempotent;
 *   reruns converge to zero writes).
 * - Updates ONLY the first_video field; unrelated lecture fields untouched.
 * - Batched writes (400/batch, Firestore limit 500).
 * - Per-lecture failures are collected; processing continues because each
 *   lecture is an independent single-document write and reruns repair
 *   gaps idempotently. Nonzero exit when any lecture failed.
 *
 * Usage:
 *   node scripts\backfill_first_video.cjs                 (DRY-RUN)
 *   node scripts\backfill_first_video.cjs --apply         (perform writes)
 *
 * Credentials (read-only-safe — pick ONE):
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
      "Run \"npm install\" inside the functions/ folder first.",
  );
  process.exit(1);
}

const APPLY = process.argv.includes("--apply");
const DRY_RUN = !APPLY;
const BATCH_LIMIT = 400;
const EXPECTED_PROJECT_ID = "dr-tarek-platform";

function log(message) {
  console.log(message);
}

/**
 * Strict target-project guard (Phase 8).
 * firebase use / .firebaserc NEVER control the Admin SDK; the effective
 * project must come from the Admin SDK configuration actually in use.
 * This guard runs unconditionally (dry-run AND --apply) BEFORE any
 * Firestore query. It logs only the project ID — never keys, tokens,
 * or credential file contents.
 */
function normalizeProjectId(value) {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed === "" ? null : trimmed;
}

function parseFirebaseConfigProjectId(env) {
  try {
    const raw = env && env.FIREBASE_CONFIG;
    if (!raw) return null;
    const parsed = JSON.parse(raw);
    return normalizeProjectId(parsed && parsed.projectId);
  } catch {
    return null;
  }
}

function extractCredentialProjectIdFromJsonText(text) {
  try {
    if (typeof text !== "string" || text.trim() === "") return null;
    const parsed = JSON.parse(text);
    return normalizeProjectId(parsed && parsed.project_id);
  } catch {
    return null;
  }
}

function readCredentialFileProjectId(credPath) {
  try {
    if (!credPath) return null;
    const fs = require("node:fs");
    const text = fs.readFileSync(credPath, "utf8");
    return extractCredentialProjectIdFromJsonText(text);
  } catch {
    return null;
  }
}

function collectProjectIdCandidates({
  adminOptionsProjectId = null,
  adminCredentialProjectId = null,
  env = {},
  credentialFileProjectId = null,
} = {}) {
  const candidates = [];
  const push = (value) => {
    const normalized = normalizeProjectId(value);
    if (normalized) candidates.push(normalized);
  };
  push(adminOptionsProjectId);
  push(adminCredentialProjectId);
  push(env && env.GOOGLE_CLOUD_PROJECT);
  push(env && env.GCLOUD_PROJECT);
  push(parseFirebaseConfigProjectId(env));
  push(credentialFileProjectId);
  return candidates;
}

function resolveEffectiveProjectId({
  adminOptionsProjectId = null,
  adminCredentialProjectId = null,
  env = {},
  credentialFileProjectId = null,
} = {}) {
  const candidates = collectProjectIdCandidates({
    adminOptionsProjectId,
    adminCredentialProjectId,
    env,
    credentialFileProjectId,
  });
  const distinct = [...new Set(candidates)];
  if (distinct.length === 0) {
    return {projectId: null, reason: "missing", candidates, distinct};
  }
  if (distinct.length > 1) {
    return {projectId: null, reason: "ambiguous", candidates, distinct};
  }
  return {projectId: distinct[0], reason: "ok", candidates, distinct};
}

function verifyTargetProject({
  env = {},
  adminOptionsProjectId = null,
  adminCredentialProjectId = null,
  credentialFileProjectId = null,
} = {}) {
  const usingEmulator = !!(env && env.FIRESTORE_EMULATOR_HOST);
  if (usingEmulator) {
    const emulatorProject =
      normalizeProjectId(adminOptionsProjectId) ||
      normalizeProjectId(env && env.GCLOUD_PROJECT) ||
      normalizeProjectId(env && env.GOOGLE_CLOUD_PROJECT) ||
      normalizeProjectId(credentialFileProjectId) ||
      "unknown-emulator-project";
    log(
      `[guard] emulator mode; Firestore target project: ${emulatorProject} ` +
        `(FIRESTORE_EMULATOR_HOST is set; production guard bypassed for emulator only)`
    );
    return emulatorProject;
  }
  const resolved = resolveEffectiveProjectId({
    adminOptionsProjectId,
    adminCredentialProjectId,
    env,
    credentialFileProjectId,
  });
  if (!resolved.projectId) {
    throw new Error(
      `[guard] unable to determine Admin SDK target project (${resolved.reason}; ` +
        `expected "${EXPECTED_PROJECT_ID}"). ` +
        `Provide an explicit Admin SDK projectId or a valid service-account ` +
        `credential; refusing to touch Firestore.`
    );
  }
  if (resolved.projectId !== EXPECTED_PROJECT_ID) {
    throw new Error(
      `[guard] Admin SDK target project "${resolved.projectId}" does not match ` +
        `expected "${EXPECTED_PROJECT_ID}"; refusing to touch Firestore.`
    );
  }
  log(`[guard] verified Firestore target project: ${resolved.projectId}`);
  return resolved.projectId;
}

function verifyTargetProjectOrExit(deps) {
  try {
    return verifyTargetProject(deps);
  } catch (error) {
    console.error(error && error.message ? error.message : String(error));
    process.exit(1);
    return null;
  }
}

/**
 * Canonical eligibility on a raw lecture_resources document snapshot.
 * Pure — mirrors Phase 2/3 exactly.
 */
function isFirstVideoEligible(id, data) {
  if (!data || typeof data !== "object") return false;
  if (data.resource_type !== "video") return false;
  if (data.is_visible !== true) return false;
  if (data.is_deleted === true) return false;
  const bunnyVideoId = data.bunny_video_id;
  if (typeof bunnyVideoId !== "string" || bunnyVideoId.trim() === "") {
    return false;
  }
  return true;
}

/**
 * Canonical winner selection over [{id, data}]. Explicit local sort by
 * (display_order, id) so the result never depends on transport order.
 * Pure — returns the winning entry or null.
 */
function selectFirstVideo(entries) {
  let winner = null;
  let winnerOrder = 0;
  for (const entry of entries) {
    if (!isFirstVideoEligible(entry.id, entry.data)) continue;
    const rawOrder = entry.data.display_order;
    const order =
      typeof rawOrder === "number" && Number.isFinite(rawOrder)
        ? Math.trunc(rawOrder)
        : 0;
    if (
      winner === null ||
      order < winnerOrder ||
      (order === winnerOrder && entry.id < winner.id)
    ) {
      winner = entry;
      winnerOrder = order;
    }
  }
  return winner;
}

/**
 * Serializes the winner into the denormalized first_video map.
 * Pure — identity + display metadata only.
 */
function firstVideoFields(winner) {
  const data = winner.data;
  const title = typeof data.title === "string" ? data.title.trim() : "";
  const thumbnailPath =
    typeof data.thumbnail === "string" && data.thumbnail.trim() !== ""
      ? data.thumbnail.trim()
      : null;
  const thumbnailProvider =
    typeof data.thumbnail_storage_provider === "string" &&
    data.thumbnail_storage_provider.trim() !== ""
      ? data.thumbnail_storage_provider.trim()
      : typeof data.thumbnailStorageProvider === "string" &&
        data.thumbnailStorageProvider.trim() !== ""
      ? data.thumbnailStorageProvider.trim()
      : null;
  return {
    resource_id: winner.id,
    bunny_video_id: data.bunny_video_id.trim(),
    title: title,
    display_order:
      typeof data.display_order === "number" &&
      Number.isFinite(data.display_order)
        ? Math.trunc(data.display_order)
        : 0,
    thumbnail_path: thumbnailPath,
    thumbnail_storage_provider: thumbnailProvider,
  };
}

/**
 * Normalized comparison so reruns skip byte-identical values
 * (idempotency without relying on Firestore update timestamps).
 */
function sameFirstVideo(stored, computed) {
  if (stored == null && computed == null) return true;
  if (stored == null || computed == null) return false;
  const keys = [
    "resource_id",
    "bunny_video_id",
    "title",
    "display_order",
    "thumbnail_path",
    "thumbnail_storage_provider",
  ];
  for (const key of keys) {
    if ((stored[key] ?? null) !== (computed[key] ?? null)) return false;
  }
  return true;
}

async function backfillFirstVideo() {
  log(
    `=== lectures.first_video backfill (${DRY_RUN ? "DRY-RUN" : "APPLY"}) ===`
  );
  const usingEmulator = !!process.env.FIRESTORE_EMULATOR_HOST;
  if (!usingEmulator && !process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    console.error(
      "ERROR: set GOOGLE_APPLICATION_CREDENTIALS to your service-account " +
        "JSON path first\n(or set FIRESTORE_EMULATOR_HOST to run against " +
        "the emulator)."
    );
    process.exit(1);
  }
  if (admin.apps.length === 0) {
    if (usingEmulator) {
      // Emulator path unchanged: the emulator project (demo-*) comes from
      // the environment so emulator-seeded data stays addressable.
      admin.initializeApp();
    } else {
      // Production path: explicit target project. This alone proves
      // nothing — the guard below still validates the effective identity
      // (including any conflicting explicit/env/credential values) before
      // any Firestore client is created.
      admin.initializeApp({projectId: EXPECTED_PROJECT_ID});
    }
  }
  // Strict target-project guard: unconditional for DRY-RUN and --apply,
  // placed BEFORE admin.firestore() and BEFORE the first Firestore query.
  // firebase use / .firebaserc do NOT control the Admin SDK.
  {
    const appOptions = (admin.app() && admin.app().options) || {};
    const adminOptionsProjectId = normalizeProjectId(appOptions.projectId);
    let adminCredentialProjectId = null;
    try {
      adminCredentialProjectId = normalizeProjectId(
        appOptions.credential && appOptions.credential.projectId
      );
    } catch {
      adminCredentialProjectId = null;
    }
    const credentialFileProjectId = readCredentialFileProjectId(
      process.env.GOOGLE_APPLICATION_CREDENTIALS
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
    scanned: 0,
    updated: 0,
    assigned: 0,
    cleared: 0,
    noEligible: 0,
    malformedResources: 0,
    tieWins: 0,
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

  const lecturesSnap = await db.collection("lectures").get();
  for (const lectureDoc of lecturesSnap.docs) {
    const lectureId = lectureDoc.id;
    counters.scanned++;
    try {
      const resourcesSnap = await db
        .collection("lecture_resources")
        .where("lecture_id", "==", lectureId)
        .where("is_visible", "==", true)
        .orderBy("display_order")
        .get();

      const entries = [];
      const seenOrders = new Set();
      let duplicateOrder = false;
      for (const resourceDoc of resourcesSnap.docs) {
        const data = resourceDoc.data() ?? {};
        if (typeof data !== "object" || Array.isArray(data)) {
          counters.malformedResources++;
          continue;
        }
        entries.push({id: resourceDoc.id, data});
        if (data.resource_type === "video" && data.is_deleted !== true) {
          const orderKey = `${data.display_order ?? 0}`;
          if (seenOrders.has(orderKey)) duplicateOrder = true;
          seenOrders.add(orderKey);
        }
      }

      const winner = selectFirstVideo(entries);
      if (duplicateOrder && winner !== null) counters.tieWins++;
      const computed =
        winner === null ? null : firstVideoFields(winner);

      const storedRaw = lectureDoc.data()?.first_video ?? null;
      const stored =
        storedRaw !== null && typeof storedRaw === "object"
          ? storedRaw
          : null;
      if (sameFirstVideo(stored, computed)) continue;

      if (computed === null) {
        counters.noEligible++;
        counters.cleared++;
      } else {
        counters.assigned++;
      }
      counters.updated++;

      if (DRY_RUN) {
        log(
          `[dry-run] ${lectureId}: would write ` +
            (computed === null
              ? "first_video=null"
              : `first_video={resource_id=${computed.resource_id}, ` +
                `bunny_video_id=${computed.bunny_video_id}, ` +
                `display_order=${computed.display_order}}`)
        );
        continue;
      }
      batch.update(lectureDoc.ref, {first_video: computed});
      batchOps++;
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

  log("=== backfill summary ===");
  log(`lectures scanned: ${counters.scanned}`);
  log(
    DRY_RUN
      ? `lectures that would update: ${counters.updated}`
      : `lectures updated: ${counters.updated}`
  );
  log(`first_video assigned: ${counters.assigned}`);
  log(`first_video cleared: ${counters.cleared}`);
  log(`lectures with no eligible video: ${counters.noEligible}`);
  log(`malformed resources skipped: ${counters.malformedResources}`);
  log(`winners decided under duplicate display_order: ${counters.tieWins}`);
  log(`errors: ${counters.errors}`);
  if (failedLectures.length > 0) {
    log(`failed lectures: ${failedLectures.join(", ")}`);
    process.exitCode = 1;
  }
}

module.exports = {
  isFirstVideoEligible,
  selectFirstVideo,
  firstVideoFields,
  sameFirstVideo,
  BATCH_LIMIT,
  EXPECTED_PROJECT_ID,
  normalizeProjectId,
  parseFirebaseConfigProjectId,
  extractCredentialProjectIdFromJsonText,
  readCredentialFileProjectId,
  collectProjectIdCandidates,
  resolveEffectiveProjectId,
  verifyTargetProject,
  verifyTargetProjectOrExit,
};

if (require.main === module) {
  backfillFirstVideo().catch((error) => {
    console.error("[Backfill] Failed:", error);
    process.exitCode = 1;
  });
}
