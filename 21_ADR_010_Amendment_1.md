# ADR-010 — Amendment 1: Configurable Library Identity

Status: Implemented (code + tests), pending deployment
Date: 2026-11-13
Amends: `21_ADR_010_Multi_Library_Bunny_Stream.md` (implementation detail only)
Authority: Platform Owner final execution authorization (2026-11-13), which explicitly
authorized removing the hardcoded production-library identity and resolving the staging
identity split.

No security guarantee of ADR-010 is modified by this amendment.

## Context

Two defects were proven during Missions 10 and 11:

1. `DEFAULT_BUNNY_LIBRARY_ID = "736742"` was a compiled constant, and it was *always*
   active (`isDefault`), so no environment could name its own canonical library.
2. `BUNNY_STREAM_LIBRARY_ID` was overloaded. Setting it to `780700` (staging) made Stream
   metadata calls target `780700` while the canonical library id stayed `"736742"` — an
   identity split that could label `780700` data as `736742` and vice versa.

Additionally, `bunny_library_catalog.dart` and the mobile authoring fallback pinned
`'736742'` at compile time, so a staging build silently authored against the production
library id.

## Decision

### A1.1 Canonical default is configuration, not a compiled assumption

- New variable `BUNNY_DEFAULT_LIBRARY_ID` (numeric id, trimmed).
- `resolveDefaultBunnyLibraryId(env)`: non-empty numeric override wins; anything else
  (absent, blank, malformed) falls back to the compiled `DEFAULT_BUNNY_LIBRARY_ID`.
- `DEFAULT_BUNNY_LIBRARY_ID` is retained as **the production fallback**, so every
  environment that does not set the override behaves exactly as before (no deploy-time
  behaviour change on production).
- Library definition lookup, legacy fallback, playback runtime and Stream runtime all use
  the resolved id, so the canonical id and the credentials agree.

### A1.2 The identity split is surfaced, never silent

`describeBunnyEnvironment(env)` returns
`{defaultLibraryId, streamApiLibraryId, mismatch}`; `functions/src/index.ts` logs a warning
at boot when `BUNNY_STREAM_LIBRARY_ID` disagrees with the canonical default. Diagnostic
only — no resolution path depends on it, and it is skipped under `NODE_ENV=test`.

### A1.3 Clients carry a build-time default, not a hardcoded production id

`defaultBunnyLibraryId` (Dashboard) and `_defaultBunnyLibraryId` (mobile authoring) read
`String.fromEnvironment('BUNNY_DEFAULT_LIBRARY_ID', defaultValue: '736742')`.
Default builds are byte-identical to today; non-production builds pass
`--dart-define=BUNNY_DEFAULT_LIBRARY_ID=<id>`.

### A1.4 Unchanged guarantees

- `bunny_library_id` remains server-owned; clients still cannot write it.
- Non-default libraries still require explicit `BUNNY_ACTIVE_LIBRARY_IDS` activation.
- `BUNNY_LEGACY_LIBRARY_FALLBACK=false` still disables the legacy fallback.
- Unknown / inactive / incomplete / mismatched libraries still fail closed with a typed
  reason; there is still no "try another library" path.
- `created_at` immutability, receipt binding (resource, lecture, library, video), 600s TTL,
  constant-time comparison and the cutover gate are untouched.

## Consequences

- A staging environment can be made coherent with two variables
  (`BUNNY_DEFAULT_LIBRARY_ID=780700` + `BUNNY_STREAM_LIBRARY_ID=780700`) instead of a code
  change.
- Production needs no configuration change: the fallback is the current library.
- The `isDefault` bypass remains (a deliberate backward-compatibility decision). Making the
  default subject to the activation list is a separate decision and is **not** taken here.

## What this amendment does NOT do

The server-managed Firestore catalog, account-API provisioning, per-library Secret Manager
reads and the activation verification gate (Mission 8 §H, Mission 10 §7) are **authorized
but not implemented**. ADR-010's "no code change per library" objective is therefore still
unmet; this amendment only removes the hardcoded identity and makes the environment
self-describing. Tracked in `reports/adr010/FINAL_BUNNY_MULTI_LIBRARY_COMPLETION_REPORT.md`
§12.
