# 14 Platform Availability, Feature Matrix, Permission Matrix & Audit System

## Dr. Tarek Platform

Version: 1.0
Status: Draft — pending Teacher (Platform Owner) review before "Approved"

---

# 1. Purpose

This document defines three interconnected governance systems:

1. **Platform Availability** — which platforms (Android, iOS, Web) support which features.
2. **Feature Matrix** — which features are available under which membership plan, controlled entirely from the database.
3. **Permission Matrix** — which user roles can perform which actions.
4. **Audit System** — how every significant action is logged, retained, and reviewed.

This document is the single source of truth for access control across the platform. It does not duplicate business rules from 02 PRD or feature specifications from 04 Features; it *organizes and cross-references* them for implementation and verification.

---

# 2. Platform Availability

## 2.1 Supported Platforms

| Platform | Version 1 Status | Notes |
|----------|-----------------|-------|
| **Android** | ✅ Fully Supported | Primary platform (Mobile First) |
| **iOS** | ✅ Fully Supported | Feature parity with Android |
| **Web** | ✅ Fully Supported | Responsive design, PWA-ready |
| **Desktop (Windows/macOS/Linux)** | ❌ Out of Scope | Planned for future (see 01 Project Vision) |
| **Tablet (Android/iPad)** | ✅ Supported via Responsive | Layout adapts via breakpoints |

## 2.2 Feature Availability by Platform

| Feature | Android | iOS | Web | Platform-Specific Notes |
|---------|---------|-----|-----|------------------------|
| Authentication (Custom Tokens) | ✅ | ✅ | ✅ | Web uses Firebase Auth JS SDK |
| Device Binding | ✅ | ✅ | ⚠️ Limited | Web: session-based, no hardware ID |
| Video Player | ✅ | ✅ | ✅ | Web: HTML5 video with signed URL |
| Offline Video Download | ✅ | ✅ | ❌ | Web: streaming only |
| PDF Viewer | ✅ | ✅ | ✅ | Web: browser PDF viewer fallback |
| Offline PDF Download | ✅ | ✅ | ❌ | Web: view only |
| Push Notifications (FCM) | ✅ | ✅ | ⚠️ Limited | Web: requires service worker + browser permission |
| In-App Notifications | ✅ | ✅ | ✅ | Unified across all platforms |
| Screen Recording Detection | ✅ (API 34+) | ✅ (iOS 11+) | ❌ | Web: not applicable |
| Screenshot Prevention | ✅ (WindowManager) | ❌ (iOS limitation) | ❌ | iOS: detection only, not prevention |
| Picture in Picture | ✅ | ✅ | ✅ | Web: Picture-in-Picture API |
| Cast to TV | ✅ (Chromecast) | ✅ (AirPlay) | ❌ | Web: not applicable |
| Biometric Login (Future) | ✅ | ✅ | ❌ | V1.2+ consideration |
| Deep Linking | ✅ | ✅ | ✅ | Web: URL routing |
| Background Download | ✅ | ✅ | ❌ | Web: foreground only |
| AES-256 DRM | ✅ | ✅ | ❌ | Web: no offline content protection |
| Secure Storage (Keys) | ✅ (Keystore) | ✅ (Keychain) | ⚠️ Limited | Web: IndexedDB + encryption |
| Timeline Quizzes | ✅ | ✅ | ✅ | Unified |
| Exams | ✅ | ✅ | ✅ | Unified |
| Chat | ✅ | ✅ | ✅ | Unified |
| Notes | ✅ | ✅ | ✅ | Unified |
| Bookmarks | ✅ | ✅ | ✅ | Unified |
| Admin Dashboard | ⚠️ Web Primary | ⚠️ Web Primary | ✅ Primary | Mobile: read-only or limited |
| Teacher Dashboard | ⚠️ Web Primary | ⚠️ Web Primary | ✅ Primary | Mobile: read-only or limited |

### Legend
- ✅ Fully supported
- ⚠️ Supported with limitations
- ❌ Not supported / Out of scope

---

# 3. Feature Matrix

## 3.1 Principles

- **No hardcoded permissions.** Every feature availability is controlled by `plan_features` collection in Firestore (see 05 Database Section 16).
- **Plan determines features, not code.** Changing a feature's availability requires only a Dashboard toggle — no app update, no code change.
- **Feature keys use dot notation** (per 00 Master Architecture Section 9.2).
- **Default values** are defined here as the "factory settings" for each plan. Admin/Teacher can override any value from the Dashboard.

## 3.2 Feature Keys

### Video & Media

| Feature Key | Description | Default Public Free | Default Center Free | Default Center Pro | Default Center Max |
|-------------|-------------|---------------------|---------------------|--------------------|--------------------|
| `video.access` | Watch videos | Preview only | ✅ Full | ✅ Full | ✅ Full |
| `video.preview_duration` | Preview minutes | 5 min | Unlimited | Unlimited | Unlimited |
| `video.quality.max` | Max resolution | 480p | 720p | 1080p | 1080p |
| `video.quality.options` | Quality choices | Single | Single | Multi | Multi |
| `video.playback_speed` | Speed control | ❌ | ❌ | ✅ | ✅ |
| `video.pip` | Picture in Picture | ❌ | ❌ | ✅ | ✅ |
| `video.cast` | Cast to TV | ❌ | ❌ | ❌ | ✅ |
| `video.download` | Offline download | ❌ | ❌ | ❌ | ✅ |
| `video.download.max_count` | Max offline videos | 0 | 0 | 0 | 50 |
| `video.download.quality` | Download quality | N/A | N/A | N/A | 720p |
| `video.resume` | Resume playback | ✅ | ✅ | ✅ | ✅ |
| `video.watermark` | Dynamic watermark | ✅ | ✅ | ✅ | ✅ |
| `video.security.screen_record_detect` | Detect screen recording | ✅ | ✅ | ✅ | ✅ |
| `video.security.screenshot_prevent` | Prevent screenshots | ✅ | ✅ | ✅ | ✅ |

### PDF & Documents

| Feature Key | Description | Default Public Free | Default Center Free | Default Center Pro | Default Center Max |
|-------------|-------------|---------------------|---------------------|--------------------|--------------------|
| `pdf.access` | View PDFs | Preview only | ✅ Full | ✅ Full | ✅ Full |
| `pdf.preview_pages` | Preview page count | 5 pages | Unlimited | Unlimited | Unlimited |
| `pdf.download` | Download PDF | ❌ | ❌ | ✅ | ✅ |
| `pdf.offline` | Offline reading | ❌ | ❌ | ✅ | ✅ |
| `pdf.search` | Search within PDF | ❌ | ✅ | ✅ | ✅ |
| `pdf.zoom` | Zoom control | ✅ | ✅ | ✅ | ✅ |
| `pdf.bookmarks` | PDF bookmarks | ❌ | ❌ | ✅ | ✅ |
| `pdf.toc` | Table of Contents | ❌ | ✅ | ✅ | ✅ |
| `pdf.print` | Print PDF | ❌ | ❌ | ❌ | ❌ |
| `pdf.copy` | Copy text | ❌ | ❌ | ❌ | ❌ |
| `pdf.share` | Share PDF | ❌ | ❌ | ❌ | ❌ |
| `pdf.watermark` | Dynamic watermark | ✅ | ✅ | ✅ | ✅ |

### Attachments

> ✅ **CONFIRMED BY TEACHER** (supersedes the earlier placeholder mirror of
> pdf.* rows). Per the ratified permission rule, attachments gate on their
> own independent keys — nothing shared with or inherited from `pdf.*`.

| Feature Key | Description | Default Public Free | Default Center Free | Default Center Pro | Default Center Max |
|-------------|-------------|---------------------|---------------------|--------------------|--------------------|
| `attachment.access` | Open attachments | ❌ | ✅ Full | ✅ Full | ✅ Full |
| `attachment.download` | Download attachments | ❌ | ❌ | ✅ | ✅ |

### Learning & Assessment

| Feature Key | Description | Default Public Free | Default Center Free | Default Center Pro | Default Center Max |
|-------------|-------------|---------------------|---------------------|--------------------|--------------------|
| `quiz.access` | Take timeline quizzes | ❌ | ✅ | ✅ | ✅ |
| `quiz.attempts` | Max attempts per quiz | 0 | Unlimited | Unlimited | Unlimited |
| `quiz.review` | Review answers | ❌ | ✅ | ✅ | ✅ |
| `quiz.explanation` | See explanations | ❌ | ✅ | ✅ | ✅ |
| `exam.access` | Take exams | ❌ | ✅ | ✅ | ✅ |
| `exam.practice_mode` | Practice exam mode | ❌ | ✅ | ✅ | ✅ |
| `exam.attempts` | Max exam attempts | 0 | Per exam config | Per exam config | Per exam config |
| `exam.result.visibility` | When results show | N/A | Per exam config | Per exam config | Per exam config |
| `progress.tracking` | Track learning progress | ✅ | ✅ | ✅ | ✅ |
| `progress.analytics` | View personal analytics | ❌ | ✅ | ✅ | ✅ |

### Communication

| Feature Key | Description | Default Public Free | Default Center Free | Default Center Pro | Default Center Max |
|-------------|-------------|---------------------|---------------------|--------------------|--------------------|
| `chat.admin` | Chat with Admin | ❌ | ✅ | ✅ | ✅ |
| `chat.doctor_channel` | Read Doctor announcements | ✅ | ✅ | ✅ | ✅ |
| `chat.attachments` | Send attachments in chat | ❌ | ❌ | ✅ | ✅ |
| `question.submit` | Ask questions to Admin | ❌ | ✅ | ✅ | ✅ |
| `question.attachments` | Attach files to questions | ❌ | ❌ | ✅ | ✅ |
| `notification.push` | Push notifications | ✅ | ✅ | ✅ | ✅ |
| `notification.in_app` | In-app notifications | ✅ | ✅ | ✅ | ✅ |
| `notification.quiet_hours` | Configure quiet hours | ❌ | ✅ | ✅ | ✅ |

### Productivity

| Feature Key | Description | Default Public Free | Default Center Free | Default Center Pro | Default Center Max |
|-------------|-------------|---------------------|---------------------|--------------------|--------------------|
| `notes.create` | Create personal notes | ❌ | ✅ | ✅ | ✅ |
| `notes.image` | Image notes | ❌ | ❌ | ✅ | ✅ |
| `notes.voice` | Voice notes (V1.1+) | ❌ | ❌ | ❌ | ❌ |
| `notes.export` | Export notes | ❌ | ❌ | ❌ | ✅ |
| `notes.smart` | Save Smart Notes | ❌ | ✅ | ✅ | ✅ |
| `bookmark.create` | Create bookmarks | ❌ | ✅ | ✅ | ✅ |
| `bookmark.max_count` | Max bookmarks | 0 | 50 | 100 | Unlimited |
| `bookmark.search` | Search bookmarks | ❌ | ✅ | ✅ | ✅ |

### Device & Security

| Feature Key | Description | Default Public Free | Default Center Free | Default Center Pro | Default Center Max |
|-------------|-------------|---------------------|---------------------|--------------------|--------------------|
| `device.max_count` | Max active devices | 1 | 1 | 1 | 2 |
| `device.replace` | Self-service device replacement | ❌ | ❌ | ❌ | ❌ |
| `device.factory_reset` | Factory reset handling | Admin approval | Admin approval | Admin approval | Admin approval |
| `security.score` | View security score | ❌ | ✅ | ✅ | ✅ |
| `offline.mode` | Offline learning mode | ❌ | ❌ | ❌ | ✅ |
| `offline.encryption` | AES-256 DRM | N/A | N/A | N/A | ✅ |

### Profile & Account

| Feature Key | Description | Default Public Free | Default Center Free | Default Center Pro | Default Center Max |
|-------------|-------------|---------------------|---------------------|--------------------|--------------------|
| `profile.edit_name` | Edit full name | ✅ | ✅ | ✅ | ✅ |
| `profile.edit_photo` | Edit profile photo | ✅ | ✅ | ✅ | ✅ |
| `profile.change_password` | Change password | ✅ | ✅ | ✅ | ✅ |
| `profile.view_device` | View device info | ✅ | ✅ | ✅ | ✅ |
| `profile.view_membership` | View membership details | ✅ | ✅ | ✅ | ✅ |
| `profile.display_handle` | Set public handle | ❌ | ❌ | ✅ | ✅ |

## 3.3 Feature Value Types

Features in `plan_features` can have different value types:

| Type | Example | Database Representation |
|------|---------|------------------------|
| **Boolean** | `video.access` = true/false | `enabled: true/false` |
| **Number** | `video.preview_duration` = 5 | `feature_value: 5` |
| **String** | `video.quality.max` = "720p" | `feature_value: "720p"` |
| **Enum** | `exam.result.visibility` = "immediate" | `feature_value: "immediate"` |
| **List** | `video.quality.options` = ["480p","720p","1080p"] | `feature_value: ["480p","720p","1080p"]` |
| **JSON** | Complex configuration | `feature_value: { ... }` |

## 3.4 Feature Override Hierarchy

When multiple sources define a feature value, the following priority applies (highest wins):

```
1. Student-specific override (Admin/Teacher manually set for individual student)
2. Active subscription plan features
3. Student type default features
4. System default features
5. Feature hardcoded fallback (last resort, logged as warning)
```

## 3.5 Feature Matrix Change Audit

Every change to `plan_features` is logged:

| Field | Description |
|-------|-------------|
| `plan_id` | Which plan was modified |
| `feature_key` | Which feature was changed |
| `old_value` | Previous value |
| `new_value` | New value |
| `changed_by` | Admin/Teacher user ID |
| `changed_at` | Timestamp |
| `reason` | Optional justification |

Collection: `plan_feature_audit_logs` (new collection, to be added to 05 Database if approved).

---

# 4. Permission Matrix

## 4.1 Permission Model

The platform uses **Role-Based Access Control (RBAC)** with **Attribute-Based Access Control (ABAC)** extensions:

- **RBAC:** Primary control via `users.role` (new_student, student, admin, teacher).
- **ABAC:** Secondary control via Custom Claims (`student_type`, `plan_id`, `max_devices`, `approved`) and Feature Matrix.
- **Resource-level:** Tertiary control via Firestore document ownership and relationships.

## 4.2 Action Permission Matrix

### Student-Facing Actions

| Action | New Student | Student | Admin | Teacher |
|--------|-------------|---------|-------|---------|
| **Authentication** |
| Register account | ✅ | N/A | N/A | N/A |
| Login | ✅ (pending only) | ✅ | ✅ | ✅ |
| Logout | ✅ | ✅ | ✅ | ✅ |
| Request password reset | ✅ | ✅ | ❌ | ❌ |
| **Dashboard & Navigation** |
| View Student Dashboard | ❌ | ✅ | ❌ | ❌ |
| View subjects list | ❌ | ✅ | ✅ (all) | ✅ (all) |
| Enter subject | ❌ | ✅ | ✅ | ✅ |
| **Content Consumption** |
| Watch video | ❌ | Per Feature Matrix | ✅ | ✅ |
| Read PDF | ❌ | Per Feature Matrix | ✅ | ✅ |
| Take timeline quiz | ❌ | Per Feature Matrix | ✅ | ✅ |
| Take exam | ❌ | Per Feature Matrix | ✅ | ✅ |
| Resume learning | ❌ | ✅ | ✅ | ✅ |
| **Productivity** |
| Create notes | ❌ | Per Feature Matrix | ✅ | ✅ |
| Create bookmarks | ❌ | Per Feature Matrix | ✅ | ✅ |
| Ask question to Admin | ❌ | Per Feature Matrix | ✅ | ✅ |
| Chat with Admin | ❌ | Per Feature Matrix | ✅ | ✅ |
| Read Doctor announcements | ❌ | ✅ | ✅ | ✅ |
| **Profile** |
| View profile | ❌ | ✅ | ✅ (any student) | ✅ (any student) |
| Edit name | ❌ | ✅ | ✅ (any student) | ✅ (any student) |
| Edit photo | ❌ | ✅ | ✅ (any student) | ✅ (any student) |
| Change password | ❌ | ✅ | ❌ | ❌ |
| View membership | ❌ | ✅ | ✅ | ✅ |
| View device info | ❌ | ✅ | ✅ | ✅ |

### Administrative Actions

| Action | Admin | Teacher | Notes |
|--------|-------|---------|-------|
| **Student Management** |
| Approve registration | ✅ | ✅ | |
| Reject registration | ✅ | ✅ | |
| Suspend student | ✅ | ✅ | |
| Activate student | ✅ | ✅ | |
| Change student type | ✅ | ✅ | Public ↔ Center |
| Assign membership plan | ✅ | ✅ | |
| Reset student password | ❌ | ✅ | Teacher (Platform Owner) has full authority. Admin may reset student passwords only when explicitly granted the password_reset permission by the Teacher. |
| Replace student device | ✅ | ✅ | |
| View student progress | ✅ | ✅ | |
| View student analytics | ✅ | ✅ | |
| **Content Management** |
| Create subject | ✅ | ✅ | |
| Edit subject | ✅ | ✅ | |
| Delete subject (soft) | ✅ | ✅ | |
| Create section | ✅ | ✅ | |
| Edit section | ✅ | ✅ | |
| Delete section (custom) | ✅ | ✅ | System sections: hide only |
| Create lecture | ✅ | ✅ | |
| Edit lecture | ✅ | ✅ | |
| Publish lecture | ✅ | ✅ | |
| Archive lecture | ✅ | ✅ | |
| Upload video (Bunny CDN) | ✅ | ✅ | Enter video_id in Dashboard |
| Upload PDF | ✅ | ✅ | |
| Upload attachment | ✅ | ✅ | |
| Configure lecture access | ✅ | ✅ | |
| Reset watch attempts | ✅ | ✅ | |
| **Quiz & Exam Management** |
| Create timeline quiz | ✅ | ✅ | |
| Edit timeline quiz | ✅ | ✅ | |
| Create exam | ✅ | ✅ | |
| Edit exam | ✅ | ✅ | |
| Publish exam | ✅ | ✅ | |
| Grade essay questions | ✅ | ✅ | |
| Configure exam security | ✅ | ✅ | |
| **Question Management** |
| Create question bank item | ✅ | ✅ | |
| Edit question bank item | ✅ | ✅ | |
| **Communication** |
| Reply to student questions | ✅ | ✅ | |
| Send broadcast answer | ✅ | ✅ | |
| Chat with students | ✅ | ✅ | |
| Publish Doctor announcement | ❌ | ✅ | Teacher only |
| Create poll | ❌ | ✅ | Teacher only |
| Schedule announcement | ❌ | ✅ | Teacher only |
| **Notification Management** |
| Create notification template | ✅ | ✅ | |
| Send notification | ✅ | ✅ | |
| Schedule notification | ✅ | ✅ | |
| Configure notification rules | ✅ | ✅ | |
| **Membership & Monetization** |
| Configure Feature Matrix | ❌ | ✅ | Teacher only |
| Configure plan pricing | ❌ | ✅ | Teacher only |
| Create promo code | ❌ | ✅ | Teacher only |
| Log payment | ❌ | ✅ | Teacher only |
| View payment logs | ✅ | ✅ | Admin: view only |
| **Platform Settings** |
| Configure system settings | ❌ | ✅ | Teacher only |
| Enable/disable registration | ❌ | ✅ | Teacher only |
| Enable/disable trial | ❌ | ✅ | Teacher only |
| Set maintenance mode | ❌ | ✅ | Teacher only |
| Manage admin accounts | ❌ | ✅ | Teacher only |
| **Analytics & Reports** |
| View platform analytics | ✅ | ✅ | Admin: limited |
| View business reports | ❌ | ✅ | Teacher only |
| View revenue reports | ❌ | ✅ | Teacher only |
| Export data | ❌ | ✅ | Teacher only |
| **Audit** |
| View audit logs | ✅ | ✅ | Admin: operational only |
| View security events | ✅ | ✅ | |
| View analytics events | ❌ | ✅ | Teacher only |

## 4.3 Permission Enforcement Layers

Permissions are enforced at multiple layers for defense in depth:

```
Layer 1: UI Layer (Flutter)
  → Widgets hide/disable actions based on role/claims
  → NOT a security boundary — UX convenience only

Layer 2: Application Logic (Riverpod / Use Cases)
  → Business logic validates permissions before execution
  → Returns PermissionFailure if denied

Layer 3: Cloud Functions
  → Server-side validation of all privileged operations
  → Rejects unauthorized requests with structured errors

Layer 4: Firestore Security Rules
  → Enforced by Firebase, cannot be bypassed
  → Uses Custom Claims for zero-read validation
  → The ONLY true security boundary

Layer 5: Firebase Storage Rules
  → Controls file access independently
  → Signed URLs generated server-side only

Layer 6: Bunny CDN
  → Token-authenticated, time-limited URLs
  → Quality/filtering enforced at URL generation time
```

---

# 5. Audit System

## 5.1 Audit Principles

- **Every significant action is logged.** (per 00 Master Architecture Section 7)
- **Logs are immutable.** Soft delete only; never hard delete audit records.
- **Logs are queryable.** Composite indexes support filtering by user, action type, date.
- **Logs are retained.** Minimum 2 years for compliance and dispute resolution.
- **Logs are tamper-evident.** Created by server-side Cloud Functions, not client writes.

## 5.2 Audit Event Types

### Authentication & Security Events

| Event | Collection | Logged By | Retention |
|-------|-----------|-----------|-----------|
| Login success | `analytics_events` | Cloud Function | 2 years |
| Login failure | `analytics_events` | Cloud Function | 2 years |
| Logout | `analytics_events` | Client + Server | 2 years |
| Password change | `analytics_events` + `password_reset_requests` | Cloud Function | 2 years |
| Password reset requested | `password_reset_requests` | Cloud Function | 2 years |
| Device bound | `devices` + `analytics_events` | Cloud Function | 2 years |
| Device unbound | `devices` + `analytics_events` | Cloud Function | 2 years |
| Unauthorized device attempt | `analytics_events` | Cloud Function | 2 years |
| Security violation detected | `security_events` (new) | Client + Server | 3 years |

### Administrative Events

| Event | Collection | Logged By | Retention |
|-------|-----------|-----------|-----------|
| Student approved | `analytics_events` | Cloud Function | 2 years |
| Student rejected | `analytics_events` | Cloud Function | 2 years |
| Student suspended | `analytics_events` | Cloud Function | 2 years |
| Student type changed | `analytics_events` | Cloud Function | 2 years |
| Membership plan changed | `analytics_events` + `plan_feature_audit_logs` | Cloud Function | 2 years |
| Device replaced | `analytics_events` | Cloud Function | 2 years |
| Content published | `analytics_events` | Cloud Function | 2 years |
| Content deleted (soft) | `analytics_events` | Cloud Function | 2 years |
| Exam graded | `analytics_events` | Cloud Function | 2 years |
| Payment logged | `payment_logs` + `analytics_events` | Cloud Function | 5 years |
| Notification sent | `notifications` + `analytics_events` | Cloud Function | 1 year |
| Feature Matrix changed | `plan_feature_audit_logs` | Cloud Function | 2 years |

### Learning Events

| Event | Collection | Logged By | Retention |
|-------|-----------|-----------|-----------|
| Subject opened | `analytics_events` | Client | 1 year |
| Lecture opened | `analytics_events` | Client | 1 year |
| Video played | `analytics_events` | Client | 1 year |
| Video completed | `analytics_events` | Client | 1 year |
| PDF opened | `analytics_events` | Client | 1 year |
| Quiz started | `analytics_events` | Client | 1 year |
| Quiz submitted | `analytics_events` | Client | 1 year |
| Exam started | `analytics_events` | Client | 1 year |
| Exam submitted | `analytics_events` | Client | 1 year |
| Note created | `analytics_events` | Client | 1 year |
| Bookmark created | `analytics_events` | Client | 1 year |
| Question submitted | `analytics_events` | Client | 1 year |
| Chat message sent | `analytics_events` | Client | 1 year |

## 5.3 Audit Log Schema

All audit events share a common schema (extends `analytics_events` from 05 Database):

```
analytics_events (existing collection)
├── id: String (UUID)
├── user_id: String
├── event_type: String (from enum)
├── reference_id: String (document ID of affected resource)
├── metadata: Map<String, dynamic> (event-specific details)
├── device_id: String
├── ip_address: String (Cloud Function only)
├── user_agent: String (Web only)
├── created_at: Timestamp
├── created_by: String (server: "system", client: user_id)
```

### Security Events Schema (new collection)

```
security_events
├── id: String (UUID)
├── user_id: String
├── event_type: String (screenshot, screen_record, jailbreak, emulator, device_mismatch, etc.)
├── severity: String (low, medium, high, critical)
├── context: Map (lecture_id, video_timestamp, pdf_page, etc.)
├── device_info: Map (model, os_version, app_version)
├── screenshot_detected: Boolean
├── screen_record_detected: Boolean
├── action_taken: String (warning, pause, stop, logout, notify_admin)
├── created_at: Timestamp
```

## 5.4 Audit Log Access

| Role | Access Level |
|------|-------------|
| Teacher (Platform Owner) | Full access to all audit logs |
| Admin | Operational audit logs (auth, content, notifications) — no payment/revenue logs |
| Student | Own learning events only (via personal analytics screen) |
| System | Automated monitoring, alerting, and compliance exports |

## 5.5 Audit Alerts

Automated alerts are triggered for:

| Condition | Severity | Notification |
|-----------|----------|--------------|
| > 5 unauthorized device attempts in 1 hour | High | Admin + Teacher push + in-app |
| Security score > threshold | Medium | Admin in-app |
| Payment log anomaly | High | Teacher push + in-app |
| Feature Matrix changed | Low | Teacher in-app |
| Student type conversion | Medium | Admin in-app |
| Failed login > 10 attempts / user / hour | Medium | Admin in-app |

---

# 6. Implementation Checklist

### Feature Matrix Implementation

- [ ] `plan_features` collection seeded with default values for all 4 plans.
- [ ] Dashboard UI for viewing and editing Feature Matrix.
- [ ] `plan_feature_audit_logs` collection created with composite index.
- [ ] Cloud Function `getFeatureMatrix(plan_id)` returns merged features (plan + overrides).
- [ ] Flutter: `featureMatrixProvider` reads and caches features per plan.
- [ ] Flutter: `hasFeature(featureKey)` utility checks Feature Matrix before enabling UI.

### Permission Matrix Implementation

- [ ] Firestore Security Rules enforce all permissions from Section 4.2.
- [ ] Cloud Functions validate permissions server-side for all privileged operations.
- [ ] Flutter: Route guards prevent navigation to unauthorized screens.
- [ ] Flutter: Widgets conditionally render based on role + Feature Matrix.
- [ ] Admin Dashboard enforces "Teacher only" actions via UI + backend.

### Audit System Implementation

- [ ] `security_events` collection created with composite indexes.
- [ ] All Cloud Functions write `analytics_events` on completion.
- [ ] Client-side analytics batching (queue + flush) to reduce writes.
- [ ] Audit log viewer in Admin Dashboard (filtered by type, date, user).
- [ ] Automated alert Cloud Function (`processAuditAlerts`).
- [ ] Data retention Cloud Function (archive old events per retention policy).

---

# 7. Open Items

- [ ] Confirm `security_events` collection addition to 05 Database schema.
- [ ] Confirm `plan_feature_audit_logs` collection addition to 05 Database schema.
- [ ] Define exact security score thresholds for alerts.
- [ ] Confirm data retention periods (proposed: learning 1yr, auth 2yr, security 3yr, payment 5yr).
- [ ] Design audit log viewer UI — depends on 03 UI & UX.
- [ ] Confirm if GDPR/privacy compliance requires additional audit fields (consent, data portability).
- [ ] Define export format for audit logs (CSV, JSON, PDF report).

---

END OF DOCUMENT
