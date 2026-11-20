# ADR-010 — Workstream E: Dashboard & Flutter Change Map

Date: 2026-11-12
Mode: DESIGN ONLY — no UI, code, or design file changed.

## 1. Dashboard — resource authoring flow

### Add Lecture → Add Video

- `dashboard/lib/features/students/presentation/widgets/add_lecture_resources.dart`
  - `_videoDialog` **277–336**: fields are Video Name, **"Video ID (Bunny Video ID only)"** (`bunnyId`
    controller at 282–283), Display Order. Validation at 314–330 rejects empty and non-GUID input.
  - Returns `StagedResource(bunnyVideoId: ...)` — no library field exists.

### Edit Lecture → resources

- `dashboard/lib/features/students/presentation/providers/subject_details_provider.dart`
  - `getLectureForEdit` **~885–900**: reads `bunny_video_id` (895) into `LectureEditResource`.
  - create path **812–816**: batch writes `'bunny_video_id': resource.bunnyVideoId`.
  - update path **1078–1092**: `updateFields['bunny_video_id']` only when non-null (1086–1089).
  - delete path: soft delete only (`is_deleted`) — unchanged by ADR-010.

### Quick Upload

- `dashboard/lib/features/home/presentation/widgets/quick_upload_modal.dart`
  - validation **45–47** (GUID), resource write **424–440** (`'bunny_video_id': bunnyVideoId`).
  - duplicate logic: the same write exists in `publishQuickLecture` (~340–470).

### Content-authoring (Flutter admin path)

- `dashboard/lib/features/content_authoring/domain/entities/admin_content_entities.dart:145–155`
  (`bunnyVideoId`, with the comment "NEVER a raw URL").
- `dashboard/lib/features/content_authoring/data/datasources/admin_content_remote_data_source_impl.dart`
  ~583 (read) / ~732 (write `resource_url` for external links only).

### Smallest consistent change

1. Add `bunnyLibraryId` (nullable) to the three dashboard models: `StagedResource`,
   `NewLectureResource`/`UpdatedLectureResource`, `LectureEditResource`.
2. Add a **library selector** next to the Video ID field in `_videoDialog` and in Quick Upload:
   options come from the configured library registry exposed to staff (a read-only
   `system_settings/bunny_libraries` document or a staff-only callable), never from secrets.
3. Default selection: the default library for new resources; the stored value for existing resources;
   "legacy/default" when null.
4. Persist `'bunny_library_id'` in the same three write paths (create / update / quick upload) and read it
   in `getLectureForEdit`.
5. No change to `resource_url`, display order, visibility, or `first_video` computation (unless the
   denormalized pointer is extended — see migration design).

**Figma status: BLOCKED (design pending).** No library-selector component or spec exists in the codebase,
and no approved Figma spec for this control has been identified. Per ADR-010 and the task rules, the
selector's visual implementation must wait for the Platform Owner to confirm whether an existing Figma
design covers it or a new one is required. The data-model + write-path changes above are independent of
the visual design and can proceed.

## 2. Flutter (student app)

### Model

- `lib/features/video_streaming/domain/entities/playback_entities.dart:240`
  `VideoResource` — add `final String? bunnyLibraryId;` and parse it in `fromCallablePayload` (325–345).
  Missing key must remain valid (null) for older deployments.

### Request path

- `lib/features/video_streaming/data/services/video_source_resolver.dart:296–330`
  payload `{videoId, quality, subjectId, lectureId, deviceId}`.
  Optional: forward `libraryId` as a hint (server validates it). **Not required** — the server resolves
  from the resource record, so the contract can stay unchanged.

### Player / caching / renewal

- `video_playback_controller.dart`: `_loadEngine` 650–860 (engine at 762–772), source cache
  `_prefetchedSources` 190/664–668/906–935, invalidation 1170/1249/1282/1525, prefetch 909–940.
- Renewal is server-driven (`expiresAt`, 300 s) — no client change needed.
- `lib/core/constants/bunny_playback_headers.dart:13` sends a fixed `Referer`. Verified compatible with
  both Pull Zones, so no change is required for library `775315`.

### Verdict on the contract

**The existing playback contract can remain unchanged.** Flutter needs only the optional additive
`bunnyLibraryId` field for display/diagnostics; authorization and signing stay server-side.

## 3. Files that must change (client side)

| File | Change | Risk |
|---|---|---|
| `dashboard/.../widgets/add_lecture_resources.dart` | selector + model field | medium (UI) |
| `dashboard/.../home/.../quick_upload_modal.dart` | selector + write field | medium |
| `dashboard/.../providers/subject_details_provider.dart` | read/write `bunny_library_id` | medium |
| `dashboard/.../content_authoring/domain/entities/admin_content_entities.dart` | model field | low |
| `dashboard/.../content_authoring/data/datasources/admin_content_remote_data_source_impl.dart` | map field | low |
| `lib/features/video_streaming/domain/entities/playback_entities.dart` | optional field | low |
| `lib/features/video_streaming/data/services/video_source_resolver.dart` | optional forward | low |

No new screens, no redesign, no visual specification invented.
