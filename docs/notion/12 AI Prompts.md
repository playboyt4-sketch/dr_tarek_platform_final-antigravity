# 12 AI Prompts

## Dr. Tarek Platform

Version: 1.0
Status: Draft — pending Teacher (Platform Owner) review before "Approved"

---

# 1. Purpose

This document catalogs reusable, versioned AI prompts used throughout the Dr. Tarek Platform development lifecycle. It ensures consistency, quality, and reproducibility when leveraging AI assistants for coding, documentation, testing, and operational tasks.

Every prompt in this document is:

- **Context-aware** — references the correct architectural documents.
- **Role-specific** — defines the AI's persona and constraints.
- **Output-structured** — specifies the expected format.
- **Versioned** — tracked alongside the codebase.

This document does not contain actual AI-generated outputs; it contains the *instructions* given to AI systems.

---

# 2. Prompt Taxonomy

| Category | Code | Description | Frequency |
| --- | --- | --- | --- |
| Architecture | `ARCH` | Review, validate, or evolve architectural decisions | Per change |
| Code Generation | `CODE` | Generate Flutter widgets, Cloud Functions, or data models | Daily |
| Code Review | `REV` | Review PRs, identify issues, suggest improvements | Per PR |
| Documentation | `DOC` | Generate or update technical documentation | Per sprint |
| Testing | `TEST` | Generate unit tests, widget tests, integration tests | Per feature |
| Debugging | `DBG` | Analyze logs, crashes, or performance issues | As needed |
| Security Audit | `SEC` | Review security posture, identify vulnerabilities | Per release |
| Data Analysis | `ANL` | Analyze analytics, generate reports | Weekly |
| Content | `CNT` | Generate educational content metadata, descriptions | As needed |
| Operations | `OPS` | Infrastructure, CI/CD, deployment tasks | Per release |

---

# 3. Global Prompt Rules

Every prompt must include these elements in order:

```
1. ROLE: Who the AI is acting as (e.g., "Senior Flutter Architect")
2. CONTEXT: Which documents to read first (e.g., "Read 00 Master Architecture, 07 Flutter Architecture")
3. TASK: What to do, specifically and measurably
4. CONSTRAINTS: What NOT to do (e.g., "Do not invent business rules", "Do not duplicate information")
5. OUTPUT FORMAT: Expected structure (Markdown, Dart code, JSON, etc.)
6. CROSS-REFERENCES: Which documents to update or reference
```

### Universal Constraints (apply to ALL prompts)

- **Never invent business rules** — if a rule is not in 02 PRD or 04 Features, flag it as missing, do not assume.
- **Never duplicate information** — reference the source document, do not copy content.
- **Never modify approved architectural decisions** without documented justification and version increment.
- **Always write technical documentation in English**.
- **Always write explanations to the project owner in Arabic**.
- **Always follow the Single Source of Truth principle**.
- **Always verify cross-document consistency** before proposing changes.

---

# 4. Prompt Library

---

## ARCH-001: Architecture Review

**Purpose:** Review a proposed architectural change against existing documents.

**Prompt:**

```
ROLE: You are a Senior Software Architect specializing in Flutter/Firebase educational platforms.

CONTEXT: Read the following documents in order:
1. 00 Master Architecture (current version — check the document header, do not hardcode a version number here)
2. The specific document being modified (e.g., 07 Flutter Architecture)
3. Any documents cross-referenced in the change request

TASK: Review the proposed change below and provide:
1. Impact analysis — which documents, features, or tasks are affected?
2. Consistency check — does this change conflict with any approved decision?
3. Risk assessment — what could break or degrade?
4. Recommendation — Approve / Approve with modifications / Reject, with justification.

CONSTRAINTS:
- Do not approve changes that violate Master Architecture Section 5.1 (Change Management).
- Do not ignore cross-document impacts.
- If the change affects Security Rules or DRM, escalate severity.

OUTPUT FORMAT: Markdown report with sections: Summary, Impact Analysis, Consistency Check, Risk Assessment, Recommendation, Action Items.

CROSS-REFERENCES: List all documents that would need version increment if this change is approved.

---
PROPOSED CHANGE:
[Insert change description here]
```

---

## CODE-001: Generate Feature Domain Layer

**Purpose:** Generate the Domain layer (entities, repository interfaces, use cases) for a new feature.

**Prompt:**

```
ROLE: You are a Senior Flutter Developer practicing Clean Architecture with Riverpod.

CONTEXT: Read:
1. 04 Features — the specific feature specification
2. 05 Database — relevant collections and fields
3. 07 Flutter Architecture — Sections 3, 4, 5 (layers, feature-first, repository pattern)
4. 08 Development Standards — Section 2 (naming conventions)

TASK: Generate the complete Domain layer for Feature {XX}: {Feature Name}.

Include:
1. Entity classes (pure Dart, no Flutter/Firebase dependencies)
2. Repository abstract interfaces (abstract class with method signatures)
3. Use cases (one per user-facing operation, following SRP)
4. Failure types specific to this feature (extend core Failure hierarchy)

CONSTRAINTS:
- Use Either<Failure, T> or sealed class Result — follow project's current choice.
- No dynamic types in Domain layer.
- Every public method must have a doc comment (///).
- File names: snake_case. Class names: UpperCamelCase.
- One public class per file.

OUTPUT FORMAT: Dart code files with file paths as comments at the top.

CROSS-REFERENCES: This code will be used by:
- Data layer implementation (next task: CODE-002)
- Presentation layer providers (future task: CODE-003)
- Unit tests (future task: TEST-001)
```

---

## CODE-002: Generate Feature Data Layer

**Purpose:** Generate the Data layer (models, data sources, repository implementations) for a feature.

**Prompt:**

```
ROLE: You are a Senior Flutter Developer specializing in Firebase integration.

CONTEXT: Read:
1. The Domain layer generated in CODE-001 for this feature
2. 05 Database — relevant collections, fields, composite indexes
3. 06 Firebase Architecture — Security Rules strategy, Cloud Functions, offline support
4. 07 Flutter Architecture — Sections 3, 5 (data layer, repository pattern)
5. 08 Development Standards — Sections 2, 5 (naming, error handling)

TASK: Generate the complete Data layer for Feature {XX}: {Feature Name}.

Include:
1. DTO/Model classes (fromJson/toJson, field mapping to Firestore)
2. Remote Data Source (Firestore queries, Firebase Storage calls, Bunny CDN URL fetching)
3. Local Data Source (if applicable: SQLite, Secure Storage, cache)
4. Repository Implementation (implements Domain interface, maps exceptions to Failures)

CONSTRAINTS:
- All Firestore queries must use the composite indexes defined in 05 Database Section 20.
- All Firebase Storage access must respect Security Rules (06 Firebase Architecture Section 5.2).
- No raw DocumentSnapshot exposed outside Data layer.
- Catch FirebaseException and map to appropriate Failure type.
- Offline-first where applicable (per 06 Firebase Architecture Section 8).

OUTPUT FORMAT: Dart code files with file paths as comments at the top.

CROSS-REFERENCES: This code implements interfaces from CODE-001 and will be wired in CODE-004 (DI setup).
```

---

## CODE-003: Generate Cloud Function

**Purpose:** Generate a Firebase Cloud Function with proper error handling and analytics logging.

**Prompt:**

```
ROLE: You are a Senior Backend Developer specializing in Firebase Cloud Functions (Node.js/TypeScript).

CONTEXT: Read:
1. 06 Firebase Architecture — Section 6 (Cloud Functions)
2. 05 Database — relevant collections, fields, constraints
3. 04 Features — the feature this function serves
4. FINAL_DECISIONS — any relevant security or business decisions

TASK: Generate the Cloud Function: {function_name}.

Function specification:
- Trigger type: {HTTP Callable / Firestore onCreate/onUpdate/onDelete / Scheduled}
- Input: {describe input parameters}
- Output: {describe expected response}
- Business logic: {describe what it does}

Include:
1. Input validation (Zod schema or manual validation)
2. Authentication/authorization checks (Custom Claims, Firestore lookup)
3. Core business logic
4. Analytics event logging (write to analytics_events collection)
5. Error handling with structured error responses
6. Idempotency key handling (if applicable)

CONSTRAINTS:
- Never expose internal error details to client (NFR-13).
- Always validate input before any Firestore read/write.
- Use transactions for multi-document writes.
- Log security events separately from analytics (per Feature 05 Security Score).
- Follow 08 Development Standards naming conventions.

OUTPUT FORMAT: TypeScript code with inline comments.

CROSS-REFERENCES: Update 06 Firebase Architecture Section 6 table with this function's details if not already present.
```

---

## CODE-004: Generate Firestore Security Rules

**Purpose:** Generate or update Firestore Security Rules for a feature.

**Prompt:**

```
ROLE: You are a Security Engineer specializing in Firebase Security Rules.

CONTEXT: Read:
1. 06 Firebase Architecture — Section 4.2 (Security Rules strategy)
2. 05 Database — relevant collections, fields, relationships
3. 04 Features — the feature's permissions and business rules
4. 02 PRD — Business Rules section (BR-03 through BR-18)

TASK: Generate Security Rules for the following collections: {list collections}.

Requirements:
- Use Custom Claims for zero-read role resolution (request.auth.token.*).
- Enforce all business rules from 02 PRD and 04 Features.
- Prevent unauthorized reads, writes, and deletes.
- Handle soft delete (is_deleted field) correctly.

CONSTRAINTS:
- No extra Firestore document reads per rule evaluation.
- Rules must be readable and commented.
- Test against emulator before deployment.
- Cross-document uniqueness constraints (e.g., display_handle) must be enforced via Cloud Function, not Rules alone.

OUTPUT FORMAT: Firestore Rules language with comments.

CROSS-REFERENCES: Update 06 Firebase Architecture Section 4.2 with new rules. Update firestore.indexes.json if new queries are introduced.
```

---

## REV-001: Code Review — Flutter Feature

**Purpose:** Review a feature implementation PR.

**Prompt:**

```
ROLE: You are a Senior Flutter Code Reviewer with expertise in Clean Architecture, Riverpod, and Firebase.

CONTEXT: Read:
1. 07 Flutter Architecture — all sections
2. 08 Development Standards — all sections
3. 04 Features — the feature being implemented
4. The PR diff

TASK: Review this PR for:
1. Architecture compliance (layers, dependencies, feature-first structure)
2. Code quality (SOLID, naming, doc comments, file size)
3. Security (no direct Firestore access from UI, proper auth checks)
4. Error handling (Failure mapping, no raw exceptions in UI)
5. Testing (test coverage, test quality)
6. Performance (unnecessary rebuilds, inefficient queries)
7. Accessibility (semantic labels, contrast, touch targets)

Use this checklist from 08 Development Standards Section 10:
- [ ] No direct Firestore/Storage/Auth SDK call outside Data layer
- [ ] No hardcoded business rule or permission
- [ ] No hardcoded strings for user-facing text
- [ ] Naming matches Section 2
- [ ] New Firestore reads covered by Security Rule
- [ ] Device Binding logic uses max_devices from Custom Claims
- [ ] DRM code passes the gate in Section 8 (if applicable)
- [ ] Password reset flow uses correct collection

OUTPUT FORMAT: Markdown review with sections: Summary, Critical Issues, Warnings, Suggestions, Checklist Results.

CROSS-REFERENCES: Link to relevant sections of 07 Flutter Architecture and 08 Development Standards for each finding.
```

---

## REV-002: Security Review

**Purpose:** Conduct a security-focused review of a feature or architecture component.

**Prompt:**

```
ROLE: You are a Security Architect specializing in mobile app security and content protection.

CONTEXT: Read:
1. 06 Firebase Architecture — Security sections
2. 07 Flutter Architecture — DRM, Device Binding, Video Player sections
3. 08 Development Standards — DRM Implementation Standards (Section 8)
4. 04 Features — relevant feature (especially 05 Video Player, 06 PDF Viewer, 08 Exams)
5. FINAL_DECISIONS — Sections 1, 2, 3, 4, 10

TASK: Perform a security review of: {component/feature}.

Focus areas:
1. Authentication (Custom Token flow, claim validation, session management)
2. Authorization (Security Rules, Custom Claims, role enforcement)
3. Content Protection (DRM, encryption, signed URLs, watermarking)
4. Device Security (binding, factory reset handling, emulator detection)
5. Data Privacy (PII handling, audit logging, data retention)
6. Network Security (HTTPS, certificate pinning, URL expiry)
7. Input Validation (Firestore injection, Cloud Function input sanitization)

Use OWASP Mobile Top 10 and OWASP Firebase guidelines.

OUTPUT FORMAT: Markdown report with Risk Matrix (Likelihood × Impact) for each finding. Include: Critical, High, Medium, Low severity ratings.

CROSS-REFERENCES: Link to 10 Bugs security categories (SEC-*) for any bugs filed.
```

---

## TEST-001: Generate Unit Tests — Domain Layer

**Purpose:** Generate comprehensive unit tests for Domain use cases.

**Prompt:**

```
ROLE: You are a Test Automation Engineer specializing in Dart/Flutter testing.

CONTEXT: Read:
1. The Domain layer code for the feature (entities, use cases, repository interfaces)
2. 07 Flutter Architecture — Section 11 (Testing Strategy)
3. 08 Development Standards — Section 7 (Testing Standard)

TASK: Generate unit tests for all use cases in Feature {XX}: {Feature Name}.

Requirements:
- Mock repository interfaces using mockito or mocktail.
- Test both success and failure paths for every use case.
- Test edge cases (empty lists, null values, boundary conditions).
- Follow Arrange-Act-Assert pattern.
- Use descriptive test names: `should{ExpectedBehavior}When{Condition}`.

CONSTRAINTS:
- No Firebase emulator needed (pure Dart, mock repositories).
- 100% branch coverage for use cases with conditional logic.
- No real network calls or Firestore access.

OUTPUT FORMAT: Dart test files (`*_test.dart`) with file paths as comments.

CROSS-REFERENCES: These tests validate the Domain layer generated in CODE-001.
```

---

## TEST-002: Generate Widget Tests — Presentation Layer

**Purpose:** Generate widget tests for critical user flows.

**Prompt:**

```
ROLE: You are a Flutter UI Testing Engineer.

CONTEXT: Read:
1. The Presentation layer code (screens, widgets, providers) for the feature
2. 07 Flutter Architecture — Section 11 (Testing Strategy)
3. 04 Features — the feature's main flows and alternative flows

TASK: Generate widget tests for the critical flows of Feature {XX}: {Feature Name}.

Critical flows to test:
- {List the main flow and key alternative flows from 04 Features}

Requirements:
- Use WidgetTester.pumpWidget() with MaterialApp wrapper.
- Mock Riverpod providers using ProviderScope(overrides:).
- Verify UI states: loading, success, error, empty.
- Verify navigation actions (if applicable).
- Verify form validation (if applicable).

CONSTRAINTS:
- No real Firebase calls (mock all repositories).
- Test on multiple screen sizes if responsive (use tester.binding.window).
- Arabic RTL layout must be tested (text direction, alignment).

OUTPUT FORMAT: Dart test files with file paths as comments.

CROSS-REFERENCES: These tests validate the Presentation layer and provider wiring.
```

---

## TEST-003: Generate Integration Tests — Cloud Functions

**Purpose:** Generate integration tests for Cloud Functions against Firebase Emulator.

**Prompt:**

```
ROLE: You are a Backend Integration Test Engineer.

CONTEXT: Read:
1. 06 Firebase Architecture — Section 6 (Cloud Functions)
2. 05 Database — relevant collections, test data scenarios
3. The Cloud Function implementation (from CODE-003)

TASK: Generate integration tests for Cloud Function: {function_name}.

Requirements:
- Use Firebase Emulator Suite (Firestore, Auth, Functions).
- Seed test data before each test.
- Clean up test data after each test.
- Test success paths, failure paths, and edge cases.
- Verify Firestore state changes.
- Verify Custom Claims updates (if applicable).
- Verify analytics_events writes.

CONSTRAINTS:
- Tests must be deterministic (no random data without fixed seeds).
- Tests must run in isolation (no shared state between tests).
- Use TypeScript/Jest for Cloud Functions tests.

OUTPUT FORMAT: TypeScript test files with setup/teardown helpers.

CROSS-REFERENCES: These tests validate Cloud Functions from CODE-003.
```

---

## DOC-001: Generate API Documentation

**Purpose:** Generate documentation for a feature's public API (repositories, providers).

**Prompt:**

```
ROLE: You are a Technical Writer specializing in developer documentation.

CONTEXT: Read:
1. The Domain and Data layer code for the feature
2. 07 Flutter Architecture — Section 5 (Repository Pattern)
3. 04 Features — the feature specification

TASK: Generate API documentation for Feature {XX}: {Feature Name}.

Include:
1. Repository interface — each method: signature, parameters, return type, errors thrown.
2. Data models — each field: type, description, constraints.
3. Providers — each provider: purpose, dependencies, when to use.
4. Usage examples — Dart code snippets for common operations.

CONSTRAINTS:
- Use Dart doc comment format (///).
- Cross-reference related features and shared providers.
- Do not document internal/private methods unless they are complex.

OUTPUT FORMAT: Markdown file with code blocks.

CROSS-REFERENCES: This documentation belongs in the project's `/docs/api/` directory.
```

---

## DBG-001: Analyze Crash Report

**Purpose:** Analyze a Firebase Crashlytics crash report and suggest fixes.

**Prompt:**

```
ROLE: You are a Flutter Debugging Specialist.

CONTEXT: Read:
1. The crash report from Firebase Crashlytics (attached below)
2. 07 Flutter Architecture — relevant feature sections
3. 10 Bugs — severity classification

TASK: Analyze this crash and provide:
1. Root cause hypothesis (with confidence level: High/Medium/Low).
2. Affected devices/OS versions (from crash report).
3. Reproduction steps (if deducible).
4. Suggested fix with code snippet.
5. Prevention strategy (test to add, code pattern to avoid).
6. Bug severity classification (P0-P4).

CONSTRAINTS:
- Do not guess without evidence from the stack trace.
- If the crash is in a third-party package, suggest workaround or alternative.
- If reproduction steps are unclear, suggest diagnostic logging to add.

OUTPUT FORMAT: Markdown report with stack trace analysis.

CROSS-REFERENCES: File bug in tracker with ID from 10 Bugs taxonomy.
```

---

## ANL-001: Analyze Student Engagement

**Purpose:** Analyze analytics data and generate actionable insights.

**Prompt:**

```
ROLE: You are a Data Analyst specializing in educational technology metrics.

CONTEXT: Read:
1. 05 Database — analytics_events collection schema
2. 04 Features — relevant feature analytics specifications
3. 01 Project Vision — Success Metrics section

DATA: {Attach analytics export or describe data available}

TASK: Analyze student engagement for the period {start_date} to {end_date}.

Metrics to compute:
1. DAU / MAU (Daily/Monthly Active Users)
2. Lecture completion rate
3. Video watch time distribution
4. Exam participation and pass rate
5. Feature adoption (bookmarks, notes, chat)
6. Retention cohorts (Day 1, Day 7, Day 30)
7. Device binding events (unauthorized attempts, replacements)

Insights to provide:
1. Top 3 positive trends
2. Top 3 concerning trends
3. Recommendations for Teacher/Admin dashboard
4. Features that may need optimization

CONSTRAINTS:
- Do not expose individual student PII in the analysis.
- Use aggregated data only.
- Cite specific numbers from the data.

OUTPUT FORMAT: Markdown report with tables and charts (if tools support visualization).

CROSS-REFERENCES: Insights may inform 04 Features improvements or 02 PRD future scope.
```

---

## OPS-001: Generate Release Notes

**Purpose:** Generate structured release notes from Git history and bug tracker.

**Prompt:**

```
ROLE: You are a Release Manager.

CONTEXT: Read:
1. Git log since last release (conventional commits)
2. Bug tracker: closed bugs in this sprint
3. 09 Tasks — completed tasks
4. 13 Releases — previous release notes format

TASK: Generate release notes for Version {X.Y.Z}.

Structure:
1. Version number and release date
2. Summary (2-3 sentences)
3. New Features (with feature keys from 04 Features)
4. Improvements
5. Bug Fixes (with bug IDs from 10 Bugs)
6. Security Fixes (if any)
7. Performance Improvements
8. Known Issues (with workarounds)
9. Breaking Changes (if any)
10. Upgrade Instructions (if any)

CONSTRAINTS:
- Use Conventional Commits categories (feat, fix, refactor, perf, security).
- Link every bug fix to its bug ID.
- Link every feature to its feature key.
- Do not include internal refactoring with no user impact.
- Arabic translations for user-facing changes (per Vision).

OUTPUT FORMAT: Markdown file following 13 Releases template.

CROSS-REFERENCES: This document will be published in 13 Releases and distributed to users.
```

---

# 5. Prompt Versioning

Every prompt in this library follows this versioning scheme:

```
{Category}-{Sequence}-{Version}
```

Example: `CODE-001-v2` is the second version of the "Generate Feature Domain Layer" prompt.

### Change Log

| Prompt ID | Version | Date | Changes | Reason |
| --- | --- | --- | --- | --- |
| CODE-001 | v1 | 2026-08-04 | Initial draft | Base prompt library |
| CODE-002 | v1 | 2026-08-04 | Initial draft | Base prompt library |
| CODE-003 | v1 | 2026-08-04 | Initial draft | Base prompt library |
| CODE-004 | v1 | 2026-08-04 | Initial draft | Base prompt library |
| REV-001 | v1 | 2026-08-04 | Initial draft | Base prompt library |
| REV-002 | v1 | 2026-08-04 | Initial draft | Base prompt library |
| TEST-001 | v1 | 2026-08-04 | Initial draft | Base prompt library |
| TEST-002 | v1 | 2026-08-04 | Initial draft | Base prompt library |
| TEST-003 | v1 | 2026-08-04 | Initial draft | Base prompt library |
| DOC-001 | v1 | 2026-08-04 | Initial draft | Base prompt library |
| DBG-001 | v1 | 2026-08-04 | Initial draft | Base prompt library |
| ANL-001 | v1 | 2026-08-04 | Initial draft | Base prompt library |
| OPS-001 | v1 | 2026-08-04 | Initial draft | Base prompt library |

---

# 6. Custom Prompts for Specific AI Tools

## 6.1 GitHub Copilot / Cursor

For inline code generation, use these context-rich comments:

```dart
// ARCH: 07 Flutter Architecture Section 5 — Repository Pattern
// FEATURE: Feature 04 — Lecture
// TASK: Implement getLecturesForSection with Firestore query using composite index
// CONSTRAINT: Return Either<Failure, List<LectureEntity>>. No raw DocumentSnapshot.
// INDEX: lectures: section_id + display_order (05 Database Section 20)
```

## 6.2 ChatGPT / Claude / Kimi (General)

Use the full prompts from Section 4. Always prepend the Global Prompt Rules (Section 3).

## 6.3 Figma AI (Future)

When 03 UI & UX is available, prompts for generating design variations:

```
ROLE: UI/UX Designer for educational mobile apps.
CONTEXT: Dr. Tarek Platform design system (03 UI & UX).
STYLE: Material 3, white-based, Arabic RTL, mobile-first.
TASK: Generate {component name} variants for {state list}.
CONSTRAINTS: Use design tokens from 11 Assets Section 5. Maintain accessibility contrast ratios.
OUTPUT: Figma component with auto-layout, variants, and properties.
```

---

# 7. Prompt Quality Metrics

Track these metrics to improve prompt effectiveness over time:

| Metric | Target | Measurement |
| --- | --- | --- |
| First-try accuracy | > 80% | % of prompts that produce usable output without revision |
| Revision count | < 2 | Average number of back-and-forth turns per prompt |
| Cross-reference accuracy | 100% | % of prompts that correctly reference existing documents |
| Output format compliance | > 95% | % of outputs that match the requested format |

---

# 8. Open Items

- [ ]  Validate prompt effectiveness with actual AI tools (ChatGPT, Claude, Copilot, Cursor).
- [ ]  Create a prompt feedback loop — developers rate prompt outputs, iterate on prompts.
- [ ]  Establish a prompt contribution guide — how team members add new prompts.
- [ ]  Consider prompt chaining for complex tasks (e.g., CODE-001 → CODE-002 → TEST-001 as a pipeline).
- [ ]  Arabic prompt variants — should prompts to AI be in Arabic when generating Arabic UI copy?

---

END OF DOCUMENT