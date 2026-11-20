/**
 * ADR-010 — `lecture_resources.bunny_library_id` backfill utility.
 *
 * READ-ONLY BY CONSTRUCTION. This build has no write path: `--apply` is
 * refused by the pure execution-mode guard, so no invocation can write
 * production data. A separate, explicitly authorized executor is required to
 * ever perform the backfill.
 *
 * Usage (from `functions/`, after `npm run build`):
 *   node lib/scripts/backfill_bunny_library_id.js --mapping mapping.json
 *   node lib/scripts/backfill_bunny_library_id.js --mapping mapping.json --apply   # refused
 *
 * Options:
 *   --mapping <path>   REQUIRED. JSON array of mapping entries:
 *                      {videoId, libraryId, resourceId?, lectureId?, subjectId?}
 *   --out <path>       Report directory. Default: reports/adr010/migration.
 *   --project <id>     Firebase project (default: GCLOUD_PROJECT/env).
 *   --apply            Refused by design (see above).
 *
 * The run prints and persists:
 *   <stamp>-plan.json      full per-resource decisions + summary
 *   <stamp>-backup.json    previous values + snapshot update times (rollback source)
 * and never opens a write.
 */
import {initializeApp, applicationDefault} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {mkdirSync, readFileSync, writeFileSync} from "node:fs";
import {join} from "node:path";
import {
  BunnyLibraryBackfillRow,
  BunnyLibraryMappingEntry,
  buildBunnyLibraryBackfillBackup,
  planBunnyLibraryBackfill,
  resolveBunnyLibraryBackfillMode,
} from "../core/video/bunny_library_migration";

interface Args {
  mappingPath: string | null;
  outDir: string;
  apply: boolean;
  projectId: string | null;
}

function parseArgs(argv: string[]): Args {
  const args: Args = {
    mappingPath: null,
    outDir: "reports/adr010/migration",
    apply: false,
    projectId: null,
  };
  for (let i = 0; i < argv.length; i++) {
    const token = argv[i];
    switch (token) {
    case "--mapping":
      args.mappingPath = argv[++i] ?? null;
      break;
    case "--out":
      args.outDir = argv[++i] ?? args.outDir;
      break;
    case "--project":
      args.projectId = argv[++i] ?? null;
      break;
    case "--apply":
      args.apply = true;
      break;
    default:
      throw new Error(`Unknown argument: ${token}`);
    }
  }
  return args;
}

function loadMapping(path: string): BunnyLibraryMappingEntry[] {
  const raw = JSON.parse(readFileSync(path, "utf8")) as unknown;
  if (!Array.isArray(raw)) {
    throw new Error("Mapping file must be a JSON array of mapping entries.");
  }
  return raw.map((entry) => {
    const record = (entry ?? {}) as Record<string, unknown>;
    const mapping: BunnyLibraryMappingEntry = {
      videoId: typeof record.videoId === "string" ? record.videoId : "",
      libraryId: typeof record.libraryId === "string" ? record.libraryId : "",
    };
    if (typeof record.resourceId === "string") mapping.resourceId = record.resourceId;
    if (typeof record.lectureId === "string") mapping.lectureId = record.lectureId;
    if (typeof record.subjectId === "string") mapping.subjectId = record.subjectId;
    return mapping;
  });
}

async function readSnapshot(projectId: string | null): Promise<BunnyLibraryBackfillRow[]> {
  if (projectId) process.env.GCLOUD_PROJECT = projectId;
  initializeApp({credential: applicationDefault()});
  const db = getFirestore();
  const rows: BunnyLibraryBackfillRow[] = [];
  let cursor: string | null = null;
  for (;;) {
    let query = db.collection("lecture_resources").orderBy("__name__").limit(300);
    if (cursor !== null) query = query.startAfter(cursor);
    const snap = await query.get();
    if (snap.empty) break;
    for (const doc of snap.docs) {
      const data = doc.data() as Record<string, unknown>;
      rows.push({
        resourceId: doc.id,
        bunnyVideoId: typeof data.bunny_video_id === "string" ?
          data.bunny_video_id : null,
        bunnyLibraryId: typeof data.bunny_library_id === "string" ?
          data.bunny_library_id : null,
        resourceType: typeof data.resource_type === "string" ?
          data.resource_type : null,
        lectureId: typeof data.lecture_id === "string" ? data.lecture_id : null,
        subjectId: typeof data.subject_id === "string" ? data.subject_id : null,
        updateTime: doc.updateTime.toDate().toISOString(),
        isDeleted: data.is_deleted === true,
      });
    }
    cursor = snap.docs[snap.docs.length - 1].id;
  }
  return rows;
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));
  if (!args.mappingPath) {
    throw new Error("--mapping <path> is required (explicit verified mapping).");
  }
  const mode = resolveBunnyLibraryBackfillMode({apply: args.apply});
  if (mode.mode === "blocked_apply") {
    // Refuse BEFORE any filesystem read or Firestore access: an apply request
    // cannot reach a project connection at all.
    console.error(`Refused: ${mode.reason}`);
    process.exitCode = 3;
    return;
  }
  const mapping = loadMapping(args.mappingPath);
  const rows = await readSnapshot(args.projectId);
  const plan = planBunnyLibraryBackfill(rows, mapping, process.env);

  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  mkdirSync(args.outDir, {recursive: true});
  const planPath = join(args.outDir, `${stamp}-plan.json`);
  const backupPath = join(args.outDir, `${stamp}-backup.json`);
  const backup = buildBunnyLibraryBackfillBackup(
    plan,
    rows,
    new Date().toISOString(),
  );
  writeFileSync(planPath, JSON.stringify(plan, null, 2), "utf8");
  writeFileSync(backupPath, JSON.stringify(backup, null, 2), "utf8");

  const report = {
    mode: mode.mode,
    modeReason: mode.reason,
    mappingPath: args.mappingPath,
    resourcesInspected: plan.summary.total,
    plannedUpdates: plan.summary.set,
    unchanged: plan.summary.unchanged,
    withoutVideoId: plan.summary.skippedNoVideoId,
    notVideo: plan.summary.skippedNotVideo,
    conflicts: plan.summary.conflict,
    invalidMappings: plan.mappingErrors.length,
    missingResources: plan.unresolvedMappings.length,
    manualReview: plan.summary.manualReview,
    writable: plan.writable,
    planPath,
    backupPath,
    backupEntries: backup.entries.length,
  };
  console.log(JSON.stringify(report, null, 2));

  let exitCode = 0;
  if (plan.mappingErrors.length > 0) {
    console.error("Mapping errors — resolve before any future apply:");
    for (const error of plan.mappingErrors) console.error(` - ${error}`);
    exitCode = 1;
  }
  if (plan.conflicts.length > 0) {
    console.error(`${plan.conflicts.length} conflict(s) require manual review:`);
    for (const conflict of plan.conflicts) {
      console.error(` - ${conflict.resourceId} (${conflict.videoId}): ${conflict.reason}`);
    }
    exitCode = 1;
  }
  if (plan.unresolvedMappings.length > 0) {
    console.error("Unresolved mapping entries:");
    for (const entry of plan.unresolvedMappings) {
      console.error(` - ${entry.resourceId} (${entry.videoId}): ${entry.reason}`);
    }
    exitCode = 1;
  }
  console.log("DRY RUN — no documents were read for writing and none were changed.");
  if (exitCode !== 0) process.exitCode = exitCode;
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
