# ZZedc Documentation Index
*2026-04-30 16:50 PDT*

This directory holds long-form documentation, design notes,
operations runbooks, and development artefacts that complement
the package vignettes. For end-user guidance, start with the
vignettes; for operations, decisions, and contributor material,
read on.

## Where to start

If you are setting up ZZedc for a clinical trial, the two
canonical role-based runbooks live in `vignettes/` and are
linked here for convenience:

- [Content-Author Guide](../vignettes/content-author-guide.Rmd)
  — for the non-technical study coordinator who provides the
  trial content
- [Technical-Lead Guide](../vignettes/technical-lead-guide.Rmd)
  — for the statistician/IT-adjacent team member who deploys
  and maintains the application
- [Getting Started](../vignettes/getting-started.Rmd) — a
  one-page router that points to the right runbook for your
  role

## Reference vignettes

| Topic | Vignette |
|---|---|
| Backend selection (all five) | `vignettes/backend-quickstart.Rmd` |
| REDCap migration | `vignettes/mysql-redcap-migration-roadmap.Rmd` |
| Setup wizard | `vignettes/setup-wizard-guide.Rmd` |
| Whitepaper (executive overview) | `vignettes/zzedc-whitepaper.Rmd` |

Encryption, disaster recovery, and AWS deployment are covered
in `vignettes/technical-lead-guide.Rmd` (Chapters 5, 9, and 8
respectively). The full whitepaper long form lives at
`whitepaper/whitepaper.Rmd`.

## Worked examples

| Example | Vignette |
|---|---|
| Demonstration trial via CSV | `vignettes/demonstration-trial-setup.Rmd` |
| Demonstration trial via Google Sheets | `vignettes/demonstration-trial-via-gsheets.Rmd` |

## What lives in this directory (`docs/`)

The `docs/` tree contains design and development materials,
not end-user runbooks. The end-user runbooks are the vignettes
above.

| Subdirectory | Contents |
|---|---|
| `compliance/` | Canonical regulatory reference (`gdpr-and-cfr-part11.md`), delta-only open-work roadmap, CRF design best practices, security-architecture overview |
| `decisions/` | Architecture Decision Records (ADRs) — currently a candidate-list `README.md`; ADRs not yet authored |
| `development/` | Active contributor notes: competitive analysis, custom-modules and REST API patterns, local-dev troubleshooting |
| `features/` | Live feature roadmaps and operational guides (encryption troubleshooting, validation DSL guide, system readme, feasibility ranking) |
| `operations/` | Operator-facing runbooks: sysadmin guide, HTTPS/TLS deployment, master-key custody scenarios |
| `whitepaper/` | Long-form whitepaper and bibliography (the vignette is the executive-overview short form) |
| `archive/` | Superseded retrospectives, point-in-time assessments, and shipped-feature planning logs (organised by source subdirectory) |

| Top-level file | Purpose |
|---|---|
| `NEXT_STEPS.md` | Sequenced plan of remaining work (CRAN submission, live-server validation, etc.) |
| `claude.md` | Working notes orienting AI assistants to current package state |
| `database-abstraction-plan.md` | Original design rationale for the R6 adapter (with current-state note at the top) |
| `performance-architecture-whitepaper.md` | Performance design notes |

The canonical regulatory-compliance reference is
`compliance/gdpr-and-cfr-part11.md`; open work is tracked in
`compliance/regulatory-compliance-implementation-roadmap.md`
(delta only).

Most files in `docs/` are written for the package maintainers
and contributors. End users should use the vignettes.

## Consolidation history (2026-04-30)

The current layout is the result of a consolidation that took
the documentation tree from 82 active markdown files plus 22
vignettes down to 22 active markdown files plus 9 vignettes.
Retired material was preserved under `archive/`, organised by
its source subdirectory. The vignettes index at
`../vignettes/README.md` lists the final vignette set and what
each was retired in favour of.

Headline outcomes of that consolidation:

- One canonical compliance reference (`compliance/gdpr-and-cfr-part11.md`)
  replaces four conflicting summary documents that quoted
  different compliance percentages with no shared denominator.
  The new reference cites every claim with `R/<file>:<line>`.
- A delta-only open-work roadmap
  (`compliance/regulatory-compliance-implementation-roadmap.md`)
  replaces the December 2025 roadmap whose 'still to do' items
  had largely shipped.
- Encryption, disaster recovery, and AWS deployment vignettes
  were folded into the Technical-Lead Guide.
- Five per-backend quickstart vignettes were unified into one
  parameterised `backend-quickstart.Rmd` with a decision tree
  and appendices.
- The whitepaper was shrunk to a 3 K-word executive overview as
  a vignette; the full long form moved to `whitepaper/`.
- Sysadmin, HTTPS/TLS, and master-key custody material was
  promoted to a new `operations/` subdirectory.

## Updating the documentation

The two role-based runbooks (`content-author-guide`,
`technical-lead-guide`) are the canonical entry points; keep
them current as the package evolves. The reference vignettes
change only when their specific topic changes. Five older
vignettes were retired during the 2026-04-30 consolidation
(`gsheets-authoring-guide`, `quick-start-solo-researcher`,
`small-project-guide`, `medium-project-guide`,
`feature-encryption-at-rest`, `disaster-recovery`,
`quick-start-aws-devops`, `advanced-features`, and the five
`quickstart-<backend>` files); their archival copies are at
`archive/vignettes/`. Do not re-introduce them; extend the
canonical guides instead.

---
*Source: ~/Dropbox/prj/sfw/05-zzedc/zzedc/docs/README.md*
