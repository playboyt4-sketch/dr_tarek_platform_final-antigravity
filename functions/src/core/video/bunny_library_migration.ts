/**
 * ADR-010 — Bunny library backfill planner (PURE, no I/O).
 *
 * Produces a per-resource decision list for backfilling
 * `lecture_resources.bunny_library_id` from an EXPLICIT, human-verified
 * mapping, plus the concurrency/backup metadata a future executor needs.
 *
 * This module NEVER writes. It also carries the execution-mode guard: apply
 * mode is refused in this build, so no code path here can write production.
 *
 * Safety rules encoded here:
 * - No inference. A resource whose video id is absent from the mapping, or
 *   whose mapping entry targets a different resource/lecture/subject, is a
 *   CONFLICT — never a guess.
 * - Idempotent: a resource whose stored library already matches is `unchanged`.
 * - Never silently overwrite: a stored, different library is a conflict.
 * - Non-video resources and placeholder rows (empty `bunny_video_id`) are
 *   skipped, not written.
 * - Mapping entries are validated against the same registry the runtime uses;
 *   duplicates (same video id or same resource id) are rejected.
 * - Mapping entries may not carry unexpected fields (typo protection).
 */

import {
  BunnyLibraryEnv,
  findBunnyLibraryDefinition,
  normalizeBunnyLibraryId,
} from "./bunny_library_registry";

/** Fields a mapping entry may carry. Anything else is rejected. */
export const BUNNY_LIBRARY_MAPPING_FIELDS: readonly string[] = [
  "videoId",
  "libraryId",
  "resourceId",
  "lectureId",
  "subjectId",
];

export interface BunnyLibraryMappingEntry {
  videoId: string;
  libraryId: string;
  /** Optional: scope the mapping to one resource document. */
  resourceId?: string;
  /** Optional: cross-check the resource's lecture. */
  lectureId?: string;
  /** Optional: cross-check the resource's subject. */
  subjectId?: string;
}

export interface BunnyLibraryBackfillRow {
  /** `lecture_resources` document id. */
  resourceId: string;
  bunnyVideoId: string | null;
  bunnyLibraryId: string | null;
  resourceType?: string | null;
  lectureId?: string | null;
  subjectId?: string | null;
  /** ISO instant of the snapshot's `updateTime` (concurrency baseline). */
  updateTime?: string | null;
  /** Soft-deleted rows are still planned (they must be correct if restored). */
  isDeleted?: boolean;
}

export type BunnyLibraryBackfillAction =
  | "set"
  | "unchanged"
  | "skipped_no_video_id"
  | "skipped_not_video"
  | "conflict";

export interface BunnyLibraryBackfillDecision {
  resourceId: string;
  action: BunnyLibraryBackfillAction;
  videoId: string | null;
  fromLibraryId: string | null;
  toLibraryId: string | null;
  reason: string | null;
  requiresManualReview: boolean;
}

export interface BunnyLibraryBackfillUnresolvedMapping {
  resourceId: string;
  videoId: string;
  reason: string;
}

export interface BunnyLibraryBackfillPlan {
  decisions: BunnyLibraryBackfillDecision[];
  summary: {
    total: number;
    set: number;
    unchanged: number;
    skippedNoVideoId: number;
    skippedNotVideo: number;
    conflict: number;
    manualReview: number;
  };
  /** Blocking mapping defects — an apply run must refuse while any exist. */
  mappingErrors: string[];
  conflicts: BunnyLibraryBackfillDecision[];
  /** Mapping entries explicitly scoped to a resource that the snapshot lacks. */
  unresolvedMappings: BunnyLibraryBackfillUnresolvedMapping[];
  /** True only when a future executor would have nothing to refuse. */
  writable: boolean;
}

function normalizeId(raw: unknown): string {
  return typeof raw === "string" ? raw.trim() : "";
}

/**
 * A mapping may only target a library that is active in this environment.
 * The default library is always active; any other library requires an
 * explicit `BUNNY_ACTIVE_LIBRARY_IDS` entry, so a premature mapping fails
 * validation instead of producing unusable writes.
 * @param {string} libraryId canonical library id.
 * @param {BunnyLibraryEnv} env env snapshot.
 * @return {boolean} True when the library may be targeted.
 */
function isConfiguredLibrary(
  libraryId: string,
  env: BunnyLibraryEnv,
): boolean {
  const definition = findBunnyLibraryDefinition(libraryId);
  if (definition === null) return false;
  if (definition.isDefault) return true;
  const raw = env.BUNNY_ACTIVE_LIBRARY_IDS;
  const allowList = typeof raw === "string" ? raw : "";
  return allowList
    .split(",")
    .map((entry) => entry.trim())
    .filter((entry) => entry !== "")
    .includes(definition.libraryId);
}

/**
 * Validate mapping entries: structure, unexpected fields, empties, registry
 * membership, activation, duplicates (video id and resource id).
 * @param {Array} mapping explicit mapping entries.
 * @param {object} env env snapshot used for library resolution.
 * @return {Array<string>} human-readable errors (empty when valid).
 */
export function validateBunnyLibraryMapping(
  mapping: readonly BunnyLibraryMappingEntry[],
  env: BunnyLibraryEnv,
): string[] {
  const errors: string[] = [];
  if (!Array.isArray(mapping)) {
    return ["mapping must be an array of objects"];
  }
  const seenVideo = new Map<string, string>();
  const seenResource = new Set<string>();
  mapping.forEach((entry, index) => {
    const label = `mapping[${index}]`;
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
      errors.push(`${label} must be an object`);
      return;
    }
    for (const key of Object.keys(entry as Record<string, unknown>)) {
      if (!BUNNY_LIBRARY_MAPPING_FIELDS.includes(key)) {
        errors.push(`${label} has unexpected field "${key}"`);
      }
    }
    const videoId = normalizeId(entry.videoId);
    const libraryId = normalizeBunnyLibraryId(entry.libraryId);
    if (videoId === "") {
      errors.push(`${label} has an empty videoId`);
      return;
    }
    if (libraryId === null) {
      errors.push(`${label} (${videoId}) has an empty libraryId`);
      return;
    }
    if (findBunnyLibraryDefinition(libraryId) === null) {
      errors.push(`${label} (${videoId}) references unknown library ${libraryId}`);
      return;
    }
    if (!isConfiguredLibrary(libraryId, env)) {
      errors.push(
        `${label} (${videoId}) references library ${libraryId} that is not configured`,
      );
      return;
    }
    const resourceId = normalizeId(entry.resourceId);
    if (resourceId !== "") {
      if (seenResource.has(resourceId)) {
        errors.push(`resource ${resourceId} is mapped more than once`);
        return;
      }
      seenResource.add(resourceId);
    }
    for (const field of ["lectureId", "subjectId"] as const) {
      const value = entry[field];
      if (value !== undefined && normalizeId(value) === "") {
        errors.push(`${label} (${videoId}) has an empty ${field}`);
        return;
      }
    }
    const previous = seenVideo.get(videoId);
    if (previous !== undefined) {
      errors.push(
        previous === libraryId ?
          `video ${videoId} is mapped more than once` :
          `video ${videoId} is mapped to two libraries (${previous}, ${libraryId})`,
      );
      return;
    }
    seenVideo.set(videoId, libraryId);
  });
  return errors;
}

/**
 * Build the dry-run plan. Deterministic, idempotent and side-effect free.
 * @param {Array} rows authoritative `lecture_resources` projections.
 * @param {Array} mapping explicit verified mapping entries.
 * @param {object} env env snapshot (defaults to no env: only the default
 *   library is active).
 * @return {object} plan with per-resource decisions, conflicts and summary.
 */
export function planBunnyLibraryBackfill(
  rows: readonly BunnyLibraryBackfillRow[],
  mapping: readonly BunnyLibraryMappingEntry[],
  env: BunnyLibraryEnv = {},
): BunnyLibraryBackfillPlan {
  const mappingErrors = validateBunnyLibraryMapping(mapping, env);
  const byVideoId = new Map<string, BunnyLibraryMappingEntry>();
  if (mappingErrors.length === 0) {
    for (const entry of mapping) {
      byVideoId.set(normalizeId(entry.videoId), entry);
    }
  }

  const decisions: BunnyLibraryBackfillDecision[] = [];
  const resolvedResources = new Set<string>();

  for (const row of rows) {
    const resourceType = normalizeId(row.resourceType ?? "video");
    const videoId = normalizeId(row.bunnyVideoId);
    const stored = normalizeBunnyLibraryId(row.bunnyLibraryId);

    if (resourceType !== "video") {
      decisions.push({
        resourceId: row.resourceId,
        action: "skipped_not_video",
        videoId: videoId === "" ? null : videoId,
        fromLibraryId: stored,
        toLibraryId: null,
        reason: `resource_type is "${resourceType}", not video`,
        requiresManualReview: false,
      });
      continue;
    }
    if (videoId === "") {
      decisions.push({
        resourceId: row.resourceId,
        action: "skipped_no_video_id",
        videoId: null,
        fromLibraryId: stored,
        toLibraryId: null,
        reason: "resource has no bunny_video_id",
        requiresManualReview: false,
      });
      continue;
    }

    const entry = byVideoId.get(videoId);
    if (entry === undefined) {
      decisions.push({
        resourceId: row.resourceId,
        action: "conflict",
        videoId,
        fromLibraryId: stored,
        toLibraryId: null,
        reason: mappingErrors.length > 0 ?
          "mapping is invalid" :
          "video id is not present in the mapping",
        requiresManualReview: true,
      });
      continue;
    }
    resolvedResources.add(row.resourceId);

    const scopedResource = normalizeId(entry.resourceId);
    if (scopedResource !== "" && scopedResource !== row.resourceId) {
      decisions.push({
        resourceId: row.resourceId,
        action: "conflict",
        videoId,
        fromLibraryId: stored,
        toLibraryId: normalizeBunnyLibraryId(entry.libraryId),
        reason: `mapping is scoped to resource ${scopedResource}`,
        requiresManualReview: true,
      });
      continue;
    }
    const scopeMismatch = (): string | null => {
      for (const field of ["lectureId", "subjectId"] as const) {
        const expected = normalizeId(entry[field]);
        if (expected === "") continue;
        const actual = normalizeId(row[field]);
        if (actual === "") return `cannot verify ${field} (missing on the resource)`;
        if (actual !== expected) return `${field} mismatch (${actual} != ${expected})`;
      }
      return null;
    };
    const scopeProblem = scopeMismatch();
    if (scopeProblem !== null) {
      decisions.push({
        resourceId: row.resourceId,
        action: "conflict",
        videoId,
        fromLibraryId: stored,
        toLibraryId: normalizeBunnyLibraryId(entry.libraryId),
        reason: scopeProblem,
        requiresManualReview: true,
      });
      continue;
    }

    const target = normalizeBunnyLibraryId(entry.libraryId);
    if (target === null) {
      decisions.push({
        resourceId: row.resourceId,
        action: "conflict",
        videoId,
        fromLibraryId: stored,
        toLibraryId: null,
        reason: "mapping entry has no usable library id",
        requiresManualReview: true,
      });
      continue;
    }
    if (stored !== null && stored !== target) {
      decisions.push({
        resourceId: row.resourceId,
        action: "conflict",
        videoId,
        fromLibraryId: stored,
        toLibraryId: target,
        reason:
          `stored library ${stored} disagrees with mapping ${target} ` +
          "(refusing to overwrite silently)",
        requiresManualReview: true,
      });
      continue;
    }
    if (stored === target) {
      decisions.push({
        resourceId: row.resourceId,
        action: "unchanged",
        videoId,
        fromLibraryId: stored,
        toLibraryId: target,
        reason: null,
        requiresManualReview: false,
      });
      continue;
    }
    decisions.push({
      resourceId: row.resourceId,
      action: "set",
      videoId,
      fromLibraryId: null,
      toLibraryId: target,
      reason: null,
      requiresManualReview: false,
    });
  }

  const unresolvedMappings: BunnyLibraryBackfillUnresolvedMapping[] = [];
  if (mappingErrors.length === 0) {
    const rowIds = new Set(rows.map((row) => row.resourceId));
    for (const entry of mapping) {
      const scoped = normalizeId(entry.resourceId);
      if (scoped === "") continue;
      if (!rowIds.has(scoped)) {
        unresolvedMappings.push({
          resourceId: scoped,
          videoId: normalizeId(entry.videoId),
          reason: "mapping targets a resource that is not in the snapshot",
        });
      } else if (!resolvedResources.has(scoped)) {
        unresolvedMappings.push({
          resourceId: scoped,
          videoId: normalizeId(entry.videoId),
          reason: "mapping did not resolve: video id or scope mismatch",
        });
      }
    }
  }

  const conflicts = decisions.filter((decision) => decision.action === "conflict");
  const manualReview = conflicts.length + unresolvedMappings.length;
  return {
    decisions,
    summary: {
      total: decisions.length,
      set: decisions.filter((decision) => decision.action === "set").length,
      unchanged: decisions.filter((decision) => decision.action === "unchanged").length,
      skippedNoVideoId: decisions.filter(
        (decision) => decision.action === "skipped_no_video_id",
      ).length,
      skippedNotVideo: decisions.filter(
        (decision) => decision.action === "skipped_not_video",
      ).length,
      conflict: conflicts.length,
      manualReview,
    },
    mappingErrors,
    conflicts,
    unresolvedMappings,
    writable:
      mappingErrors.length === 0 &&
      conflicts.length === 0 &&
      unresolvedMappings.length === 0,
  };
}

export type BunnyLibraryBackfillMode = "dry-run" | "blocked_apply";

/**
 * Execution-mode guard. Production writes are DISABLED in this build: an
 * apply request is reported as blocked and the caller must not write.
 * @param {object} args Parsed CLI arguments.
 * @return {object} mode plus a reason when blocked.
 */
export function resolveBunnyLibraryBackfillMode(
  args: {apply?: boolean},
): {mode: BunnyLibraryBackfillMode; reason: string | null} {
  if (args?.apply === true) {
    return {
      mode: "blocked_apply",
      reason:
        "apply mode is disabled in this build: production writes require a " +
        "separate authorized executor",
    };
  }
  return {mode: "dry-run", reason: null};
}

export interface BunnyLibraryWriteEvaluation {
  allowed: boolean;
  reason:
    | "ok"
    | "not_a_write"
    | "writes_disabled"
    | "stale_snapshot"
    | "resource_missing";
}

/**
 * Would a future executor be allowed to write this decision? Pure so the
 * concurrency contract is testable without Firestore. `writesEnabled` must be
 * passed explicitly — there is no ambient "true".
 * @param {object} decision planner decision.
 * @param {object|null} row snapshot row the decision was planned from.
 * @param {object} options explicit write enablement and expected update time.
 * @return {object} allow/deny verdict with a machine-readable reason.
 */
export function evaluateBunnyLibraryBackfillWrite(
  decision: BunnyLibraryBackfillDecision,
  row: BunnyLibraryBackfillRow | null | undefined,
  options: {writesEnabled?: boolean; expectedUpdateTime?: string | null} = {},
): BunnyLibraryWriteEvaluation {
  if (!row) return {allowed: false, reason: "resource_missing"};
  if (options.writesEnabled !== true) return {allowed: false, reason: "writes_disabled"};
  if (decision.action !== "set") return {allowed: false, reason: "not_a_write"};
  const expected = normalizeId(options.expectedUpdateTime);
  if (expected !== "") {
    const actual = normalizeId(row.updateTime);
    if (actual !== expected) return {allowed: false, reason: "stale_snapshot"};
  }
  return {allowed: true, reason: "ok"};
}

export interface BunnyLibraryBackupEntry {
  resourceId: string;
  videoId: string;
  previousLibraryId: string | null;
  nextLibraryId: string;
  lectureId: string | null;
  subjectId: string | null;
  updateTime: string | null;
}

/**
 * Backup/rollback metadata for every planned write. Written before any future
 * apply; also the rollback source (previous value per resource).
 * @param {object} plan planner output.
 * @param {Array} rows snapshot rows (for ids and update times).
 * @param {string} createdAt ISO timestamp of the backup.
 * @return {object} backup document.
 */
export function buildBunnyLibraryBackfillBackup(
  plan: BunnyLibraryBackfillPlan,
  rows: readonly BunnyLibraryBackfillRow[],
  createdAt: string,
): {
  createdAt: string;
  entries: BunnyLibraryBackupEntry[];
  /** Restore instructions for a rollback run. */
  rollback: string;
} {
  const byId = new Map(rows.map((row) => [row.resourceId, row]));
  const entries: BunnyLibraryBackupEntry[] = [];
  for (const decision of plan.decisions) {
    if (decision.action !== "set") continue;
    const row = byId.get(decision.resourceId);
    entries.push({
      resourceId: decision.resourceId,
      videoId: normalizeId(decision.videoId),
      previousLibraryId: decision.fromLibraryId,
      nextLibraryId: decision.toLibraryId ?? "",
      lectureId: normalizeId(row?.lectureId) || null,
      subjectId: normalizeId(row?.subjectId) || null,
      updateTime: normalizeId(row?.updateTime) || null,
    });
  }
  return {
    createdAt,
    entries,
    rollback:
      "For each entry, restore bunny_library_id to previousLibraryId " +
      "guarded by the recorded updateTime.",
  };
}
