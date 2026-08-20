# 00 MASTER ARCHITECTURE

# Dr. Tarek Platform

## Single Source of Truth

Version: 1.2
Status: Approved

## Version History

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
- Device Binding enabled.
- Subject-based educational structure.
- Firebase is the backend.
- Bunny CDN is used for video delivery.
- Monetization rules exist only in the Monetization document.
- Subject-based membership plans.
- Device limit per student is plan-based (default: 1 device for Free/Pro; 2+ for Center Max, configurable from Dashboard — see FINAL_DECISIONS Section 1 and 05 Database Section 14/19).
- Academic Year and Term are administrative only.
- Students only browse Subjects.
- Feature availability is controlled from Firestore.
- Every user action is logged as an Analytics Event.
- Course price is paid externally (outside the application) in Version 1. Payment logs are recorded manually by Admin/Teacher for record-keeping only (see `payment_logs` in 05 Database).
- Online payment methods are deferred to a future release (see 02 PRD, Version 1.2 — Payment Integration).

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