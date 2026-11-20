/**
 * ADR-010 Amendment 1 — server-managed Bunny library catalog (PURE, no I/O).
 *
 * `bunny_libraries/{libraryId}` is the trusted, non-secret source of truth for
 * which Bunny Stream libraries this platform may use. It contains NO key
 * material: only ids, host, booleans, verification timestamps and the NAMES of
 * the Secret Manager entries that hold the credentials.
 *
 * Contract:
 * - This module never reads Firestore, Secret Manager or `process.env`.
 * - Validation FAILS CLOSED: a document that is not active + verified is never
 *   eligible, and an unknown/invalid id is never projected as usable.
 * - Secrets can never be represented here: `credential_refs` values are secret
 *   NAMES matching a strict pattern, and any other key in that map is dropped.
 * - Production behaviour is unchanged until the catalog is enabled: this module
 *   is additive and is consumed only after an explicit feature flag.
 */

export const BUNNY_CATALOG_COLLECTION = "bunny_libraries";

/** Secret Manager name shape (env-var style, upper snake case). */
const SECRET_NAME = /^[A-Z][A-Z0-9_]{2,63}$/;

/** Numeric Bunny library id (never a path, UUID or URL). */
const LIBRARY_ID = /^\d{1,20}$/;

/** System playback hostname served by Bunny (`vz-….b-cdn.net`). */
const PLAYBACK_HOST = /^[a-z0-9][a-z0-9-]{0,62}\.b-cdn\.net$/;

export type BunnyCatalogStatus =
  | "pending_verification"
  | "active"
  | "disabled"
  | "error";

/**
 * How this library's playback is protected (ADR-010 Amendment 3).
 *
 * - `signed`: the pull zone enforces CDN token authentication, so playback
 *   must be issued as a signed directory-token URL.
 * - `unsigned`: the pull zone has no token authentication (an external
 *   constraint for libraries an older platform consumes), so playback is a
 *   plain URL. The platform's own authorization gates are unchanged.
 */
export type BunnyTokenAuthMode = "signed" | "unsigned";

export type BunnyCatalogSource =
  | "auto_discovered"
  | "manual_registration"
  | "legacy_env";

export interface BunnyCatalogEntry {
  libraryId: string;
  displayName: string;
  status: BunnyCatalogStatus;
  pullZoneId: number;
  playbackHost: string;
  tokenAuthEnabled: boolean;
  tokenAuthVerified: boolean;
  /**
   * Declared protection mode, or null when it was never determined (a row
   * written before this field existed). A null mode is never treated as
   * `unsigned`: only an explicit, probed mode can make a library usable.
   */
  tokenAuthMode: BunnyTokenAuthMode | null;
  credentialRefs: {streamApiKey: string; tokenKey: string};
  source: BunnyCatalogSource;
  lastVerifiedAtMs: number | null;
  lastErrorCode: string | null;
}

export type BunnyCatalogProblem =
  | "invalid_library_id"
  | "missing_display_name"
  | "unknown_status"
  | "invalid_pull_zone_id"
  | "invalid_playback_host"
  | "unknown_source"
  | "invalid_credential_ref"
  | "unknown_token_auth_mode";

export type BunnyCatalogValidation =
  | {ok: true; entry: BunnyCatalogEntry}
  | {ok: false; reason: BunnyCatalogProblem};

const STATUSES: readonly BunnyCatalogStatus[] = [
  "pending_verification",
  "active",
  "disabled",
  "error",
];

const SOURCES: readonly BunnyCatalogSource[] = [
  "auto_discovered",
  "manual_registration",
  "legacy_env",
];

function str(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

/** True only for a structurally valid numeric library id. */
export function isValidBunnyLibraryId(value: unknown): boolean {
  return LIBRARY_ID.test(str(value));
}

/** True only for a Bunny system playback hostname. */
export function isValidBunnyPlaybackHost(value: unknown): boolean {
  return PLAYBACK_HOST.test(str(value).toLowerCase());
}

/**
 * Validate + normalize one catalog document.
 *
 * Unknown fields are ignored (the projection below is an allow-list), so a
 * malformed or hostile document can never smuggle extra data into resolution.
 * @param {unknown} raw Firestore document data.
 * @return {BunnyCatalogValidation} Normalized entry or a typed reason.
 */
export function parseBunnyCatalogEntry(raw: unknown): BunnyCatalogValidation {
  const data = (raw ?? {}) as Record<string, unknown>;
  const libraryId = str(data.library_id);
  if (!LIBRARY_ID.test(libraryId)) return {ok: false, reason: "invalid_library_id"};

  const displayName = str(data.display_name);
  if (displayName === "") return {ok: false, reason: "missing_display_name"};

  const status = str(data.status);
  if (!STATUSES.includes(status as BunnyCatalogStatus)) {
    return {ok: false, reason: "unknown_status"};
  }

  const pullZoneId = Number(data.pull_zone_id);
  if (!Number.isInteger(pullZoneId) || pullZoneId <= 0) {
    return {ok: false, reason: "invalid_pull_zone_id"};
  }

  const playbackHost = str(data.playback_host).toLowerCase();
  if (!PLAYBACK_HOST.test(playbackHost)) {
    return {ok: false, reason: "invalid_playback_host"};
  }

  const source = str(data.source);
  if (!SOURCES.includes(source as BunnyCatalogSource)) {
    return {ok: false, reason: "unknown_source"};
  }

  const refs = (data.credential_refs ?? {}) as Record<string, unknown>;
  const streamApiKey = str(refs.stream_api_key);
  const tokenKey = str(refs.token_key);
  if (!SECRET_NAME.test(streamApiKey) || !SECRET_NAME.test(tokenKey)) {
    return {ok: false, reason: "invalid_credential_ref"};
  }

  const verifiedRaw = data.last_verified_at;
  const lastVerifiedAtMs =
    verifiedRaw && typeof (verifiedRaw as {toMillis?: unknown}).toMillis === "function" ?
      (verifiedRaw as {toMillis: () => number}).toMillis() :
      null;

  const lastErrorCode = str(data.last_error_code);

  // Absent/null means "not determined yet"; anything else must be a known mode.
  const rawMode = data.token_auth_mode;
  let tokenAuthMode: BunnyTokenAuthMode | null;
  if (rawMode === undefined || rawMode === null || rawMode === "") {
    tokenAuthMode = null;
  } else if (rawMode === "signed" || rawMode === "unsigned") {
    tokenAuthMode = rawMode;
  } else {
    return {ok: false, reason: "unknown_token_auth_mode"};
  }

  return {
    ok: true,
    entry: {
      libraryId,
      displayName,
      status: status as BunnyCatalogStatus,
      pullZoneId,
      playbackHost,
      tokenAuthEnabled: data.token_auth_enabled === true,
      tokenAuthVerified: data.token_auth_verified === true,
      tokenAuthMode,
      credentialRefs: {streamApiKey, tokenKey},
      source: source as BunnyCatalogSource,
      lastVerifiedAtMs,
      lastErrorCode: lastErrorCode === "" ? null : lastErrorCode,
    },
  };
}

/**
 * Effective protection mode of one parsed entry.
 *
 * A row that predates `token_auth_mode` is interpreted conservatively: an
 * enabled token flag means `signed`; a disabled one stays `null` (undetermined)
 * so a legacy row is never silently promoted to `unsigned`.
 * @param {BunnyCatalogEntry} entry Parsed catalog entry.
 * @return {BunnyTokenAuthMode|null} Effective mode.
 */
export function bunnyCatalogTokenAuthMode(
  entry: BunnyCatalogEntry,
): BunnyTokenAuthMode | null {
  if (entry.tokenAuthMode !== null) return entry.tokenAuthMode;
  return entry.tokenAuthEnabled ? "signed" : null;
}

/**
 * May this library be used to issue playback / accept new associations?
 *
 * Requires: parsed successfully, `status === "active"`, a probe recorded the
 * protection mode as verified, and the stored mode agrees with the stored
 * token flag (`signed` ⇔ token auth enabled). A dashboard toggle or a declared
 * mode alone is never enough — Amendment 3 requires the behavioural probe.
 * @param {unknown} raw Firestore document data.
 * @return {boolean} True only for a fully verified active library.
 */
export function isBunnyCatalogEntryUsable(raw: unknown): boolean {
  const parsed = parseBunnyCatalogEntry(raw);
  if (!parsed.ok) return false;
  const entry = parsed.entry;
  if (entry.status !== "active" || !entry.tokenAuthVerified) return false;
  const mode = bunnyCatalogTokenAuthMode(entry);
  if (mode === "signed") return entry.tokenAuthEnabled === true;
  if (mode === "unsigned") return entry.tokenAuthEnabled === false;
  return false;
}

/**
 * Client-safe projection for `listEligibleBunnyLibraries`.
 *
 * Deliberately excludes pull zone, host, credential refs, verification stamps
 * and error codes: the client needs only an id and a label.
 * @param {unknown} raw Firestore document data.
 * @return {{libraryId: string, displayName: string} | null} Projection or null.
 */
export function toEligibleLibraryOption(
  raw: unknown,
): {libraryId: string; displayName: string} | null {
  if (!isBunnyCatalogEntryUsable(raw)) return null;
  const parsed = parseBunnyCatalogEntry(raw) as {
    ok: true;
    entry: BunnyCatalogEntry;
  };
  return {
    libraryId: parsed.entry.libraryId,
    displayName: parsed.entry.displayName,
  };
}

/**
 * Deterministic Secret Manager names for one library.
 *
 * Determinism is what makes rotation auditable: the same library always maps
 * to the same secret, never to an operator-chosen name.
 * @param {string} libraryId Numeric library id.
 * @return {{streamApiKey: string, tokenKey: string}} Secret names.
 */
export function bunnySecretNames(
  libraryId: string,
): {streamApiKey: string; tokenKey: string} {
  const id = str(libraryId);
  if (!LIBRARY_ID.test(id)) {
    throw new Error(`Invalid Bunny library id: ${id}`);
  }
  return {
    streamApiKey: `BUNNY_${id}_STREAM_API_KEY`,
    tokenKey: `BUNNY_${id}_TOKEN_KEY`,
  };
}
