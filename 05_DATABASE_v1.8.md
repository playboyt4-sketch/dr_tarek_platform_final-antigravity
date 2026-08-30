# 05 Database

## Dr. Tarek Platform

Version: 1.9
Status: Proposed — Pending Teacher Database Change Approval

## Version History

- **1.9** (2026-08-25, proposed): Ratified addendum FINAL_DECISIONS §11–15.
  Added `lectures.public_free_enabled` + `lectures.public_free_preview_minutes`
  (§11 per-lecture Public Free access control). Added
  `lecture_resources.storage_provider` ("bunny" | "firebase") for
  pdf/attachment resources and `lecture_resources.thumbnail_storage_provider`
  for uploaded thumbnails (§15 dual storage providers; video stays implicitly
  Bunny with no provider field). Added
  `system_settings.default_storage_provider` (§15/E, default "firebase").
  Documented image attachment types (jpg/jpeg/png) as an approved attachment
  option separate from thumbnails, the section-deletion block when active
  lectures exist, and the scheduled auto-publish behavior on `lectures.status`.
- **1.8** (2026-08-15, proposed): Feature 14 Membership + Independent Subject Access + updated approval/access rules. Version 1.7 remains preserved as the approved baseline.
- **1.7** (2026-08-10): Formally added `devices.fcm_token` to the `devices` collection schema to support the approved Firebase Cloud Messaging token-storage decision.
- **1.6** (2026-08-04): Added `grade` field to `users` (Section on `users` collection) to support the approved Figma registration flow — student self-selects their Grade (الفرقة) at signup. This is a new, distinct field from `subjects.current_term` / `system_settings.current_term` ("Academic Year/Term"), which remains admin-only scheduling metadata and is unaffected by this change (Section 10 and 23 rules on hiding Academic Year/Term from students still apply). Added corresponding per-grade color tokens reference to 11 Assets.
- **1.5** and earlier: see prior revisions.

---

# 1. Database Overview

**Database Engine**

- Cloud Firestore

**Authentication**

- Firebase Authentication

**Storage**

- Firebase Storage

**Notification**

- Firebase Cloud Messaging

---

# 2. Database Principles

- UUID Primary Keys
- Soft Delete
- Audit Fields
- Repository Pattern Only
- No Direct UI Access
- Strong Relationships by IDs
- Mobile First Queries
- Scalable Collections
- Feature Flag Ready
- Analytics Ready
- No Hardcoded Business Rules
- All Permissions Data-Driven
- Offline-Sync Ready

---

# 3. Naming Convention

## Collections

```
snake_case
```

Example

```
users
subjects
timeline_quizzes
payment_logs
```

## Fields

```
snake_case
```

Example

```
created_at
subject_id
video_url
plan_id
```

## Boolean

```
is_
has_
can_
```

Example

```
is_active
is_visible
has_access
can_download
```

## Timestamp

```
*_at
```

Example

```
created_at
updated_at
published_at
expires_at
```

---

# 4. Common Fields

Every document uses the following common identity and audit convention. `id` means the Firestore Document ID. It does not require every collection to duplicate that identity as a stored `id` field. A collection may use a deterministic Firestore Document ID when the approved schema specifies one.

| Identity / Field | Type | Meaning |
| --- | --- | --- |
| id | Firestore Document ID | Document identity; not necessarily a duplicated stored field |
| created_at | Timestamp |
| updated_at | Timestamp |
| created_by | String |
| updated_by | String |
| is_deleted | Boolean |
| deleted_at | Timestamp |
| deleted_by | String |

---

# 5. User Roles

```
new_student
student
admin
teacher
```

Note: Per ADR-001, the role is `teacher` (display name: "Teacher (Platform Owner)"), matching Project Vision and PRD. The platform currently serves a single Teacher (per Project Vision, Multi-Teacher Support and Multi-Tenant Architecture are explicitly out of scope for Version 1). See Master Architecture Section 6.1 for the full Display Name / Enum Value mapping.

---

# 6. Student Types

Introduced to support both marketing/trial audiences and officially enrolled students, per the Features document.

```
public_student
center_student
```

| Type | Description | Available Plans |
| --- | --- | --- |
| public_student | Acquisition / marketing audience | public_free |
| center_student | Officially enrolled student | center_free, center_pro, center_max |

- Stored on `users.student_type`.
- Determines which `plans` are selectable for that user.
- Teacher or an explicitly delegated Admin may request conversion between types. Before changing `users.student_type`, all active, non-deleted subject subscriptions must be checked against the target Student Type.
- If any subscription plan is incompatible with the target Student Type, conversion stops and returns a conflict; no subscription deletion, downgrade, automatic conversion, replacement, or Student Type change is allowed.
- If no incompatible subscription exists, conversion preserves all learning data (progress, notes, exam attempts, quizzes, analytics, and history), and the action is audited and recorded as an Analytics Event.
- Every conversion is logged as an Analytics Event.

---

# 7. User Flow

```
Register
   ↓
New Student
   ↓
Manual Approval
   ↓
Student (student_type assigned: public or center)
   ↓
Default Free Plan available implicitly
   ↓
Subject Subscription (explicit, created on first subject access or upgrade)
   ↓
Platform Access
```

**Business Rule — Conditional Free Plan Activation:**
Approval does not require an explicit subscription record for every subject in advance. When a student opens a subject for the first time, the backend may create the Free Plan matching the student's `student_type` (`public_free` or `center_free`) only after a non-deleted `subject_access_assignments/{student_id}_{subject_id}` document with `enabled = true` has been confirmed. If the assignment is missing or disabled, access is denied and no Subscription is created. The existing one-active-subscription-per-subject rule remains intact.

---

# 8. Educational Structure

```
Subject
   ↓
Section (system-defined or custom, admin-configurable)
   ↓
Lecture
   ↓
Resources
   ↓
Timeline Quiz
```

---

# 9. Subject Sections

Sections are **not** a fixed enum. Admin/Teacher can enable, disable, reorder, add, or remove sections per subject without an application update.

### System Sections (seeded by default, optional per subject)

```
Explanation
Revision
Final Review
```

### Custom Sections (unlimited, admin-defined)

Examples:

```
Online Sessions
Important Announcements
Special Videos
Exam Instructions
Bonus Lectures
```

Custom sections behave identically to system sections — same content model, same visibility rules, same membership gating.

Deletion rule (NEW in v1.9, ratified Open-Question answer): deleting a section is BLOCKED while the section contains any non-archived lecture (`is_deleted == false`) — no orphaning allowed. The repository returns a specific catchable Failure and the admin UI shows: «لا يمكن حذف القسم لوجود محاضرات نشطة بداخله. يرجى أرشفة المحاضرات أولاً.» Archive or move the lectures first, then delete.

Visibility rule: if a subject has no Revision content configured, the Revision section is hidden entirely (not shown empty) — same for any section with zero published content, unless the Admin explicitly publishes an empty-state section.

---

# 10. Student Experience

Student never sees

- Academic Year (subject-scheduling metadata, `subjects.current_term` / `system_settings.current_term`)
- Semester
- Current Term

**Note:** This is unrelated to `users.grade` (الفرقة), which the student *does* set themselves at registration (see `users` collection). "Academic Year" here refers only to a subject's administrative scheduling metadata, not the student's own grade/year level.

Student only sees

```
My Subjects
   ↓
Subject
   ↓
[Configured Sections — system or custom]
```

---

# 11. Resume Learning (New in v1.1)

The platform tracks the student's last position at three levels, per the Features document (Subject Navigation).

## 11.1 `learning_progress`

One document per (student, subject). Tracks the top two resume levels.

| Field | Type |
| --- | --- |
| student_id | String |
| subject_id | String |
| last_section_id | String |
| last_lecture_id | String |

## 11.2 `lecture_progress`

One document per (student, lecture). Tracks the lecture-level resume point and completion state.

| Field | Type |
| --- | --- |
| student_id | String |
| lecture_id | String |
| video_position_seconds | Number |
| pdf_last_page | Number |
| is_completed | Boolean |
| completed_at | Timestamp |

## 11.3 `subject_progress_summary`

Cached, precomputed completion percentage per (student, subject) — avoids recalculating on every dashboard load.

| Field | Type |
| --- | --- |
| student_id | String |
| subject_id | String |
| total_lectures | Number |
| completed_lectures | Number |
| completion_percentage | Number |
| last_recalculated_at | Timestamp |

Recalculated whenever `lecture_progress.is_completed` changes, via Repository-layer logic (not client-side).

---

# 12. Membership

Subscription belongs to the Subject, and is scoped by Student Type.

```
Subject
   ↓
public_free  (Public Student)
   ↓
center_free / center_pro / center_max  (Center Student)
```

## Supported Membership Operations

- Upgrade
- Downgrade
- Renewal
- Freeze
- Resume
- Public → Center conversion (and reverse)

No student data is lost during any of the above operations.

---

# 13. Trial

Supports

- Enable / Disable
- Trial Days
- Subject
- Plan
- Auto Expire
- Visibility

---

# 14. Device Policy

- Device Limit Is Plan-Based (default 1 device; 2+ for Center Max — see `plan_features`)
- Device Binding Enabled
- Device Replacement Requires Admin Approval

---

# 15. Analytics Policy

Every user action generates an Analytics Event. This includes membership operations (upgrade, downgrade, freeze, resume, and Student Type conversion) and unauthorized device attempts. Gift Membership is removed from the current business flow and does not generate a current-version Gift event.

---

# 16. Collections

## users

Stores all platform users.

Contains

| Field | Type | Description |
| --- | --- | --- |
| full_name | String | |
| display_handle | String \| null | Optional public-facing handle (e.g. `Dr/tarekelaraby`). Shown in place of `full_name` wherever the UI displays a user publicly, if set. Primarily used for the Teacher's public identity; available to any role. Must be unique when set. |
| profile_photo | String | Storage URL |
| phone_number | String | |
| role | String | `new_student` / `student` / `admin` / `teacher` |
| student_type | String | `public_student` / `center_student` |
| grade | String | Student's self-selected academic grade/year (الفرقة), e.g. `grade_one` / `grade_two` / `grade_three` / `grade_four`. Set once at registration; not editable by the student afterward. Distinct from `subjects.current_term` / `system_settings.current_term` ("Academic Year/Term"), which is unrelated content-scheduling metadata and remains admin-only (Section 10, 23). The set of valid grades is configurable, not hardcoded, per Master Architecture Section 5. |
| approval_status | String | Registration approval workflow status |
| account_status | String | Active / suspended / disabled |
| current_device_id | String | Reference to `devices` |
| password_last_changed_at | Timestamp | |

---

## devices

Stores registered devices.

Contains

| Field | Type | Description |
| --- | --- | --- |
| user_id | String | Reference to the owning `users` document. |
| device_id | String | Stable device identifier used by Device Binding. |
| device_name | String \| null | Human-readable device name when available. |
| platform | String | Device platform / operating system family. |
| os_version | String \| null | Operating-system version when available. |
| app_version | String \| null | Installed application version when available. |
| last_login | Timestamp \| null | Last successful login timestamp for the device. |
| active_device | Boolean | Whether the device is currently authorized/active. |
| fcm_token | String \| null | Current Firebase Cloud Messaging token for this device; updated on token refresh and used for push notification delivery. |

The `fcm_token` field is stored per device, not per user, because one user may have multiple authorized devices under the plan-based Device Binding policy.

---

## subjects

Stores all subjects.

Contains

- Subject Name
- Thumbnail
- Display Order
- Current Term
- Visibility
- Status

---

## subject_sections

Configurable sections inside every subject (system or custom — see Section 9).

Contains

| Field | Type | Description |
| --- | --- | --- |
| subject_id | String | Reference to `subjects` |
| section_key | String \| null | `explanation` / `revision` / `final_review` for system sections; `null` for custom |
| is_system_section | Boolean | Distinguishes system vs custom sections |
| title | String | Display name (editable even for system sections) |
| display_order | Number | Ordering within the subject |
| is_visible | Boolean | Publish/hide toggle |

---

## lectures

Stores all lectures.

Contains

- Section ID
- Title
- Description
- Display Order
- Publish Date
- Status
- Public Free Enabled (NEW in v1.9, boolean, default `false`) — FINAL_DECISIONS §11: when `true`, this individual lecture is available to Public Free students even without a subject subscription (Public Free has NO whole-subject access).
- Public Free Preview Minutes (NEW in v1.9, number | null) — per-lecture playback cap in minutes for Public Free students; independent per lecture. When null, the plan-level `video.preview_duration` default applies; when both are unset, the lecture is listed but playback is capped at zero (upgrade prompt immediately).

Scheduled auto-publish (FINAL_DECISIONS addendum Part D): a scheduled Cloud Function flips `status: 'draft' → 'published'` when `publish_date <= now`. Manual publish remains available at any time regardless of `publish_date`.

---

## lecture_resources

Stores lecture content.

Types

```
Video

PDF

Attachment

External Link
```

Contains

- Lecture ID
- Resource Type
- Resource URL
- Thumbnail
- Duration
- Visibility
- Storage Provider (NEW in v1.9, string `"bunny" | "firebase"`, pdf/attachment only) — FINAL_DECISIONS §15 dual-provider support: recorded at upload time from the admin's per-file selector, defaulting to `system_settings.default_storage_provider`. Student delivery callables read it and dispatch to the correct backend automatically.
- Thumbnail Storage Provider (NEW in v1.9, string `"bunny" | "firebase"`, optional) — provider used for the uploaded thumbnail image bytes of a video resource. Kept separate so pure video resources stay implicitly Bunny with no provider field (§15).

Attachment file types (approved): zip/doc/docx/xls/xlsx/ppt/pptx/txt PLUS image types jpg/jpeg/png as an additional attachment option — distinct from the video thumbnail upload path.

---

## learning_progress

See Section 11.1. Tracks subject-level and section-level resume pointers.

---

## lecture_progress

See Section 11.2. Tracks lecture-level resume position and completion.

---

## subject_progress_summary

See Section 11.3. Cached completion percentage per student per subject.

---

## timeline_quizzes

Stores quizzes linked to lecture progress. Unlock points are configured manually per lecture by Admin/Teacher — they are **not** fixed intervals; duration and count vary per lecture length.

Examples

```
10 Minutes

20 Minutes

30 Minutes

Full Lecture

Cumulative (all prior lectures in the section)
```

Contains

- Lecture ID
- Unlock Time (seconds into the video)
- Quiz Scope (`partial_interval` / `full_lecture` / `cumulative`)
- Quiz ID
- Visibility

---

## question_bank

Reusable questions.

Types

```
MCQ

True / False

Essay
```

Contains

- Question
- Choices
- Correct Answer
- Difficulty
- Explanation
- Status

---

## exams

Stores exams.

Contains

- Subject ID
- Section ID
- Title
- Duration
- Total Marks
- Publish Status

---

## exam_questions

Links Question Bank with Exams.

Contains

- Exam ID
- Question ID
- Order
- Marks

---

## exam_attempts

Stores student attempts.

Contains

- Student ID
- Exam ID
- Start Time
- Submit Time
- Score
- Percentage
- Status

---

## notes

Personal Notes only. Questions to Admin are no longer stored here — see `student_questions` below.

Supports

- Video Timestamp
- PDF Page

Contains

- Student ID
- Lecture ID
- Content
- Timestamp
- PDF Page
- Status

---

## student_questions

Stores questions submitted by students to the Admin.

Contains

- Student ID
- Question
- Lecture ID
- Subject ID
- Status
- Created Date
- Closed Date
- Assigned Admin (if applicable)

---

## student_question_replies

Stores replies to student questions.

Contains

- Question ID
- Sender
- Reply
- Created At

---

## bookmarks

Stores student bookmarks for quick access to saved learning locations (Feature 10 — Bookmarks).

Contains

| Field | Type | Description |
| --- | --- | --- |
| student_id | String | Reference to `users` |
| subject_id | String | Reference to `subjects` |
| lecture_id | String | Reference to `lectures` |
| resource_id | String \| null | Reference to `lecture_resources`; null when the bookmark targets the lecture itself |
| bookmark_type | String | `video_timestamp` / `pdf_page` / `lecture` |
| title | String | Optional student-provided title |
| video_timestamp_seconds | Number \| null | Set when `bookmark_type = video_timestamp` |
| pdf_page | Number \| null | Set when `bookmark_type = pdf_page` |
| created_at | Timestamp | |

---

## notifications

Stores push notifications.

Types

```
Lecture

Payment

Reminder

Chat

Trial

Subscription

System
```

Contains

- User ID
- Type
- Title
- Body
- Read Status
- Sent Time

---

## chat_rooms

Stores conversations.

Contains

- Student ID
- Admin ID
- Status
- Last Message
- Last Activity

---

## chat_messages

Stores conversation messages.

Contains

- Room ID
- Sender ID
- Message Type
- Message
- Attachment
- Read Status
- Sent At

---

## plans

Stores membership plans.

Examples

```
public_free

center_free

center_pro

center_max
```

Contains

| Field | Type | Description |
| --- | --- | --- |
| plan_name | String | Display name |
| plan_key | String | `public_free` / `center_free` / `center_pro` / `center_max` |
| student_type | String | Which student type this plan applies to (`public_student` / `center_student`) — new |
| display_order | Number | Ordering |
| is_active | Boolean | Availability toggle |

---


**Note on max_devices:** The maximum number of devices allowed per student is controlled through `plan_features` (Feature Matrix) rather than a hardcoded field on `plans`. The Cloud Function `onLoginAttempt` reads this value from the active plan's features to enforce device binding limits. Default values: Free/Pro plans = 1 device, Center Max plan = 2+ devices (configurable from Dashboard).

## plan_features

Controls every feature without modifying code (Feature Matrix).

Examples

```
Video Quality

Daily Video Limit

Resume Video

PDF Access

Download PDF

Playback Speed

Timeline Quiz

Notes

Chat

Preview Duration

Revision Section

Final Review Section

Offline Mode

Picture in Picture

Export
Max Devices
```

Contains

- Plan ID
- Feature Key
- Enabled
- Feature Value

---

## subscriptions

Stores student subscriptions.

Contains

| Field | Type | Description |
| --- | --- | --- |
| student_id | String | Reference to `users` |
| subject_id | String | Reference to `subjects` |
| plan_id | String | Reference to `plans` |
| duration_type | String | `weekly` / `monthly` / `semester` / `annual` / `lifetime` |
| start_date | Timestamp | |
| end_date | Timestamp \| null | Null for lifetime plans |
| status | String | `active` / `expired` / `cancelled` / `trial` |
| is_frozen | Boolean | New — freeze support |
| frozen_at | Timestamp \| null | New |
| resumed_at | Timestamp \| null | New |
| is_gifted | Boolean | LEGACY / DEPRECATED; retained for compatibility and not used by the current Membership workflow |
| gifted_by | String \| null | LEGACY / DEPRECATED; retained for compatibility and not used by the current Membership workflow |
| renewal_count | Number | New — tracks how many times renewed |
| previous_plan_id | String \| null | New — set on upgrade/downgrade for history |

Constraint: one active (non-deleted, `status = active`) subscription per (student, subject) pair.

---

## subject_access_assignments

Stores the independent Subject Access decision for one student and one subject. Subject Access is not stored inside `subscriptions`.

Document ID

```text
{student_id}_{subject_id}
```

This deterministic Firestore Document ID is sufficient for `subject_access_assignments`; no duplicated stored `id` field is required unless an existing approved repository/database convention explicitly requires it.

Contains

| Field | Type | Description |
| --- | --- | --- |
| student_id | String | Reference to `users` |
| subject_id | String | Reference to `subjects` |
| enabled | Boolean | Internal Subject Access decision; disabled denies access |
| created_at | Timestamp | Common audit field |
| updated_at | Timestamp | Common audit field |
| created_by | String | Creating actor or server identity |
| updated_by | String | Last updating actor or server identity |
| is_deleted | Boolean | Soft-delete flag |
| deleted_at | Timestamp \| null | Soft-delete timestamp |
| deleted_by | String \| null | Deleting actor |

Constraint: one deterministic, non-deleted assignment per (student, subject) pair. Missing or disabled Subject Access denies access, even if a Subscription, Active Plan, and plan feature would otherwise allow access.

---

## trial_campaigns

Stores trial campaigns.

Contains

- Subject ID
- Plan ID
- Trial Days
- Visible
- Active
- Start Date
- End Date

---

## payment_logs

Stores payment history. Course price is paid externally in Version 1 (per Master Architecture, Section 7); online payment methods are deferred to Version 1.2. This log records externally-collected payments manually, for platform membership tracking only.

Contains

- Student ID
- Subject ID
- Amount
- Payment Date
- Collected By
- Receipt Number
- Notes

---

## analytics_events

Stores every user action.

Examples

```
Login

Logout

Open Subject

Open Lecture

Play Video

Pause Video

Complete Video

Open PDF

Create Note

Send Question

Receive Reply

Start Quiz

Submit Quiz

Upgrade Plan

Downgrade Plan

Freeze Membership

Resume Membership

Convert Student Type

Open Notification

Open Chat

Unauthorized Device Attempt
```

Contains

- User ID
- Event Type
- Reference ID
- Metadata
- Device ID
- Created At

---

## system_settings

Application configuration.

Contains

- Current Term
- Maintenance Mode
- Registration Enabled
- Trial Enabled
- Free Plan Enabled
- Default Plan
- Latest Version
- Minimum Version
- Default Storage Provider (NEW in v1.9, string `"bunny" | "firebase"`, default `"firebase"`) — FINAL_DECISIONS §11–15 addendum / Part E: platform default that pre-selects the provider in the admin upload UI; the Admin/Teacher can still override per file at upload time. Editable only by the Teacher via the audited `setDefaultStorageProvider` callable (Rules keep this collection read/write-denied for clients; writes are callable-only).

---

# 17. Enums

## User Roles

```
new_student
student
admin
teacher
```

## Student Types

```
public_student
center_student
```

## Section Type

```
system   (fixed labels: explanation / revision / final_review)
custom   (admin-defined, free text title)
```

## Resource Types

```
video
pdf
attachment
external_link
```

## Question Types

```
mcq
true_false
essay
```

## Plan Types

```
public_free
center_free
center_pro
center_max
```

## Subscription Status

```
active
expired
cancelled
trial
```

## Quiz Scope

```
partial_interval
full_lecture
cumulative
```

## Notification Types

```
lecture
payment
chat
reminder
trial
subscription
system
```

## Note Types

```
personal
```

## Question Status

```
open
in_review
answered
closed
```

# 18. Relationships

```
users
 ├── devices
 ├── subject_access_assignments
 ├── subscriptions
 ├── notes
 ├── student_questions
 ├── bookmarks
 ├── exam_attempts
 ├── notifications
 ├── payment_logs
 ├── analytics_events
 ├── learning_progress
 ├── lecture_progress
 ├── subject_progress_summary
 └── chat_rooms

subjects
 ├── subject_sections
 ├── subject_access_assignments
 ├── subscriptions
 ├── learning_progress
 ├── subject_progress_summary
 ├── student_questions
 └── bookmarks

subject_sections
 └── lectures

lectures
 ├── lecture_resources
 ├── timeline_quizzes
 ├── lecture_progress
 ├── notes
 ├── student_questions
 └── bookmarks

question_bank
 └── exam_questions

exams
 ├── exam_questions
 └── exam_attempts

student_questions
 └── student_question_replies

plans
 ├── plan_features
 ├── subscriptions
 └── trial_campaigns

chat_rooms
 └── chat_messages
```

---

# 19. Database Constraints

- UUID is required for every document.
- Every collection uses Soft Delete.
- Every document contains Audit Fields.
- `users.display_handle`, when set, must be unique across all users.
- Device limit per student is plan-based (default 1 device; 2+ for Center Max, per `plan_features`).
- One active subscription per subject.
- Subject Access is an independent gate and is evaluated before Subscription, Active Plan, and `plan_features`.
- Missing or disabled Subject Access denies access and prevents first-open Free Plan activation.
- New students do not receive default-all-subjects access; initial assignments come from the approved application review toggles.
- Subject Access mutations require Teacher authority or explicitly delegated Admin permission, and every mutation is server-authorized and audited.
- A subject's sections are fully configurable (system or custom) — not a fixed closed list.
- Lecture belongs to one section.
- Resource belongs to one lecture.
- Timeline Quiz belongs to one lecture; unlock points are set manually per lecture, not fixed globally.
- Exam uses Question Bank only.
- Student cannot access unpublished content.
- Membership controls all premium features via Feature Matrix (`plan_features`) — no hardcoded permissions.
- A plan is only selectable by users whose `student_type` matches the plan's `student_type`.
- Converting a student's type preserves all learning data; only plan eligibility changes.
- Students never see Academic Year or Term.
- All permissions are validated by Firestore Security Rules.
- Every user action, including membership operations, creates an Analytics Event.
- `subject_progress_summary` is a cache — always derived from `lecture_progress`, never the source of truth.
- `notes` stores personal notes only; questions to Admin are stored exclusively in `student_questions`.
- A bookmark never overrides Resume Learning (`learning_progress` / `lecture_progress`) — bookmarks are manual reference points only.

**Offline Learning Rules**

- Offline resources remain encrypted.
- Offline resources are available only inside the application.
- Progress continues while offline.
- Resume position is stored locally.
- Local progress synchronizes automatically after connectivity is restored.
- Membership validation is enforced after synchronization.
- Offline files become inaccessible if membership is revoked.

---

# 20. Composite Indexes

```
users
role + approval_status

users
student_type + is_active

users
is_active + role

subjects
display_order

subject_sections
subject_id + display_order

lectures
section_id + display_order

lecture_resources
lecture_id + resource_type

timeline_quizzes
lecture_id + unlock_time

learning_progress
student_id + subject_id

lecture_progress
student_id + lecture_id

subject_progress_summary
student_id + subject_id

subscriptions
student_id + subject_id

subscriptions
subject_id + status

plans
student_type + is_active

exam_attempts
student_id + exam_id

notes
student_id + lecture_id

student_questions
student_id + status

student_questions
subject_id + status

student_question_replies
question_id + created_at

bookmarks
student_id + subject_id

bookmarks
student_id + lecture_id

notifications
user_id + is_read

chat_messages
room_id + created_at

analytics_events
user_id + event_type + created_at

payment_logs
student_id + payment_date

subject_access_assignments
student_id + is_deleted + enabled

subject_access_assignments
subject_id + is_deleted + enabled
```

---

# 21. Security Overview

## Teacher

- Full Access

## Admin

- Manage Students
- Manage Subject Access only when the Teacher explicitly delegates the required permission; an Admin cannot self-grant it.
- Approve Registration
- Assign / Convert Student Type
- Manage Subjects
- Manage Content
- Manage Sections (system and custom)
- Manage Membership Plans
- Manage Payments
- Manage Devices
- Answer Student Questions
- View Analytics
- Send Notifications

## Student

- Access Approved Subjects only after Subject Access, Subscription, Active Plan, and `plan_features` checks pass.
- Cannot modify Subject Access or Student Type.
- Watch Allowed Content (per Feature Matrix)
- Submit Exams
- Create Notes
- Create Bookmarks
- Send Questions to Admin
- Read Notifications

## New Student

- Registration Only
- Waiting For Approval

---

# 22. Query Patterns

Student Dashboard

```
student
↓
grade
↓
applicable subjects
↓
subject_access_assignments
↓
subscriptions
↓
active plan
↓
plan_features
↓
entitlement
```

The student may see an applicable subject and its resulting availability state, but a missing or disabled Subject Access assignment cannot be bypassed by a direct route or first-open activation.

Subject Page

```
subjects
↓
subject_sections
↓
lectures
↓
learning_progress (resume pointer)
```

Lecture Page

```
lectures
↓
lecture_resources

timeline_quizzes

notes

student_questions

bookmarks

lecture_progress (resume position)
```

Membership / Entitlement Check

```
student
↓
student_type
↓
subject_access_assignment
↓
subscription
↓
active plan (filtered by student_type)
↓
plan_features
↓
entitlement
```

Progress / Completion

```
lecture_progress (raw events)
↓
subject_progress_summary (cached %)
```

---

# 23. Final Architecture Notes

- Firestore is the Single Source of Truth.
- `subject_access_assignments` is a top-level collection independent from `subscriptions`; Subject Access is evaluated before Subscription.
- `docs/notion/05_DATABASE.md` remains the older Version 1.6 reference, while root `05_DATABASE.md` remains an ADR-003 fragment; `05_DATABASE_v1.7.md` is the preserved approved baseline for this change.
- No UI accesses Firestore directly.
- All business logic passes through Repositories.
- All permissions are database-driven.
- Feature availability is controlled from Firestore (Feature Matrix).
- Students interact only with Subjects.
- Academic Year and Term are administrative entities only.
- Multi-Teacher and Multi-Tenant support are explicitly out of scope for Version 1 (per Project Vision) — this schema does not include tenant-scoping fields by design, to avoid premature complexity. Revisit this document when that expansion is planned.
- Offline learning is a local-first extension of the same data model: local progress always reconciles against Firestore as the source of truth once connectivity and membership are revalidated.
- Database is optimized for scalability, analytics, and future expansion without structural changes.

---



---

# 24. Feature 14 Database Change — Independent Subject Access

This section records the complete proposed Database Change from Version 1.7 to Version 1.8. It is pending Teacher Database Change approval; Version 1.7 remains the approved baseline until approval is granted.

## 24.1 Change reason

Feature 14 Membership + Independent Subject Access + updated approval/access rules.

## 24.2 Authoritative access order

```text
Subject Access
↓
Subscription
↓
Active Plan
↓
plan_features
↓
Entitlement
```

Missing Subject Access and disabled Subject Access both result in DENY. This remains true even when Subscription is active, the plan is `center_max`, and the relevant feature is enabled.

## 24.3 Approval and initial assignments

New Student Approval requires Student Type selection and per-subject Toggle Switch configuration. The selected states become the student's initial `subject_access_assignments`. The administrative UI uses only the Toggle Switch representation: enabled is a green/enabled switch and disabled is an off switch. The UI must not expose `true`, `false`, `ON`, or `OFF` as the primary control representation. No default-all-subjects behavior is permitted. Acceptance persists `approved_by`, `approved_at`, the assignments, and an audit action.

## 24.4 Mutation authority

Subject Access mutation is permitted to the Teacher or an Admin with explicit delegated permission from the Teacher. Students cannot mutate it, and Admins cannot self-grant permission. Cloud Functions and Firestore Rules are authoritative, and all mutations are audited with actor, role, target, previous state, new state, permission basis, and server timestamp.

## 24.5 Existing-student migration

Migration uses an active, non-deleted subject Subscription as the default and authoritative evidence. An active, non-deleted subject Subscription results in `enabled = true`; no active, non-deleted subject Subscription results in `enabled = false`, unless an explicit authoritative administrative access source is already documented in the approved project architecture. No such alternative source may be inferred from learning artifacts. `learning_progress`, `lecture_progress`, `bookmarks`, `notes`, `exam_attempts`, `analytics`, historical activity, and Grade-to-Subject membership alone do not grant Subject Access during migration. Migration is idempotent and does not delete or modify existing `subscriptions` or any learning data.

## 24.6 Student Type conflict behavior

Before conversion between `public_student` and `center_student`, active, non-deleted subject Subscriptions are checked against the target Student Type. An incompatible plan causes STOP and returns the student, subject, current type, target type, current plan, and conflicting Subscription. No automatic deletion, downgrade, plan conversion, plan replacement, or Student Type mutation occurs. If no conflict exists, conversion preserves learning history and is audited.

## 24.7 Gift and payment boundaries

Gift Membership is removed from the current business flow. Gift UI, callable, repository method, provider, permission, analytics, tests, and lifecycle are not part of Version 1.8. `is_gifted` and `gifted_by` remain LEGACY / DEPRECATED schema fields and are not deleted or used. Payment remains external only; manually recorded external payments are retained, while checkout, gateways, card payment, online subscription purchase, and automatic online renewal payment are excluded.

## 24.8 Source reconciliation

The authoritative baseline for this change is `05_DATABASE_v1.7.md`, Version 1.7, Status Approved. `docs/notion/05_DATABASE.md` is the older Version 1.6 reference and is not modified in this change. Root `05_DATABASE.md` is an ADR-003 fragment and is not the canonical complete Database specification. None of these older files is silently deleted or overwritten.

---

END OF DOCUMENT
