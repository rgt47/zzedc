# ZZedc — Claude Code Working Notes
*2026-05-02 11:30 PDT*

This file orients Claude Code (and any other AI assistant
working in this repository) to the current state of the
package. It is *not* a roadmap, design document, or release
log; those live elsewhere. The contents below should be true
*today*; older notes have been archived to
`docs/archive/`.

## Quick orientation

ZZedc is an R/Shiny Electronic Data Capture system for
clinical trials. The codebase is shaped as a CRAN-targetable
R package.

- **R source:** ~61 KLOC across 95 files in `R/`.
- **Tests:** 3,224 tinytest assertions across 30+ files in
  `inst/tinytest/`. Full suite runs in roughly 11 minutes.
- **`R CMD check`:** Status OK (0 ERRORs, 0 WARNINGs, 0 NOTEs).
- **Vignettes:** two canonical role-based runbooks
  (`content-author-guide.Rmd`, `technical-lead-guide.Rmd`)
  plus 11 reference vignettes plus 5 redirect stubs.

## Architecture in one paragraph

The Shiny application sits on top of a module layer (auth,
EDC, reports, exports, compliance). Modules talk only to an
R6 `DatabaseAdapter` whose concrete implementations cover
SQLite (the default, with SQLCipher AES-256 encryption at
rest), DuckDB, PostgreSQL, MySQL/MariaDB, and ClickHouse.
Backend selection is per-project in `config.yml`. Every
database mutation appends to a hash-chained `audit_log`;
`verify_audit_log_integrity()` validates the chain end-to-end
and is the load-bearing check for the trial's 21 CFR Part 11
continuity-of-record claim.

## Conventions in this codebase

- **Native pipe `|>` only.** No `%>%`.
- **`<-` for assignment.** Never `=`.
- **`snake_case`** everywhere.
- **`testthat` is gone.** All tests are tinytest. The runner
  is `tinytest::run_test_dir('inst/tinytest')`. Do not
  reintroduce `testthat`.
- **No em dashes in prose.** Single quotes preferred over
  double quotes in user-facing text (Markdown / LaTeX);
  R code itself uses double quotes for string literals when
  appropriate, single quotes when nesting matters.
- **Roxygen2 7.3.x** with `Roxygen: list(markdown = TRUE)`.
- **Existing helper layer in `R/db_users.R`** for
  `edc_users`-table operations; do not open-code another
  CREATE TABLE / INSERT for that table.
- **Defensive `tryCatch` is the established convention.**
  The codebase has ~600 `tryCatch` sites. Almost all serve a
  real purpose: wrapping I/O (database, file, network), giving
  callers better error messages, providing sensible defaults
  for Shiny UI rendering, or letting per-item failures not
  abort a multi-item loop. The standard return shape on the
  error path is `list(success = FALSE, message = e$message)`
  or `list(success = FALSE, error = ...)`; callers depend on
  this contract. **Do not preemptively remove `tryCatch`
  blocks.** New code wrapping I/O (DB, file, network, AWS)
  or improving error messages should follow the surrounding
  pattern. Pure-R operations (paste, nrow, list construction,
  arithmetic) do not need wrapping; if you encounter such a
  wrap during other refactoring you may remove it, but only
  after confirming no caller relies on the success/failure
  list shape.
- **`on.exit(DBI::dbDisconnect(conn), add = TRUE)` immediately
  after every `connect_encrypted_db()` or `DBI::dbConnect()`.**
  This is the established teardown pattern; it is in place
  in `R/audit_logging.R`, `R/audit_enhanced.R`,
  `R/secure_export.R`, `R/db_migration.R`, `R/db_connection.R`,
  and `R/database_monitoring.R`. Do not rely on explicit
  late `dbDisconnect()` calls; they leak the connection on
  the error path. The exception is `R/validation_framework.R`
  test-runner code, where each test is wrapped in its own
  `tryCatch` and the connection scope is intentionally
  test-local; refactoring those into the IIFE pattern is on
  the deferred list.

## Recent work the assistant should be aware of

Substantive changes in the most recent work cycles
(roughly Feb-Apr 2026):

1. **REDCap migration importer (`R/redcap_import.R`).** Phases
   C1 (CSV emission), C2 (one-call direct-to-DB with audit
   replay), and C3a (REST API source mode) shipped. Phase
   C3b (`.sql` dump source mode) is still a stub. The full
   roadmap is `vignette('mysql-redcap-migration-roadmap')`.

2. **MySQL/MariaDB adapter (`R/db_adapter_mysql.R`).** Fifth
   backend; tested against synthetic SQLite-shaped fixtures
   only. Live-server validation against a real
   MariaDB instance is in `docs/NEXT_STEPS.md` Tier 1 item 1.

3. **testthat → tinytest migration.** Complete. The migration
   tooling lives in a separate repo at
   `~/prj/res/34-testthat-to-tinytest/`. If you need to
   re-run it for some reason, use that toolset; do not write
   a new translator.

4. **`edc_users` schema unification.** Four call sites
   (setup wizard, Shiny admin UI, gsheets setup, REDCap
   importer) previously had subtly different `CREATE TABLE`
   and INSERT statements; the differences caused a latent
   schema-divergence bug. They now all delegate to
   `ensure_edc_users_table()` and `db_insert_user()` in
   `R/db_users.R`. **If you are adding a fifth caller, use
   those helpers.**

5. **Documentation consolidation.** Two role-based runbooks
   (content-author-guide, technical-lead-guide) replaced a
   sprawling collection of overlapping vignettes. Five older
   vignettes are now one-paragraph redirects. `getting-started.Rmd`
   is a one-page role router. **Do not add new entry-point
   vignettes; extend the canonical guides instead.**

6. **'toy' → 'demonstration' rename.** Throughout user-facing
   docs and example trials, 'toy' has been replaced with
   'demonstration'. Any new docs should use 'demonstration'.

## Where things live

| Concern | File / directory |
|---|---|
| R6 adapter parent and concrete adapters | `R/db_adapter_*.R` |
| Encrypted database init / connection | `R/db_connection.R`, `R/encryption_utils.R` |
| Hash-chained audit log | `R/audit_logging.R` |
| AWS KMS encryption-key custody | `R/aws_kms_utils.R` |
| Setup wizard (web UI for non-technical setup) | `R/setup_wizard_utils.R` |
| Setup from Google Sheets | `R/validation_gsheets_integration.R` |
| Setup from CSV | `R/setup_*` (search `setup_zzedc_from_csv`) |
| REDCap migration importer | `R/redcap_import.R` |
| `edc_users` table helpers | `R/db_users.R` |
| 21 CFR Part 11 features | `R/cfr_part11_extensions.R`, `R/electronic_signatures.R`, `R/data_correction.R`, `R/protocol_compliance.R` |
| GDPR features | `R/gdpr_database_extensions.R`, `R/dsar.R`, `R/erasure.R`, `R/portability.R`, `R/rectification.R`, `R/restriction.R`, `R/retention.R`, `R/consent.R`, `R/breach_notification.R`, `R/privacy_impact.R`, `R/objection.R` |
| Multi-backend portability | `R/portability.R` |

## How to run the test suite

```r
# Full suite (slow; ~11 minutes)
tinytest::run_test_dir('inst/tinytest')

# Single file (fast)
tinytest::run_test_file('inst/tinytest/test_redcap-import.R')

# Filtered (regex over test file names)
tinytest::run_test_dir('inst/tinytest', filter = 'redcap|gsheets')
```

Always run from the package root.

## How to run R CMD check

```bash
cd /tmp && rm -rf zzedc.Rcheck zzedc_*.tar.gz
R CMD build /Users/zenn/Dropbox/prj/sfw/05-zzedc/zzedc
_R_CHECK_FORCE_SUGGESTS_=false \
  R CMD check zzedc_1.0.0.tar.gz \
  --no-manual --ignore-vignettes
```

`_R_CHECK_FORCE_SUGGESTS_=false` is needed because some
Suggests packages (`RMariaDB`, `REDCapR`) may not be
installed in every R environment; their absence triggers a
spurious ERROR otherwise.

## Documentation rendering

When rendering Markdown to PDF with pandoc, use xelatex with
DejaVu Sans Mono for Unicode box-drawing characters:

```bash
pandoc doc.md -o doc.pdf \
  --pdf-engine=xelatex \
  -V monofont="DejaVu Sans Mono"
```

When rendering Rmd vignettes to PDF, use `rmarkdown::render`:

```r
rmarkdown::render(
  'vignettes/content-author-guide.Rmd',
  output_format = rmarkdown::pdf_document(
    toc = TRUE, toc_depth = 2, latex_engine = 'xelatex'),
  output_file = 'content-author-guide.pdf'
)
```

## What NOT to do

- Do not re-introduce `testthat`. The package no longer
  imports or suggests it. The migration is complete.
- Do not open-code `CREATE TABLE edc_users` or
  `INSERT INTO edc_users`. Use `R/db_users.R`.
- Do not call `save_user_to_db()` from non-Shiny code. It is
  the Shiny admin-UI helper and expects a reactive `db_pool`.
  The programmatic path is `db_insert_user()`.
- Do not add new entry-point vignettes. Extend
  `content-author-guide.Rmd` or `technical-lead-guide.Rmd`.
- Do not commit changes without explicit instruction. The
  package's git workflow expects the human to authorise
  commits.
- Do not skip pre-commit hooks (`--no-verify`). If a hook
  fails, fix the underlying issue.

## Useful entry points for common questions

- "Where do I start as a new user?" → `vignette('getting-started')`
- "How do I set up my trial's content?" → `vignette('content-author-guide')`
- "How do I deploy this thing?" → `vignette('technical-lead-guide')`
- "How do I migrate from REDCap?" → `vignette('mysql-redcap-migration-roadmap')`
- "What's left before CRAN submission?" → `docs/NEXT_STEPS.md`
- "Where are the regulatory claims implemented?" →
  `vignette('technical-lead-guide')` Appendix C

## Companion files

- `docs/NEXT_STEPS.md` — sequenced plan of remaining work
- `docs/README.md` — top-level docs-tree index
- `docs/archive/` — superseded development logs, point-in-time
  retrospectives, and stale planning artefacts (organised by
  source subdirectory)
- `vignettes/zzedc-whitepaper.Rmd` — architectural rationale
  and design discussion

---
*Source: ~/Dropbox/prj/sfw/05-zzedc/zzedc/docs/claude.md*
