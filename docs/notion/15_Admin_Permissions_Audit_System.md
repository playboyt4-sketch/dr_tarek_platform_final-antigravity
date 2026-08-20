# 15 Admin Permissions & Audit System

## Dr. Tarek Platform

Version: 1.0
Status: Draft — pending Teacher (Platform Owner) review before "Approved"

---

# 1. Purpose

This document defines the administrative permission model, role delegation system, audit trail requirements, and compliance framework for the Dr. Tarek Platform. It serves as the operational companion to **14 Platform Availability, Feature Matrix, Permission Matrix & Audit System**, focusing specifically on the **Admin and Teacher (Platform Owner) experience**.

While Document 14 defines the *student-facing* permission matrix and feature availability, this document defines:
- How administrative permissions are granted, revoked, and delegated.
- How the Teacher (Platform Owner) controls what Admins can and cannot do.
- How every administrative action is audited, reviewed, and retained.
- How the platform ensures accountability and prevents unauthorized administrative changes.

This document does not duplicate 14; it *specializes* it for the administrative domain.

---

# 2. Administrative Roles Hierarchy

```
Teacher (Platform Owner)
    ├── Full System Access
    ├── Can create/manage Admin accounts
    ├── Can configure all platform settings
    ├── Can access monetization & business settings
    ├── Can view all audit logs
    └── Can override any Admin decision

Admin
    ├── Delegated permissions only
    ├── Cannot create other Admins
    ├── Cannot access monetization settings
    ├── Cannot modify platform-wide business configuration
    ├── Cannot reset student passwords (V1)
    └── Audit trail of all actions visible to Teacher
```

## 2.1 Role Definitions

### Teacher (Platform Owner)

The Teacher is the sole owner of the platform instance. There is exactly one Teacher account per platform deployment (per 01 Project Vision: "Single Teacher" in V1).

**Identity:**
- `users.role` = `teacher`
- `users.display_handle` = public-facing identity (e.g., "Dr/tarekelaraby")
- Custom Claims: `role: "teacher"`, `approved: true`

**Characteristics:**
- Account cannot be deleted (only disabled by system).
- Account cannot have its role changed.
- Password reset requires physical verification or secondary channel (not automated).
- All platform settings default to Teacher's preferences.

### Admin

Admins are operational staff appointed by the Teacher to assist in daily platform management.

**Identity:**
- `users.role` = `admin`
- Custom Claims: `role: "admin"`, `approved: true`

**Characteristics:**
- Created exclusively by the Teacher.
- Permissions are granted individually per Admin (not a blanket "all Admins can do X").
- The Teacher can revoke any Admin permission or deactivate the Admin account at any time.
- Admin actions are always logged with the Admin's ID and the Teacher can review them.

---

# 3. Admin Permission Delegation Model

## 3.1 Permission Granularity

Admin permissions are **not binary** (Admin vs. non-Admin). Instead, the Teacher grants specific permission *sets* to each Admin.

### Permission Sets

| Permission Set | Code | Description | Default for New Admin |
|---------------|------|-------------|----------------------|
| Student Management | `ADMIN_STUDENTS` | Approve, suspend, manage student accounts | ✅ Enabled |
| Content Management | `ADMIN_CONTENT` | Create, edit, publish subjects, lectures, exams | ✅ Enabled |
| Communication | `ADMIN_CHAT` | Reply to questions, chat with students, send notifications | ✅ Enabled |
| Analytics (Operational) | `ADMIN_ANALYTICS` | View student progress, exam results, engagement metrics | ❌ Disabled |
| Device Management | `ADMIN_DEVICES` | Replace student devices, view binding logs | ❌ Disabled |
| Payment View | `ADMIN_PAYMENTS_VIEW` | View payment logs (read-only) | ❌ Disabled |
| System Settings (Limited) | `ADMIN_SETTINGS` | Configure non-business settings (notifications, terms) | ❌ Disabled |

### Permission Set Details

#### ADMIN_STUDENTS — Student Management

| Action | Requires Permission | Additional Constraints |
|--------|--------------------|------------------------|
| View pending registrations | `ADMIN_STUDENTS` | — |
| Approve student | `ADMIN_STUDENTS` | — |
| Reject student | `ADMIN_STUDENTS` | — |
| Suspend student | `ADMIN_STUDENTS` | Cannot suspend Teacher |
| Activate suspended student | `ADMIN_STUDENTS` | — |
| Change student type | `ADMIN_STUDENTS` | Requires Teacher approval if changing Center → Public |
| Assign membership plan | `ADMIN_STUDENTS` | Cannot assign plans above Admin's authority level |
| View student profile | `ADMIN_STUDENTS` | — |
| Edit student name/photo | `ADMIN_STUDENTS` | — |
| Replace student device | `ADMIN_DEVICES` | Requires `ADMIN_DEVICES` permission |
| Reset student password | ❌ Not permitted | Teacher (Platform Owner) has full authority. Admin may reset student passwords only when explicitly granted the password_reset permission by the Teacher. |

#### ADMIN_CONTENT — Content Management

| Action | Requires Permission | Additional Constraints |
|--------|--------------------|------------------------|
| Create subject | `ADMIN_CONTENT` | — |
| Edit subject | `ADMIN_CONTENT` | Cannot delete subjects with active subscriptions |
| Archive subject | `ADMIN_CONTENT` | Soft delete only |
| Create section | `ADMIN_CONTENT` | — |
| Edit section | `ADMIN_CONTENT` | System sections: edit content only, not delete |
| Create lecture | `ADMIN_CONTENT` | — |
| Edit lecture | `ADMIN_CONTENT` | — |
| Publish lecture | `ADMIN_CONTENT` | — |
| Archive lecture | `ADMIN_CONTENT` | — |
| Upload video (enter video_id) | `ADMIN_CONTENT` | Video file uploaded to Bunny CDN separately |
| Upload PDF | `ADMIN_CONTENT` | Max file size enforced |
| Create timeline quiz | `ADMIN_CONTENT` | — |
| Edit timeline quiz | `ADMIN_CONTENT` | — |
| Create exam | `ADMIN_CONTENT` | — |
| Edit exam | `ADMIN_CONTENT` | — |
| Publish exam | `ADMIN_CONTENT` | — |
| Grade essay questions | `ADMIN_CONTENT` | — |
| Configure lecture access rules | `ADMIN_CONTENT` | — |
| Reset student watch attempts | `ADMIN_CONTENT` | — |

#### ADMIN_CHAT — Communication

| Action | Requires Permission | Additional Constraints |
|--------|--------------------|------------------------|
| Reply to student questions | `ADMIN_CHAT` | — |
| Send broadcast answer | `ADMIN_CHAT` | Target: students they manage |
| Chat with students (1-on-1) | `ADMIN_CHAT` | — |
| Send notification | `ADMIN_CHAT` | Cannot send as "Doctor" — Teacher only |
| Create notification template | `ADMIN_CHAT` | — |
| Schedule notification | `ADMIN_CHAT` | — |

#### ADMIN_ANALYTICS — Operational Analytics

| Action | Requires Permission | Additional Constraints |
|--------|--------------------|------------------------|
| View student progress | `ADMIN_ANALYTICS` | Any student |
| View exam results | `ADMIN_ANALYTICS` | Any exam |
| View engagement metrics | `ADMIN_ANALYTICS` | Dashboard only |
| View quiz analytics | `ADMIN_ANALYTICS` | — |
| Export student reports | `ADMIN_ANALYTICS` | PDF/CSV format |
| View security events | `ADMIN_ANALYTICS` | Operational events only |

#### ADMIN_DEVICES — Device Management

| Action | Requires Permission | Additional Constraints |
|--------|--------------------|------------------------|
| View student devices | `ADMIN_DEVICES` | — |
| Unbind/replace device | `ADMIN_DEVICES` | Logs reason for replacement |
| View unauthorized attempt logs | `ADMIN_DEVICES` | — |
| Approve factory reset rebind | `ADMIN_DEVICES` | — |

#### ADMIN_PAYMENTS_VIEW — Payment View (Read-Only)

| Action | Requires Permission | Additional Constraints |
|--------|--------------------|------------------------|
| View payment logs | `ADMIN_PAYMENTS_VIEW` | Read-only |
| Filter payment logs | `ADMIN_PAYMENTS_VIEW` | — |
| Export payment summary | `ADMIN_PAYMENTS_VIEW` | Aggregated only, no individual receipts |

**Cannot do:**
- Log new payments (Teacher only)
- Modify payment records (Teacher only)
- Access revenue reports (Teacher only)

#### ADMIN_SETTINGS — Limited System Settings

| Action | Requires Permission | Additional Constraints |
|--------|--------------------|------------------------|
| Edit platform terms | `ADMIN_SETTINGS` | Draft only, Teacher must approve |
| Configure notification defaults | `ADMIN_SETTINGS` | Non-business notifications |
| Manage FAQ content | `ADMIN_SETTINGS` | — |
| Configure support categories | `ADMIN_SETTINGS` | — |

**Cannot do:**
- Enable/disable registration (Teacher only)
- Enable/disable trial (Teacher only)
- Set maintenance mode (Teacher only)
- Configure Feature Matrix (Teacher only)
- Configure monetization (Teacher only)

## 3.2 Permission Storage

Admin permissions are stored in Firestore:

```
admin_permissions (collection)
├── admin_id: String (reference to users/{adminId})
├── granted_by: String (Teacher user ID)
├── granted_at: Timestamp
├── updated_at: Timestamp
├── is_active: Boolean
├── permissions: Map<String, Boolean>
│   ├── admin_students: true
│   ├── admin_content: true
│   ├── admin_chat: true
│   ├── admin_analytics: false
│   ├── admin_devices: false
│   ├── admin_payments_view: false
│   └── admin_settings: false
└── restrictions: Array<String> (specific limitations, e.g., ["cannot_approve_center_to_public"])
```

**Note:** This collection is new and needs formal addition to 05 Database if approved.

## 3.3 Permission Enforcement

### Dashboard UI Enforcement

```
Before rendering any Admin Dashboard action:
1. Read admin_permissions document for current user.
2. Check if the required permission set is enabled.
3. If disabled: hide the UI element (not just disable — completely remove from DOM/widget tree).
4. If enabled but with restrictions: render with restriction warnings.
```

### API Enforcement

```
Every Admin-facing Cloud Function:
1. Verify request.auth.token.role == "admin".
2. Read admin_permissions for request.auth.uid.
3. Check if required permission is true.
4. If false: return PermissionDenied (403) with logging.
5. If true: proceed with business logic.
6. Log action to admin_audit_log (see Section 5).
```

### Firestore Security Rules

```
match /admin_permissions/{docId} {
  allow read: if request.auth.token.role == "teacher"
              || (request.auth.uid == docId && request.auth.token.role == "admin");
  allow write: if request.auth.token.role == "teacher";
}
```

---

# 4. Admin Lifecycle

## 4.1 Creating an Admin

```
1. Teacher opens Admin Management in Dashboard.
2. Teacher enters: full name, phone number, email (optional).
3. Teacher selects permission sets to grant.
4. Teacher sets any restrictions.
5. System creates user account with role "admin".
6. System creates admin_permissions document.
7. System sends invitation (in-app notification + push).
8. Admin sets password on first login.
9. Admin account is active immediately (no approval needed for Admin accounts).
```

## 4.2 Modifying an Admin

```
1. Teacher opens Admin Management.
2. Teacher selects an existing Admin.
3. Teacher can:
   - Enable/disable permission sets
   - Add/remove restrictions
   - Disable account (soft delete)
   - Reset Admin password
4. Changes are effective immediately (Custom Claims refreshed on next token refresh).
5. System logs all changes to admin_permission_audit_log.
```

## 4.3 Deactivating an Admin

```
1. Teacher selects "Deactivate Admin".
2. System sets is_active = false on admin_permissions.
3. System sets account_status = "disabled" on users.
4. Admin is logged out on next token refresh (within 15 minutes).
5. All Admin's past actions remain in audit log.
6. Admin account can be reactivated by Teacher at any time.
```

## 4.4 Admin Self-Service

Admins can:
- View their own permission sets (read-only).
- Change their own password.
- Update their profile photo.
- View their own audit trail.

Admins cannot:
- Grant themselves additional permissions.
- View other Admins' permissions.
- View Teacher-only settings.

---

# 5. Admin Audit System

## 5.1 Purpose

The Admin Audit System ensures that every administrative action is:
- **Attributed:** Know exactly who did what.
- **Timestamped:** Know exactly when it happened.
- **Contextual:** Know the full context (student affected, old value, new value).
- **Immutable:** Cannot be altered or deleted.
- **Reviewable:** Teacher can review any Admin's actions at any time.

## 5.2 Audit Collection Schema

```
admin_audit_log (collection)
├── id: String (UUID)
├── actor_id: String (the Admin or Teacher who performed the action)
├── actor_role: String ("admin" or "teacher")
├── actor_name: String (denormalized for display)
├── action: String (from enum — see 5.3)
├── target_collection: String (e.g., "users", "lectures", "subscriptions")
├── target_document_id: String
├── target_description: String (human-readable, e.g., "Student: Ahmed Hassan")
├── old_value: Map<String, dynamic> (snapshot before change)
├── new_value: Map<String, dynamic> (snapshot after change)
├── change_summary: String (auto-generated diff description)
├── ip_address: String
├── user_agent: String
├── session_id: String
├── admin_permission_context: Map (which permissions the actor had at the time)
├── approval_required: Boolean (was Teacher approval needed?)
├── approved_by: String | null (Teacher ID if approval was required)
├── approved_at: Timestamp | null
├── rejection_reason: String | null
├── created_at: Timestamp
└── is_undone: Boolean (if the action was later reversed)
```

**Note:** This collection is new and needs formal addition to 05 Database if approved.

## 5.3 Admin Action Enum

```
ADMIN_STUDENT_APPROVED
ADMIN_STUDENT_REJECTED
ADMIN_STUDENT_SUSPENDED
ADMIN_STUDENT_ACTIVATED
ADMIN_STUDENT_TYPE_CHANGED
ADMIN_MEMBERSHIP_ASSIGNED
ADMIN_DEVICE_REPLACED
ADMIN_CONTENT_CREATED
ADMIN_CONTENT_UPDATED
ADMIN_CONTENT_PUBLISHED
ADMIN_CONTENT_ARCHIVED
ADMIN_EXAM_GRADED
ADMIN_QUESTION_ANSWERED
ADMIN_NOTIFICATION_SENT
ADMIN_NOTIFICATION_SCHEDULED
ADMIN_SETTINGS_CHANGED
ADMIN_PERMISSION_GRANTED
ADMIN_PERMISSION_REVOKED
ADMIN_ACCOUNT_DEACTIVATED
ADMIN_ACCOUNT_REACTIVATED
ADMIN_PASSWORD_RESET
TEACHER_OVERRIDE (Teacher overriding an Admin action)
TEACHER_PAYMENT_LOGGED
TEACHER_FEATURE_MATRIX_CHANGED
TEACHER_PLAN_CREATED
TEACHER_ADMIN_CREATED
TEACHER_ADMIN_MODIFIED
```

## 5.4 Actions Requiring Teacher Approval

Some Admin actions require explicit Teacher approval before taking effect:

| Action | Approval Required | Auto-Approve Window | Escalation |
|--------|------------------|---------------------|------------|
| Change student type (Center → Public) | ✅ Yes | None | Teacher must approve |
| Assign Center Max plan | ✅ Yes | None | Teacher must approve |
| Suspend > 10 students at once | ✅ Yes | None | Teacher must approve |
| Archive a subject with > 100 active students | ✅ Yes | None | Teacher must approve |
| Export student data (bulk) | ✅ Yes | None | Teacher must approve |
| Change platform terms | ✅ Yes | None | Teacher must approve |
| Modify own permissions | ❌ No | N/A | Impossible (only Teacher can) |
| Approve single student | ❌ No | Immediate | — |
| Publish lecture | ❌ No | Immediate | — |
| Send notification | ❌ No | Immediate | — |

### Approval Workflow

```
1. Admin submits action requiring approval.
2. Action is queued in pending_admin_actions collection.
3. Teacher receives in-app notification + push.
4. Teacher reviews action details (old value, new value, impact).
5. Teacher approves or rejects with reason.
6. If approved: action executes, logged as normal.
7. If rejected: action cancelled, Admin notified, logged as rejected.
8. If no response in 48 hours: action auto-expires, Admin notified.
```

## 5.5 Audit Log Viewer (Dashboard)

The Teacher Dashboard includes an Audit Log Viewer with:

### Filters
- Date range
- Actor (Admin name)
- Action type
- Target (student, lecture, exam, etc.)
- Approval status

### Views
- **Timeline View:** Chronological list of all actions.
- **Admin View:** All actions by a specific Admin.
- **Student View:** All actions affecting a specific student.
- **Impact View:** High-impact actions (type changes, suspensions, bulk operations).
- **Approval Queue:** Pending actions awaiting Teacher approval.

### Export
- CSV export for date range.
- PDF summary report.
- JSON for programmatic access (Teacher only).

---

# 6. Compliance & Governance

## 6.1 Data Retention

| Audit Data Type | Retention Period | Auto-Archive | Auto-Delete |
|----------------|-----------------|--------------|-------------|
| Admin audit log | 3 years | After 1 year (to cold storage) | After 3 years |
| Pending approvals | 30 days | N/A | After expiry |
| Admin permission history | 2 years | After 1 year | After 2 years |
| Login/session logs | 1 year | After 6 months | After 1 year |

## 6.2 Compliance Requirements

### Egyptian Context (Primary)
- **Data Localization:** Student data stored in Firebase (region: `europe-west` or `me-central` if available).
- **Consent:** Student registration includes explicit consent for data processing.
- **Right to Access:** Students can request their data export (Admin can generate).
- **Right to Deletion:** Account deletion request → soft delete + 90-day retention → permanent deletion.

### GDPR Considerations (Future)
- If platform serves EU students in future versions:
  - Data Processing Agreement with Firebase.
  - Explicit consent for analytics and push notifications.
  - Data portability (JSON export).
  - Right to be forgotten (hard delete after retention period).

## 6.3 Fraud Prevention

### Detecting Suspicious Admin Behavior

| Pattern | Detection | Action |
|---------|-----------|--------|
| Admin approves 50+ students in 1 hour | Analytics threshold | Flag for Teacher review |
| Admin accesses outside business hours | Time-based anomaly | Log as "unusual hours" |
| Admin changes same student's plan 3+ times | Frequency threshold | Flag for Teacher review |
| Admin exports bulk data repeatedly | Frequency threshold | Require re-approval |
| Admin login from new device | Device binding | Require email/phone verification |
| Admin permissions changed unexpectedly | Audit diff | Immediate Teacher alert |

### Automated Safeguards

- **Rate limiting:** Admin actions limited to 100/hour per Admin (configurable).
- **Bulk operation limits:** Max 50 students per bulk action without Teacher approval.
- **Session timeout:** Admin sessions expire after 8 hours of inactivity.
- **Concurrent session limit:** One active Admin session per device.
- **Action confirmation:** Destructive actions (archive, suspend) require confirmation dialog.

---

# 7. Admin Dashboard Architecture

## 7.1 Technology Stack

The Admin/Teacher Dashboard is a **web-first** application:

| Layer | Technology | Notes |
|-------|-----------|-------|
| Frontend | Flutter Web | Shared codebase with mobile where possible |
| State Management | Riverpod | Consistent with mobile app |
| Backend | Firebase (same project) | Shared Firestore, Auth, Functions |
| Hosting | Firebase Hosting | `admin.drtarek.app` or subdirectory |
| Authentication | Same Custom Tokens | Role-based routing after login |

## 7.2 Dashboard Modules

```
Admin/Teacher Dashboard
├── Authentication
│   └── Login (same Custom Token flow, role checked post-login)
├── Home / Overview
│   ├── Key metrics (students, active today, pending approvals)
│   ├── Recent activity feed
│   └── Alerts requiring attention
├── Student Management
│   ├── Pending Approvals
│   ├── All Students (search, filter, bulk actions)
│   ├── Student Detail (profile, progress, devices, payments)
│   └── Student Type & Membership Management
├── Content Management
│   ├── Subjects (create, edit, order, archive)
│   ├── Sections (system + custom)
│   ├── Lectures (create, edit, publish, configure access)
│   ├── Resources (video IDs, PDFs, attachments)
│   ├── Timeline Quizzes
│   └── Exams (create, grade, publish, configure)
├── Communication
│   ├── Student Questions (inbox, reply, broadcast)
│   ├── Chat Management
│   ├── Notifications (send, schedule, templates)
│   └── Doctor Announcements (Teacher only)
├── Membership & Monetization (Teacher only)
│   ├── Feature Matrix Configuration
│   ├── Plan Management
│   ├── Payment Logging
│   └── Revenue Reports
├── Analytics
│   ├── Student Engagement
│   ├── Content Performance
│   ├── Exam Statistics
│   └── Security Events
├── Device Management
│   ├── Bound Devices
│   ├── Unauthorized Attempts
│   └── Replacement Requests
├── Audit & Compliance
│   ├── Admin Audit Log
│   ├── Pending Approvals Queue
│   ├── Security Events
│   └── Data Export
└── Settings
    ├── Platform Settings (Teacher only)
    ├── Admin Management (Teacher only)
    ├── Notification Settings
    └── Profile Settings
```

## 7.3 Role-Based UI Rendering

```dart
// Example: Conditional rendering based on role and permissions
class DashboardMenu extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(userRoleProvider);
    final permissions = ref.watch(adminPermissionsProvider);

    return Column(
      children: [
        // All admins see this
        MenuItem(icon: Icons.home, label: 'Overview'),

        // Permission-gated
        if (permissions.canManageStudents)
          MenuItem(icon: Icons.people, label: 'Students'),

        if (permissions.canManageContent)
          MenuItem(icon: Icons.book, label: 'Content'),

        if (permissions.canViewAnalytics)
          MenuItem(icon: Icons.analytics, label: 'Analytics'),

        // Teacher only
        if (role == 'teacher') ...[
          MenuItem(icon: Icons.payments, label: 'Monetization'),
          MenuItem(icon: Icons.admin_panel_settings, label: 'Admin Management'),
          MenuItem(icon: Icons.settings, label: 'Platform Settings'),
        ],
      ],
    );
  }
}
```

---

# 8. Implementation Checklist

### Admin Permission System

- [ ] `admin_permissions` collection created in Firestore.
- [ ] `admin_permission_audit_log` collection created.
- [ ] `pending_admin_actions` collection created (for approval workflow).
- [ ] Cloud Function `createAdmin` — Teacher-only, creates user + permissions.
- [ ] Cloud Function `updateAdminPermissions` — Teacher-only.
- [ ] Cloud Function `deactivateAdmin` — Teacher-only.
- [ ] Cloud Function `processPendingAction` — Teacher approves/rejects.
- [ ] Security Rules for admin_permissions (Teacher full access, Admin read-own-only).
- [ ] Flutter Web Dashboard: Admin Management screen (Teacher only).
- [ ] Flutter Web Dashboard: Permission editor UI.

### Admin Audit System

- [ ] `admin_audit_log` collection created with composite indexes.
- [ ] Cloud Function `logAdminAction` — called by all Admin-facing functions.
- [ ] Cloud Function `processAuditAlerts` — detects suspicious patterns.
- [ ] Dashboard: Audit Log Viewer with filters and export.
- [ ] Dashboard: Pending Approvals Queue.
- [ ] Dashboard: Admin Activity Timeline.
- [ ] Automated data retention job (archive old logs).

### Dashboard Implementation

- [ ] Flutter Web project setup (or shared mobile/web codebase).
- [ ] Role-based routing (redirect non-Admin users).
- [ ] Responsive layout for desktop/tablet.
- [ ] RTL Arabic support.
- [ ] Dark mode support.
- [ ] Real-time updates (Firestore listeners for pending approvals, new registrations).

---

# 9. Open Items

- [ ] Confirm `admin_permissions`, `admin_permission_audit_log`, `pending_admin_actions`, and `admin_audit_log` collections for addition to 05 Database.
- [ ] Confirm if multiple Teachers (Platform Owners) should be supported in V1.2+ — currently single Teacher only.
- [ ] Design Admin Dashboard UI — depends on 03 UI & UX.
- [ ] Confirm Admin invitation flow (email vs. in-app only vs. SMS).
- [ ] Define "business hours" for unusual hours anomaly detection.
- [ ] Confirm if Admin accounts require 2FA in V1 (proposed: V1.2).
- [ ] Define cold storage solution for archived audit logs (Firestore → Cloud Storage → BigQuery?).
- [ ] Confirm data export format for student data portability requests.

---

END OF DOCUMENT
