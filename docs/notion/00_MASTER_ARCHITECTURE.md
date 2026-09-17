# 00 MASTER ARCHITECTURE

# Dr. Tarek Platform

## Single Source of Truth

Version: 2.0
Status: Approved

## Version History

- **2.0** (2026-09-14): Major architectural change to Subject-Level Device Binding (ADR-004). Supersedes the previous account-level device-binding/login-rejection model. Authentication is account-level and never rejected for device reasons; device authorization is evaluated per Student + Subject + Device on first actual subject access; each Subject independently consumes its own subscription's device allowance; Guest/limited access never mutates the subscription; identity claims are de-scoped from Subject-specific authorization. See Section 7.1 and Section 5.3 (ADR-004). Other documents are not rewritten in this step and must be aligned in follow-up steps per the project workflow.
- **1.2** (2026-08-04): Clarified "One active device per student" (Section 7) to reflect the plan-based device policy — this bullet, taken literally, contradicted the Center Max plan's 2+ device allowance already documented in 05 Database and 04 Features, and confirmed in FINAL_DECISIONS Section 1. The rule is now stated as plan-configurable, not a fixed single-device rule. Also updated 01 Project Vision (v2.0) and 02 PRD (v1.3) to remove the Offline Learning V1/future-scope conflict.
- **1.1** and earlier: see prior revisions.

---

# 1. Project Identity

## Product Name

Dr. Tarek Platform

## Product Type

Educational Learning Management System (LMS)

## Target

University Students

## Platforms

- Android
- iOS
- Web

---

# 2. Project Goal

Build an enterprise-grade educational platform that delivers a secure, organized, and scalable learning experience.

The project must remain maintainable and scalable for many years without requiring architectural redesign.

---

# 3. Technology Stack

## Frontend

- Flutter
- Material 3
- Riverpod

## Backend

- Firebase Authentication
- Cloud Firestore
- Firebase Storage
- Firebase Cloud Messaging

## Video

- Bunny CDN

## Design

- Figma

## IDE

- VS Code

---

# 4. Architecture

The project follows:

- Clean Architecture
- Feature-First Architecture
- Repository Pattern
- Dependency Injection
- Reusable Components
- Single Source of Truth

---

# 5. Project Rules

- One responsibility per document.
- Never duplicate information.
- Never regenerate completed documents.
- Discuss architectural changes before applying them.
- UI contains no business logic.
- Widgets never access Firestore directly.
- All data passes through Repositories.
- Every feature must be reusable.
- Mobile First.
- All premium features are controlled from database.
- No hardcoded business rules.
- All permissions are data-driven.

---

# 5.1 Documentation Governance

## Documentation Versioning

- Every document maintains its own version number.
- Minor documentation improvements increment the minor version.
- Architectural changes increment the major version.
- Every version update must include a documented reason.

## Document Status

Every document must have one of the following statuses:

- Draft
- In Review
- Approved
- Deprecated
- Archived

Only **Approved** documents may be used as implementation references.

## Change Management

Architectural decisions may only be modified after:

- Clear justification
- Impact analysis
- Cross-document consistency review
- Version increment

No architectural change may be applied silently.

---

# 5.2 Architecture Decision Records (ADR)

Major architectural decisions must be documented as Architecture Decision Records.

Each ADR must contain:

- Decision
- Context
- Alternatives Considered
- Consequences
- Status
- Date
- Version

Architectural decisions become permanent references unless officially superseded.

# 5.3 Architecture Decision Records History

## ADR-004 — Subject-Level Device Binding

- **Decision:** Authentication is account-level and never fails for device reasons. Device authorization is subject-level, evaluated per Student + Subject + Device on first actual subject access. Each Subject independently consumes the device allowance of that Subject's own active subscription plan (Free = 1, Pro = 1, Max = 2 for that Subject). A device authorized for one Subject is not automatically authorized for another. An authenticated student on an unauthorized device keeps a successful login and receives Guest/limited access for that Subject without mutating the subscription. Max means two authorized devices for the Subject plus a single active playback session with continuity from the saved resume position, not concurrent playback. Identity claims stay limited to identity-level information such as role, student type, and approval status; Subject subscription and Subject-Device authorization are resolved from the server-side source of truth. The five concepts of Account Authentication, Device Registry, Subject-Device Authorization, Subject Subscription, and Active Playback Session are architecturally separate.
- **Context:** The previously approved documentation used an account-level device-binding model in which the first login bound the whole account to a device and a new device caused the entire login to be rejected pending Admin action. The Teacher approved the prior impact analysis and then resolved that login must succeed from any device, that membership belongs to the Subject with possibly different plans per Subject, that each Subject enforces its own allowance, that Guest is a non-mutating limited tier, and that Max provides continuity with single-session playback. The prior model could not represent a student with different plans and different authorized devices per Subject.
- **Alternatives Considered:** (1) Retain the account-level binding and login-rejection model and only raise the global device limit. Rejected because it cannot express per-Subject allowances, forces a valid login to fail, and contradicts the approved per-Subject examples. (2) Treat Guest as a subscription-plan change or downgrade on the unauthorized device. Rejected because the Teacher resolved that Guest must never mutate the underlying subscription. (3) Interpret the highest plan as a global device pool granting higher allowances to lower-plan Subjects. Rejected because the Teacher resolved that each Subject independently consumes its own plan allowance. (4) Define exact Guest minute values, exact user-facing wording, storage mechanisms for reset, session-transport mechanisms, and fingerprint algorithms in Master Architecture. Deferred because Master Architecture records business and architectural decisions, while those implementation details belong to their owning documents under the project workflow.
- **Consequences:** The previous account-level device-binding and login-rejection model is superseded and must not be used as an implementation reference. Other documents that describe login rejection, first-login account binding, a single global plan display, single-plan authorization claims, or global device replacement still conflict with this decision and must be aligned one document at a time without silently resolving contradictions. No database schema, collection design, Flutter structure, Cloud Function behavior, rule design, or code is introduced by this ADR.
- **Status:** Approved.
- **Date:** 2026-09-14.
- **Version:** Master Architecture 2.0.

# 6. User Roles

- New Student
- Current Student
- Teacher (Platform Owner)
- Admin

Permissions are defined inside the PRD and Features documents.

## 6.1 Display Name vs. Enum Value

Per ADR-002, every role has a Business Display Name (used in Vision, PRD, personas, UI copy) and a Technical Enum Value (used in Database, Firestore Security Rules, and code). A mismatch between the two is expected and correct — this table is the single authoritative mapping.

| Display Name | Enum Value (`users.role`) |
| --- | --- |
| New Student | `new_student` |
| Current Student | `student` |
| Teacher (Platform Owner) | `teacher` |
| Admin | `admin` |

Any future role or type introduced into the platform must add a row to this table at the time it is introduced. See ADR-001 for the history of this correction (the role was previously, incorrectly, documented as `Owner` in this document and in 05 Database).

---

# 7. Fixed Business Decisions

- Manual student approval.
- Subject-Level Device Binding enabled (see Section 7.1 and ADR-004). The previous account-level device-binding/login-rejection model is superseded and must not be used.
- Subject-based educational structure.
- Firebase is the backend.
- Bunny CDN is used for video delivery.
- Monetization rules exist only in the Monetization document.
- Subject-based membership plans. A student may hold different plans for different Subjects. No single global subscription plan is displayed for the student; each Subject displays its own plan indicator (Free / Pro / Max).
- Device authorization is subject-level and plan-based per Subject: Free = 1 authorized device for that Subject; Pro = 1 authorized device for that Subject; Max = 2 authorized devices for that Subject. A device authorized for one Subject is not automatically authorized for another Subject. Each Subject independently consumes the device allowance of that Subject's own active subscription plan. A higher plan on one Subject never grants a higher device allowance to another Subject.
- Account authentication never fails for device reasons. A valid student may log in from any device; device authorization affects the Subject access tier (full vs Guest/limited), never the success of the account login.
- Academic Year and Term are administrative only.
- Students only browse Subjects.
- Feature availability is controlled from Firestore.
- Every user action is logged as an Analytics Event.
- Course price is paid externally (outside the application) in Version 1. Payment logs are recorded manually by Admin/Teacher for record-keeping only (see `payment_logs` in 05 Database).
- Online payment methods are deferred to a future release (see 02 PRD, Version 1.2 — Payment Integration).
- Subscriptions are term-based. When the academic term ends, the relevant subscriptions stop according to the existing subscription lifecycle rules. No separate device behavior is defined for end of term beyond what the subscription lifecycle requires.

---

# 7.1 Subject-Level Device Binding Principles

This section records Teacher-approved business and architectural rules only. It defines no database schema, no collection or field design, no Flutter structure, no Cloud Function behavior, and no session-transport mechanism. Those details belong to their owning documents and later workflow steps.

## 7.1.1 Account Authentication

- Authentication is account-level.
- The student's phone number remains the primary V1 identity and authentication identifier.
- No separate student-number field is used as the student's system identity.
- Any serial number shown in an Admin or Dashboard student list is a list and display sequence only, not the student's system identity.
- A valid approved student may log in from any device.
- Device authorization must never reject the account login.

## 7.1.2 Subject-Level Subscription

- Membership and subscription belong to the Subject.
- A student may hold different plans for different Subjects at the same time.
- The student's plan is evaluated per Subject.
- The application must not present one global subscription plan for the student.
- In the student's profile, each Subject displays its own plan indicator reflecting that Subject's actual subscription (Free / Pro / Max).

## 7.1.3 Subject-Device Authorization

- Device authorization is evaluated per Student + Subject + Device.
- A device authorized for one Subject is not automatically authorized for another Subject.
- Authorization is established on first actual access to the Subject, not merely on account login.

## 7.1.4 Guest / Limited Access

- Guest is an access tier for the current device on a Subject. It is not a subscription plan and it never upgrades, downgrades, or otherwise mutates the student's underlying subscription for that Subject.
- When the student is authenticated and may access a Subject, but the current device is not authorized for full access to that Subject, the account login still succeeds and the student may enter the Subject with Guest/limited access for that Subject.
- Guest may watch only a predefined limited amount of video content, configured in advance for limited viewing of one video or a limited number of videos. Exact amounts and exact user-facing wording are not defined in this document.
- Guest cannot download protected content.
- Guest cannot access protected PDFs and protected resources.
- Guest cannot receive full premium content access.

## 7.1.5 Max Plan Continuity

- Max provides two authorized devices for the Subject.
- Max is intended primarily to provide device continuity across two authorized devices for the same Subject.
- The same Subject content must not play concurrently on both authorized devices.
- If content is playing on one authorized device and the student starts the same content on the other authorized device, playback on the first device must stop and playback must continue on the second device. The reverse applies identically.
- The student continues from the saved resume position.
- The technical transport and session mechanism for this behavior is not defined in this document.

## 7.1.6 Device Identity and Registry

- The platform identifies devices independently from the student's phone number.
- Device records support recognizing a previously known device and include device metadata needed for later identification and audit, such as device type and platform, device identity and fingerprint information, IP information, and other relevant device metadata.
- IP address is metadata only and must not be treated as the sole permanent device identity because it can change.
- Stable device identification follows the existing Development Standards. No new fingerprint algorithm is defined in this document.

## 7.1.7 Authorization Sources

- Identity and general authorization claims remain limited to identity-level information such as role, student type, and approval status.
- Subject-specific plan, device allowance, subscription status, and Subject-Device authorization and tier must not rely on claims as the authoritative source and must be resolved from the server-side source of truth. Claim, index, rule, and caching design belong to the owning documents.

## 7.1.8 Device Reset and Lost Device

- When the Teacher or an authorized Admin performs the approved Device Reset for a student, existing device-binding and authorization data is cleared according to the approved reset operation, the old bindings are no longer considered authorized, the student is not blocked from logging in, the student starts a new device-binding cycle from scratch, and the first new device is eligible to become authorized again under the Subject-level authorization rules. Whether that operation uses physical deletion, soft deletion, or another storage mechanism is not defined in this document.
- If a student's device is lost without such an action, nothing happens automatically merely because the device was lost and no automatic global unbind occurs. Intervention occurs only when the student requests it and the Teacher or authorized Admin performs the approved reset or management action.

## 7.1.9 Architectural Separation

The following are separate concepts and must not be conflated:

- Account Authentication: proving the student's account identity at login.
- Device Registry: recognizing known devices and retaining device metadata for identification and audit.
- Subject-Device Authorization: deciding whether a given device has full or Guest/limited access to a given Subject.
- Subject Subscription: the per-Subject membership plan and lifecycle governing what full access means for that Subject.
- Active Playback Session: the single-device continuity rule for content playback on a Max Subject.

---

# 8. Design Principles

- Mobile First
- Material 3
- White-based UI
- Minimal Design
- Consistent Components
- Reusable UI
- Accessibility First
- Responsive Layouts

Figma is the only visual source of truth.

---

# 9. Coding Principles

- Feature First
- Small Widgets
- Reusable Components
- Strong Typing
- SOLID Principles
- Separation of Concerns
- No duplicated code

# 9.1 Documentation Principles

The documentation follows the following principles:

- Single Source of Truth
- No duplicated information
- Cross-document references instead of copied content
- Clear ownership for every document
- Consistent terminology across the project

Every piece of information must exist in only one document.

Whenever information belongs to another document, only a reference should be written.

Duplicated architectural information is considered a documentation defect.

---

# 9.2 Naming Standards

The following naming conventions are mandatory across the project.

## Collections

snake_case

Example

users

learning_progress

timeline_quizzes

## Fields

snake_case

Example

created_at

updated_at

subject_id

video_url

## Feature Keys

dot.notation

Example

lecture.video.download

lecture.video.preview

subscription.freeze

subscription.upgrade

notification.push

analytics.event

---

# 10. Database Principles

- UUID IDs
- Soft Delete
- Audit Fields
- Timestamp Fields
- Consistent Collection Naming
- Feature Flags supported.
- Analytics-first architecture.
- Firestore optimized queries.

Database details belong only to the Database document.

---

# 11. Firebase Principles

Services used:

- Authentication
- Firestore
- Storage
- Cloud Messaging

Implementation details belong only to the Firebase document.

# 11.1 Version Compatibility

Every architectural document must remain compatible with:

- Master Architecture
- Project Vision
- Product Requirements (PRD)
- Features
- Database
- Firebase Architecture
- Flutter Architecture
- Development Standards

Whenever a conflict exists between documents:

1. Master Architecture
2. Project Vision
3. Product Requirements (PRD)
4. Features
5. Database
6. Firebase
7. Flutter Architecture
8. Development Standards

The conflict must be resolved before implementation begins.

---

# 12. Documentation Structure

00 Master Architecture
Project rules and permanent architectural decisions.

01 Project Vision
Business vision only.

02 Product Requirements (PRD)
Product requirements only.

03 UI & UX
User experience and interface specifications.

04 Features
Complete feature specifications.

05 Database
Database design.

06 Firebase
Firebase architecture.

07 Flutter Architecture
Flutter project architecture.

08 Development Standards
Coding standards.

09 Tasks
Development tasks.

10 Bugs
Bug tracking.

11 Assets
Project assets.

12 AI Prompts
AI prompts.

13 Releases
Release history.

14 Platform Availability, Feature Matrix, Permission Matrix & Audit System

15 Admin Permissions & Audit System

99 Archive
Archived documents.

---

# 13. Current Status

Completed

- Project Vision
- Product Requirements (PRD)
- Features
- Database

---

# 14. AI Instructions

Every AI working on this project must follow these rules.

- Read this document first.
- Treat this document as the architectural reference.
- Never rewrite completed documents.
- Work on one document at a time.
- Do not duplicate information between documents.
- Do not change architectural decisions without justification.
- Follow the current Figma design.
- Keep all documents consistent.
- Never invent business rules.
- Never infer missing requirements.

---

# 15. Working Workflow

Every contributor (human or AI) must follow this workflow.

1. Read Master Architecture.
2. Verify existing architectural decisions.
3. Read only the current document.
4. Identify architectural conflicts.
5. Resolve conflicts before making changes.
6. Review the latest approved Figma design if UI work is involved.
7. Complete the current document.
8. Update cross-document references if necessary.
9. Increment the document version when applicable.
10. Never duplicate information across documents.
11. Never modify approved architectural decisions without documented justification.
12. All technical documentation must be written in English.
13. Explanations provided to the project owner are written in Arabic.

---

# 15.1 Project Lifecycle

The project follows a fixed lifecycle.

Planning

↓

Architecture

↓

Documentation

↓

UI / UX Design

↓

Implementation

↓

Testing

↓

Release

↓

Maintenance

↓

Future Expansion

Every phase must be completed before progressing to the next unless explicitly approved.

# 16. Project Objective

The final objective is to produce documentation that allows any professional AI assistant to build the entire Flutter application with minimal ambiguity and without making architectural or design decisions independently.