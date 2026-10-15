
> DEPRECATED POINTER (2026-10-14): authoritative content lives in `docs/notion/06_FIREBASE_ARCHITECTURE .md` (Draft). This file is a stale ADR-003 excerpt, not the source of truth.

## Academic Period Enforcement � ADR-003

Academic-period state is authoritative in Firestore. Cloud Functions must validate the active period server-side. Teacher (Platform Owner) controls lifecycle changes. Client/UI must not determine academic-period validity.

