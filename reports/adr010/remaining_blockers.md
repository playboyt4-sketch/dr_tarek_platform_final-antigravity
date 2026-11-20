# ADR-010 — Remaining Blockers

Status after the autonomous implementation pass. None of these was worked around.

## Deployment-time blockers (outside local authority)

| # | Blocker | Why it blocks | Owner action |
|---|---|---|---|
| B1 | Stream API key for library `775315` | the existing library-scoped key returns 401 for `775315`; metadata (poster/post-edit previews) cannot be resolved for that library | create `BUNNY_775315_STREAM_API_KEY` and bind it |
| B2 | Token-signing key for `775315` + decision to enable token auth on its Pull Zone | the zone currently serves unsigned HLS (HTTP 200 with the app `Referer`), so playback would be unprotected | enable token authentication on `vz-c850a9e1-eb4` and create `BUNNY_775315_TOKEN_KEY` |
| B3 | Playback URL template for `775315` | no template exists; the resolver fails closed with `incomplete_configuration` | create `BUNNY_775315_PLAYBACK_URL_TEMPLATE` for `vz-c850a9e1-eb4` |
| B4 | Activation entry | the second library is deliberately absent from `BUNNY_ACTIVE_LIBRARY_IDS` | add `775315` only after B1–B3 are in place and verified |
| B5 | `BUNNY_STREAM_API_KEY` lives in a plain function env var, not Secret Manager | conflicts with ADR-010's secret-handling requirement | migrate the value to Secret Manager and bind it |
| B6 | Deployment authorization | implementation gate requires per-resource verified mappings, passing tests and owner approval | owner decision after review |

With B1–B4 absent, every `775315` resolution returns `library_not_activated` or
`incomplete_configuration` — verified by tests. No accidental activation path exists.

## Product/design blockers

| # | Blocker | Effect |
|---|---|---|
| D1 | No approved Figma spec for the library picker | the Dashboard library **selector UI** is not implemented. The data layer, staging, persistence, validation and legacy handling are complete; the Video dialog still has only Name / Video ID / Order fields. |

Consequences of D1 (documented, not hidden):

- A doctor cannot choose a library from the Dashboard today; new videos go to the
  default library, and edits preserve the stored association.
- If a doctor pastes a Video ID that actually belongs to `775315` while the default
  library is active, the association stays `736742` and playback fails at source
  preparation — exactly today's behaviour, so no regression, but the fix requires
  either the picker (after Figma) or the verified backfill.

## Content-management issue (separate, out of ADR-010 scope)

| # | Item |
|---|---|
| C1 | 7 `video` resources with an empty `bunny_video_id` (`1Lv5zsow5Ap5GJNaArcP`, `Ey3Nqi1zgTQ8hOpXOcYv`, `ICz33MA21JQSy9e8OJ7h`, `YmV7LRp9diX9kUCn4PRT`, `ju1taw2UbenaC6FIrgFV`, `qctAJDSdM9sxND9e2Ehq`, `yjwx89srQkzr3d4PKdGe`). The planner skips them (`skipped_no_video_id`) and they remain untouched. |
| C2 | Duplicate Video ID `6ffb23ad…` on two resource documents. |
| C3 | Archived/`is_deleted` lectures remain issuable (issuance checks existence only). Out of ADR-010 scope; unchanged and needs separate approval. |

## Tooling limitations recorded

- `npx eslint src/index.ts` reports ~9 000 `linebreak-style` errors because the
  working copy of that file uses CRLF (it did before this task; `HEAD` is LF). The
  file's pre-existing uncommitted modifications were not reformatted. The new files
  added by this task are LF and lint clean.
- The emulator-backed suite (`npm test`) and the full Dashboard/Flutter test folders
  were **not** run; only the new targeted suites and analyses were.
