# Security Audit Snapshot

## Current state
- `firestore.rules` is the Firebase starter rule: `allow read, write: if request.time < timestamp.date(2026, 9, 9);` under a recursive wildcard.
- `storage.rules` does not exist.
- `firebase.json` configures Firestore rules/indexes, Functions, and Firestore/Auth/Functions emulators, but no Storage rules entry.

## Approved database facts from `docs/notion/05_DATABASE.md`
- Roles: `new_student`, `student`, `admin`, `teacher` (single platform owner teacher in v1).
- Student types: `public_student`, `center_student`.
- User fields include `full_name`, `display_handle`, `profile_photo`, `phone_number`, `role`, `student_type`, `grade`, `approval_status`, `account_status`, `current_device_id`, and sensitive `password_hash`.
- Common audit fields: `id`, `created_at`, `updated_at`, `created_by`, `updated_by`, `is_deleted`, `deleted_at`, `deleted_by`.
- Students must not see academic scheduling metadata such as `subjects.current_term` or `system_settings.current_term`.
- Important collections documented include users, devices, subjects, subject_sections, lectures, lecture_resources, learning_progress, lecture_progress, subject_progress_summary, timeline_quizzes, and membership/subscription collections later in the document.
- Sensitive user fields and role/status transitions must be changed through Cloud Functions/Admin SDK rather than direct client writes.

## User-mandated implementation constraints
- Implement and locally test Firestore and Storage rules before feature work.
- Do not deploy Firebase.
- Add real rules tests and execute them using Firebase emulator / rules unit testing.
- Audit existing `lib/features/*` before creating duplicated domain/data code.
- Continue features in documented order, use centralized design tokens, use Arabic visible text, and report every incomplete or blocked part honestly.
