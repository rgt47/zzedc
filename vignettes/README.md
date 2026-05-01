# Vignettes Index
*2026-04-30 16:50 PDT*

The ZZedc vignette set is organised around two canonical
role-based runbooks plus a small number of focused references
and worked examples. The two runbooks are the entry points;
read those first and follow their internal cross-references to
the reference material.

This file is excluded from the package build (see
`.Rbuildignore`) and exists only as an internal index.

## Final 9 vignettes

| File | Words | Role |
|---|---:|---|
| `getting-started.Rmd` | 650 | Role router. One page; points to the right runbook for your job. |
| `content-author-guide.Rmd` | 6,116 | Canonical runbook for the **content owner** (study coordinator, PI's research assistant). Forms, validation rules, user roster, day-to-day operations. |
| `technical-lead-guide.Rmd` | 7,244 | Canonical runbook for the **technical lead** (statistician, IT-adjacent colleague). Installation, config, encryption, deployment, multi-site, backups, audit-log verification, day-2 operations. AWS, encryption, and disaster-recovery material is folded in here as Chapters 5, 8, and 9. |
| `backend-quickstart.Rmd` | 3,893 | Unified backend setup. Decision tree at the top; per-backend appendices (A: SQLite, B: DuckDB, C: MySQL/MariaDB, D: PostgreSQL, E: ClickHouse). Replaces the five earlier per-backend quickstarts. |
| `demonstration-trial-setup.Rmd` | 2,397 | Worked example: a synthetic 20-subject memory-study trial set up via the CSV authoring path. |
| `demonstration-trial-via-gsheets.Rmd` | 1,988 | The same worked example via the Google Sheets authoring path. Companion to the CSV vignette. |
| `mysql-redcap-migration-roadmap.Rmd` | 3,783 | MySQL/MariaDB current capability plus the REDCap-to-ZZedc migration roadmap (phases C1, C2, C3a shipped; C3b pending). |
| `setup-wizard-guide.Rmd` | 347 | Brief reference for the in-app web setup wizard as an alternative to the Google Sheets path. |
| `zzedc-whitepaper.Rmd` | 2,845 | Executive overview: positioning, architecture in one diagram, audit chain, deployment patterns, where the package boundary ends. The full long-form whitepaper lives at `../docs/whitepaper/whitepaper.Rmd`. |

Total active: ~29,000 words across 9 vignettes.

## Consolidation history (2026-04-30)

This vignette set replaces a previous collection of 22
overlapping vignettes. Retired files have been moved to
`../docs/archive/vignettes/` for provenance and are not
intended to be revived. They include:

- the five per-backend quickstarts (`quickstart-{sqlite,duckdb,mysql,postgresql,clickhouse}.Rmd`), now subsumed by `backend-quickstart.Rmd`;
- the top-level capability tour `quickstart.Rmd`, subsumed by `getting-started.Rmd`;
- `feature-encryption-at-rest.Rmd`, `disaster-recovery.Rmd`, and `quick-start-aws-devops.Rmd`, folded into the Technical-Lead Guide;
- four redirect stubs (`gsheets-authoring-guide.Rmd`, `quick-start-solo-researcher.Rmd`, `small-project-guide.Rmd`, `medium-project-guide.Rmd`);
- `advanced-features.Rmd`, with its unique custom-module and REST-API content extracted to `../docs/development/custom-modules-and-api.md` and the rest superseded by the Technical-Lead Guide.

The unused 42 KB `references-edc.bib` was archived alongside.

If you find yourself wanting to author a new entry-point
vignette, extend the relevant canonical runbook instead.

---
*Source: ~/Dropbox/prj/sfw/05-zzedc/zzedc/vignettes/README.md*
