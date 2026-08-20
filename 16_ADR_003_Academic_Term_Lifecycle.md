# ADR-003 — Academic Term Lifecycle Control

Status: Approved
Date: 2026-08-11
Version: 1.0

## Decision

The platform shall use four fixed academic-period states within an academic year:

1. term_1 — Term 1
2. term_2 — Term 2
3. summer_course — Summer Course
4. exceptional — Exceptional Period

Each period has:

- start_date
- end_date
- status

The Teacher (Platform Owner) controls the lifecycle from the administrative Dashboard.

The platform does not use a fixed subscription duration as the authoritative academic-access boundary. Membership access is associated with the active academic period.

Ending a period is an explicit administrative action performed by the Teacher (Platform Owner).

Students never see Academic Year / Term administration.

## Consequences

- Membership expiration logic must use the active academic period rather than a hardcoded semester duration.
- The Dashboard must expose all four periods with their start/end dates and lifecycle status.
- Cloud Functions must validate the active period server-side.
- Firestore remains the Single Source of Truth.
- All lifecycle changes must generate audit/analytics records.
- Existing users.grade remains unchanged and is not related to academic-period state.

## Implementation

The existing current_term/end_date mechanism will be migrated to the four-period model without changing the student Grade model.

