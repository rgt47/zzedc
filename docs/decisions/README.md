# Architecture Decision Records (ADRs)
*2026-04-30 16:35 PDT*

This directory holds architecture decision records for ZZedc:
each file documents a single design decision with its context,
the alternatives considered, and the rationale for the choice
made. ADRs are written **once** at the time of the decision
and updated only to mark them superseded.

The ADRs are not yet authored. The decisions worth capturing,
based on a review of the documentation tree, are listed below
as candidates. Each candidate cites the design material that
should source it; that material currently lives elsewhere in
the docs tree or in archived files.

| Candidate ADR | Source material | Notes |
|---|---|---|
| 001-r6-database-adapter | `docs/database-abstraction-plan.md` | Update backend list to five; capture why R6 over S4/Reference |
| 002-encryption-design | `docs/archive/features/feature-01-*.md` (planning series) | Distill the SQLCipher choice, key-rotation model, and AWS KMS integration into one document |
| 003-audit-chain | `docs/archive/compliance/auditability-documentation.md` | Reconcile against the as-shipped hash-chained `audit_log` |
| 004-master-key-custody | `docs/operations/master-key-access-scenarios.md` | Already a coherent operational document; consider promoting into an ADR |
| 005-validation-dsl | `docs/features/validation-dsl-guide.md`, `docs/features/validation-system-readme.md` | Capture the DSL language design and parser conservatism (NA on unrecognised constructs) |
| 006-toy-to-demonstration-rename | (no extant doc) | Capture the rename rationale before institutional memory loses it |
| 007-redcap-migration-phasing | `vignette('mysql-redcap-migration-roadmap')` Part 2 | Capture the C1/C2/C3a/C3b sequencing decision |

ADR format suggestion:

```
# ADR NNN: <decision title>

## Context
What problem prompted this decision; what constraints applied.

## Decision
The choice made.

## Alternatives considered
What else was on the table and why it was not picked.

## Consequences
What this decision makes easy, hard, or impossible.

## Status
Proposed / Accepted / Superseded by ADR NNN.

## Date
YYYY-MM-DD.
```

---
*Source: ~/Dropbox/prj/sfw/05-zzedc/zzedc/docs/decisions/README.md*
