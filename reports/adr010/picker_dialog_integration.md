# ADR-010 — Picker State Integration (Mission 3, Workstream A)

Status: **DONE (nonvisual)**. No pixel, layout, colour, spacing, typography or
interaction was added; the existing dialogs keep their exact appearance.

## 1. What was wired

| Flow | File | Change |
|---|---|---|
| Add resource (subject details) | `dashboard/lib/features/students/presentation/widgets/add_lecture_resources.dart` → `_videoDialog` | Builds `BunnyLibrarySelection` from the form (new vs existing), applies `withVideoId(...)`, resolves the write value through `selectLibrary(defaultBunnyLibraryId)` for new videos, and stages `libraryReviewRequired` |
| Edit resource (subject details) | same `_videoDialog` with `existing` | Loads `forExisting(videoId, storedLibraryId)`; keeps the stored association; flags review when the Video ID changed; **legacy rows stay legacy** |
| Add resource (lecture form) | `dashboard/lib/features/students/presentation/widgets/add_lecture_overlay.dart` → `_handleAddResource` | New video association resolved through `BunnyLibrarySelection.forNewVideo(...).selectLibrary(default)` |
| Edit resource (lecture form) | same file → `_handleEditExistingResource` | Remembers the previous Video ID, applies `withVideoId(new)` and stores `libraryIdForWrite` + `libraryReviewRequired` |
| Quick Upload | `dashboard/lib/features/home/presentation/widgets/quick_upload_modal.dart` | Writes through `bunnyLibraryIdForCreate(...)` fed by `BunnyLibrarySelection.forNewVideo(...)`, so the default rule has one source of truth |
| Staging | `StagedResource` / `_StagedResource` / `_ExistingResourceEntry` | Carry `bunnyLibraryId` (already) plus the nonvisual `libraryReviewRequired` / `libraryId` echo |
| Persistence | `subject_details_provider.dart` | Unchanged from Mission 1/2: create writes the resolved association, update keeps it when null |

## 2. Behaviour guarantees

| Requirement | Behaviour | Proof |
|---|---|---|
| New video resolves a valid association | `736742` staged explicitly | widget test "new video stages the default library" |
| Existing video loads its stored association | stored id echoed | widget test "existing video keeps its stored association" |
| Legacy video preserved | `null` staged, no invented id | widget test "legacy video stays legacy" |
| Unrelated edit preserves association | `null` on update = keep stored | `bunny_library_persistence_test.dart` |
| Changed Video ID requires revalidation | `libraryReviewRequired == true`, library unchanged (never guessed) | widget test "changing the Video ID flags review…" |
| Invalid selection never persisted | state model never returns an invalid id; dialog refuses invalid Video ID | widget test "invalid Video ID never stages a resource" + selection tests |
| Quick Upload preserves the association | create path writes the resolved default | persistence + quick-upload suites |
| PDF / external link unaffected | `bunnyLibraryId == null` | widget test + persistence tests |

## 3. Tests added

`dashboard/test/bunny_library_dialog_test.dart` — 6 widget tests driving the real
`showResourceDialog` (new video, existing, legacy, changed Video ID, invalid Video ID,
external link). Uses `Key('resourceDialogSave')`; no production widget was altered.

## 4. What is still blocked (Figma)

The picker itself. Exact missing specification, so the field can be dropped in later:

1. Placement of the library field inside the existing Video dialog (below Video ID?)
   and whether it is a dropdown, segmented control or read-only chip.
2. Label copy and helper text, plus the legacy/default display ("Legacy (default)").
3. Disabled/not-yet-selectable presentation for `775315`.
4. Review state presentation after a Video ID change (inline warning vs save block).
5. Loading/error presentation for the server validation callable.
6. Responsive sizing/dimensions, colours, typography and icon per the design system.

Wiring point is isolated: pass the chosen id into
`BunnyLibrarySelection.selectLibrary(...)`; everything downstream (staging,
persistence, review flag) already works.
