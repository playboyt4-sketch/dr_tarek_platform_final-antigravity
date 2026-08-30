
## Academic Term Lifecycle � ADR-003

The platform uses four fixed academic periods: Term 1, Term 2, Summer Course, and Exceptional Period. Each period has start/end dates and is manually ended by Teacher (Platform Owner). Membership access follows the active academic period. See 16_ADR_003_Academic_Term_Lifecycle.md.

---

## 11. Public Free — Per-Lecture Access Control
- Public Free students have no whole-subject access — only individual
  lectures explicitly marked available to them.
- Each lecture in the admin panel has:
  - A toggle switch "إتاحة للفري العام" (green = available / gray = not available).
  - A numeric field next to it: minutes allowed for THIS specific lecture 
    for Public Free students (independent per lecture).
- Playback stops automatically when the allowed minute count is reached, 
  showing an upgrade prompt.

## 12. Center Free — Rolling 24-Hour Single-Video Limit
- Center Free students have full access to all subjects of their current 
  grade + any prior-grade subjects manually granted (see Section 13).
- Limit: only ONE video may be started per rolling 24-hour window.
  - The window starts the moment a video is first opened.
  - Within that window, the student may resume/replay THAT SAME video 
    without restriction.
  - Attempting to start a DIFFERENT video before the window expires is 
    blocked entirely, showing "Upgrade to Pro".
  - The window resets from the timestamp of whichever video was most 
    recently opened (a rolling window, not a fixed daily reset).

## 13. Grade-Based Prior-Term Access (Center Student Only)
- When accepting a Center Student, the Admin/Teacher sets their current grade.
- A student in grade N may be granted access to subjects from any grade 
  1 to N-1 (for students repeating failed subjects).
- Grade 1 students have no prior grades — no such grant is possible.
- Granting happens at two points only:
  a. During registration review (initial approval).
  b. Later, from the student's profile screen, at any time.
- This is entirely separate from `users.grade` itself — prior-grade subject 
  access is managed via `subject_access_assignments` (already in the schema), 
  NOT by changing the student's own grade field.

## 14. Center Pro vs Center Max — Device Limit Only
- The only difference between the two plans is allowed device count:
  - Center Pro: exactly 1 device.
  - Center Max: more than 1, count set manually per-student from the dashboard.
- Each subscription (Pro or Max) covers exactly one subject (already 
  established in FINAL_DECISIONS Section 5 — unchanged, restated for clarity).

## 15. Dual Storage Provider Support (Bunny + Firebase) — Per-Resource
- The platform supports BOTH Bunny Storage and Firebase Storage 
  simultaneously for PDFs/attachments/thumbnails — NOT a single global 
  choice, and NOT a per-upload manual pick by default either. Every stored 
  resource carries its own `storage_provider` value ("bunny" | "firebase") 
  recorded at upload time.
- The admin upload screen lets the Admin/Teacher choose the provider at 
  upload time per file (a simple selector next to each upload action), 
  defaulting to whichever provider the Teacher configures as the platform 
  default (a `system_settings.default_storage_provider` value, editable 
  from the dashboard).
- The student-facing resource-delivery logic (signed URL generation) reads 
  `storage_provider` from the resource document and dispatches to the 
  correct backend automatically — Bunny path uses the Bunny signed-URL flow, 
  Firebase path uses Firebase Storage's own access-controlled download flow. 
  Neither the student nor the playback UI needs to know or care which 
  provider served a given file.
- Video files remain Bunny-only (per FINAL_DECISIONS Section 4 — unchanged); 
  this dual-provider flexibility applies to PDFs/attachments/thumbnails only.

