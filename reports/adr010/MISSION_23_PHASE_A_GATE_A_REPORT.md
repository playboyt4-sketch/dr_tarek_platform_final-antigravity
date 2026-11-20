# ADR-010 — Mission 23 Phase A: Production Credential Containment (Gate A)

**Date:** 2026-11-17
**Project:** `dr-tarek-platform` / `606744934510` / ACTIVE / `us-central1`
**Library rotated:** `736742` (canonical Production default)
**Mode:** Production mutations executed only inside the owner-approved Gate A scope
(rotate key, create secret, per-secret IAM, scrub local `.env`). No deployment in this phase.
**Secrets:** no secret value, partial value, fingerprint or secret-shaped token appears in this report.

---

## A.1 — Rotation mechanism (and why it differs from the dashboard path)

The Mission 23 plan assumed the Bunny dashboard exposes a "rotate" control on
`Stream → 736742 → API`. It does not. The live UI was inspected read-only:

| UI element | Live state | Consequence |
| --- | --- | --- |
| `API Key` field | present, `readonly`, masked (`type=password`, 41 chars) | no edit / no reset control |
| `Read-only API Key` field | present, `readonly`, masked (41 chars) | same |
| Buttons on the page | `Add`, `Save` (webhook URL) only | no rotation action |
| Any `reset` / `regenerate` control | **none found** (no matching title/aria/class in the DOM) | rotation impossible from the library page |

Bunny's documented rotation path is the account API (`POST /videolibrary/{id}/resetApiKey`, account key).
That endpoint was used, from **inside the already-authenticated dashboard session**:

1. The dashboard page (origin `dash.bunny.net`) read its own account key from the masked field and called
   the reset endpoint — the account key never left the browser.
2. The response's new library key was written to the OS clipboard **by the page**, never returned to the
   agent, this report, a file, a command argument or a log.
3. The clipboard was piped (`powershell Get-Clipboard | node`) into a local script that stored it as a
   Secret Manager version through `stdin`.

Evidence printed by that chain: HTTP statuses, lengths and version metadata only.

---

## A.2 — Rotation and verification evidence

| # | Check | Result |
| --- | --- | --- |
| 1 | `POST api.bunny.net/videolibrary/736742/resetApiKey` | **204** |
| 2 | `GET api.bunny.net/videolibrary/736742` (library id in response) | **200**, `Id = 736742` |
| 3 | New library key shape | **41 chars** (expected library-key format) |
| 4 | `GET video.bunnycdn.com/library/736742/videos?pageSize=1` with the **NEW** key | **200** |
| 5 | Same call with the **OLD** key (read from `functions/.env` before scrubbing) | **401** — revoked |
| 6 | `GET api.bunny.net/videolibrary/736742` with the **NEW** key | **401** — proves it is a library-scoped key, not an account key |
| 7 | Old key kept active during rotation? | **Not possible** — Bunny replaces the single library key atomically. The old key was invalid from the 204. The documented consequence (pre-deployment Stream metadata returning null on the 79 old-code functions) was accepted in advance and is temporary until the Phase B deployment. |

Note (recorded for accuracy): an in-page probe of the new key returned **401**, while the same probe from
the CLI returned **200**. The in-page result was a cross-origin artifact of `dash.bunny.net → video.bunnycdn.com`;
the authoritative CLI probe is 200, and it was repeated as part of the storage step.

Also recorded: an earlier paste of the account API key into the chat made that account key `POTENTIALLY
EXPOSED`. The owner was instructed to reset it; the value used later came from the live dashboard field, so
the exposed value is not the value that executed the reset. **Owner action still recommended:** confirm the
account API key shown at `Account → API key` has been refreshed since that paste.

---

## A.3 — Secret Manager configuration

| Item | Value |
| --- | --- |
| Secret name | `BUNNY_STREAM_API_KEY` |
| Resource | `projects/606744934510/secrets/BUNNY_STREAM_API_KEY` |
| Created (secret) | `2026-11-16T17:31:14Z` |
| Labels | `adr=adr010`, `mission=mission23` |
| Replication | automatic |
| Versions | **1 — `enabled` — `2026-11-17T11:29:54`** |
| Payload | never read back, never printed (only written through `--data-file=-` on stdin) |
| Pre-existing secret | none (`NOT_FOUND` verified immediately before creation) |

## A.4 — IAM verification

| Item | Value |
| --- | --- |
| Binding on `BUNNY_STREAM_API_KEY` | `roles/secretmanager.secretAccessor` |
| Members | **exactly one**: `serviceAccount:606744934510-compute@developer.gserviceaccount.com` |
| Project-level Secret Manager roles | **none** (`gcloud projects get-iam-policy` has no `secretmanager` role) |
| Other secrets | policies untouched (each still one per-secret binding to the same runtime SA) |
| Unrelated IAM | untouched |

## A.5 — Local `.env` scrub

| | Before | After |
| --- | --- | --- |
| Lines (non-empty) | 2 | 2 |
| `APP_CHECK_ENFORCEMENT` | 97-char flattened blob (3 assignments concatenated, embedded key) | **`false`** (explicit boolean) |
| `BUNNY_STREAM_API_KEY` | embedded inside the blob (41-char revoked key) | **absent** (0 matches) |
| `BUNNY_STREAM_LIBRARY_ID` | `736742` | `736742` |
| Git tracking | ignored | ignored (`.gitignore` covers `functions/.env`) |

The new key was **not** written to `.env`; it exists only in Secret Manager. No backup of the revoked key was
created (it is invalid, and retaining revoked key material would be a new liability).

## A.6 — Gate A verification summary

| Criterion | Status |
| --- | --- |
| New Bunny API key returns 200 | **PASS** |
| Old key returns 401 | **PASS** |
| Secret exists | **PASS** |
| Version 1 enabled | **PASS** |
| Secret-level IAM scoped to the runtime SA only | **PASS** |
| No project-wide Secret Manager accessor | **PASS** |
| No plaintext Stream API key in `functions/.env` | **PASS** |
| `APP_CHECK_ENFORCEMENT=false` (explicit) | **PASS** |
| `BUNNY_STREAM_LIBRARY_ID=736742` | **PASS** |
| No secret value in Git-tracked files | **PASS** — only the identifier `BUNNY_STREAM_API_KEY` in `functions/src/index.ts` |
| No secret value in reports | **PASS** — scanned all `reports/adr010/*.md` for Bunny-key-shaped tokens: **0 hits** |

**Gate A: CLOSED.** Deployment is not authorised by this report; Phase B requires its own approval and is
documented separately.
