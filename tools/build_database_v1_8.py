from pathlib import Path

base = Path('/home/ubuntu/dr_tarek_platform/dr_tarek_platform_final/05_DATABASE_v1.7.md')
out = Path('/home/ubuntu/dr_tarek_platform/dr_tarek_platform_final/05_DATABASE_v1.8.md')
text = base.read_text()

replacements = [
    (
        'Version: 1.7\nStatus: Approved\n',
        'Version: 1.8\nStatus: Proposed — Pending Teacher Database Change Approval\n',
    ),
    (
        '## Version History\n\n',
        '## Version History\n\n- **1.8** (2026-08-15, proposed): Feature 14 Membership + Independent Subject Access + updated approval/access rules. Version 1.7 remains preserved as the approved baseline.\n',
    ),
    (
        '- Admin/Teacher may convert a student between types at any time.\n- Conversion preserves all learning data (progress, notes, exam attempts, analytics). Only permissions/plan eligibility change.\n',
        '- Teacher or an explicitly delegated Admin may request conversion between types. Before changing `users.student_type`, all active, non-deleted subject subscriptions must be checked against the target Student Type.\n- If any subscription plan is incompatible with the target Student Type, conversion stops and returns a conflict; no subscription deletion, downgrade, automatic conversion, replacement, or Student Type change is allowed.\n- If no incompatible subscription exists, conversion preserves all learning data (progress, notes, exam attempts, quizzes, analytics, and history), and the action is audited and recorded as an Analytics Event.\n',
    ),
    (
        '**Business Rule — Free Plan Activation:**\nApproval does not require an explicit subscription record for every subject in advance. When a student opens a subject for the first time and no `subscriptions` record exists for that (student, subject) pair, the backend automatically creates one using the Free plan matching the student\'s `student_type` (`public_free` or `center_free`), as configured in `system_settings.default_plan`. This keeps the "one active subscription per subject" rule intact while satisfying automatic Free Plan activation.\n',
        '**Business Rule — Conditional Free Plan Activation:**\nApproval does not require an explicit subscription record for every subject in advance. When a student opens a subject for the first time, the backend may create the Free Plan matching the student\'s `student_type` (`public_free` or `center_free`) only after a non-deleted `subject_access_assignments/{student_id}_{subject_id}` document with `enabled = true` has been confirmed. If the assignment is missing or disabled, access is denied and no Subscription is created. The existing one-active-subscription-per-subject rule remains intact.\n',
    ),
    (
        '- Gift Membership\n',
        '',
    ),
    (
        '| is_gifted | Boolean | New — gift membership support |\n| gifted_by | String \\| null | New — reference to `users` (Admin/Teacher) |\n',
        '| is_gifted | Boolean | LEGACY / DEPRECATED; retained for compatibility and not used by the current Membership workflow |\n| gifted_by | String \\| null | LEGACY / DEPRECATED; retained for compatibility and not used by the current Membership workflow |\n',
    ),
    (
        'Every user action generates an Analytics Event. This includes membership operations (upgrade, downgrade, freeze, resume, gift, student type conversion) and unauthorized device attempts.\n',
        'Every user action generates an Analytics Event. This includes membership operations (upgrade, downgrade, freeze, resume, and Student Type conversion) and unauthorized device attempts. Gift Membership is removed from the current business flow and does not generate a current-version Gift event.\n',
    ),
    (
        '## trial_campaigns\n',
        '## subject_access_assignments\n\nStores the independent Subject Access decision for one student and one subject. Subject Access is not stored inside `subscriptions`.\n\nDocument ID\n\n```text\n{student_id}_{subject_id}\n```\n\nContains\n\n| Field | Type | Description |\n| --- | --- | --- |\n| student_id | String | Reference to `users` |\n| subject_id | String | Reference to `subjects` |\n| enabled | Boolean | Internal Subject Access decision; disabled denies access |\n| created_at | Timestamp | Common audit field |\n| updated_at | Timestamp | Common audit field |\n| created_by | String | Creating actor or server identity |\n| updated_by | String | Last updating actor or server identity |\n| is_deleted | Boolean | Soft-delete flag |\n| deleted_at | Timestamp \\| null | Soft-delete timestamp |\n| deleted_by | String \\| null | Deleting actor |\n\nConstraint: one deterministic, non-deleted assignment per (student, subject) pair. Missing or disabled Subject Access denies access, even if a Subscription, Active Plan, and plan feature would otherwise allow access.\n\n---\n\n## trial_campaigns\n',
    ),
    (
        'users\n ├── devices\n ├── subscriptions\n',
        'users\n ├── devices\n ├── subject_access_assignments\n ├── subscriptions\n',
    ),
    (
        'subjects\n ├── subject_sections\n ├── subscriptions\n',
        'subjects\n ├── subject_sections\n ├── subject_access_assignments\n ├── subscriptions\n',
    ),
    (
        '- One active subscription per subject.\n',
        '- One active subscription per subject.\n- Subject Access is an independent gate and is evaluated before Subscription, Active Plan, and `plan_features`.\n- Missing or disabled Subject Access denies access and prevents first-open Free Plan activation.\n- New students do not receive default-all-subjects access; initial assignments come from the approved application review toggles.\n- Subject Access mutations require Teacher authority or explicitly delegated Admin permission, and every mutation is server-authorized and audited.\n',
    ),
    (
        'payment_logs\nstudent_id + payment_date\n```\n',
        'payment_logs\nstudent_id + payment_date\n\nsubject_access_assignments\nstudent_id + is_deleted + enabled\n\nsubject_access_assignments\nsubject_id + is_deleted + enabled\n```\n',
    ),
    (
        '## Admin\n\n- Manage Students\n',
        '## Admin\n\n- Manage Students\n- Manage Subject Access only when the Teacher explicitly delegates the required permission; an Admin cannot self-grant it.\n',
    ),
    (
        '## Student\n\n- Access Approved Subjects\n',
        '## Student\n\n- Access Approved Subjects only after Subject Access, Subscription, Active Plan, and `plan_features` checks pass.\n- Cannot modify Subject Access or Student Type.\n',
    ),
    (
        'Student Dashboard\n\n```\nusers\n↓\nsubscriptions\n↓\nsubjects\n```\n',
        'Student Dashboard\n\n```\nstudent\n↓\ngrade\n↓\napplicable subjects\n↓\nsubject_access_assignments\n↓\nsubscriptions\n↓\nactive plan\n↓\nplan_features\n↓\nentitlement\n```\n\nThe student may see an applicable subject and its resulting availability state, but a missing or disabled Subject Access assignment cannot be bypassed by a direct route or first-open activation.\n',
    ),
    (
        'Membership Check\n\n```\nstudent\n↓\nstudent_type\n↓\nsubscription\n↓\nplan (filtered by student_type)\n↓\nplan_features\n```\n',
        'Membership / Entitlement Check\n\n```\nstudent\n↓\nstudent_type\n↓\nsubject_access_assignment\n↓\nsubscription\n↓\nactive plan (filtered by student_type)\n↓\nplan_features\n↓\nentitlement\n```\n',
    ),
    (
        '- Firestore is the Single Source of Truth.\n',
        '- Firestore is the Single Source of Truth.\n- `subject_access_assignments` is a top-level collection independent from `subscriptions`; Subject Access is evaluated before Subscription.\n- `docs/notion/05_DATABASE.md` remains the older Version 1.6 reference, while root `05_DATABASE.md` remains an ADR-003 fragment; `05_DATABASE_v1.7.md` is the preserved approved baseline for this change.\n',
    ),
]

for old, new in replacements:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'Expected exactly one occurrence, found {count}: {old[:100]!r}')
    text = text.replace(old, new, 1)

feature_section = r'''

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

Migration uses actual access evidence. An active, non-deleted subject Subscription or clear existing learning-access evidence results in `enabled = true`; no evidence results in `enabled = false`. Grade membership alone is not evidence. Migration is idempotent and does not delete or mutate `subscriptions`, `learning_progress`, `lecture_progress`, `notes`, `exam_attempts`, `analytics`, or `history`.

## 24.6 Student Type conflict behavior

Before conversion between `public_student` and `center_student`, active, non-deleted subject Subscriptions are checked against the target Student Type. An incompatible plan causes STOP and returns the student, subject, current type, target type, current plan, and conflicting Subscription. No automatic deletion, downgrade, plan conversion, plan replacement, or Student Type mutation occurs. If no conflict exists, conversion preserves learning history and is audited.

## 24.7 Gift and payment boundaries

Gift Membership is removed from the current business flow. Gift UI, callable, repository method, provider, permission, analytics, tests, and lifecycle are not part of Version 1.8. `is_gifted` and `gifted_by` remain LEGACY / DEPRECATED schema fields and are not deleted or used. Payment remains external only; manually recorded external payments are retained, while checkout, gateways, card payment, online subscription purchase, and automatic online renewal payment are excluded.

## 24.8 Source reconciliation

The authoritative baseline for this change is `05_DATABASE_v1.7.md`, Version 1.7, Status Approved. `docs/notion/05_DATABASE.md` is the older Version 1.6 reference and is not modified in this change. Root `05_DATABASE.md` is an ADR-003 fragment and is not the canonical complete Database specification. None of these older files is silently deleted or overwritten.

---

END OF DOCUMENT
'''

if not text.endswith('END OF DOCUMENT\n'):
    raise RuntimeError('Baseline ending not found')
text = text[:text.rfind('END OF DOCUMENT\n')] + feature_section
out.write_text(text)
print(out)
print(f'lines={len(text.splitlines())}')
