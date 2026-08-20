# Feature 14 — Database Source Reconciliation Note

## Canonical baseline for this change

`05_DATABASE_v1.7.md` is the authoritative approved Database baseline for Feature 14. It is Version 1.7 with Status `Approved`. The exact supplied baseline was imported into the project without content modification and verified against the supplied attachment with SHA-256:

```text
70132c313af4db45c1778d65fa695d398d96d7ae98b12b8d492ea5eb8aa1fa17
```

The proposed `05_DATABASE_v1.8.md` is derived directly from that file and contains the approved Feature 14 changes only. Version 1.7 must remain preserved and must not be edited in place.

## Existing files and their roles

| File | Role | Treatment in this change |
|---|---|---|
| `05_DATABASE_v1.7.md` | Current approved baseline, Version 1.7. | Preserved unchanged. Used as the only baseline for v1.8. |
| `docs/notion/05_DATABASE.md` | Older complete Database reference, Version 1.6, Status Approved. | Not used as the baseline for Feature 14. Not silently replaced, downgraded, or deleted. |
| Root `05_DATABASE.md` | Short ADR-003 Academic Period Lifecycle fragment. | Not a complete Database specification and not canonical for Feature 14. Not silently replaced or deleted. |
| `05_DATABASE_v1.8.md` | Complete proposed Database specification. | New proposal. Status is Proposed pending Teacher Database Change approval. |

## Promotion rule

If the project later requires `docs/notion/05_DATABASE.md` to be the canonical path, the approved Version 1.8 content may be promoted to that path only after the Database Change Authority is approved and a separate controlled promotion is authorized. Such promotion must preserve Version 1.6 history and must not silently overwrite the existing file during this documentation-only step.

## Reconciliation outcome

The source conflict is resolved by the explicit Teacher decision in `pasted_content_14.txt`: Version 1.7 is the only baseline for this Feature 14 change. The older v1.6 reference and ADR-003 fragment remain in place as historical or specialized documents. No content from either older file is used to reconstruct v1.7, and no unrelated Database section is inferred or rewritten.
