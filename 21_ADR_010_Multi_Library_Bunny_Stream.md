# ADR-010 — Multi-Library Bunny Stream Architecture

Status: Approved by Platform Owner - Amended by Amendment 2 (Option C recorded)
Date: 2026-11-12
Version: 1.0
Authority: Project Owner decision (documentation record; implementation not started)
Decision ID: ADR-010 (next available number in the ADR registry: ADR-003, ADR-006, ADR-007, ADR-008, ADR-009 are taken)

This ADR records a Project-Owner-approved decision. It does not rewrite any
Approved document, does not promote any Draft document, and does not change
any Flutter code, Cloud Function, Firestore/Storage Rules, Firebase
configuration, Bunny configuration, production data, or test in this step.
Current-system references use the canonical role terminology: Doctor
(Platform Owner).

## Context

Dr. Tarek Platform delivers protected lecture video through Bunny Stream.
Production evidence (2026-11-11) established that the account owns several
Stream libraries, while the backend is configured for exactly one:

- Default/configured library: `736742` ("اختبار", 2 videos) — its pull zone is
  `vz-c6abe953-876.b-cdn.net`, which is the value of
  `BUNNY_PLAYBACK_URL_TEMPLATE`.
- Content library actually holding the published Financial Accounting
  lectures: `775315` ("المنصة القديمة", 74 videos) — its pull zone is
  `vz-c850a9e1-eb4.b-cdn.net`.

The three published lecture Video IDs exist and play (HTTP 200,
`application/vnd.apple.mpegurl`) on the `775315` pull zone, and return HTTP
404 on the configured `736742` pull zone. The platform therefore issues a
correctly signed URL for a resource that does not exist in the configured
library, and playback fails at source preparation with HTTP 404.

Root architectural cause: one global playback template + one global token
key + one global Stream library ID, while `lecture_resources` stores only
`bunny_video_id`. Nothing in the data model expresses which library a video
belongs to.

## Decision

Dr. Tarek Platform shall support multiple Bunny Stream Libraries.

1. Every Bunny video resource shall be associated with its actual Bunny
   Library and Video ID.
2. The backend shall resolve the trusted playback configuration from
   server-managed library configuration.
3. Clients must never select signing credentials or construct trusted
   playback URLs.

## Resource Schema

Add to `lecture_resources`:

- `bunny_library_id`: nullable string during migration.
- Existing `bunny_video_id`: preserved unchanged.

Do not change `resource_url`; it remains dedicated to external links and
existing document compatibility (`external_link` target and the legacy
`storage_path ?? resource_url` document fallback).

Notes:

- `null` / absent `bunny_library_id` means "legacy resource" and is resolved
  through the default library only during the controlled migration period.
- No video re-upload, and no change to existing resource IDs or Video IDs.
- Whether the denormalized `lectures.first_video` pointer also carries the
  library is an implementation detail; if it does, it must be additive and
  backward compatible.

## Backend

The existing `generateBunnySignedUrl` function shall resolve the correct
library configuration using the trusted resource record (not client input).

Requirements:

- Library-specific configuration must include the required playback template,
  token-signing configuration, and Stream API credential reference.
- Secrets must remain server-side in Firebase Secret Manager. No secret value
  is returned to any client, written to Firestore, or logged.
- Library resolution order: trusted resource record → server-side library
  registry → default library (legacy resources only, during migration).
- Unknown or unverified library mappings must fail closed with a clear
  server error, never a silent fallback to another library.
- A client-supplied library identifier may only be used as a lookup hint; the
  server must validate it against the stored resource before any signing
  credential is selected.
- Poster/preview metadata resolution (`fetchBunnyVideoMeta`) and the signed
  poster/preview fallback (`buildBunnyFileUrl`) must use the same per-library
  resolution as playback, so display media and playback can never diverge.
- `getLectureResources` must expose the resolved library identifier to
  authorized clients as additive metadata, keeping existing response keys
  unchanged.
- Authorization behavior is unchanged: authentication, per-lecture deny,
  subject access, active subject subscription, plan validity for the
  student type, Feature Matrix, device tier, rolling window, quality matrix,
  and playback sessions continue to be enforced before issuance.

## Dashboard

- The content authoring workflow shall support selecting an existing
  configured library and entering its corresponding Video ID.
- The selected library is stored on the resource as `bunny_library_id`.
- Default selection for new resources is the default library; existing
  resources show their stored value (or "legacy/default" when absent).
- Library configuration management and secret management remain restricted
  to authorized platform-level administration. The Dashboard must not display
  or transmit signing secrets.

## Flutter

- Flutter shall continue requesting playback through the existing backend
  contract (`generateBunnySignedUrl`), with any required resource metadata
  changes introduced compatibly (additive field, tolerant parsing).
- No direct Bunny secret access is permitted. No client-side URL construction,
  token generation, or library selection is authorized.
- Player behavior (headers, HLS hint, caching, renewal, error mapping) is
  unchanged unless a defect is proven separately.

## Preserved Rules

- Subscription and Feature Matrix enforcement.
- Device Binding and playback takeover.
- Preview restrictions.
- Video quality rules.
- Existing resource IDs and Video IDs.
- Publication state and resource ordering.

## Migration

1. Inventory all video resources.
2. Verify each Video ID against its actual Bunny Library.
3. Configure and validate every required library.
4. Implement backward-compatible backend resolution.
5. Add Dashboard library selection.
6. Backfill verified library associations.
7. Validate playback and security.
8. Remove legacy fallback only after successful migration.

## Explicitly Out of Scope

- Video re-upload.
- Subscription redesign.
- Device Binding redesign.
- Changes to `resource_url`.
- Unrelated archived/deleted lecture authorization fixes, which require
  separate approval.

## Implementation Gate

No production deployment or migration execution until:

- All required library credentials are configured.
- Every existing video resource has a verified library mapping.
- The implementation and regression tests pass.
- The Platform Owner authorizes deployment.

## Implementation Anchors (current code, for the implementing engineer)

Read-only audit references; no change is authorized by this section.

- Playback issuance: `functions/src/index.ts` — `generateBunnySignedUrl`
  (4272), secrets binding (4273–4274), resource lookup (4308–4320),
  lecture existence check (4396), per-lecture deny (4393 → 1243–1251),
  playback template + directory token (4649–4698).
- Single-library assumptions to make configurable:
  `SECRET_BUNNY_TOKEN_KEY` (24), `hashVideoDirectoryToken` (1527),
  `buildBunnyFileUrl` (1559–1580), `bunnyStreamApiConfig` (1599–1603),
  `fetchBunnyVideoMeta` Stream API URL (1630), `resolveVideoDisplayMedia`
  (1695–1734), `getLectureResources` secrets (4945) and serialization
  (4988–5002).
- Client contract: `lib/features/video_streaming/data/services/video_source_resolver.dart`
  (payload 296–330), `lib/features/video_streaming/domain/entities/playback_entities.dart`
  (VideoResource 240, `fromCallablePayload` 325).
- Dashboard writes: `dashboard/lib/features/students/presentation/providers/subject_details_provider.dart`
  (812–816, 895, 1086–1089), `dashboard/lib/features/students/presentation/widgets/add_lecture_resources.dart`
  (277–336), `dashboard/lib/features/home/presentation/widgets/quick_upload_modal.dart`
  (424–440).

## Consequences and Risks

- Playback becomes dependent on per-library correctness of stored data; an
  incorrect `bunny_library_id` must fail closed, not fall back silently.
- Each library carries its own token key and pull-zone request filters
  (hotlink/Referer); adding a library requires validating those filters for
  the app's playback headers.
- Secret count grows with the number of libraries; secret rotation becomes a
  per-library operation.
- Backward compatibility depends on the default-library fallback staying in
  place until every resource is backfilled and verified.

## Open Items (blocking implementation, tracked separately)

- **WITHDRAWN by Amendment 2 (§5):** the requirement to configure library `775315`.
  `775315` remains deferred and inactive under N10; no `BUNNY_775315_*` secret may be
  created and it must not appear in `BUNNY_ACTIVE_LIBRARY_IDS`. Re-activation requires a
  new, separate owner decision.
- Confirm the library mapping for every existing video resource (not only the
  three inspected published lectures). Tracked as D-09.
- Documentation naming conflict remains unmodified by this ADR:
  `docs/notion/06_FIREBASE_ARCHITECTURE .md` (§6.4) and
  `docs/notion/11_Assets.md` still name `generateSignedVideoUrl`; the
  implemented and deployed callable is `generateBunnySignedUrl`.

## Change Log

- 1.0 (2026-11-12): Initial approved decision — multi-library Bunny Stream
  architecture, nullable `bunny_library_id`, server-side trusted resolution,
  Dashboard library selection, backward-compatible migration, explicit
  out-of-scope items and implementation gate. No code, data, configuration,
  or existing document changed.
- 1.1 (2026-11-17): Amended by `21_ADR_010_Amendment_2.md`. Option C recorded as the
  target architecture; N1–N12 incorporated as normative decisions; the `775315`
  configuration Open Item withdrawn in favour of the N10 deferral.
