/**
 * ADR-010 Option C — Bunny library lifecycle (PURE, no I/O).
 *
 * Owns the registration / deactivation / reactivation state machine and the
 * audit payload shape for those operations. It never touches Firestore,
 * Secret Manager or `process.env`, so every rule below is unit-testable.
 *
 * Fail-closed contract:
 * - Registration can only produce `pending_verification`. Nothing in this
 *   module can produce `active`; only a successful verification probe can.
 * - Deactivation is always allowed from any state (an operator must be able to
 *   stop delivery immediately).
 * - Reactivation never returns straight to `active`; it returns to
 *   `pending_verification` so re-verification is mandatory.
 */

import {bunnySecretNames, isValidBunnyLibraryId, isValidBunnyPlaybackHost} from "./bunny_library_catalog";
import type {BunnyCatalogSource, BunnyCatalogStatus, BunnyTokenAuthMode} from "./bunny_library_catalog";

export interface BunnyLibraryRegistrationInput {
  libraryId?: unknown;
  displayName?: unknown;
  pullZoneId?: unknown;
  playbackHost?: unknown;
  source?: unknown;
}

export type BunnyLibraryRegistrationProblem =
  | "invalid_library_id"
  | "missing_display_name"
  | "invalid_pull_zone_id"
  | "invalid_playback_host"
  | "invalid_source";

export interface BunnyLibraryRegistrationDocument {
  library_id: string;
  display_name: string;
  status: "pending_verification";
  pull_zone_id: number;
  playback_host: string;
  token_auth_enabled: false;
  token_auth_verified: false;
  /**
   * Undetermined at registration: only a behavioural probe may set it
   * (ADR-010 Amendment 3), so a declared mode can never make a library usable.
   */
  token_auth_mode: null;
  credential_refs: {stream_api_key: string; token_key: string};
  source: BunnyCatalogSource;
  last_verified_at: null;
  last_error_code: null;
}

export type BunnyLibraryRegistrationPlan =
  | {ok: true; libraryId: string; document: BunnyLibraryRegistrationDocument}
  | {ok: false; reason: BunnyLibraryRegistrationProblem};

function str(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

/**
 * Validate one registration request and build the document to write.
 *
 * The credential names are DERIVED from the library id; an operator can never
 * supply them. The document is always `pending_verification` with both token
 * flags false, so registration alone can never make a library eligible.
 * @param {BunnyLibraryRegistrationInput} input Raw callable payload.
 * @return {BunnyLibraryRegistrationPlan} Plan or a typed reason.
 */
export function planBunnyLibraryRegistration(
  input: BunnyLibraryRegistrationInput,
): BunnyLibraryRegistrationPlan {
  const libraryId = str(input.libraryId);
  if (!isValidBunnyLibraryId(libraryId)) {
    return {ok: false, reason: "invalid_library_id"};
  }
  const displayName = str(input.displayName);
  if (displayName === "") return {ok: false, reason: "missing_display_name"};

  const rawPullZone = typeof input.pullZoneId === "number" ?
    input.pullZoneId :
    Number(str(input.pullZoneId));
  if (!Number.isInteger(rawPullZone) || rawPullZone <= 0) {
    return {ok: false, reason: "invalid_pull_zone_id"};
  }

  const playbackHost = str(input.playbackHost).toLowerCase();
  if (!isValidBunnyPlaybackHost(playbackHost)) {
    return {ok: false, reason: "invalid_playback_host"};
  }

  const rawSource = str(input.source);
  if (
    rawSource !== "" &&
    rawSource !== "auto_discovered" &&
    rawSource !== "manual_registration" &&
    rawSource !== "legacy_env"
  ) {
    return {ok: false, reason: "invalid_source"};
  }
  const source: BunnyCatalogSource =
    rawSource === "" ? "manual_registration" : (rawSource as BunnyCatalogSource);

  const names = bunnySecretNames(libraryId);
  return {
    ok: true,
    libraryId,
    document: {
      library_id: libraryId,
      display_name: displayName,
      status: "pending_verification",
      pull_zone_id: rawPullZone,
      playback_host: playbackHost,
      token_auth_enabled: false,
      token_auth_verified: false,
      token_auth_mode: null,
      credential_refs: {
        stream_api_key: names.streamApiKey,
        token_key: names.tokenKey,
      },
      source,
      last_verified_at: null,
      last_error_code: null,
    },
  };
}

export type BunnyLibraryLifecycleAction =
  | "deactivate"
  | "reactivate"
  | "retry";

export type BunnyLibraryLifecycleProblem =
  | "unknown_library"
  | "invalid_status"
  | "already_disabled"
  | "not_disabled";

export type BunnyLibraryLifecyclePlan =
  | {ok: true; previousStatus: BunnyCatalogStatus; status: BunnyCatalogStatus}
  | {ok: false; reason: BunnyLibraryLifecycleProblem};

/**
 * Decide the next status for an operator-initiated lifecycle action.
 *
 * Invariants:
 * - `deactivate` always wins and always yields `disabled`.
 * - `reactivate` is only valid from `disabled` and yields
 *   `pending_verification` — never `active`.
 * - `retry` is valid from `error` and yields `pending_verification`.
 * @param {BunnyCatalogStatus} currentStatus Current catalog status.
 * @param {BunnyLibraryLifecycleAction} action Requested action.
 * @return {BunnyLibraryLifecyclePlan} Plan or a typed reason.
 */
export function planBunnyLibraryStatusTransition(
  currentStatus: BunnyCatalogStatus,
  action: BunnyLibraryLifecycleAction,
): BunnyLibraryLifecyclePlan {
  if (action === "deactivate") {
    if (currentStatus === "disabled") {
      return {ok: false, reason: "already_disabled"};
    }
    return {ok: true, previousStatus: currentStatus, status: "disabled"};
  }
  if (action === "reactivate") {
    if (currentStatus !== "disabled") {
      return {ok: false, reason: "not_disabled"};
    }
    return {
      ok: true,
      previousStatus: currentStatus,
      status: "pending_verification",
    };
  }
  // retry
  if (currentStatus !== "error") {
    return {ok: false, reason: "invalid_status"};
  }
  return {
    ok: true,
    previousStatus: currentStatus,
    status: "pending_verification",
  };
}

/**
 * The outcome of one verification probe, reduced to what the catalog stores.
 */
export interface BunnyLibraryVerificationOutcome {
  tokenAuthEnabled: boolean;
  tokenAuthVerified: boolean;
  /**
   * Protection mode observed by the probe (Amendment 3). When absent it is
   * derived from `tokenAuthEnabled`, so legacy callers keep their behaviour.
   */
  tokenAuthMode?: BunnyTokenAuthMode | null;
  /** Typed code only; never a provider message. */
  errorCode: string | null;
}

export interface BunnyLibraryVerificationWrite {
  status: BunnyCatalogStatus;
  token_auth_enabled: boolean;
  token_auth_verified: boolean;
  token_auth_mode: BunnyTokenAuthMode | null;
  last_error_code: string | null;
  verified: boolean;
}

/**
 * Map a verification outcome to the exact fields written to the catalog.
 *
 * A library becomes `active` only when the probe PROVED one of the two
 * documented modes (ADR-010 Amendment 3):
 * - `signed` — token authentication is enabled and a signed URL returned 200;
 * - `unsigned` — the pull zone does not enforce tokens and a plain URL
 *   returned 200. This is a recorded, reviewed condition, not a failure.
 * Everything else fails closed exactly as before: a failure from an `active`
 * library moves it to `error`; from `pending_verification` it stays pending
 * with the typed code recorded.
 * @param {BunnyCatalogStatus} currentStatus Current catalog status.
 * @param {BunnyLibraryVerificationOutcome} outcome Probe outcome.
 * @return {BunnyLibraryVerificationWrite} Fields to write.
 */
export function planBunnyLibraryVerificationWrite(
  currentStatus: BunnyCatalogStatus,
  outcome: BunnyLibraryVerificationOutcome,
): BunnyLibraryVerificationWrite {
  const mode = outcome.tokenAuthMode ??
    (outcome.tokenAuthEnabled ? "signed" : null);
  const verified =
    mode === "signed" ?
      outcome.tokenAuthEnabled === true && outcome.tokenAuthVerified === true :
      mode === "unsigned" ?
        outcome.tokenAuthEnabled === false && outcome.tokenAuthVerified === true :
        false;

  if (verified) {
    return {
      status: "active",
      token_auth_enabled: mode === "signed",
      token_auth_verified: true,
      token_auth_mode: mode,
      last_error_code: null,
      verified: true,
    };
  }
  return {
    status: currentStatus === "active" ? "error" : currentStatus,
    token_auth_enabled: outcome.tokenAuthEnabled,
    token_auth_verified: false,
    token_auth_mode: null,
    last_error_code: outcome.errorCode ?? "token_auth_unverified",
    verified: false,
  };
}

/**
 * Map a Stream API list response status onto a typed probe code.
 *
 * A 404 is the provider's answer for a library that does not exist (or is not
 * visible to that key); 401/403 mean the credential was rejected. Keeping this
 * pure makes the "library not found" branch testable without the network.
 * @param {number} status HTTP status of `GET /library/{id}/videos`.
 * @return {string|null} Typed code, or null when the call succeeded.
 */
export function bunnyProbeFailureReasonForStatus(status: number): string | null {
  if (status >= 200 && status < 300) return null;
  if (status === 404) return "library_not_found";
  if (status === 401 || status === 403) return "credential_rejected";
  return "video_list_unavailable";
}

export interface BunnyLibraryAuditInput {
  action:
    | "bunny_library_register"
    | "bunny_library_verify"
    | "bunny_library_deactivate"
    | "bunny_library_reactivate"
    | "bunny_video_discover"
    | "bunny_library_associate"
    | "bunny_library_migrate";
  actorId: string;
  actorRole: string;
  permissionBasis: string;
  libraryId: string;
  previousStatus?: BunnyCatalogStatus | null;
  newStatus?: BunnyCatalogStatus | null;
  reasonCode?: string | null;
  reason?: string | null;
  source?: string | null;
}

/**
 * Build the `admin_audit_log` payload for a lifecycle action.
 *
 * Deliberately contains NO credential name, value, host or pull-zone id.
 * @param {BunnyLibraryAuditInput} input Audit fields.
 * @return {Record<string, unknown>} Audit document (without timestamps).
 */
export function buildBunnyLibraryAuditEntry(
  input: BunnyLibraryAuditInput,
): Record<string, unknown> {
  const entry: Record<string, unknown> = {
    action: input.action,
    entity: "bunny_library",
    target_id: input.libraryId,
    library_id: input.libraryId,
    actor_id: input.actorId,
    actor_role: input.actorRole,
    permission_basis: input.permissionBasis,
    previous_status: input.previousStatus ?? null,
    new_status: input.newStatus ?? null,
  };
  if (input.reasonCode) entry.reason_code = input.reasonCode;
  if (input.reason) entry.reason = input.reason;
  if (input.source) entry.source = input.source;
  return entry;
}

/**
 * Secret Manager name of the dedicated association-receipt key (N5).
 *
 * Kept as a plain env-var name until the Owner approves creating the secret:
 * the callables read it only when it is bound, and otherwise keep signing with
 * the CDN token key. This means adding the secret later needs no code change.
 */
export const BUNNY_ASSOCIATION_RECEIPT_KEY_VAR =
  "BUNNY_ASSOCIATION_RECEIPT_KEY";

export interface BunnyReceiptSigningKeys {
  /** Key used to SIGN new receipts. */
  signKey: string;
  /** Keys accepted when VERIFYING (dual-verification window). */
  verifyKeys: string[];
}

/**
 * Resolve the receipt signing/verification keys.
 *
 * Order:
 * 1. When a dedicated receipt key is present it signs, and during the
 *    transition window the CDN token key is still accepted.
 * 2. Otherwise the CDN token key signs and verifies (current behaviour).
 *
 * The dedicated key is never mixed into playback signing.
 * @param {object} input Env snapshot plus the optional mounted receipt secret.
 * @return {BunnyReceiptSigningKeys|null} Keys, or null when nothing is usable.
 */
export function resolveBunnyReceiptSigningKeys(input: {
  env: Readonly<Record<string, string | undefined>>;
  mountedReceiptKey?: string | null;
  legacyTokenKey?: string | null;
}): BunnyReceiptSigningKeys | null {
  const mounted = str(input.mountedReceiptKey);
  const fromEnv = str(input.env[BUNNY_ASSOCIATION_RECEIPT_KEY_VAR]);
  const dedicated = mounted !== "" ? mounted : fromEnv;
  const legacy = str(input.legacyTokenKey) || str(input.env["BUNNY_TOKEN_KEY"]);

  if (dedicated !== "") {
    return {
      signKey: dedicated,
      verifyKeys: legacy !== "" ? [dedicated, legacy] : [dedicated],
    };
  }
  if (legacy !== "") {
    return {signKey: legacy, verifyKeys: [legacy]};
  }
  return null;
}
