/**
 * ADR-010 — per-library Secret Manager resolver (server-only, Mission 17).
 *
 * Trust model:
 * - The library id is ALWAYS trusted, server-side input (a stored resource
 *   field or a server-resolved registry id). A client hint never reaches this
 *   module.
 * - The library is resolved through the authoritative Firestore catalog
 *   (`bunny_libraries/{libraryId}`) and must pass the existing pure activation
 *   gate (active + token auth enabled + probe-verified + valid metadata).
 * - Only that library's own secrets are read, and only when the caller needs
 *   them (`need.streamApiKey` / `need.tokenKey`). A metadata-only flow never
 *   reads the token-signing key, and a signing-only flow never reads the
 *   Stream API key.
 * - Secret NAMES come from the catalog, but they are verified against the
 *   deterministic `BUNNY_<libraryId>_*` convention. A catalog document for
 *   library A that points at library B's secret is rejected
 *   (`credential_name_mismatch`) before any secret is read. Cross-library
 *   credential reuse is therefore structurally impossible.
 * - There is NO fallback to another library's credentials. The only legacy
 *   path is the canonical DEFAULT library with no catalog row (ADR-010
 *   Amendment 1 / ADR-010 migration step 8); it reads that library's own
 *   pre-existing `BUNNY_STREAM_API_KEY` / `BUNNY_TOKEN_KEY` values and can be
 *   disabled with `BUNNY_LEGACY_LIBRARY_FALLBACK=false`.
 * - Every failure is typed and fails closed. Secret values, secret names and
 *   Secret Manager resource paths never appear in an error message.
 *
 * Secret Manager access:
 * - Production uses the official `@google-cloud/secret-manager` client with
 *   `projects/{project}/secrets/{name}/versions/latest`.
 * - The Functions emulator (or any process with `FIRESTORE_EMULATOR_HOST`)
 *   reads the same secret NAME from the process environment, mirroring the
 *   existing `resolveBunnyStreamApiKey` emulator behaviour. This keeps the
 *   suites deterministic and offline; it is never used outside emulation.
 * - A short positive cache (default 60 s) bounds repeated reads while keeping
 *   rotation effective. Negative results are never cached.
 */

import {
  BunnyTokenAuthMode,
  bunnyCatalogTokenAuthMode,
  bunnySecretNames,
  isBunnyCatalogEntryUsable,
  parseBunnyCatalogEntry,
} from "./bunny_library_catalog";
import {
  BUNNY_LEGACY_FALLBACK_VAR,
  BunnyLibraryDefinition,
  BunnyLibraryEnv,
  BunnyPlaybackRuntime,
  BunnyStreamApiRuntime,
  findBunnyLibraryDefinition,
  isBunnyLibraryActive,
  normalizeBunnyLibraryId,
  resolveBunnyPlaybackRuntime,
  resolveBunnyStreamApiRuntime,
} from "./bunny_library_registry";
import type {SecretManagerServiceClient} from "@google-cloud/secret-manager";

/** Default positive-cache lifetime for a resolved secret value. */
export const BUNNY_SECRET_CACHE_TTL_MS = 60_000;

/** Secret name shape accepted by Secret Manager resource paths. */
const SECRET_NAME = /^[A-Z][A-Z0-9_]{2,63}$/;

/** Secret value shape: printable ASCII, no whitespace or control characters. */
const SECRET_VALUE = /^[\x21-\x7E]{8,512}$/;

/** Numeric Bunny library id (never a path, UUID or URL). */
const LIBRARY_ID = /^\d{1,20}$/;

export type BunnySecretFailureReason =
  | "unknown_library"
  | "library_not_activated"
  | "incomplete_configuration"
  | "invalid_catalog_entry"
  | "credential_name_mismatch"
  | "catalog_unavailable"
  | "secret_not_found"
  | "secret_permission_denied"
  | "secret_unavailable"
  | "invalid_secret_value";

export interface BunnySecretFailure {
  ok: false;
  reason: BunnySecretFailureReason;
  libraryId: string;
}

/** Minimal Secret Manager surface the resolver needs. */
export interface BunnySecretAccessor {
  readSecret(name: string): Promise<string>;
}

/** One catalog document (or null when the library is not registered). */
export interface BunnyCatalogDocumentSource {
  get(libraryId: string): Promise<{id: string; data: unknown} | null>;
}

export interface BunnySecretResolverDeps {
  catalog: BunnyCatalogDocumentSource;
  secrets: BunnySecretAccessor;
  env: BunnyLibraryEnv;
}

export interface BunnyResolvedCredentials {
  libraryId: string;
  source: "catalog" | "legacy_default";
  apiLibraryId: string;
  playbackUrlTemplate: string;
  /** Present only when the caller asked for it. */
  streamApiKey: string | null;
  /** Present only when the caller asked for it. */
  tokenKey: string | null;
  tokenAuthMode?: BunnyTokenAuthMode;
}

export type BunnyCredentialResolution =
  | {ok: true; credentials: BunnyResolvedCredentials}
  | BunnySecretFailure;

interface BunnyCredentialPlan {
  libraryId: string;
  source: "catalog" | "legacy_default";
  definition: BunnyLibraryDefinition;
  secretNames: {streamApiKey: string; tokenKey: string} | null;
  apiLibraryId: string;
  playbackUrlTemplate: string;
  tokenAuthMode?: BunnyTokenAuthMode;
}

export type BunnyCredentialPlanResult =
  | {ok: true; plan: BunnyCredentialPlan}
  | BunnySecretFailure;

function readEnv(env: BunnyLibraryEnv, name: string): string {
  const raw = env[name];
  return typeof raw === "string" ? raw.trim() : "";
}

function legacyFallbackDisabled(env: BunnyLibraryEnv): boolean {
  return readEnv(env, BUNNY_LEGACY_FALLBACK_VAR).toLowerCase() === "false";
}

function failure(
  reason: BunnySecretFailureReason,
  libraryId: string,
): BunnySecretFailure {
  return {ok: false, reason, libraryId};
}

/**
 * Derive the registry-shaped definition for a catalog-only library.
 *
 * Mission 8 §H.3 keeps `bunny_library_registry.ts` as the single naming
 * authority, but a library onboarded through the catalog is not compiled into
 * `BUNNY_LIBRARIES`. This derivation reproduces the approved convention
 * (`BUNNY_<id>_*`) so a new library is a configuration action, never a code
 * change. It is ONLY used when an authoritative catalog row exists and the
 * library is allow-listed; `findBunnyLibraryDefinition` is untouched, so an
 * id that is neither compiled nor catalogued still fails as `unknown_library`.
 * @param {string} libraryId Numeric Bunny library id.
 * @return {BunnyLibraryDefinition|null} Derived definition, or null.
 */
export function deriveCatalogLibraryDefinition(
  libraryId: string,
): BunnyLibraryDefinition | null {
  const id = typeof libraryId === "string" ? libraryId.trim() : "";
  if (!LIBRARY_ID.test(id)) return null;
  return {
    libraryId: id,
    label: `Catalog library ${id}`,
    playbackUrlTemplateVar: `BUNNY_${id}_PLAYBACK_URL_TEMPLATE`,
    tokenKeyVar: `BUNNY_${id}_TOKEN_KEY`,
    streamApiKeyVar: `BUNNY_${id}_STREAM_API_KEY`,
    streamLibraryIdVar: null,
    isDefault: false,
  };
}

/**
 * Decide HOW one library's credentials may be resolved. Pure: no I/O.
 *
 * The registry remains the first gate for compiled libraries (unknown / not
 * activated), so the existing `unknown_library` / `library_not_activated`
 * contract is unchanged. A catalog row is authoritative for eligibility and
 * secret names; it can never point at another library's secret.
 * @param {object} input Trusted library id plus the catalog document (or null).
 * @param {BunnyLibraryEnv} input.env Env snapshot.
 * @return {BunnyCredentialPlanResult} Plan or a typed, fail-closed reason.
 */
export function planBunnyLibraryCredentialResolution(input: {
  libraryId: unknown;
  document: {id: string; data: unknown} | null;
  env: BunnyLibraryEnv;
}): BunnyCredentialPlanResult {
  const libraryId = normalizeBunnyLibraryId(input.libraryId);
  if (libraryId === null || !LIBRARY_ID.test(libraryId)) {
    return failure("unknown_library", "");
  }

  const compiled = findBunnyLibraryDefinition(libraryId, input.env);
  if (compiled === null && input.document === null) {
    return failure("unknown_library", libraryId);
  }
  const definition =
    compiled ?? deriveCatalogLibraryDefinition(libraryId);
  if (definition === null) {
    return failure("unknown_library", libraryId);
  }
  // Registry activation is preserved verbatim (the default library is always
  // active; any other library must be listed in BUNNY_ACTIVE_LIBRARY_IDS).
  if (!isBunnyLibraryActive(definition, input.env)) {
    return failure("library_not_activated", libraryId);
  }

  const apiLibraryId = definition.streamLibraryIdVar === null ?
    definition.libraryId :
    readEnv(input.env, definition.streamLibraryIdVar);
  const playbackUrlTemplate =
    readEnv(input.env, definition.playbackUrlTemplateVar);

  if (input.document !== null) {
    // Mission 8 §H.1: the document id is the canonical library id.
    if (input.document.id !== libraryId) {
      return failure("invalid_catalog_entry", libraryId);
    }
    const parsed = parseBunnyCatalogEntry(input.document.data);
    if (!parsed.ok || parsed.entry.libraryId !== libraryId) {
      return failure("invalid_catalog_entry", libraryId);
    }
    if (!isBunnyCatalogEntryUsable(input.document.data)) {
      // Parsed but not usable: either not active, or not probe-verified.
      return parsed.entry.status === "active" ?
        failure("incomplete_configuration", libraryId) :
        failure("library_not_activated", libraryId);
    }
    const mode = bunnyCatalogTokenAuthMode(parsed.entry) ?? "signed";
    const derivedTemplate = `https://${parsed.entry.playbackHost}/{videoId}/playlist.m3u8`;
    const resolvedPlaybackUrlTemplate =
      playbackUrlTemplate !== "" ? playbackUrlTemplate : derivedTemplate;
    const expected = bunnySecretNames(libraryId);
    if (parsed.entry.credentialRefs.streamApiKey !== expected.streamApiKey) {
      // A catalog row may never point at another library's secret.
      return failure("credential_name_mismatch", libraryId);
    }
    if (mode === "signed" && parsed.entry.credentialRefs.tokenKey !== expected.tokenKey) {
      return failure("credential_name_mismatch", libraryId);
    }
    return {
      ok: true,
      plan: {
        libraryId,
        source: "catalog",
        definition,
        secretNames: expected,
        apiLibraryId,
        playbackUrlTemplate: resolvedPlaybackUrlTemplate,
        tokenAuthMode: mode,
      },
    };
  }

  // No catalog row: only the canonical default library may use the legacy
  // environment credentials, and only while the fallback is enabled.
  if (!definition.isDefault || legacyFallbackDisabled(input.env)) {
    return failure("incomplete_configuration", libraryId);
  }
  return {
    ok: true,
    plan: {
      libraryId,
      source: "legacy_default",
      definition,
      secretNames: null,
      apiLibraryId,
      playbackUrlTemplate,
    },
  };
}

function isSecretValueValid(value: string): boolean {
  return SECRET_VALUE.test(value.trim());
}

/**
 * Read one library's credentials through the catalog + Secret Manager.
 *
 * Only the secrets named by `need` are read. Every read failure is mapped to a
 * typed reason; the returned object never carries a secret value, a secret
 * name or a Secret Manager resource path.
 * @param {object} input Trusted library id, need flags and dependencies.
 * @return {Promise<BunnyCredentialResolution>} Credentials or typed failure.
 */
export async function resolveBunnyLibraryCredentials(input: {
  libraryId: unknown;
  need: {streamApiKey: boolean; tokenKey: boolean};
  deps: BunnySecretResolverDeps;
}): Promise<BunnyCredentialResolution> {
  const normalized = normalizeBunnyLibraryId(input.libraryId);
  if (normalized === null) {
    return failure("unknown_library", "");
  }

  let document: {id: string; data: unknown} | null;
  try {
    document = await input.deps.catalog.get(normalized);
  } catch {
    return failure("catalog_unavailable", normalized);
  }

  const planned = planBunnyLibraryCredentialResolution({
    libraryId: normalized,
    document,
    env: input.deps.env,
  });
  if (!planned.ok) return planned;
  const plan = planned.plan;

  let streamApiKey: string | null = null;
  let tokenKey: string | null = null;

  if (plan.source === "catalog" && plan.secretNames !== null) {
    if (input.need.streamApiKey) {
      const read = await readSecretValue(
        input.deps.secrets,
        plan.secretNames.streamApiKey,
        plan.libraryId,
      );
      if (!read.ok) return read;
      streamApiKey = read.value;
    }
    if (input.need.tokenKey && plan.tokenAuthMode !== "unsigned") {
      const read = await readSecretValue(
        input.deps.secrets,
        plan.secretNames.tokenKey,
        plan.libraryId,
      );
      if (!read.ok) return read;
      tokenKey = read.value;
    } else if (plan.tokenAuthMode === "unsigned") {
      tokenKey = "";
    }
  } else {
    // Legacy default: the values are that library's own mounted env secrets.
    if (input.need.streamApiKey) {
      const value = readEnv(input.deps.env, "BUNNY_STREAM_API_KEY");
      if (!isSecretValueValid(value)) {
        return failure("incomplete_configuration", plan.libraryId);
      }
      streamApiKey = value;
    }
    if (input.need.tokenKey) {
      const value = readEnv(input.deps.env, "BUNNY_TOKEN_KEY");
      if (!isSecretValueValid(value)) {
        return failure("incomplete_configuration", plan.libraryId);
      }
      tokenKey = value;
    }
  }

  return {
    ok: true,
    credentials: {
      libraryId: plan.libraryId,
      source: plan.source,
      apiLibraryId: plan.apiLibraryId,
      playbackUrlTemplate: plan.playbackUrlTemplate,
      streamApiKey,
      tokenKey,
      tokenAuthMode: plan.tokenAuthMode,
    },
  };
}

async function readSecretValue(
  accessor: BunnySecretAccessor,
  name: string,
  libraryId: string,
): Promise<
  {ok: true; value: string} | BunnySecretFailure
> {
  if (!SECRET_NAME.test(name)) {
    return failure("invalid_catalog_entry", libraryId);
  }
  let raw: string;
  try {
    raw = await accessor.readSecret(name);
  } catch (error) {
    const kind = error instanceof BunnySecretAccessError ?
      error.kind :
      "unavailable";
    return failure(
      kind === "permission_denied" ?
        "secret_permission_denied" :
        kind === "not_found" ?
          "secret_not_found" :
          "secret_unavailable",
      libraryId,
    );
  }
  if (!isSecretValueValid(raw)) {
    return failure("invalid_secret_value", libraryId);
  }
  return {ok: true, value: raw.trim()};
}

/**
 * Build an env snapshot that exposes ONLY the requested library's resolved
 * values, then let the existing pure registry resolvers validate it. This is
 * the Mission 8 §H.3 adapter: the decision logic stays pure and every existing
 * fail-closed branch remains authoritative.
 * @param {object} input Base env, library id and resolved values.
 * @return {BunnyLibraryEnv} Per-library env snapshot (server-only).
 */
export function buildBunnyLibraryEnvSnapshot(input: {
  env: BunnyLibraryEnv;
  libraryId: string;
  credentials: {
    streamApiKey?: string | null;
    tokenKey?: string | null;
    apiLibraryId?: string | null;
    playbackUrlTemplate?: string | null;
  };
  definition?: BunnyLibraryDefinition | null;
}): BunnyLibraryEnv {
  const snapshot: Record<string, string | undefined> = {...input.env};
  const definition =
    input.definition ??
    findBunnyLibraryDefinition(input.libraryId, input.env) ??
    deriveCatalogLibraryDefinition(input.libraryId);
  if (definition === null) return snapshot;
  if (typeof input.credentials.streamApiKey === "string") {
    snapshot[definition.streamApiKeyVar] = input.credentials.streamApiKey;
  }
  if (typeof input.credentials.tokenKey === "string") {
    snapshot[definition.tokenKeyVar] = input.credentials.tokenKey;
  }
  if (
    definition.streamLibraryIdVar !== null &&
    typeof input.credentials.apiLibraryId === "string"
  ) {
    snapshot[definition.streamLibraryIdVar] = input.credentials.apiLibraryId;
  }
  if (
    typeof input.credentials.playbackUrlTemplate === "string" &&
    input.credentials.playbackUrlTemplate.trim() !== ""
  ) {
    snapshot[definition.playbackUrlTemplateVar] = input.credentials.playbackUrlTemplate;
  }
  return snapshot;
}

function mapRegistryFailure(
  reason: string,
  libraryId: string,
): BunnySecretFailure {
  if (reason === "unknown_library") {
    return failure("unknown_library", libraryId);
  }
  if (reason === "library_not_activated") {
    return failure("library_not_activated", libraryId);
  }
  return failure("incomplete_configuration", libraryId);
}

/**
 * Stream API (metadata) credentials for one library.
 * @param {object} input Trusted library id plus dependencies.
 * @return {Promise<object>} Stream runtime or a typed failure.
 */
export async function resolveBunnyStreamApiCredentials(input: {
  libraryId: unknown;
  deps: BunnySecretResolverDeps;
}): Promise<
  {ok: true; runtime: BunnyStreamApiRuntime} | BunnySecretFailure
> {
  const resolved = await resolveBunnyLibraryCredentials({
    libraryId: input.libraryId,
    need: {streamApiKey: true, tokenKey: false},
    deps: input.deps,
  });
  if (!resolved.ok) return resolved;
  const snapshot = buildBunnyLibraryEnvSnapshot({
    env: input.deps.env,
    libraryId: resolved.credentials.libraryId,
    credentials: {
      streamApiKey: resolved.credentials.streamApiKey,
      apiLibraryId: resolved.credentials.apiLibraryId,
      playbackUrlTemplate: resolved.credentials.playbackUrlTemplate,
    },
  });
  const runtime = resolveBunnyStreamApiRuntime(
    snapshot,
    resolved.credentials.libraryId,
    resolveBunnyLibraryDefinition(resolved.credentials.libraryId, input.deps.env),
  );
  if (!runtime.ok) {
    return mapRegistryFailure(
      runtime.reason,
      resolved.credentials.libraryId,
    );
  }
  return {ok: true, runtime: runtime.runtime};
}

/**
 * Playback signing credentials (pull-zone template + token key) for one
 * library. The signing ALGORITHM and URL construction are not touched here.
 * @param {object} input Trusted library id plus dependencies.
 * @return {Promise<object>} Playback runtime or a typed failure.
 */
export async function resolveBunnyPlaybackCredentials(input: {
  libraryId: unknown;
  deps: BunnySecretResolverDeps;
}): Promise<
  {ok: true; runtime: BunnyPlaybackRuntime} | BunnySecretFailure
> {
  const resolved = await resolveBunnyLibraryCredentials({
    libraryId: input.libraryId,
    need: {streamApiKey: false, tokenKey: true},
    deps: input.deps,
  });
  if (!resolved.ok) return resolved;
  const snapshot = buildBunnyLibraryEnvSnapshot({
    env: input.deps.env,
    libraryId: resolved.credentials.libraryId,
    credentials: {
      tokenKey: resolved.credentials.tokenKey,
      apiLibraryId: resolved.credentials.apiLibraryId,
      playbackUrlTemplate: resolved.credentials.playbackUrlTemplate,
    },
  });
  const runtime = resolveBunnyPlaybackRuntime(
    snapshot,
    resolved.credentials.libraryId,
    resolveBunnyLibraryDefinition(resolved.credentials.libraryId, input.deps.env),
    resolved.credentials.tokenAuthMode,
  );
  if (!runtime.ok) {
    return mapRegistryFailure(
      runtime.reason,
      resolved.credentials.libraryId,
    );
  }
  return {ok: true, runtime: runtime.runtime};
}

/**
 * The registry-shaped definition for one library: the compiled entry when one
 * exists (preserving the default library's historical env-var names), else the
 * derived catalog definition. Never widens `findBunnyLibraryDefinition` — the
 * caller must still gate on a catalog row / activation.
 * @param {string} libraryId Canonical library id.
 * @param {BunnyLibraryEnv} env Env snapshot.
 * @return {BunnyLibraryDefinition|null} Definition or null.
 */
export function resolveBunnyLibraryDefinition(
  libraryId: string,
  env: BunnyLibraryEnv,
): BunnyLibraryDefinition | null {
  return (
    findBunnyLibraryDefinition(libraryId, env) ??
    deriveCatalogLibraryDefinition(libraryId)
  );
}

/** Failure kinds exposed by a Secret Manager accessor. */
export type BunnySecretAccessErrorKind =
  | "not_found"
  | "permission_denied"
  | "unavailable";

/**
 * Typed accessor failure. Carries NO secret name and NO raw provider error.
 */
export class BunnySecretAccessError extends Error {
  readonly kind: BunnySecretAccessErrorKind;

  /**
   * @param {BunnySecretAccessErrorKind} kind Stable failure category.
   */
  constructor(kind: BunnySecretAccessErrorKind) {
    super("Bunny library credential is unavailable.");
    this.name = "BunnySecretAccessError";
    this.kind = kind;
  }
}

/** Minimal structural view of the official Secret Manager client. */
export interface BunnySecretManagerClient {
  accessSecretVersion(request: {name: string}): Promise<[
    {payload?: {data?: Uint8Array | string | null} | null},
  ]>;
}

export interface BunnySecretAccessorOptions {
  /** True inside the Functions emulator / local test harness. */
  isEmulator: boolean;
  /** Env source (defaults to process.env). */
  env?: Readonly<Record<string, string | undefined>>;
  /** Explicit GCP project id (defaults to GCLOUD_PROJECT). */
  projectId?: string;
  /** Injectable client factory (unit tests). */
  clientFactory?: () =>
    BunnySecretManagerClient | Promise<BunnySecretManagerClient>;
  /** Positive cache lifetime in milliseconds (0 disables caching). */
  cacheTtlMs?: number;
  /** Injectable clock (unit tests). */
  now?: () => number;
}

function mapSecretManagerError(error: unknown): BunnySecretAccessError {
  const code = (error as {code?: unknown} | null)?.code;
  const text = typeof code === "number" ?
    String(code) :
    typeof code === "string" ?
      code.toUpperCase() :
      "";
  if (text === "7" || text.includes("PERMISSION_DENIED")) {
    return new BunnySecretAccessError("permission_denied");
  }
  if (text === "5" || text.includes("NOT_FOUND")) {
    return new BunnySecretAccessError("not_found");
  }
  return new BunnySecretAccessError("unavailable");
}

/**
 * Create the server-side secret accessor.
 *
 * In production this reads Secret Manager; in emulation it reads the same
 * secret NAME from the environment (never outside emulation). Values are
 * cached for at most `cacheTtlMs` (default 60 s), so rotation takes effect
 * within that bound and is never masked indefinitely.
 * @param {BunnySecretAccessorOptions} options Accessor configuration.
 * @return {BunnySecretAccessor} Accessor.
 */
export function createBunnySecretAccessor(
  options: BunnySecretAccessorOptions,
): BunnySecretAccessor {
  const env = options.env ?? process.env;
  const cacheTtlMs = options.cacheTtlMs ?? BUNNY_SECRET_CACHE_TTL_MS;
  const now = options.now ?? (() => Date.now());
  const cache = new Map<string, {value: string; expiresAt: number}>();
  let clientPromise: Promise<BunnySecretManagerClient> | null = null;

  async function getClient(): Promise<BunnySecretManagerClient> {
    if (options.clientFactory) {
      return await options.clientFactory();
    }
    if (clientPromise === null) {
      clientPromise = import("@google-cloud/secret-manager").then(
        (module) =>
          new module.SecretManagerServiceClient() as unknown as
            BunnySecretManagerClient,
      );
    }
    try {
      return await clientPromise;
    } catch {
      // A failed import must not poison every later attempt.
      clientPromise = null;
      throw new BunnySecretAccessError("unavailable");
    }
  }

  return {
    async readSecret(name: string): Promise<string> {
      if (!SECRET_NAME.test(name)) {
        throw new BunnySecretAccessError("not_found");
      }
      if (cacheTtlMs > 0) {
        const cached = cache.get(name);
        if (cached && now() < cached.expiresAt) return cached.value;
        if (cached) cache.delete(name);
      }

      let value: string;
      if (options.isEmulator) {
        const raw = env[name];
        if (typeof raw !== "string" || raw.trim() === "") {
          throw new BunnySecretAccessError("not_found");
        }
        value = raw;
      } else {
        const projectId = (
          options.projectId ??
          env.GCLOUD_PROJECT ??
          env.GOOGLE_CLOUD_PROJECT ??
          ""
        ).trim();
        if (projectId === "") {
          throw new BunnySecretAccessError("unavailable");
        }
        try {
          const client = await getClient();
          const [response] = await client.accessSecretVersion({
            name: `projects/${projectId}/secrets/${name}/versions/latest`,
          });
          const data = response.payload?.data;
          if (data === undefined || data === null) {
            throw new BunnySecretAccessError("not_found");
          }
          value = typeof data === "string" ?
            data :
            Buffer.from(data).toString("utf8");
        } catch (error) {
          if (error instanceof BunnySecretAccessError) throw error;
          throw mapSecretManagerError(error);
        }
      }

      if (cacheTtlMs > 0 && isSecretValueValid(value)) {
        cache.set(name, {
          value,
          expiresAt: now() + cacheTtlMs,
        });
      }
      return value;
    },
  };
}

/**
 * True when the process is running against local emulators. The Functions
 * emulator sets `FUNCTIONS_EMULATOR`; `firebase emulators:exec` test commands
 * expose `FIRESTORE_EMULATOR_HOST`. Neither exists in production.
 * @param {Readonly<Record<string, string | undefined>>} env Env source.
 * @return {boolean} True for local emulation.
 */
export function isBunnySecretEmulator(
  env: Readonly<Record<string, string | undefined>> = process.env,
): boolean {
  if (env.FUNCTIONS_EMULATOR === "true") return true;
  const host = env.FIRESTORE_EMULATOR_HOST;
  return typeof host === "string" && host.trim() !== "";
}

/** Minimal Firestore surface for the catalog lookup. */
export interface BunnyCatalogFirestore {
  collection(name: string): {
    doc(id: string): {
      get(): Promise<{exists: boolean; id: string; data(): unknown}>;
    };
  };
}

/**
 * Firestore-backed catalog source for one library document.
 * @param {BunnyCatalogFirestore} db Firestore handle (or a test double).
 * @return {BunnyCatalogDocumentSource} Catalog source.
 */
export function firestoreBunnyCatalogSource(
  db: BunnyCatalogFirestore,
): BunnyCatalogDocumentSource {
  return {
    async get(libraryId: string) {
      const snapshot = await db
        .collection("bunny_libraries")
        .doc(libraryId)
        .get();
      if (!snapshot.exists) return null;
      return {id: snapshot.id, data: snapshot.data()};
    },
  };
}

/**
 * Map a credential failure onto the playback/association registry vocabulary.
 * Secret-specific failures are intentionally collapsed to
 * `incomplete_configuration` so clients learn nothing about secret state.
 * @param {BunnySecretFailureReason} reason Typed failure.
 * @return {string} Registry-style reason.
 */
export function bunnyCredentialFailureReason(
  reason: BunnySecretFailureReason,
): string {
  if (reason === "unknown_library") return "unknown_library";
  if (reason === "library_not_activated") return "library_not_activated";
  return "incomplete_configuration";
}

/** Re-exported for callers that only need the client type. */
export type {SecretManagerServiceClient};
