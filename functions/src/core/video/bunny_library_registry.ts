/**
 * ADR-010 — Bunny Stream library registry (PURE, no I/O).
 *
 * Trusted, server-managed mapping from a stored `lecture_resources.
 * bunny_library_id` to the environment variable names that hold that
 * library's playback template, token-signing key and Stream API key.
 *
 * Contract:
 * - This module never reads `process.env` itself: every resolver takes an
 *   explicit env snapshot, so it stays pure and unit-testable.
 * - It never returns a secret value to a client shape; the runtime objects
 *   it produces are consumed only by server-side helpers.
 * - Resolution FAILS CLOSED. There is no "try another library" path:
 *   an unknown, unactivated or incompletely configured library returns a
 *   typed failure, and callers must surface an error.
 * - Legacy resources (no `bunny_library_id`) resolve through the default
 *   library during the controlled migration window. That fallback can be
 *   disabled with `BUNNY_LEGACY_LIBRARY_FALLBACK=false` once every resource
 *   is backfilled and verified (ADR-010 Migration step 8).
 * - A client-supplied library identifier is a HINT only. It can never
 *   select credentials: it is compared with the trusted stored value and a
 *   disagreement fails closed; with no stored value the hint is ignored.
 */

/**
 * Compiled fallback for the canonical default library.
 *
 * PRODUCTION BEHAVIOUR IS UNCHANGED when no override is present: every
 * environment that does not set `BUNNY_DEFAULT_LIBRARY_ID` resolves exactly
 * this id. The override exists so a non-production environment (staging,
 * emulator) can name its own library WITHOUT the identity split produced by
 * `BUNNY_STREAM_LIBRARY_ID` alone (canonical id stayed `736742` while
 * metadata calls targeted another library).
 */
export const DEFAULT_BUNNY_LIBRARY_ID = "736742";

/** Optional canonical default-library override (numeric library id). */
export const BUNNY_DEFAULT_LIBRARY_VAR = "BUNNY_DEFAULT_LIBRARY_ID";

/** Comma-separated allow-list of non-default libraries that may be used. */
export const BUNNY_LIBRARY_ACTIVATION_VAR = "BUNNY_ACTIVE_LIBRARY_IDS";

/** `false` disables the legacy → default library fallback (post-migration). */
export const BUNNY_LEGACY_FALLBACK_VAR = "BUNNY_LEGACY_LIBRARY_FALLBACK";

/**
 * Canonical default library id for THIS environment.
 *
 * Resolution order: `BUNNY_DEFAULT_LIBRARY_ID` (trimmed, non-empty) → the
 * compiled `DEFAULT_BUNNY_LIBRARY_ID`. A malformed value is treated as absent
 * so the environment can never lose its default library by typo.
 * @param {BunnyLibraryEnv} env Env snapshot.
 * @return {string} Canonical default library id.
 */
export function resolveDefaultBunnyLibraryId(env: BunnyLibraryEnv): string {
  const raw = env[BUNNY_DEFAULT_LIBRARY_VAR];
  const value = typeof raw === "string" ? raw.trim() : "";
  return /^\d{1,20}$/.test(value) ? value : DEFAULT_BUNNY_LIBRARY_ID;
}

/**
 * Resolve the Stream API key for the CURRENT runtime.
 *
 * Order:
 * 1. Secret Manager value (mounted by `defineSecret`) — production path.
 * 2. The plain env var ONLY under the Functions emulator, where secrets may
 *    not be mounted; this is what keeps fixture-driven suites usable.
 * 3. Empty string.
 *
 * There is deliberately NO fallback to another library's key and no fallback
 * to a stale value: an empty result makes `resolveBunnyStreamApiRuntime`
 * return `incomplete_configuration`, so metadata stays disabled instead of
 * silently using production credentials.
 * @param {object} input Mounted secret value plus the env snapshot.
 * @return {string} Resolved Stream API key (empty when unavailable).
 */
export function resolveBunnyStreamApiKey(input: {
  secretValue?: string | null;
  env: BunnyLibraryEnv;
  isEmulator: boolean;
}): string {
  const fromSecret = typeof input.secretValue === "string" ?
    input.secretValue.trim() : "";
  if (fromSecret !== "") return fromSecret;
  if (!input.isEmulator) return "";
  const fromEnv = input.env["BUNNY_STREAM_API_KEY"];
  return typeof fromEnv === "string" ? fromEnv.trim() : "";
}

/**
 * Environment invariant reported at boot (diagnostic only, never throws).
 *
 * The one drift this platform actually suffered is: the canonical default
 * library and the Stream API library id disagree, so metadata is fetched from
 * a different library than the one whose credentials sign playback. This
 * function makes that visible instead of silent.
 * @param {BunnyLibraryEnv} env Env snapshot.
 * @return {{defaultLibraryId: string, streamApiLibraryId: string,
 *   mismatch: boolean}} Invariant snapshot.
 */
export function describeBunnyEnvironment(
  env: BunnyLibraryEnv,
): {defaultLibraryId: string; streamApiLibraryId: string; mismatch: boolean} {
  const defaultLibraryId = resolveDefaultBunnyLibraryId(env);
  const rawStream = env["BUNNY_STREAM_LIBRARY_ID"];
  const streamApiLibraryId =
    typeof rawStream === "string" && rawStream.trim() !== "" ?
      rawStream.trim() :
      defaultLibraryId;
  return {
    defaultLibraryId,
    streamApiLibraryId,
    mismatch: streamApiLibraryId !== defaultLibraryId,
  };
}

export interface BunnyLibraryDefinition {
  /** Canonical library id stored on the resource. */
  libraryId: string;
  /** Human-readable label (logs/reports only, never a secret). */
  label: string;
  /** Env var holding the pull-zone playback URL template. */
  playbackUrlTemplateVar: string;
  /** Env var holding the pull-zone token-signing key. */
  tokenKeyVar: string;
  /** Env var holding the Stream API key used for metadata calls. */
  streamApiKeyVar: string;
  /**
   * Optional env var overriding the numeric library id used for Stream API
   * calls. The default library keeps reading `BUNNY_STREAM_LIBRARY_ID` so
   * existing production metadata behaviour is byte-identical.
   */
  streamLibraryIdVar: string | null;
  /** The default library is always considered active (backward compat). */
  isDefault: boolean;
}

/**
 * Registry of every library the platform knows about.
 *
 * The first entry is the DEFAULT SLOT: it owns the environment's global
 * credential env-var names and is only reachable for the id returned by
 * `resolveDefaultBunnyLibraryId(env)`. It is never served for a different
 * (e.g. foreign-environment) id — see `findBunnyLibraryDefinition`.
 *
 * Library `775315` is DEFINED but NOT ACTIVATED: it is absent from
 * `BUNNY_ACTIVE_LIBRARY_IDS` and its env vars do not exist, so any attempt
 * to resolve it fails closed. Adding it later is a configuration action
 * (secrets + allow-list entry), never a code change.
 */
export const BUNNY_LIBRARIES: readonly BunnyLibraryDefinition[] = [
  {
    libraryId: DEFAULT_BUNNY_LIBRARY_ID,
    label: "Default (production-configured library)",
    playbackUrlTemplateVar: "BUNNY_PLAYBACK_URL_TEMPLATE",
    tokenKeyVar: "BUNNY_TOKEN_KEY",
    streamApiKeyVar: "BUNNY_STREAM_API_KEY",
    streamLibraryIdVar: "BUNNY_STREAM_LIBRARY_ID",
    isDefault: true,
  },
  {
    libraryId: "775315",
    label: "Content library (legacy platform library)",
    playbackUrlTemplateVar: "BUNNY_775315_PLAYBACK_URL_TEMPLATE",
    tokenKeyVar: "BUNNY_775315_TOKEN_KEY",
    streamApiKeyVar: "BUNNY_775315_STREAM_API_KEY",
    streamLibraryIdVar: null,
    isDefault: false,
  },
];

export type BunnyLibraryEnv = Readonly<Record<string, string | undefined>>;

export type BunnyLibraryFailureReason =
  | "missing_library_id"
  | "unknown_library"
  | "library_not_activated"
  | "incomplete_configuration"
  | "library_mismatch"
  | "legacy_fallback_disabled"
  | "library_not_resolved";

export type BunnyLibraryResolution =
  | {ok: true; libraryId: string; source: "resource" | "legacy_default"}
  | {ok: false; reason: BunnyLibraryFailureReason; libraryId: string | null};

export interface BunnyPlaybackRuntime {
  libraryId: string;
  playbackUrlTemplate: string;
  tokenKey: string;
  tokenAuthMode?: "signed" | "unsigned";
}

export type BunnyPlaybackRuntimeResult =
  | {ok: true; runtime: BunnyPlaybackRuntime}
  | {ok: false; reason: BunnyLibraryFailureReason; libraryId: string};

export interface BunnyStreamApiRuntime {
  /** Canonical library id from the registry. */
  libraryId: string;
  /** Numeric id used in the Stream API URL path. */
  apiLibraryId: string;
  apiKey: string;
}

export type BunnyStreamApiRuntimeResult =
  | {ok: true; runtime: BunnyStreamApiRuntime}
  | {ok: false; reason: BunnyLibraryFailureReason; libraryId: string};

/**
 * Cache identity for Stream metadata lookups. The same video id in two
 * libraries is two different videos, so the library must be part of the key
 * (otherwise a poster could be served from the wrong library's zone).
 * @param {string} libraryId canonical library id.
 * @param {string} videoId Bunny video id.
 * @return {string} cache key.
 */
export function bunnyPosterCacheKey(
  libraryId: string,
  videoId: string,
): string {
  return `${libraryId}:${videoId}`;
}

/**
 * Trim + null for blank. Non-numeric ids are preserved so they fail as
 * unknown rather than silently becoming "legacy".
 * @param {unknown} raw Stored or client-supplied value.
 * @return {string|null} Normalized id, or null when absent.
 */
export function normalizeBunnyLibraryId(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const value = raw.trim();
  return value === "" ? null : value;
}

/**
 * Look up the definition that owns exactly one library id in THIS environment.
 *
 * The compiled `isDefault` entry describes the DEFAULT SLOT, not a standalone
 * library: its env-var names are the environment's global default credentials.
 * It is therefore returned ONLY for the environment's own canonical default
 * (with its id rewritten to that default). For every other id the default
 * entry is skipped, so a foreign environment's compiled id (for example
 * Production `736742` while Staging runs `780700`) is unknown here unless the
 * current environment independently configures it (catalog row + allow-list).
 * This is the Mission 19 fix for the S-1 identity fallback.
 * @param {string} libraryId Stored or resolved library id.
 * @param {BunnyLibraryEnv} env Env snapshot.
 * @return {BunnyLibraryDefinition|null} Definition, or null when unknown here.
 */
export function findBunnyLibraryDefinition(
  libraryId: string,
  env: BunnyLibraryEnv = {},
): BunnyLibraryDefinition | null {
  const normalized = normalizeBunnyLibraryId(libraryId);
  if (normalized === null) return null;
  const defaultLibraryId = resolveDefaultBunnyLibraryId(env);
  if (normalized === defaultLibraryId) {
    const override = BUNNY_LIBRARIES.find((entry) => entry.isDefault);
    if (override) {
      return override.libraryId === normalized ?
        override :
        {...override, libraryId: normalized};
    }
  }
  for (const definition of BUNNY_LIBRARIES) {
    // Never serve the compiled default slot as some OTHER library: doing so
    // would hand this environment's default credentials/template to a
    // foreign-environment id (silent cross-library substitution).
    if (definition.isDefault) continue;
    if (definition.libraryId === normalized) return definition;
  }
  return null;
}

function readEnv(env: BunnyLibraryEnv, name: string): string {
  const raw = env[name];
  return typeof raw === "string" ? raw.trim() : "";
}

/**
 * Whether a definition may be used in THIS environment.
 *
 * Only the environment's OWN canonical default bypasses the allow-list
 * (removing that would change existing production behaviour). A definition
 * that claims `isDefault` for any other id is NOT implicitly eligible: it must
 * be explicitly allow-listed like any other library, and the registry lookup
 * never returns the compiled default slot for a foreign id in the first place.
 * Any other library must be listed in `BUNNY_ACTIVE_LIBRARY_IDS`.
 * @param {BunnyLibraryDefinition} definition Registry entry.
 * @param {BunnyLibraryEnv} env Env snapshot.
 * @return {boolean} True when the library may be used in this environment.
 */
export function isBunnyLibraryActive(
  definition: BunnyLibraryDefinition,
  env: BunnyLibraryEnv,
): boolean {
  if (definition.isDefault) {
    return definition.libraryId === resolveDefaultBunnyLibraryId(env);
  }
  const allowList = readEnv(env, BUNNY_LIBRARY_ACTIVATION_VAR);
  if (allowList === "") return false;
  return allowList
    .split(",")
    .map((entry) => entry.trim())
    .filter((entry) => entry !== "")
    .includes(definition.libraryId);
}

/**
 * Resolve the library that owns one resource.
 *
 * Order (ADR-010): trusted resource record → registry → default library for
 * legacy rows only. A client hint is validated against the stored value and
 * is otherwise discarded — it never chooses credentials.
 * @param {object} input Stored library id plus optional client hint.
 * @param {BunnyLibraryEnv} env Env snapshot.
 * @return {BunnyLibraryResolution} Discriminated ok/failure result.
 */
export function resolveBunnyLibraryForResource(
  input: {
    storedLibraryId?: unknown;
    clientLibraryHintId?: unknown;
  },
  env: BunnyLibraryEnv,
): BunnyLibraryResolution {
  const stored = normalizeBunnyLibraryId(input.storedLibraryId);
  const hint = normalizeBunnyLibraryId(input.clientLibraryHintId);

  if (stored !== null && hint !== null && hint !== stored) {
    return {ok: false, reason: "library_mismatch", libraryId: stored};
  }

  if (stored !== null) {
    const definition = findBunnyLibraryDefinition(stored, env);
    if (definition === null) {
      return {ok: false, reason: "unknown_library", libraryId: stored};
    }
    if (!isBunnyLibraryActive(definition, env)) {
      return {ok: false, reason: "library_not_activated", libraryId: stored};
    }
    return {ok: true, libraryId: definition.libraryId, source: "resource"};
  }

  const defaultLibraryId = resolveDefaultBunnyLibraryId(env);
  const fallbackDisabled =
    readEnv(env, BUNNY_LEGACY_FALLBACK_VAR).toLowerCase() === "false";
  if (fallbackDisabled) {
    return {
      ok: false,
      reason: "library_not_resolved",
      libraryId: null,
    };
  }
  return {
    ok: true,
    libraryId: defaultLibraryId,
    source: "legacy_default",
  };
}

/**
 * Playback signing configuration for one library: the pull-zone template
 * plus its token-signing key (for signed libraries). Fails closed when
 * required configuration is missing.
 *
 * `definitionOverride` lets the Mission 17 Secret Manager resolver supply the
 * definition it derived for a catalog-only library (Mission 8 §H.3 adapter).
 * The id must still match, so an override can never retarget the lookup.
 * @param {BunnyLibraryEnv} env Env snapshot.
 * @param {string} libraryId Canonical library id.
 * @param {BunnyLibraryDefinition|null} definitionOverride Resolved definition.
 * @param {"signed"|"unsigned"|null} tokenAuthMode Protection mode.
 * @return {BunnyPlaybackRuntimeResult} Runtime config or a typed failure.
 */
export function resolveBunnyPlaybackRuntime(
  env: BunnyLibraryEnv,
  libraryId: string,
  definitionOverride?: BunnyLibraryDefinition | null,
  tokenAuthMode?: "signed" | "unsigned" | null,
): BunnyPlaybackRuntimeResult {
  const normalized = normalizeBunnyLibraryId(libraryId);
  const definition =
    definitionOverride !== undefined &&
    definitionOverride !== null &&
    definitionOverride.libraryId === normalized ?
      definitionOverride :
      findBunnyLibraryDefinition(libraryId, env);
  if (definition === null) {
    return {
      ok: false,
      reason: "unknown_library",
      libraryId: normalizeBunnyLibraryId(libraryId) ?? "",
    };
  }
  if (!isBunnyLibraryActive(definition, env)) {
    return {ok: false, reason: "library_not_activated", libraryId: definition.libraryId};
  }
  const playbackUrlTemplate = readEnv(env, definition.playbackUrlTemplateVar);
  const effectiveMode = tokenAuthMode ?? "signed";

  if (effectiveMode === "unsigned") {
    if (playbackUrlTemplate === "") {
      return {
        ok: false,
        reason: "incomplete_configuration",
        libraryId: definition.libraryId,
      };
    }
    return {
      ok: true,
      runtime: {
        libraryId: definition.libraryId,
        playbackUrlTemplate,
        tokenKey: "",
        tokenAuthMode: "unsigned",
      },
    };
  }

  const tokenKey = readEnv(env, definition.tokenKeyVar);
  if (playbackUrlTemplate === "" || tokenKey === "") {
    return {
      ok: false,
      reason: "incomplete_configuration",
      libraryId: definition.libraryId,
    };
  }
  return {
    ok: true,
    runtime: {
      libraryId: definition.libraryId,
      playbackUrlTemplate,
      tokenKey,
      ...(tokenAuthMode !== undefined && tokenAuthMode !== null ? {tokenAuthMode} : {}),
    },
  };
}

/**
 * Stream API (metadata) configuration for one library. Metadata is
 * best-effort by design: callers fall back to their existing poster/media
 * defaults when this returns a failure, exactly like an unset config did.
 *
 * `definitionOverride` mirrors the playback resolver: the Mission 17 resolver
 * supplies the definition for a catalog-only library, and an id mismatch still
 * fails closed as `unknown_library`.
 * @param {BunnyLibraryEnv} env Env snapshot.
 * @param {string} libraryId Canonical library id.
 * @param {BunnyLibraryDefinition|null} definitionOverride Resolved definition.
 * @return {BunnyStreamApiRuntimeResult} Runtime config or a typed failure.
 */
export function resolveBunnyStreamApiRuntime(
  env: BunnyLibraryEnv,
  libraryId: string,
  definitionOverride?: BunnyLibraryDefinition | null,
): BunnyStreamApiRuntimeResult {
  const normalized = normalizeBunnyLibraryId(libraryId);
  const definition =
    definitionOverride !== undefined &&
    definitionOverride !== null &&
    definitionOverride.libraryId === normalized ?
      definitionOverride :
      findBunnyLibraryDefinition(libraryId, env);
  if (definition === null) {
    return {
      ok: false,
      reason: "unknown_library",
      libraryId: normalizeBunnyLibraryId(libraryId) ?? "",
    };
  }
  if (!isBunnyLibraryActive(definition, env)) {
    return {ok: false, reason: "library_not_activated", libraryId: definition.libraryId};
  }
  const apiKey = readEnv(env, definition.streamApiKeyVar);
  const apiLibraryId =
    definition.streamLibraryIdVar === null ?
      definition.libraryId :
      readEnv(env, definition.streamLibraryIdVar);
  if (apiKey === "" || apiLibraryId === "") {
    return {
      ok: false,
      reason: "incomplete_configuration",
      libraryId: definition.libraryId,
    };
  }
  return {
    ok: true,
    runtime: {
      libraryId: definition.libraryId,
      apiLibraryId,
      apiKey,
    },
  };
}
