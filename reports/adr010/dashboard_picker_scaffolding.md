# ADR-010 — Dashboard Picker Scaffolding (Mission 2, Workstream C)

Files: `dashboard/lib/features/students/domain/bunny_library_catalog.dart` (new),
`dashboard/test/bunny_library_selection_test.dart` (20 tests).
Existing data layer: `bunny_library_association.dart`, `subject_details_provider.dart`,
`add_lecture_resources.dart`, `add_lecture_overlay.dart`, `quick_upload_modal.dart`.

**No UI was added or changed.** No layout, spacing, colour, typography, icon or
interaction was invented; the selector remains BLOCKED on an approved Figma spec.

## 1. Catalog model (non-secret)

`BunnyLibraryOption {id, displayName, isAvailable, isSelectable}` —
`toJson()` exposes exactly those four fields. No API key, token key, template, pull
zone, secret-manager reference or signing material can be represented by this type.

`defaultBunnyLibraryCatalog`:

| id | display name | available | selectable |
|---|---|---|---|
| `736742` | Default library | yes | yes |
| `775315` | Legacy platform library | yes | **no** (not activated, no approved design) |

Why a static catalog: no approved Firestore configuration source exists for
client-visible library metadata, and inventing a collection/field would conflict with
the approved database documentation. The catalog is therefore local, read-only data
that the future picker can render; wiring it to Firestore later is additive.

## 2. Selection state

`BunnyLibrarySelection` separates three concerns the picker needs:

- `videoId` — the Bunny Video ID currently in the form.
- `storedLibraryId` — what the document holds (null = legacy row).
- `selectedLibraryId` — the choice made in this session (null = none).

Operations:

| Operation | Behaviour |
|---|---|
| `forNewVideo({videoId})` | no stored value, no choice; write defaults to the default library via the existing provider helper |
| `forExisting({videoId, storedLibraryId})` | echoes the stored value; legacy rows stay legacy |
| `selectLibrary(id, {catalog})` | validates (unknown / unavailable / not-yet-selectable) and records the error |
| `withVideoId(next)` | flags `requiresReview` when the Video ID changes while an association exists |
| `resetSelection()` | returns to "use stored/default" |
| `toResourceFields()` | `{bunny_video_id, bunny_library_id}` raw values only |

Safety property: `libraryIdForWrite` returns the selection **only when valid**;
otherwise it falls back to the stored value (null for new/legacy rows). A rejected
choice therefore cannot reach Firestore even if a caller ignores `validationError`.

## 3. Video-ID-change protection

A Video ID belongs to exactly one library, so changing it may invalidate the stored
association. Without the picker (no server metadata call allowed from the client) the
new library cannot be resolved, so the state becomes explicitly `requiresReview`
instead of silently keeping an unrelated library. An explicit `selectLibrary(...)`
clears the flag.

Enforcement today: the flag is advisory for the future UI; the data layer still
preserves the stored association (never guesses). Once the picker exists, Save must
require `requiresReview == false`. If stronger enforcement is wanted before then, a
server-side metadata check on write is the correct place (out of this mission's scope).

## 4. Integration points for the Figma selector

| Flow | File | Hook |
|---|---|---|
| Add resource (lecture form) | `add_lecture_overlay.dart` → `_openResourceDialog` (`type == 'Video'`) | give `_AddVideoDialog` a `BunnyLibrarySelection` and pass the chosen id into `_StagedResource.libraryId` |
| Edit resource (lecture form) | `add_lecture_overlay.dart` → `_handleEditExistingResource` | initialise from `current.libraryId`, show `requiresReview`, write back on save |
| Add/Edit (subject details dialog) | `add_lecture_resources.dart` → `_videoDialog` | replace the implicit `bunnyLibraryIdForCreate(...)` with the picker's value |
| Quick upload | `quick_upload_modal.dart` | default association already written; add the selector when the design includes it |
| Staging → persistence | `subject_details_provider.dart` (`createLectureFull`, `updateLectureFull`) | already writes/keeps `bunny_library_id`; no change needed for the picker |

## 5. Tests (20, all passing)

Catalog availability/selectability, no-secret JSON key set, unknown/blank lookup,
validation of null/valid/not-selectable/unknown/unavailable, new-video state, legacy
state, stored echo, valid choice, invalid choice (error retained, not written), edit
preservation (null/ reset), Video-ID change review flag, same-id no flag, explicit
choice clearing the flag, quick-upload defaulting, malformed normalization.

## 6. Blocked

`BLOCKED — Figma`: the visual selector, its placement, states and any copy remain
undefined. The scaffolding is ready for a drop-in field without further model work.
