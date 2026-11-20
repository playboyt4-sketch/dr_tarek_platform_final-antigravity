# ADR-010 — Pre-write Library/Video Metadata Validation (Mission 3, Workstream C)

Status: **PARTIAL** — the server-side validation boundary and signed receipt are
implemented and verified; enforcement *at persistence time* is not wired because it
requires deployment (prohibited here) and no approved write path exists yet.

## 1. New server surface

`functions/src/core/video/bunny_video_validation.ts` (pure, no I/O):

- `planBunnyVideoValidation({libraryId, videoId}, env)` — format gate (bare GUID), then
  registry resolution, then Stream API configuration.
- `interpretBunnyMetadataResponse({status, body}, request)` — library-scoped verdict.
- `interpretBunnyMetadataError(error, request)` — timeout vs other transport failure.
- `signBunnyValidationReceipt(...)` / `verifyBunnyValidationReceipt(...)` — HMAC-SHA256
  receipt binding `(libraryId, videoId, expiresAt)`; constant-time comparison; expiry.

`functions/src/index.ts` → `validateBunnyVideoAssociation` (onCall, `SECURE_CALL_OPTS`,
`secrets: [BUNNY_TOKEN_KEY]`):

1. `requireDoctor(request)` — content authoring is doctor-only.
2. Plan (format → library → credentials).
3. `GET https://video.bunnycdn.com/library/{apiLibraryId}/videos/{videoId}` with the
   library's own AccessKey, 8s abort.
4. Interpret → `verified` / `mismatch` / `unavailable` / `rejected`.
5. On `verified`, return a 10-minute signed receipt.

Response shape is closed: `{status, reason, libraryId, videoId, receipt}`. No key, token,
template, pull zone or secret-manager reference is ever returned (asserted by test).

## 2. Decision table

| Situation | Result | Persisted? |
|---|---|---|
| Valid GUID + active library + metadata confirms video and library | `verified` + receipt | allowed by policy |
| 200 naming another video | `mismatch` / `video_mismatch` | no |
| 200 naming another library | `mismatch` / `library_mismatch` | no |
| 404 from the library-scoped endpoint | `mismatch` / `not_found_in_library` | no |
| 401/403 from Stream | `unavailable` / `api_unauthorized` | no (not verified) |
| Timeout / 5xx / unparseable body | `unavailable` | no |
| Unknown library id | `unavailable` / `unknown_library` | no |
| Inactive library (`775315`) | `unavailable` / `inactive_library` | no |
| Library active but credentials absent | `unavailable` / `incomplete_configuration` | no |
| URL instead of GUID | `rejected` / `invalid_video_id` | no |

`unavailable` is never treated as success and never substitutes another library.

## 3. Caching / performance

Positive **and** negative verdicts are cached in-process for 10 minutes under
`bunnyPosterCacheKey(libraryId, videoId)` — the same per-library identity as the poster
cache, so a duplicate Video ID in two libraries can never share a verdict. Timeouts and
5xx are cached too (short TTL) to avoid hammering Bunny while a doctor retries; the TTL
bounds staleness for newly uploaded videos.

## 4. Why enforcement is not yet at the write boundary

Dashboard authors write `lecture_resources` directly from the client. Enforcing the
verdict at persistence needs one of:

1. **Callable before save (preferred)** — dashboard calls `validateBunnyVideoAssociation`,
   then persists only when `status == "verified"`; requires deployment + Figma-gated UX.
2. **Server-side write** — a doctor-only callable that verifies the receipt and writes
   `bunny_library_id` itself (server-authoritative, no rules change).
3. **Trigger guard** — `onDocumentWritten` rejects/repairs a mismatched association; a
   production behaviour change that must be designed and approved first.

All three are blocked here by the no-deployment rule. The current code is the safe
foundation for any of them, and the receipt is exactly what option 2 consumes.

Legacy rows: editing never invents an association (`libraryIdForWrite` falls back to the
stored value, null stays null), so a legacy row cannot be silently re-associated.

## 5. Tests

- `functions/test/bunny_video_validation.test.js` — 26 assertions: planning gates
  (URL/empty/unknown/inactive/incomplete/activated), response interpretation
  (match, video mismatch, library mismatch, 404, 401, 5xx, unparseable), error mapping
  (timeout vs transport), receipts (valid, wrong library, wrong video, expired, tampered,
  foreign secret, malformed).
- `functions/test/bunny_library_validation_flow.test.js` — 7 emulator assertions:
  unauthenticated, non-doctor, invalid id, unknown library, inactive `775315`, empty
  library, closed response shape (no credentials).

Network behaviours (real Bunny responses) are NOT exercised: no credential for `775315`
and no live calls were made. Interpretation is covered by fixtures instead.
