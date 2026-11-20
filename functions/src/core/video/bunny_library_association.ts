/**
 * ADR-010 — server-side verified library association (PURE, no I/O).
 *
 * `lecture_resources.bunny_library_id` is an authorization-relevant value: it
 * selects which library's signing credentials issue playback. Clients may
 * therefore never write it. This module owns the decision rules and the
 * resource-bound receipt so the write path stays testable without Firestore
 * or Bunny.
 *
 * Trust model:
 * - The requested library id and video id are UNTRUSTED client input. The
 *   library is resolved through the server registry (unknown / inactive /
 *   incomplete configuration fail closed), and the receipt must have been
 *   issued by this server for exactly (resource, lecture, library, video).
 * - A receipt proves only that one association; it is never a general
 *   authorization token and cannot be replayed onto another resource,
 *   lecture, library or video.
 * - Legacy rows (created before the ADR-010 cutover) keep working through the
 *   default-library fallback. A row created at/after the cutover without a
 *   verified association is PENDING and must never play — the fallback is not
 *   a substitute for verification.
 */

import {createHmac, timingSafeEqual} from "node:crypto";
import {
  BunnyLibraryDefinition,
  BunnyLibraryEnv,
  findBunnyLibraryDefinition,
  isBunnyLibraryActive,
  normalizeBunnyLibraryId,
  resolveBunnyStreamApiRuntime,
} from "./bunny_library_registry";

/** Bare Bunny GUID — the same policy as issuance and validation. */
const BUNNY_VIDEO_GUID =
  /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

/**
 * Rows created before this instant are legacy and may use the default-library
 * fallback. Everything created afterwards must carry a server-verified
 * association. Overridable for a controlled rollout, but the built-in default
 * is the ADR-010 decision date so no deployment is required for the gate to
 * be meaningful.
 */
export const BUNNY_ASSOCIATION_CUTOVER_ENV = "BUNNY_ASSOCIATION_CUTOVER";
export const BUNNY_ASSOCIATION_CUTOVER_DEFAULT = "2026-11-13T00:00:00.000Z";

export type BunnyAssociationFailure =
  | "not_video_resource"
  | "missing_lecture"
  | "lecture_mismatch"
  | "subject_mismatch"
  | "invalid_video_id"
  | "unknown_library"
  | "inactive_library"
  | "incomplete_configuration"
  | "video_id_mismatch";

export interface BunnyAssociationPlanInput {
  resourceType?: unknown;
  resourceLectureId?: unknown;
  lectureId?: unknown;
  resourceSubjectId?: unknown;
  lectureSubjectId?: unknown;
  storedVideoId?: unknown;
  requestedVideoId?: unknown;
  storedLibraryId?: unknown;
  replaceVideo?: unknown;
}

export type BunnyAssociationPlan =
  | {ok: true; libraryId: string; videoId: string}
  | {ok: false; reason: BunnyAssociationFailure};

function clean(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

/**
 * Structural half of the association plan: everything that can be decided
 * without credentials (resource kind, lecture/subject binding, video id shape,
 * and registry membership/activation).
 *
 * Mission 17 splits this out so the callable can resolve that library's
 * credentials through Secret Manager BEFORE the configuration check, while
 * `planBunnyAssociationWrite` keeps its exact existing behaviour for every
 * caller and test.
 * @param {object} input Untrusted client shape plus trusted document values.
 * @param {BunnyLibraryEnv} env Environment snapshot.
 * @param {BunnyLibraryDefinition|null} definitionOverride Resolved definition.
 * @return {BunnyAssociationPlan} Plan (no credential check) or a reason.
 */
export function planBunnyAssociationShape(
  input: BunnyAssociationPlanInput,
  env: BunnyLibraryEnv,
  definitionOverride?: BunnyLibraryDefinition | null,
): BunnyAssociationPlan {
  if (clean(input.resourceType) !== "video") {
    return {ok: false, reason: "not_video_resource"};
  }
  const resourceLectureId = clean(input.resourceLectureId);
  const lectureId = clean(input.lectureId);
  if (resourceLectureId === "" || lectureId === "") {
    return {ok: false, reason: "missing_lecture"};
  }
  if (resourceLectureId !== lectureId) {
    return {ok: false, reason: "lecture_mismatch"};
  }
  const resourceSubjectId = clean(input.resourceSubjectId);
  const lectureSubjectId = clean(input.lectureSubjectId);
  if (
    resourceSubjectId !== "" &&
    lectureSubjectId !== "" &&
    resourceSubjectId !== lectureSubjectId
  ) {
    return {ok: false, reason: "subject_mismatch"};
  }

  const videoId = clean(input.requestedVideoId);
  if (!BUNNY_VIDEO_GUID.test(videoId)) {
    return {ok: false, reason: "invalid_video_id"};
  }
  const storedVideoId = clean(input.storedVideoId);
  if (
    storedVideoId !== "" &&
    storedVideoId !== videoId &&
    input.replaceVideo !== true
  ) {
    return {ok: false, reason: "video_id_mismatch"};
  }

  const libraryId = normalizeBunnyLibraryId(input.storedLibraryId) ?? "";
  if (libraryId === "") return {ok: false, reason: "unknown_library"};
  const definition =
    definitionOverride !== undefined &&
    definitionOverride !== null &&
    definitionOverride.libraryId === libraryId ?
      definitionOverride :
      findBunnyLibraryDefinition(libraryId, env);
  if (definition === null) return {ok: false, reason: "unknown_library"};
  if (!isBunnyLibraryActive(definition, env)) {
    return {ok: false, reason: "inactive_library"};
  }
  return {ok: true, libraryId: definition.libraryId, videoId};
}

/**
 * Decide whether one association write may be planned, and for which library.
 *
 * The library must be registry-known, active and fully configured. The video
 * id must be a bare GUID. When the row already holds a Video ID, the request
 * must either match it or explicitly ask to replace it (an edit that changes
 * the video is a deliberate, re-verified replacement, never a silent one).
 * @param {object} input Untrusted client shape plus trusted document values.
 * @param {BunnyLibraryEnv} env Environment snapshot.
 * @param {BunnyLibraryDefinition|null} definitionOverride Resolved definition.
 * @return {BunnyAssociationPlan} Plan or a typed, fail-closed reason.
 */
export function planBunnyAssociationWrite(
  input: BunnyAssociationPlanInput,
  env: BunnyLibraryEnv,
  definitionOverride?: BunnyLibraryDefinition | null,
): BunnyAssociationPlan {
  const shape = planBunnyAssociationShape(input, env, definitionOverride);
  if (!shape.ok) return shape;
  const runtime = resolveBunnyStreamApiRuntime(
    env,
    shape.libraryId,
    definitionOverride,
  );
  if (!runtime.ok) {
    return {
      ok: false,
      reason: runtime.reason === "library_not_activated" ?
        "inactive_library" :
        runtime.reason === "unknown_library" ?
          "unknown_library" :
          "incomplete_configuration",
    };
  }
  return shape;
}

/**
 * Read the cutover instant (ms). A malformed override falls back to the
 * documented default instead of disabling the gate.
 * @param {BunnyLibraryEnv} env Environment snapshot.
 * @return {number} Cutover time in milliseconds.
 */
export function resolveBunnyAssociationCutoverMs(
  env: BunnyLibraryEnv,
): number {
  const raw = env[BUNNY_ASSOCIATION_CUTOVER_ENV];
  const fallback = Date.parse(BUNNY_ASSOCIATION_CUTOVER_DEFAULT);
  if (typeof raw !== "string" || raw.trim() === "") return fallback;
  const parsed = Date.parse(raw.trim());
  return Number.isFinite(parsed) ? parsed : fallback;
}

/**
 * Whether a resource is subject to the verified-association requirement.
 * A row with no readable creation time is treated as legacy (it predates the
 * field's use by the authoring pipeline); the rules require `created_at` on
 * every new write, so this can only describe genuinely old data.
 * @param {number|null} createdAtMs Resource creation time, if known.
 * @param {number} cutoverMs Cutover instant.
 * @return {boolean} True when the row must carry a verified association.
 */
export function isBunnyAssociationRequired(
  createdAtMs: number | null,
  cutoverMs: number,
): boolean {
  if (createdAtMs === null || !Number.isFinite(createdAtMs)) return false;
  return createdAtMs >= cutoverMs;
}

/**
 * Playback gate: decide whether a video row may resolve a library.
 * - legacy row → allowed (default-library fallback)
 * - association present → allowed (the registry resolves it)
 * - pending row (post-cutover, no association) → refused
 * @param {object} input createdAt (ms), stored library id and cutover.
 * @return {boolean} True only when the row may proceed to registration.
 */
export function mayResolveBunnyLibraryForPlayback(input: {
  createdAtMs: number | null;
  storedLibraryId?: unknown;
  cutoverMs: number;
}): boolean {
  const stored = normalizeBunnyLibraryId(input.storedLibraryId);
  if (stored !== null) return true;
  return !isBunnyAssociationRequired(input.createdAtMs, input.cutoverMs);
}

/** Resource-bound verification receipt. */
export interface BunnyAssociationReceipt {
  resourceId: string;
  lectureId: string;
  libraryId: string;
  videoId: string;
  expiresAt: number;
  signature: string;
}

const RECEIPT_DOMAIN = "adr010-association-v1";

function associationPayload(input: {
  resourceId: string;
  lectureId: string;
  libraryId: string;
  videoId: string;
  expiresAt: number;
}): string {
  return [
    RECEIPT_DOMAIN,
    input.resourceId,
    input.lectureId,
    input.libraryId,
    input.videoId,
    String(input.expiresAt),
  ].join("\n");
}

/**
 * Sign a verified association for EXACTLY one resource + lecture pair.
 * HMAC-SHA256, base64url, constant-time verified by the consumer.
 * @param {object} input secret, binding fields and lifetime.
 * @return {BunnyAssociationReceipt} Receipt (no secret material).
 */
export function signBunnyAssociationReceipt(input: {
  secret: string;
  resourceId: string;
  lectureId: string;
  libraryId: string;
  videoId: string;
  issuedAtSeconds: number;
  ttlSeconds: number;
}): BunnyAssociationReceipt {
  const expiresAt =
    Math.floor(input.issuedAtSeconds) + Math.max(1, Math.floor(input.ttlSeconds));
  const signature = createHmac("sha256", input.secret)
    .update(
      associationPayload({
        resourceId: input.resourceId,
        lectureId: input.lectureId,
        libraryId: input.libraryId,
        videoId: input.videoId,
        expiresAt,
      }),
    )
    .digest("base64url");
  return {
    resourceId: input.resourceId,
    lectureId: input.lectureId,
    libraryId: input.libraryId,
    videoId: input.videoId,
    expiresAt,
    signature,
  };
}

/**
 * Verify a receipt against the exact association being written. Expired,
 * tampered, cross-resource, cross-lecture, cross-library and cross-video
 * receipts are false. Never throws.
 * @param {object} input secret, receipt and the expected binding.
 * @return {boolean} True only for a live, authentic, matching receipt.
 */
export function verifyBunnyAssociationReceipt(input: {
  secret: string;
  receipt: unknown;
  resourceId: string;
  lectureId: string;
  libraryId: string;
  videoId: string;
  nowSeconds: number;
}): boolean {
  const receipt = input.receipt as Partial<BunnyAssociationReceipt> | null;
  if (!receipt || typeof receipt !== "object") return false;
  const {resourceId, lectureId, libraryId, videoId, expiresAt, signature} =
    receipt;
  if (
    typeof resourceId !== "string" ||
    typeof lectureId !== "string" ||
    typeof libraryId !== "string" ||
    typeof videoId !== "string" ||
    typeof expiresAt !== "number" ||
    typeof signature !== "string"
  ) {
    return false;
  }
  if (
    resourceId !== input.resourceId ||
    lectureId !== input.lectureId ||
    libraryId !== input.libraryId ||
    videoId !== input.videoId
  ) {
    return false;
  }
  if (!Number.isFinite(expiresAt) || expiresAt <= Math.floor(input.nowSeconds)) {
    return false;
  }
  const expected = createHmac("sha256", input.secret)
    .update(
      associationPayload({
        resourceId,
        lectureId,
        libraryId,
        videoId,
        expiresAt,
      }),
    )
    .digest("base64url");
  const a = Buffer.from(expected);
  const b = Buffer.from(signature);
  return a.length === b.length && timingSafeEqual(a, b);
}

/**
 * The only fields the trusted write path may set on `lecture_resources` for
 * the association itself (never a template, key or signed URL).
 * @param {string} libraryId Verified library id.
 * @param {string} [videoId] Video id, when the row is being (re)bound.
 * @return {object} Firestore field map.
 */
export function bunnyAssociationWriteFields(
  libraryId: string,
  videoId?: string,
): Record<string, string> {
  const fields: Record<string, string> = {bunny_library_id: libraryId};
  if (videoId !== undefined) fields.bunny_video_id = videoId;
  return fields;
}
