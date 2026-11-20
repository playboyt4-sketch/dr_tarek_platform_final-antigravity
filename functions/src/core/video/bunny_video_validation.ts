/**
 * ADR-010 — pre-write Bunny library/video validation (PURE).
 *
 * Answers one question before a video resource is accepted: does this Video ID
 * really belong to the selected library? The module is pure so the decision
 * table and the receipt format are unit-testable without Bunny or Firestore.
 *
 * Trust model:
 * - The library id comes from server-managed configuration (registry) and the
 *   video id from the caller; the FORMAT is validated here.
 * - "Does it exist in that library?" needs the Stream API, so this module only
 *   *plans* the request and *interprets* the response. The callable performs
 *   the HTTP call and never returns credentials.
 * - Metadata unavailable is NOT success: it yields `unavailable`, which callers
 *   must not treat as verified, and which never substitutes another library.
 * - A positive verdict can be returned to the author alongside a signed
 *   receipt binding (libraryId, videoId, expiry) so a later write can prove the
 *   check happened. Receipts are HMACs over server-side secrets.
 */

import {createHmac, timingSafeEqual} from "node:crypto";
import {
  BunnyLibraryEnv,
  resolveBunnyStreamApiRuntime,
} from "./bunny_library_registry";

/** Bare Bunny GUID — same policy as issuance (URLs are never extracted). */
const BUNNY_VIDEO_GUID =
  /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

export type BunnyVideoValidationStatus =
  | "verified"
  | "mismatch"
  | "unavailable"
  | "rejected";

export type BunnyVideoValidationReason =
  | "ok"
  | "invalid_video_id"
  | "unknown_library"
  | "inactive_library"
  | "incomplete_configuration"
  | "metadata_unavailable"
  | "api_unauthorized"
  | "api_timeout"
  | "not_found_in_library"
  | "library_mismatch"
  | "video_mismatch";

export interface BunnyVideoValidationResult {
  status: BunnyVideoValidationStatus;
  reason: BunnyVideoValidationReason;
  libraryId: string;
  videoId: string;
}

export interface BunnyValidationRequest {
  libraryId: string;
  apiLibraryId: string;
  apiKey: string;
  videoId: string;
}

export type BunnyValidationPlan =
  | {ok: true; request: BunnyValidationRequest}
  | {ok: false; result: BunnyVideoValidationResult};

/**
 * Validate the id formats, resolve the library and decide whether a metadata
 * call can even be made. Never reads a secret into the result.
 *
 * `resolvedCredentials` (Mission 17) is supplied by the callable after it has
 * read that ONE library's Stream API key through the catalog + Secret Manager.
 * The format gate still runs first, so `invalid_video_id` precedence is
 * unchanged; when credentials are supplied they are used instead of the
 * env-based registry lookup, and the library id is re-validated by the
 * resolver that produced them.
 * @param {object} input Library id + video id as supplied by an authorized caller.
 * @param {object} env env snapshot.
 * @param {object} [resolvedCredentials] Resolved per-library Stream runtime.
 * @return {object} either a request plan or a terminal (non-success) result.
 */
export function planBunnyVideoValidation(
  input: {libraryId?: unknown; videoId?: unknown},
  env: BunnyLibraryEnv,
  resolvedCredentials?: {
    libraryId: string;
    apiLibraryId: string;
    apiKey: string;
  },
): BunnyValidationPlan {
  const videoId = typeof input.videoId === "string" ? input.videoId.trim() : "";
  const libraryId =
    typeof input.libraryId === "string" ? input.libraryId.trim() : "";
  if (!BUNNY_VIDEO_GUID.test(videoId)) {
    return {
      ok: false,
      result: {
        status: "rejected",
        reason: "invalid_video_id",
        libraryId,
        videoId,
      },
    };
  }
  if (libraryId === "") {
    return {
      ok: false,
      result: {
        status: "rejected",
        reason: "unknown_library",
        libraryId,
        videoId,
      },
    };
  }
  if (resolvedCredentials !== undefined) {
    if (resolvedCredentials.libraryId !== libraryId) {
      // The resolver and the caller must agree on the library; a mismatch is
      // a server-side defect and never a reason to use another library.
      return {
        ok: false,
        result: {
          status: "unavailable",
          reason: "incomplete_configuration",
          libraryId,
          videoId,
        },
      };
    }
    return {
      ok: true,
      request: {
        libraryId: resolvedCredentials.libraryId,
        apiLibraryId: resolvedCredentials.apiLibraryId,
        apiKey: resolvedCredentials.apiKey,
        videoId,
      },
    };
  }
  const runtime = resolveBunnyStreamApiRuntime(env, libraryId);
  if (!runtime.ok) {
    const mapped: BunnyVideoValidationReason =
      runtime.reason === "unknown_library" ?
        "unknown_library" :
        runtime.reason === "library_not_activated" ?
          "inactive_library" :
          "incomplete_configuration";
    return {
      ok: false,
      result: {status: "unavailable", reason: mapped, libraryId, videoId},
    };
  }
  return {
    ok: true,
    request: {
      libraryId: runtime.runtime.libraryId,
      apiLibraryId: runtime.runtime.apiLibraryId,
      apiKey: runtime.runtime.apiKey,
      videoId,
    },
  };
}

/**
 * Interpret a successful HTTP response from the Stream video endpoint.
 * The metadata endpoint is library-scoped, so a body that names a different
 * library or video is a MISMATCH, not a pass.
 * @param {object} response status + parsed body (if any).
 * @param {object} request the planned request (ids only used for comparison).
 * @return {object} validation result.
 */
export function interpretBunnyMetadataResponse(
  response: {status: number; body?: unknown},
  request: {libraryId: string; apiLibraryId: string; videoId: string},
): BunnyVideoValidationResult {
  const base = {libraryId: request.libraryId, videoId: request.videoId};
  if (response.status === 401 || response.status === 403) {
    return {...base, status: "unavailable", reason: "api_unauthorized"};
  }
  if (response.status === 404) {
    return {...base, status: "mismatch", reason: "not_found_in_library"};
  }
  if (response.status < 200 || response.status >= 300) {
    return {...base, status: "unavailable", reason: "metadata_unavailable"};
  }
  const body =
    response.body && typeof response.body === "object" ?
      (response.body as Record<string, unknown>) :
      null;
  if (body === null) {
    return {...base, status: "unavailable", reason: "metadata_unavailable"};
  }
  const guid = typeof body.guid === "string" ? body.guid.trim() : "";
  if (guid !== "" && guid.toLowerCase() !== request.videoId.toLowerCase()) {
    return {...base, status: "mismatch", reason: "video_mismatch"};
  }
  const libraryField = body.videoLibraryId;
  const bodyLibrary =
    typeof libraryField === "number" ?
      String(libraryField) :
      typeof libraryField === "string" ?
        libraryField.trim() :
        "";
  if (bodyLibrary !== "" && bodyLibrary !== request.apiLibraryId) {
    return {...base, status: "mismatch", reason: "library_mismatch"};
  }
  return {...base, status: "verified", reason: "ok"};
}

/**
 * Map a thrown fetch/abort failure onto the validation vocabulary. A timeout is
 * `unavailable` (never verified); anything else is `unavailable` too.
 * @param {unknown} error thrown value.
 * @param {object} request planned request (ids only).
 * @return {object} validation result.
 */
export function interpretBunnyMetadataError(
  error: unknown,
  request: {libraryId: string; videoId: string},
): BunnyVideoValidationResult {
  const name =
    error && typeof error === "object" && "name" in error ?
      String((error as {name?: unknown}).name ?? "") :
      "";
  return {
    status: "unavailable",
    reason: name === "AbortError" ? "api_timeout" : "metadata_unavailable",
    libraryId: request.libraryId,
    videoId: request.videoId,
  };
}

/** Signed receipt binding a successful check to library + video + expiry. */
export interface BunnyValidationReceipt {
  libraryId: string;
  videoId: string;
  expiresAt: number;
  signature: string;
}

/**
 * Sign a positive validation verdict so a later write can prove it happened.
 * HMAC-SHA256 over `libraryId\nvideoId\nexpiresAt`, base64url.
 * @param {object} input secret, ids and lifetime.
 * @return {object} receipt (signature + expiry, no secret material).
 */
export function signBunnyValidationReceipt(input: {
  secret: string;
  libraryId: string;
  videoId: string;
  issuedAtSeconds: number;
  ttlSeconds: number;
}): BunnyValidationReceipt {
  const expiresAt = Math.floor(input.issuedAtSeconds) + Math.max(1, Math.floor(input.ttlSeconds));
  const payload = `${input.libraryId}\n${input.videoId}\n${expiresAt}`;
  const signature = createHmac("sha256", input.secret)
    .update(payload)
    .digest("base64url");
  return {
    libraryId: input.libraryId,
    videoId: input.videoId,
    expiresAt,
    signature,
  };
}

/**
 * Verify a receipt for the exact library + video pair. Constant-time signature
 * comparison; expiry enforced. A tampered, mismatched or expired receipt is
 * false (never throws).
 * @param {object} input secret, receipt and the pair being written.
 * @return {boolean} true only for a live, matching, authentic receipt.
 */
export function verifyBunnyValidationReceipt(input: {
  secret: string;
  receipt: unknown;
  libraryId: string;
  videoId: string;
  nowSeconds: number;
}): boolean {
  const receipt = input.receipt as Partial<BunnyValidationReceipt> | null;
  if (!receipt || typeof receipt !== "object") return false;
  const {libraryId, videoId, expiresAt, signature} = receipt;
  if (
    typeof libraryId !== "string" ||
    typeof videoId !== "string" ||
    typeof expiresAt !== "number" ||
    typeof signature !== "string"
  ) {
    return false;
  }
  if (libraryId !== input.libraryId || videoId !== input.videoId) return false;
  if (!Number.isFinite(expiresAt) || expiresAt <= Math.floor(input.nowSeconds)) {
    return false;
  }
  const payload = `${libraryId}\n${videoId}\n${expiresAt}`;
  const expected = createHmac("sha256", input.secret)
    .update(payload)
    .digest("base64url");
  const a = Buffer.from(expected);
  const b = Buffer.from(signature);
  return a.length === b.length && timingSafeEqual(a, b);
}
