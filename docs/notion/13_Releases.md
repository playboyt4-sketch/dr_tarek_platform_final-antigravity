# 13 Releases

## Dr. Tarek Platform

Version: 1.0
Status: Draft — pending Teacher (Platform Owner) review before "Approved"

---

# 1. Purpose

This document defines the release management process, versioning strategy, release checklist, and historical record for all Dr. Tarek Platform releases. It ensures that every release is planned, tested, documented, and deployed in a consistent, repeatable, and auditable manner.

This document does not contain build scripts or CI/CD configuration — those belong in the project's repository (`.github/workflows/`, `firebase.json`, etc.). It defines the *process* and *governance* around releases.

---

# 2. Versioning Strategy

The platform follows **Semantic Versioning 2.0.0** (SemVer):

```
{MAJOR}.{MINOR}.{PATCH}
```

| Component | Increment When | Example |
|-----------|---------------|---------|
| **MAJOR** | Breaking changes, architectural redesign, or incompatible API changes | 1.0.0 → 2.0.0 |
| **MINOR** | New features, enhancements, or non-breaking additions | 1.0.0 → 1.1.0 |
| **PATCH** | Bug fixes, security patches, performance improvements | 1.0.0 → 1.0.1 |

### Pre-release Tags

For beta, alpha, or release candidate builds:

```
1.0.0-alpha.1
1.0.0-beta.2
1.0.0-rc.1
```

### Build Metadata

For CI/CD build tracking:

```
1.0.0+build.20260804.1
```

### Platform-Specific Versioning

| Platform | Version Format | Example |
|----------|---------------|---------|
| Android | `versionName` (SemVer) + `versionCode` (integer) | `1.0.0` (name), `100000` (code) |
| iOS | `CFBundleShortVersionString` (SemVer) + `CFBundleVersion` (build) | `1.0.0` (string), `100000` (build) |
| Web | SemVer in `package.json` and UI footer | `1.0.0` |

### Version Code Calculation (Android/iOS)

```
versionCode = MAJOR * 100000 + MINOR * 1000 + PATCH * 10 + BUILD

Example: 1.2.3 build 4 → 1*100000 + 2*1000 + 3*10 + 4 = 102034
```

---

# 3. Release Types

| Type | Frequency | Approval Required | Description |
|------|-----------|-------------------|-------------|
| **Production** | Per milestone | Teacher (Platform Owner) | Stable release to all users |
| **Hotfix** | As needed | Teacher (Platform Owner) | Critical bug fix, bypasses normal cycle |
| **Beta** | Per sprint | Admin / Teacher | Internal/selected user testing |
| **Alpha** | Weekly | Development Lead | Internal team testing only |
| **Nightly** | Daily | None | Automated CI build from `main` |

---

# 4. Release Lifecycle

## 4.1 Standard Release (Minor / Major)

```
Week -2: Feature Freeze
    ↓
Week -1: Code Freeze + QA Testing
    ↓
Day -3: Release Candidate (RC) Build
    ↓
Day -2: RC Testing + Bug Fixes (P0-P2 only)
    ↓
Day -1: Final Approval + Release Notes Finalized
    ↓
Day 0: Production Release
    ↓
Day +1: Monitoring + Rollback Plan Ready
    ↓
Day +7: Post-Release Review
```

## 4.2 Hotfix Release

```
Hour 0: Critical bug identified (P0 or security)
    ↓
Hour 1: Fix developed and tested locally
    ↓
Hour 2: PR reviewed and merged to `hotfix` branch
    ↓
Hour 3: Hotfix build generated, smoke tested
    ↓
Hour 4: Teacher approval (or auto-approve if SLA requires)
    ↓
Hour 5: Production deployment
    ↓
Hour 6: Monitoring verification
```

Maximum hotfix SLA: **4 hours** for P0, **24 hours** for security bugs.

---

# 5. Release Checklist

### 5.1 Pre-Release Checklist

Must be completed before any release candidate is built.

#### Code Quality
- [ ] All tasks for the milestone are closed or moved to next milestone.
- [ ] All P0 and P1 bugs are closed (see 10 Bugs Section 8).
- [ ] All security bugs are closed.
- [ ] All DRM/encryption bugs are closed.
- [ ] Code review completed for all merged PRs.
- [ ] Lint checks pass (`flutter analyze` — zero errors, zero warnings).
- [ ] Unit test coverage ≥ 80% for Domain layer.
- [ ] All widget tests pass.
- [ ] All integration tests (emulator) pass.

#### Documentation
- [ ] Release notes drafted (see Section 6).
- [ ] API documentation updated (if public API changed).
- [ ] Feature documentation updated (04 Features cross-references verified).
- [ ] Database migration guide written (if schema changed).
- [ ] Security Rules deployed and tested.
- [ ] Composite indexes deployed (`firestore.indexes.json`).

#### Security & Compliance
- [ ] Security review completed (REV-002 prompt executed, no Critical/High findings).
- [ ] DRM implementation verified (08 Development Standards Section 8 gate passed).
- [ ] Device binding logic tested on fresh install and factory reset scenario.
- [ ] Custom Claims refresh verified after Admin actions.
- [ ] Password reset flow tested end-to-end.
- [ ] Offline content encryption verified (AES-256, key derivation, Secure Storage).

#### Performance
- [ ] Cold start time < 3 seconds on mid-range device.
- [ ] Video start time < 2 seconds on 4G connection.
- [ ] Firestore query performance verified (no query > 500ms on emulator).
- [ ] Memory profile checked (no leaks > 50MB over 30 min).
- [ ] Bundle size checked (APK < 50 MB, IPA < 80 MB).

#### Platform-Specific
- [ ] Android: Signed APK/AAB generated, ProGuard/R8 rules verified.
- [ ] iOS: Signed IPA generated, App Store compliance checked.
- [ ] Web: PWA manifest valid, service worker registered, `flutter build web` succeeds.
- [ ] All platforms: Splash screen, app icon, and store screenshots updated if changed.

#### Backend
- [ ] Cloud Functions deployed and tested in staging.
- [ ] Firestore Security Rules deployed.
- [ ] Firebase Storage Rules deployed.
- [ ] FCM configuration verified (token refresh, quiet hours, grouping).
- [ ] Bunny CDN integration tested (signed URL generation, quality tiers).
- [ ] Analytics events firing correctly (verify in Firestore `analytics_events`).

### 5.2 Release Day Checklist

- [ ] Version numbers updated in all platform configs (`pubspec.yaml`, `build.gradle`, `Info.plist`).
- [ ] Git tag created: `git tag -a v1.0.0 -m "Release 1.0.0"`.
- [ ] Git tag pushed: `git push origin v1.0.0`.
- [ ] Release notes published (internal wiki + 13 Releases document).
- [ ] App uploaded to Google Play Console (Android).
- [ ] App uploaded to App Store Connect (iOS).
- [ ] Web app deployed to Firebase Hosting.
- [ ] Cloud Functions deployed to production.
- [ ] Firestore indexes verified in production.
- [ ] Rollback plan documented (previous version tag, database backup point).

### 5.3 Post-Release Checklist

- [ ] Monitor Crashlytics for 24 hours (target: zero crashes).
- [ ] Monitor Firestore usage (reads/writes within budget).
- [ ] Monitor Bunny CDN bandwidth (no anomalies).
- [ ] Verify push notification delivery rate > 95%.
- [ ] Check support channels for user-reported issues.
- [ ] Schedule post-release review meeting (Day +7).
- [ ] Update 13 Releases with actual release date and any deviations.

---

# 6. Release Notes Template

Every release must have structured release notes in the following format.

```markdown
# Release v{MAJOR}.{MINOR}.{PATCH}

**Release Date:** YYYY-MM-DD
**Status:** {Planned / In Progress / Released / Rolled Back}
**Release Owner:** {Name}
**Approver:** {Teacher Name}

---

## Summary

2-3 sentences describing the release's purpose and key highlights.

---

## What's New

### Features
- [Feature Key] Feature name — brief description. (04 Features reference)
- [Feature Key] Feature name — brief description.

### Improvements
- Description of non-feature enhancements (performance, UX, accessibility).

### Bug Fixes
- [BUG-XXX] Bug title — brief description. (10 Bugs reference)
- [BUG-XXX] Bug title — brief description.

### Security Fixes
- [SEC-XXX] Security issue — brief description and impact. (if applicable)

### Performance Improvements
- Specific metric improvement (e.g., "Cold start reduced from 4.2s to 2.8s").

---

## Known Issues

| Issue | Severity | Workaround | Planned Fix |
|-------|----------|------------|-------------|
| Description | P2/P3 | Temporary workaround | vX.Y.Z |

---

## Breaking Changes

{None, or list with migration instructions}

---

## Database Changes

{None, or migration guide with before/after schema}

---

## Upgrade Instructions

### For Students
{Automatic update via store, or manual steps if required}

### For Admins
{Any dashboard changes or new workflows to communicate}

### For Developers
{Any config changes, environment variables, or dependency updates}

---

## Rollback Plan

If critical issues are detected post-release:
1. Previous stable version: `v{previous}`
2. Database compatibility: {Backward compatible / Requires rollback script}
3. Rollback command: {Specific commands or procedure}
4. Estimated downtime: {X minutes}

---

## Metrics

| Metric | Target | Actual |
|--------|--------|--------|
| Crash-free users | > 99% | {value} |
| ANR rate (Android) | < 0.5% | {value} |
| App Store rating | > 4.5 | {value} |
| DAU (Day +7) | {target} | {value} |

---

## Acknowledgments

{Team members, external contributors, or special thanks}
```

---

# 7. Release History

## 7.1 Upcoming Releases

### v1.0.0 — Initial Production Release

| Attribute | Value |
|-----------|-------|
| **Status** | In Planning |
| **Target Date** | TBD — pending 03 UI & UX completion |
| **Milestone** | MVP Complete |
| **Scope** | All 15 Features (Domain + Data + Presentation-Scaffolding); Presentation-Final blocked on Figma |
| **Approver** | Teacher (Platform Owner) |

**Included Features:**
- Feature 01: Authentication & Registration
- Feature 02: Student Dashboard
- Feature 03: Subject Navigation
- Feature 04: Lecture
- Feature 05: Video Player
- Feature 06: PDF Viewer
- Feature 07: Timeline Quizzes & Learning Access
- Feature 08: Exams
- Feature 09: Notes
- Feature 10: Bookmarks
- Feature 11: Questions to Admin
- Feature 12: Chat
- Feature 13: Notifications
- Feature 14: Membership Plans
- Feature 15: Student Profile

**Key Architectural Deliverables:**
- Custom Token Authentication (T-000.8)
- Bunny CDN Signed URL Integration (T-000.9)
- AES-256 Offline DRM (T-000.12)
- Device Binding Enforcement (T-CF.2)
- 7 FCM Enhancements (T-000.13)

**Release Blocking Criteria:**
- 03 UI & UX approved and implemented (Presentation-Final)
- All P0-P1 bugs closed
- Security review passed (REV-002)
- DRM gate passed (08 Development Standards Section 8)
- Teacher (Platform Owner) final approval

---

### v1.1.0 — Learning Experience Enhancement

| Attribute | Value |
|-----------|-------|
| **Status** | Planned |
| **Target Date** | TBD — after v1.0.0 stable |
| **Milestone** | Learning Experience |
| **Scope** | See 02 PRD Version 1.1 and 01 Project Vision |

**Planned Features:**
- Advanced Search across all content
- Lecture Bookmarks enhancements
- PDF Highlights
- Personal Notes enhancements
- Watch Later
- Recently Viewed
- Enhanced Student Profile
- Learning Reminders
- Performance optimizations
- Faster synchronization
- Improved caching

---

### v1.2.0 — Monetization & Payments

| Attribute | Value |
|-----------|-------|
| **Status** | Planned |
| **Target Date** | TBD |
| **Milestone** | Commercial Capabilities |
| **Scope** | See 02 PRD (current version) and 01 Project Vision |

**Planned Features:**
- Online payment integration
- Subscription purchase flow
- Subscription renewal automation
- Promo codes and discount campaigns
- Digital invoices
- Payment history
- Subscription analytics
- Revenue reports
- Sales dashboard

---

### v2.0.0 — Academic Expansion

| Attribute | Value |
|-----------|-------|
| **Status** | Planned |
| **Target Date** | TBD |
| **Milestone** | Academic Features |
| **Scope** | See 02 PRD Version 2.0 and 01 Project Vision |

**Planned Features:**
- Attendance management
- Assignment submission
- Homework tracking
- Digital certificates
- Academic calendar
- Study planner
- Advanced student reports
- Teacher analytics
- Subject analytics

---

### v3.0.0 — AI Integration

| Attribute | Value |
|-----------|-------|
| **Status** | Planned |
| **Target Date** | TBD |
| **Milestone** | Artificial Intelligence |
| **Scope** | See 02 PRD Version 3.0 and 01 Project Vision |

**Planned Features:**
- AI Study Assistant
- AI Learning Recommendations
- AI Question Bank
- AI Exam Generator
- AI Performance Analysis
- AI Revision Planner
- AI Chat Support
- AI Content Summaries

---

## 7.2 Released Versions

*No releases yet. This section will be populated after v1.0.0 is deployed.*

---

# 8. Deployment Environments

| Environment | Purpose | Branch | Auto-Deploy | Audience |
|-------------|---------|--------|-------------|----------|
| **Local** | Developer testing | Feature branches | No | Individual developer |
| **Emulator** | CI testing, integration tests | `main` | On PR | CI pipeline |
| **Staging** | Pre-release validation | `staging` | On merge | QA team, internal testers |
| **Beta** | External beta testing | `beta` | Manual | Selected students, beta testers |
| **Production** | Live users | `production` | Manual (approved) | All users |

### Environment Configuration

Each environment has its own Firebase project:

```
dr-tarek-dev     — Development / Emulator
dr-tarek-staging — Staging / Beta
dr-tarek-prod    — Production
```

### Environment-Specific Settings

| Setting | Dev | Staging | Production |
|---------|-----|---------|------------|
| Analytics collection | Disabled | Enabled (test mode) | Enabled |
| Crashlytics | Enabled | Enabled | Enabled |
| FCM quiet hours | Disabled | Enabled | Enabled |
| Bunny CDN | Test library | Test library | Production library |
| Payment logging | Mock | Test data | Real |
| Device binding | Relaxed (2 devices) | Strict | Strict |
| Password reset | Auto-approve | Admin-approve | Admin-approve |

---

# 9. Rollback Procedures

### 9.1 Mobile App Rollback (Android/iOS)

**Scenario:** Critical bug detected after store release.

```
1. Halt current release promotion in Play Console / App Store Connect.
2. If previous version is still serving:
   - Android: Halt rollout, previous version automatically resumes for non-updated users.
   - iOS: Submit expedited review for previous version, or use phased release halt.
3. If previous version is not available:
   - Build hotfix from `hotfix/v{current}` branch.
   - Fast-track through store review (expedited if available).
4. Communicate to users via in-app notification and push.
5. Post-mortem within 48 hours.
```

### 9.2 Web App Rollback

**Scenario:** Critical bug in web deployment.

```
1. Firebase Hosting supports instant rollback:
   firebase hosting:clone dr-tarek-prod:live dr-tarek-prod:rollback-{timestamp}
   firebase hosting:clone dr-tarek-prod:{previous-release} dr-tarek-prod:live
2. Verify rollback via hosting URL.
3. Communicate to users if necessary.
4. Fix forward on `main`, deploy new release.
```

### 9.3 Cloud Functions Rollback

**Scenario:** Broken Cloud Function deployed.

```
1. Identify last known good function version in Firebase Console.
2. Rollback via Firebase CLI:
   firebase functions:rollback --only {function_name}
3. Or redeploy previous Git tag:
   git checkout v{previous}
   firebase deploy --only functions
4. Verify function behavior via emulator or staging.
```

### 9.4 Firestore Schema Rollback

**Scenario:** Database schema change causes issues.

```
⚠️ Firestore does not support true schema rollback.

Mitigation:
1. Schema changes must be backward-compatible (additive only in production).
2. Never rename or delete fields in production without dual-write migration.
3. If destructive change was made:
   - Restore from automated backup (if within retention window: 30 days).
   - Re-apply data migration scripts.
   - Coordinate with Teacher before any data restoration.
```

---

# 10. Release Communication

### 10.1 Internal Communication

| Audience | Channel | Timing | Content |
|----------|---------|--------|---------|
| Development Team | Slack / Teams | Day -7 | Feature freeze announcement |
| QA Team | Slack / Teams | Day -3 | RC build available |
| Admin Team | Email | Day -1 | New features preview, training materials |
| Teacher (Platform Owner) | Direct meeting | Day 0 | Final approval, go/no-go decision |

### 10.2 External Communication

| Audience | Channel | Timing | Content |
|----------|---------|--------|---------|
| All Students | Push Notification | Day 0 | "Update available — new features!" |
| All Students | In-App Notification | Day 0 | Release highlights, what's new |
| Beta Testers | Email | Day -3 (Beta) | Beta release notes, feedback form |
| Support Team | Wiki / Document | Day 0 | Known issues, workarounds, FAQ |

---

# 11. Release Metrics Dashboard

Track these metrics for every release:

| Metric | Tool | Target | Review Frequency |
|--------|------|--------|------------------|
| Adoption rate (Day 7) | Play Console / App Store Connect | > 70% | Weekly |
| Crash-free sessions | Firebase Crashlytics | > 99% | Daily (first week) |
| ANR rate | Play Console | < 0.5% | Daily (first week) |
| Average rating | Play Store / App Store | > 4.5 | Weekly |
| DAU / MAU | Custom analytics | Trending up | Weekly |
| Feature adoption | analytics_events | Per feature | Bi-weekly |
| Support tickets | Help desk | < 5% of DAU | Weekly |
| Rollback incidents | Internal tracker | 0 | Per release |

---

# 12. Open Items

- [ ] Confirm CI/CD platform (GitHub Actions, Codemagic, Bitrise, or Firebase CLI only).
- [ ] Establish beta testing program (TestFlight, Google Play Internal Testing, or Firebase App Distribution).
- [ ] Define store listing assets (screenshots, description, keywords) — depends on 03 UI & UX.
- [ ] Confirm Firebase Hosting domain for web app (`drtarek.app`, `app.drtarek.com`, etc.).
- [ ] Establish automated backup schedule for Firestore (daily automated + on-demand before releases).
- [ ] Define SLA for Teacher approval of releases (business hours only? 24/7 for P0?).
- [ ] Create release communication templates (Arabic + English).

---

END OF DOCUMENT
