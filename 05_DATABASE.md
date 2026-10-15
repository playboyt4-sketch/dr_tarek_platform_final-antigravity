
> DEPRECATED POINTER (2026-10-14): authoritative content lives in `05_DATABASE_v1.7.md` (Approved baseline) and `docs/notion/05 Database 1.8.md` (Proposed). This file is a stale ADR-003 excerpt, not the source of truth.

## Academic Period Lifecycle � ADR-003

Administrative academic periods are represented by four fixed states: 	erm_1, 	erm_2, summer_course, exceptional. Each state has start_date, end_date, and status. Teacher (Platform Owner) controls lifecycle transitions. This replaces reliance on a single current_term end date as the academic-access boundary. users.grade remains independent.

