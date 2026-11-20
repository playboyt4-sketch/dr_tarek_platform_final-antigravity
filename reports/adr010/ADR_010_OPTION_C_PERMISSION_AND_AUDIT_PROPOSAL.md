# ADR-010 Option C — Permission and Audit Proposal

Status: **PROPOSED — awaiting Platform Owner approval. Not applied.**
Date: 2026-11-17
Targets: `14_Platform_Availability_Feature_Matrix_Permission_Matrix_Audit_System.md` (v1.1, Draft)
and `15_Admin_Permissions_Audit_System.md` (v1.1, Draft)

> Proposal file only. Neither document is modified.

---

## 1. Why this is required

Option C introduces eight sensitive operations that have **no permission definition
anywhere today**. If they are implemented without a decision, the default outcome is
whatever a developer writes — which is how privilege escalation enters a system.

The specific hazard: `ADMIN_CONTENT` is a delegated, self-service-grantable permission set
(an Admin with `ADMIN_CONTENT` can manage content). Library registration is an
**infrastructure** action: it decides which external CDN account the platform trusts and
which credentials it will use. Delegating that to a content admin would let a content
admin redirect video delivery to a library they control.

---

## 2. Current verified state

| Fact | Evidence |
|---|---|
| Permission sets are `ADMIN_STUDENTS`, `ADMIN_CONTENT`, `ADMIN_CHAT`, `ADMIN_ANALYTICS`, `ADMIN_DEVICES`, `ADMIN_PAYMENTS_VIEW` | `15` §Permission Sets |
| `15` L130 defines video handling as: "Upload video (enter video_id) — `ADMIN_CONTENT` — Video file uploaded to Bunny CDN separately" | `15` L130 |
| `14` has a rich student-facing video capability model (`video.access`, `video.preview_duration`, `video.quality.max`, …) but **no** admin-side library or upload capability | `14` §3.2 |
| Server guard `requireContentManager` = `doctor` **or** `admin` with `admin_permissions.admin_content === true` and `is_active === true` | `index.ts` L7755 |
| A Doctor-only guard already exists (`requireDoctor`) and is used by eight callables | `index.ts` L958 |
| `admin_audit_log` exists, is written by 20+ callables, and denies all client writes | `firestore.rules` L197 |

---

## 3. Proposed permission model

### 3.1 The eight operations

| # | Operation | Who | Guard | Rationale |
|---|---|---|---|---|
| 1 | **Register a library** | Doctor only | `requireDoctor` | Decides which external account the platform trusts. Never delegable. |
| 2 | **Deactivate a library** | Doctor only | `requireDoctor` | Stops delivery. A content admin must not be able to black out a library. |
| 3 | **Configure library credentials** (including the one-time fallback token key) | Doctor only | `requireDoctor` | Touches key material. Never delegable, never logged. |
| 4 | **Associate a video to a lecture** | Doctor, or Admin with `ADMIN_CONTENT` | `requireContentManager` | Content work; the backend still verifies the video against the library. |
| 5 | **Upload a video** | Doctor, or Admin with `ADMIN_CONTENT` | `requireContentManager` | Content work; upload is bound server-side to one library. |
| 6 | **Trigger / view library health verification** | System triggers; Doctor views | Scheduler (system) / `requireDoctor` (view) | Verification is automated. A human may view but not fabricate a result. |
| 7 | **Emergency blocking** | Doctor only | `requireDoctor` | Incident control. |
| 8 | **Manual token-key fallback entry** | Doctor only | `requireDoctor` | Highest-sensitivity input in the system. Masked, single-use, never echoed. |

### 3.2 Explicit non-grants

The following are **not** granted by this proposal and must not be introduced by
implication during implementation:

| Must not be granted to `ADMIN_CONTENT` | Why |
|---|---|
| Library registration | Would allow redirecting delivery to an attacker-controlled library |
| Library deactivation | Would allow denial of service against paid content |
| Credential configuration | Direct key-material access |
| Emergency blocking | Incident control must stay with the owner |
| Manual token-key entry | Direct key-material input |
| Reading `bunny_libraries` directly | Would expose hosts and credential names; use the `{libraryId, displayName}` projection |

**No new `ADMIN_*` permission set is proposed.** Doctor-only rows are used instead. Adding
a permission set would create a fourth delegation axis that nothing needs today.

---

## 4. Proposed change to `15_Admin_Permissions_Audit_System.md`

### 4.1 Replace one row in the `ADMIN_CONTENT` table

**Current (L130):**

```markdown
| Upload video (enter video_id) | `ADMIN_CONTENT` | Video file uploaded to Bunny CDN separately |
```

**Proposed replacement (two rows):**

```markdown
| Upload video to a registered library | `ADMIN_CONTENT` | Library is selected from the server-provided eligible list; the backend binds the upload to that library; no credential is exposed to the browser |
| Associate a verified video to a lecture | `ADMIN_CONTENT` | Video must be verified against the selected library by the backend; cross-library association is rejected |
```

### 4.2 Add a new Doctor-only subsection

Proposed insertion after the `ADMIN_CONTENT` block:

```markdown
#### Doctor-Only Operations (Bunny Stream Libraries)

These operations are **never delegable**. They are not part of any `ADMIN_*` permission
set and cannot be granted to an Admin.

| Action | Requires | Additional Constraints |
|--------|----------|------------------------|
| Register a Bunny library | Doctor | Library must not already be registered; credentials for that library id must exist in Secret Manager; result is `pending_verification`, never `active` |
| Deactivate a Bunny library | Doctor | Immediately makes the library ineligible; existing playback of that library fails closed |
| Re-activate a Bunny library | Doctor | Returns the library to `pending_verification`; re-verification is mandatory before it can serve playback |
| Enter fallback token key | Doctor | One-time, masked input, never echoed back, never stored in Firestore, written only to Secret Manager |
| Enable/disable emergency blocking | Doctor | Can only reduce eligibility; can never grant it |
| View library health and verification history | Doctor | Read-only; verification results are produced by the system, not entered manually |
```

### 4.3 Audit requirement (per action)

Every row above must emit an `admin_audit_log` entry. The action vocabulary and forbidden
payloads are defined in `ADR_010_OPTION_C_DATABASE_SCHEMA_PROPOSAL.md` §4.2.

---

## 5. Proposed change to `14_…Permission_Matrix…md`

### 5.1 Feature keys (Section 3.2, "Video & Media")

Add two admin-side keys:

```markdown
| `video.library.manage` | Manage Bunny libraries (register, deactivate, credentials) | N/A | N/A | ? Doctor only | Not delegable |
| `video.upload` | Upload video to a registered library | N/A | N/A | ? Full | Delegable via `ADMIN_CONTENT` |
```

Note the distinction from the existing student-facing keys: `video.library.manage` is an
**operator** capability and must not appear in any student plan.

### 5.2 Effective quality clarification

`14` currently defines `video.quality.max` as a plan property. With multiple libraries the
effective maximum is the **minimum** of the plan maximum and the library's own maximum:

```markdown
**Effective maximum quality** = min(plan `video.quality.max`, library maximum).
A library that cannot serve the plan's maximum must not silently downgrade the plan
definition; it downgrades only the delivered stream, and the reason must be observable
server-side.
```

### 5.3 Administrative actions table (Section 4.2)

Add rows mirroring §3.1 above, with `Enforcement layer` = "Cloud Function (server) +
Firestore Rules (deny client writes)".

---

## 6. Audit design constraints

| Constraint | Requirement |
|---|---|
| Writer | Server only. `admin_audit_log` already denies all client writes. |
| Actor attribution | `actor_id`, `actor_role`, `permission_basis` on every entry, matching the existing convention |
| Time | Server timestamp only; never a client-supplied time |
| Secret material | Never recorded — not the value, not a fingerprint, not a masked fragment |
| Failure records | A denied attempt **may** be recorded, but must not include the attempted secret |
| Immutability | No update or delete path exists for clients; server code must not expose one |
| Retention | Out of scope for this proposal; no retention policy is invented |

---

## 7. What this proposal does **not** do

- It does not add a permission set.
- It does not widen `ADMIN_CONTENT` beyond association and upload.
- It does not give any Admin read access to `bunny_libraries` or to library credentials.
- It does not change any existing student-facing feature key.
- It does not change Firestore Rules (the audit collection already denies client writes).

---

## 8. Approval block

Proposed approval sentence:

> "I approve the permission and audit proposal: library registration, deactivation,
> credential configuration, emergency blocking and fallback token entry are Doctor-only
> and non-delegable; video association and upload remain delegable via `ADMIN_CONTENT`;
> every one of these actions writes an `admin_audit_log` entry that never contains secret
> material. No new permission set is created."
