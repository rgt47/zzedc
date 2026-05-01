# ZZedc Next Steps
*2026-04-29 06:56 PDT*

This document inventories work that remains after the current
release cycle (testthat-to-tinytest migration, MySQL adapter
incorporation, REDCap migration importer phases C1 / C2 / C3a,
'toy' to 'demonstration' rename) and proposes a sequenced plan.
It is not a feature wishlist; it is the punch list to take the
package from 'shipped with caveats' to 'shipped without
caveats'.

## 1. Status as of this writing

### Shipped and verified

- **Database abstraction.** Five backends implemented behind an
  R6 `DatabaseAdapter` parent: SQLite, DuckDB, PostgreSQL,
  MySQL/MariaDB, ClickHouse. Backend selection is per-project
  in `config.yml`. SQLite remains the default.
- **REDCap migration importer** in `R/redcap_import.R`:
  - Phase C1: `import_redcap_to_zzedc()` produces a directory
    of CSV artefacts.
  - Phase C2: `import_redcap_to_zzedc_db(source = 'db', ...)`
    creates an encrypted ZZedc database in one call, including
    hash-chained replay of the REDCap audit log for Part 11
    continuity-of-record.
  - Phase C3a: `import_redcap_to_zzedc_db(source = 'api', ...)`
    uses the REDCap REST API (via REDCapR). Audit-log
    completeness is classified as full / partial / empty;
    when not full, a `MIGRATION_AUDIT_GAP` marker is prepended
    to the chain so continuity-of-record is honestly scoped.
- **Test framework migration.** All tests run under tinytest.
  Total: 3,208 assertions across 30+ test files; full suite
  passes locally in roughly 11 minutes.
- **R CMD check.** Local check is clean apart from one
  installed-size NOTE (5.8 Mb, mostly help and compiled R
  bytecode); no WARNINGs after the
  `setup_zzedc_from_gsheets()` user-import fix in this cycle.
- **Manuscript.** Methods §2.2 reflects the shipped C2 + C3a
  paths and the partial-audit caveat.

### Shipped but not validated against real-world data

- **MySQL/MariaDB adapter** has been exercised only against a
  synthetic SQLite fixture that mimics REDCap's relational
  shape. Dialect-specific behaviours (`utf8mb4`, `JSON`
  columns, `BIT` vs `TINYINT(1)`, MariaDB-vs-MySQL function
  differences) are inspected but not verified against a live
  server.
- **REDCap migration C2 / C3a** has been verified end-to-end
  only with synthetic fixtures and mocked REDCapR responses.
  No run against a real institutional REDCap instance has
  occurred under this codebase.

## 2. Pending work, in priority order

### Tier 1: production-readiness gaps (must close before
external use)

1. **Live-server integration test for MySQL adapter.**
   Add a Dockerised CI job that spins up a transient
   MariaDB 11.4 LTS container, runs the C2 importer fixture
   against it, and asserts the resulting ZZedc database
   matches the SQLite-backed reference. Estimate: 1-2 days.
   Risk: low. Rationale: this is the only credible way to
   close the 'inspected but not verified' gap on the MySQL
   path before claiming it as production-ready.

2. **Live-REDCap migration validation.** Pair with an
   investigator who owns a non-PHI REDCap project (or the
   public REDCap demo instance) and run C3a end-to-end. Verify
   the audit chain, branching-logic translation, and the
   skipped-rules diagnostic against a domain expert's
   expectation. Estimate: 1 week including write-up.

3. ~~**`save_user_to_db()` signature reconciliation.**~~ Done.
   `R/db_users.R` now provides `ensure_edc_users_table()` and
   `db_insert_user()`; the Shiny `save_user_to_db()` add-path,
   `setup_zzedc_from_gsheets()`, and `import_redcap_to_zzedc_db()`
   all delegate to the helpers. The schema produced by the
   helper matches the canonical `create_core_tables()` output
   (`user_id TEXT PRIMARY KEY`, full audit-column complement),
   eliminating the previous `INTEGER PRIMARY KEY AUTOINCREMENT`
   divergence in the programmatic callers. 16 new test
   assertions in `inst/tinytest/test_db-users.R`.

### Tier 2: scope completion (should close to honour the
existing roadmap)

4. **Phase C3b: `.sql`-dump source mode.** Implement
   `load_redcap_sql_dump()` so callers can pass a REDCap
   mysqldump file and have the importer hydrate a transient
   MariaDB and run C2 against it. ~200 lines of orchestration;
   estimate: 2-3 days. Rationale: closes the third source
   mode promised in the roadmap and fits naturally on top of
   the MySQL CI work in item 1.

5. **Phase C4: repeating instruments and longitudinal events.**
   Currently both C2 and C3a flatten REDCap repeating forms
   and longitudinal arms into a single `visit_code` per
   `event_id`. Lifting this requires (a) extending the ZZedc
   schema with a `repeating_instance` column on `form_data`
   and (b) updating the importer's pivot logic to preserve
   the (subject, event, instance, form) tuple. Estimate:
   1-2 weeks.

6. **Audit-log windowed pulls.** C3a fetches the entire
   REDCap log in a single API call; large studies on slow
   institutional endpoints will time out. Add a date-windowed
   pull (`log_begin_date` / `log_end_date`) with retry/backoff.
   Estimate: 1 day.

### Tier 3: CRAN submission

7. **Address the installed-size NOTE.** The 5.8 Mb install
   footprint is dominated by help files and compiled R
   bytecode. Options: trim long examples, move large
   illustrative datasets to `inst/extdata` only when needed,
   or accept and explain the size in the cran-comments file.
   Estimate: half a day to investigate, depends on findings.

8. **Refresh `cran-comments.md`.** Re-record a clean
   `R CMD check --as-cran` run; document the one expected NOTE
   if size is not reduced. Estimate: half a day.

9. **First CRAN submission.** Submit and respond to CRAN
   reviewer feedback. Estimate: variable; usually 1-2 weeks
   from submission to acceptance.

### Tier 4: documentation hygiene

10. ~~**`docs/development/release-notes-v1.1.md`.**~~ Archived
    to `docs/archive/development/release-notes-v1.1.md` as part
    of the 2026-04-30 documentation consolidation. A new
    release-notes file should be authored when v1.1 is cut.

11. ~~**`docs/claude.md`.**~~ Done. Old 775-line development
    log archived to
    `docs/archive/claude-2025-12.md`; replaced
    with a current ~200-line orientation note describing
    actual package state, conventions, and how to run tests
    / R CMD check. Future development sessions land on
    accurate context.

12. ~~**`docs/README.md`.**~~ Done. Index added pointing at
    the canonical role-based runbooks
    (`content-author-guide`, `technical-lead-guide`),
    reference vignettes, and worked examples; `docs/` tree
    map included.

13. ~~**Role-based runbook consolidation.**~~ Done. Two
    canonical guides created:
    `vignettes/content-author-guide.Rmd` (10 chapters,
    ~10,500 words) and
    `vignettes/technical-lead-guide.Rmd` (12 chapters + 3
    appendices, ~7,800 words). The previous overlapping
    vignettes (`gsheets-authoring-guide`,
    `setup-wizard-guide`, `quick-start-solo-researcher`,
    `small-project-guide`, `medium-project-guide`) are now
    redirects pointing at the canonical runbooks.
    `getting-started.Rmd` is now a one-page role router.

### Tier 5: manuscript

13. **JAMIA Open submission.** Manuscript draft and bibliography
    are in `~/prj/res/33-zzedc-paper/`. Final preparation
    (cover letter, conflict-of-interest, suggested
    reviewers, formatting against journal style) and
    submission. Estimate: 1 week.

## 3. Recommended sequencing

A two-week sprint that closes most of Tier 1 and Tier 4 would
take the package to a credible 'ready for external evaluation'
state without entering Tier 2's larger work:

```
Week 1: items 1, 10, 11, 12  (CI for MySQL, doc hygiene)
Week 2: items 2, 7, 8        (real-REDCap validation, CRAN
        size investigation, cran-comments)
```

Item 3 was completed in the most recent commit cycle.

Tier 2 (C3b, C4, windowed audit pulls) and Tier 3 item 9
(actual CRAN submission) follow once Tier 1 / Tier 4 are
closed.

## 4. Risks

- **C4 (repeating instruments) is a schema change.** Existing
  ZZedc deployments will need a migration step. Consider
  introducing an opt-in flag and shipping the schema change
  alongside a documented migration procedure rather than as a
  silent default.
- **CRAN reviewer feedback is unpredictable.** The package is
  large and has many Suggests dependencies; reviewers may ask
  for the dependency surface to be trimmed. Budget for one
  round of revision.
- **Real-world REDCap schemas drift.** A migration pilot may
  surface column additions in REDCap 14.x point releases that
  the importer does not yet handle gracefully. Plan to treat
  the first three pilot migrations as bug-finding exercises
  rather than as production runs.

## 5. Out of scope for this document

The 32-feature regulatory-compliance roadmap (see
`docs/compliance/regulatory-compliance-implementation-roadmap.md`)
is a separate, longer-horizon plan. Items above focus on the
work needed to release and validate what is *already
implemented*, not on the broader feature roadmap.

---
*Source: ~/Dropbox/prj/sfw/05-zzedc/zzedc/docs/NEXT_STEPS.md*
