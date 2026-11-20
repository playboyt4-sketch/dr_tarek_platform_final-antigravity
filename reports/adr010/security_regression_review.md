# ADR-010 — Security Regression Review (Mission 2)

Scope: every file changed in Mission 2 plus the ADR-010 code from Mission 1 that this
mission touched. Read-only review; no production access was performed.

## 1. Secrets

| Check | Result |
|---|---|
| Secrets in source | **NONE added.** Registry stores env var *names*; the catalog stores ids and labels only |
| Secrets in test fixtures | **NONE.** Values are visibly fake placeholders (`fixture-token-key`, `fixture-775315-api-key`); renamed from neutral filler so pattern scans stay quiet |
| Secrets in reports | **NONE.** Reports describe names and behaviours, never values |
| Secret Manager / env changes | **NONE.** No `defineSecret` added, no env var set, no project write |
| Logging | Only `library=<id>` was added to a server log line; no template, key or token |

## 2. Server authority for signing configuration

- Credentials are selected only by `resolveBunnyLibraryForResource`, from the trusted
  Firestore row (`bunny_library_id`), never from client input.
- A client `libraryId` hint must equal the stored value or the call fails with
  `failed-precondition`; on a legacy row the hint is ignored.
- `resolveBunnyPlaybackRuntime` / `resolveBunnyStreamApiRuntime` fail closed for unknown,
  inactive and incomplete libraries; there is no "try the other library" branch.

## 3. Pull-zone / cross-library isolation

- The playback URL template and token key come from the resolved library only.
- Display media (poster / HQ preview) resolves through the same library; an unresolvable
  library yields no Bunny-derived media rather than another zone's asset.
- Stream metadata cache keys are `libraryId:videoId` (`bunnyPosterCacheKey`), proven by
  test, so identical Video IDs in two libraries cannot collide.
- Tests assert the default library never borrows `BUNNY_775315_*` values.

## 4. Entitlement and device rules

- No authorization code was edited in Mission 2.
- Pure predicates asserted: explicit per-lecture deny (incl. soft-deleted grants
  deferring), document feature keys (`<type>.access` / `<type>.download`), VIDEO-ID-ONLY
  identifier validation, window-over-tier denial precedence.
- `first_video` eligibility/ordering asserted unchanged (video + visible + live + id;
  lowest order, document-id tie-break).
- Device binding, session takeover, heartbeat, quality matrix and preview caps were
  **not opened** by this mission; their suites were not run (NOT RUN, stated).

## 5. Migration tooling

- Write capability **deleted**, not flagged: the CLI has no Firestore write call.
- `--apply` is refused before any file read or project connection (exit 3, verified).
- Planner refuses ambiguous input; conflicts block `writable`; backup metadata is built
  but no write consumes it.
- No production document was read or written by this mission (the CLI was only executed
  in its two guard paths, which exit before connecting).

## 6. Library 775315 status

- Still absent from `BUNNY_ACTIVE_LIBRARY_IDS`; no allow-list entry added.
- Its token authentication / hotlink settings were not touched.
- Its catalog entry is `isSelectable: false`, so even the future UI defaults to blocking
  it until activation and design approval.

## 7. Known issues left untouched (reported, not fixed)

1. `775315` Pull Zone serves unsigned HLS (content protection relies on GUID secrecy).
2. Archived / `is_deleted` lectures remain issuable (`generateBunnySignedUrl` and
   `getLectureResources` check existence only) — out of ADR-010 scope.
3. Duplicate `6ffb23ad…` video id on two resource documents.
4. Seven placeholder video resources with empty `bunny_video_id`.
5. `BUNNY_STREAM_API_KEY` still stored as a plain function env var rather than in Secret
   Manager (owner action).

## 8. Verdict

No security regression introduced. The additive library metadata is fail-closed,
server-authoritative, and cannot widen access, redirect signing credentials, or expose
secrets to clients. Residual risks are the pre-existing items above, all documented.
