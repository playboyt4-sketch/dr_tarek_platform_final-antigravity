# ADR-010 — Workstream F: Database & Migration Design

Date: 2026-11-12
Mode: DESIGN ONLY — no migration executed, no Firestore write.

## 1. Field definition

```text
lecture_resources.bunny_library_id : string | null
  - New, nullable, additive.
  - Value = Bunny Stream library id ("775315", "736742").
  - null / absent = legacy resource (default-library fallback during migration only).
  - Never client-authoritative: the backend re-reads the stored value.
```

- **Not defined anywhere today.** No schema document, code path, index, or production document contains
  `bunny_library_id` (grep across `lib/`, `dashboard/`, `functions/`, `docs/`).
- `resource_url` is untouched (external links + legacy document fallback).

## 2. Indexes

- No new index is required for the field itself.
- Queries stay by `lecture_id`, `is_visible`, `orderBy(display_order)` — unchanged.
- If a future admin screen filters by library, Firestore's automatic single-field index covers equality;
  no composite index needed unless combined with another equality + orderBy.

## 3. `first_video` denormalization

- `lectures.first_video` is written by the Dashboard (`subject_details_provider` → `firstVideoFields`).
- Adding the library there is **optional**. Decision: keep `first_video` unchanged in phase 1; the fast
  lane only needs `resourceId`/`bunnyVideoId` to start playback, and the server resolves the library from
  the resource document.
- If it is later extended, it must be additive (`bunny_library_id` alongside `bunny_video_id`) and the
  Dart `FirstVideoRef` parser must tolerate its absence.

## 4. Serializer / consumer tolerance

| Consumer | Tolerates missing field? | Evidence |
|---|---|---|
| `getLectureResources` (`index.ts:4988–5002`) | Yes (additive key) | `getString()` returns null |
| `VideoResource.fromCallablePayload` (325–345) | Yes (nullable) | existing pattern |
| `AdminLectureResource` | Yes if added nullable | nullable fields already used |
| Dashboard edit form | Yes | shows empty selection |
| Firestore Security Rules | Yes — no field allow-list | `firestore.rules:294–301`: the `lecture_resources` block gates on `isApprovedContent` / `hasSubjectAccess` / `isLectureDenied` for reads and `canManageContent()` for writes; no `request.resource.data` field validation exists, so an additive nullable field needs **no rules change** |

## 5. Migration plan (dry-run first)

**Inputs:** verified mapping from `bunny_resource_inventory.csv`.

**Scope:** only resources with `confidence = VERIFIED` and a non-empty `bunny_video_id` (6 rows today).
Rows with empty Video ID are skipped (nothing to map).

**Rules**
1. Never change document IDs, `lecture_id`, `subject_id`, `bunny_video_id`, ordering, visibility,
   `is_deleted`, or publication state. Only `bunny_library_id` is written.
2. Only verified mappings are written. Unverified → left null and reported.
3. Optimistic concurrency: each write uses a Firestore precondition on `update_time` captured during the
   dry-run read; if the document changed, skip and report instead of overwriting.
4. Idempotent: re-running writes the same value; already-correct rows are skipped.
5. Audit: one `admin_audit_log` row per changed document (action `lecture_resource_library_backfill`,
   actor `system_migration`), matching existing audit conventions.

**Steps**
1. Dry-run script (read-only) → emits planned changes + counts + conflicts.
2. Backup: export `lecture_resources` (and any touched `lectures`) to a timestamped JSON outside the repo.
3. Apply in small batches (≤50 writes) with the precondition and per-row result logging.
4. Verify: re-run the inventory probes; expect 6/6 verified rows with `bunny_library_id` set.
5. Rollback: restore `bunny_library_id` to `null` for the exact document list recorded in the backup
   manifest (field-level rollback; no document recreation).

## 6. Rules / permissions

- Dashboard writes require the existing content-authoring permissions (`ADMIN_CONTENT` / Doctor). No new
  permission is introduced by ADR-010.
- Students never write `lecture_resources`; read path stays through `getLectureResources`.
- Library registry read for staff should be a staff-only callable or a `system_settings` doc readable by
  staff only — never containing secrets.

## 7. Out of scope

- Cleaning up the 7 empty-Video-ID rows.
- Fixing archived/deleted lecture authorization.
- Re-uploading or moving any video.
