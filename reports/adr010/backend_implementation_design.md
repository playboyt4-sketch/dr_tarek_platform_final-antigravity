# ADR-010 — Workstream D: Backend Implementation Design

Date: 2026-11-12
Mode: DESIGN ONLY — no code changed, nothing deployed.

All paths are relative to the repository root. Line numbers refer to the current working tree
(`functions/src/index.ts` is already modified in the working tree relative to HEAD; numbers are from the
current file on disk).

## 1. Current behavior (verified by reading the code)

| Function | Location | Behavior | Single-library coupling |
|---|---|---|---|
| `generateBunnySignedUrl` | `functions/src/index.ts:4272` | auth → rate limit → resource lookup → lecture → subject → subscription → plan → features → tier → window → quality → sign URL | `BUNNY_PLAYBACK_URL_TEMPLATE` (4649), `BUNNY_TOKEN_KEY` (1527/4695), fixed `/{videoId}/` directory scope (4688) |
| `hashVideoDirectoryToken` | `1527–1538` | HMAC-SHA256 directory token | one global secret |
| `buildBunnyFileUrl` | `1559–1580` | signed poster/preview file URL under a video directory | derives origin from the playback template (1564) + same secret |
| `bunnyStreamApiConfig` | `1599–1603` | reads `BUNNY_STREAM_API_KEY` + `BUNNY_STREAM_LIBRARY_ID` | one library, one key |
| `fetchBunnyVideoMeta` | `1607–1680` | Stream API video metadata (poster filename, HQ preview), cached per videoId | hard-coded `/library/{libraryId}/videos/{id}` (1630) |
| `resolveVideoDisplayMedia` | `1695–1734` | explicit thumbnail → Bunny poster → HQ preview | delegates to the two functions above |
| `getLectureResources` | `4939–5108` | listing + serialization | secrets binding (4945); `serializeResource` (4988–5002) emits `bunnyVideoId` only |
| Secrets binding | `4273–4274`, `4945` | `defineSecret(...)` + `secrets: [...]` | static list |
| `getEnv` | `1549–1553` | throws `failed-precondition` when unset | — |

Authorization chain (unchanged by ADR-010): `requireAuthenticated` → `assertVideoRequestAllowed`
(rate limit) → `matchIssuanceResource` (383) → lecture existence (4396) → `assertLectureAccessNotDenied`
(4393 → 1243) → `requireEnabledSubjectAccess` → active subscription → plan active + `student_type` →
`getPlanFeatures` → rolling window → `evaluateSubjectTier` (device tier) → `video.access` → quality
matrix → session (Max).

## 2. Proposed library registry (server-managed)

New module file: `functions/src/bunny/library_registry.ts` (pure, unit-testable, no I/O at import).

```ts
export interface BunnyLibraryConfig {
  libraryId: string;            // "775315"
  playbackTemplate: string;     // "https://vz-....b-cdn.net/{video_id}/playlist.m3u8"
  tokenKey: string;             // signing secret for THIS pull zone
  streamApiKey: string;         // Stream API key for THIS library
  requiresToken: boolean;       // observed/declared protection model
}

export function resolveLibraryForResource(
  resource: {bunny_library_id?: unknown},
  registry: Map<string, BunnyLibraryConfig>,
  defaultLibraryId: string | null,
): {kind: "resolved"; config: BunnyLibraryConfig} | {kind: "missing"} | {kind: "unknown"; id: string};
```

Rules (ADR-010 §Backend):

1. `resource.bunny_library_id` present → must exist in the registry, otherwise `unknown` → **fail closed**
   (`failed-precondition`, no URL issued).
2. Absent/null → allowed only for legacy resources **and** only while the migration flag is on
   (`BUNNY_LEGACY_DEFAULT_ENABLED=true`); resolves to the default library.
3. A client-provided `libraryId` is accepted only as a lookup hint and must equal the resource's stored
   value; mismatch → `invalid-argument`.
4. The registry is built from environment/secret references only — never from request data.

### Secret/environment strategy (no dynamic `defineSecret`)

`firebase-functions` v2 requires secrets to be declared statically. Two supported options:

- **Option 1 (recommended):** one JSON secret `BUNNY_LIBRARY_REGISTRY` (map of libraryId → config
  references) + per-library secrets declared statically for the libraries that exist at deploy time
  (e.g. `BUNNY_TOKEN_KEY`, `BUNNY_TOKEN_KEY_775315`, `BUNNY_PLAYBACK_URL_TEMPLATE`,
  `BUNNY_PLAYBACK_URL_TEMPLATE_775315`). Adding a library = adding two secrets + redeploy.
- **Option 2:** keep templates in a `system_settings/bunny_libraries` document (not secret) and only the
  keys in Secret Manager. Adds a Firestore read per cold start (cacheable).

Recommendation: Option 1 for the template only if the template is considered sensitive; otherwise
template in `system_settings` (public config) and **keys only** in Secret Manager.

### Required changes in `functions/src/index.ts`

| # | Change | Function(s) | Notes |
|---|---|---|---|
| 1 | Add `bunnyLibraryId` to the resource lookup projection and to `serializeResource` | `generateBunnySignedUrl` (4308–4320), `getLectureResources` (4988–5002) | additive response key |
| 2 | Resolve config before signing | `generateBunnySignedUrl` (before 4649) | replaces direct `getEnv` calls |
| 3 | Parameterize template/token | `hashVideoDirectoryToken` stays pure; new `buildSignedPlaybackUrl(config, videoId, quality, format)` | removes duplicated URL assembly at 4649–4698 and 1559–1580 |
| 4 | Parameterize metadata library | `bunnyStreamApiConfig(libraryId)`, `fetchBunnyVideoMeta(videoId, libraryId)` (1607–1680) | cache key must include libraryId |
| 5 | Parameterize poster/preview signing | `resolveVideoDisplayMedia(resource)` (1695–1734) → pass resolved config | keeps display media and playback consistent |
| 6 | Optional client assertion | `request.data.libraryId` | validate against stored value only |
| 7 | Add migration flag | `BUNNY_LEGACY_DEFAULT_ENABLED` | default `false` after migration; `true` during it |
| 8 | Fail-closed error | new `HttpsError("failed-precondition", "Video library is not configured.")` | never falls back silently |

Not in scope (separate approval): `lecture.status` / `lecture.is_deleted` gates.

## 3. Idempotence & caching notes

- `bunnyPosterCache` (`1560s` region) must key on `${libraryId}:${videoId}`; otherwise a poster resolved
  from one library can be reused for the same GUID in another.
- Signed URL TTL (300 s) and the client's prefetch cache (>30 s remaining) are unchanged.
- Registry construction must be lazy and memoized per instance; no per-request secret reads.

## 4. Error contract (client-visible)

| Condition | Code | Message (stable sentinel) |
|---|---|---|
| Resource has unknown library | `failed-precondition` | `Video library is not configured.` |
| Client hint ≠ stored library | `invalid-argument` | `Video library does not match this resource.` |
| Legacy resource, fallback disabled | `failed-precondition` | `Video library mapping is required.` |
| Library known but video absent | (unchanged) CDN 404 at player — **recommend** server-side existence check (cached) as a follow-up |

## 5. Backward compatibility

- No request field is mandatory; existing clients keep working.
- `getLectureResources` adds keys, removes none.
- If the registry is empty/misconfigured, the default library path reproduces today's behavior exactly
  (with the migration flag on) — no student-visible change.

## 6. Testing hooks

Export the pure resolver + URL builder so Cloud Functions tests can assert:
library selection, unknown-library failure, legacy fallback, template/token pairing, and that a
client hint cannot change the signing key.
