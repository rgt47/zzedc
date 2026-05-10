# zzedc v0.6.0 (in development)

## Shiny modernization (Tier 1: bug fixes + safety net)

* **`shinyjs::delay()` for one-shot timers.** Replaces an
  `invalidateLater()` pattern in the instrument-import module
  that was used for a single deferred callback.
* **Login flow.** `inst/app/server.R` no longer runs both code
  paths after the enhanced gsheets integration succeeds.
* **Modal pattern modernised.** Modals in
  `audit_log_viewer_module.R` and `user_management_module.R`
  are now constructed and shown from the server via
  `shiny::showModal(modalDialog(...))` and dismissed with
  `shiny::removeModal()`. The previous pattern declared
  inline `modalDialog(id = ns(...))` in the UI tagList and
  drove visibility through `shinyjs::show()`/`shinyjs::hide()`,
  which is not the documented Shiny modal API. As a side
  effect, the user-management reset-password handler now
  correctly tracks the user_id of the row that was clicked
  rather than relying on whatever ID an earlier edit modal
  had stored.

## Shiny modernization (Tier 2: wins)

* **Quality dashboard tiles → `bslib::value_box`.** The four
  headline metrics (Total Records, Complete Records, %
  Incomplete, Flagged Issues) are now `bslib::value_box`
  components inside `bslib::layout_columns()` rather than
  hand-rolled `display-4` text divs inside generic
  `bslib::card`s. They surface the answer the user came for
  with consistent showcase icons, theme colours, and
  responsive sizing.
* **Metric outputs hoisted out of `observe()`.** The four
  `output$metric_*` assignments in
  `quality_dashboard_module.R` were previously created
  inside an `observe()` block, meaning they did not exist
  until the observer first fired. They are now declared as
  top-level `renderText({ data <- quality_data(); req(data); ... })`
  expressions, so the value-box outputs are registered up
  front and the test suite no longer needs to call
  `session$flushReact()` before reading them.
* **Audit-log viewer summary tiles → `bslib::value_box`.**
  Total Actions / Data Entries / User Actions / System
  Events were previously four hand-rolled
  `div(class = "card bg-info text-white")` blocks whose
  values were poked into the DOM via `shinyjs::html()`.
  They are now `bslib::value_box` tiles fed by
  `output$stat_*` `renderText()` outputs, with a single
  `stat_counts` reactive replacing four duplicate calls to
  `apply_filters()`.
* **Backup/restore non-blocking pause.** Both observers
  used `Sys.sleep(1)` followed by `shinyjs::hide()` purely
  so the user could see the 100% progress bar before it
  disappeared. Replaced with `shinyjs::delay(1000, ...)`,
  which schedules the hide through the browser instead of
  blocking the R event loop. (The actual file I/O is small
  enough on clinical-trial-sized SQLite files that an
  `ExtendedTask` migration was deferred — adding a
  `future`/`promises` dependency for a sub-second
  operation was not justified.)
* **`shinydashboard` dropped.** `data_correction_module.R`
  was the last consumer of `shinydashboard::valueBox`/
  `valueBoxOutput`. Its four correction-statistics tiles
  (Total Requests, Pending, Approved/Applied, Rejected)
  are now `bslib::value_box` produced via `renderUI()`,
  and `shinydashboard` is no longer in `Imports` or in the
  package-level `@importFrom`. The whole dashboard now
  uses one UI library.
* **Card standardisation.** All `div(class = "card", ...)`
  blocks in `admin_dashboard_module.R`,
  `audit_log_viewer_module.R`, `backup_restore_module.R`,
  and `user_management_module.R` migrated to
  `bslib::card()` + `bslib::card_header()` +
  `bslib::card_body()`. Header background-color
  modifiers (e.g. `bg-primary text-white`) preserved by
  passing `class =` to `card_header()`.
* **`freezeReactiveValue` before cascading
  `updateSelectInput`.** Five sites where new choices are
  pushed to a select input now first call
  `freezeReactiveValue(input, "x")` so that downstream
  reactives do not fire once with the stale `input$x`
  before the client acknowledges the new choice list:
  `data_module.R` (`viz_var_x`, `viz_var_y`),
  `version_history_module.R` (`table_name`, `version_a`,
  `version_b`, `restore_version`),
  `audit_log_viewer_module.R` (`filter_user`),
  `audit_viewer_module.R` (`event_type`).

## Lessons applied from zzpower

* **`useBusyIndicators(spinners = FALSE)`.** Added to the
  navbar in `inst/app/ui.R`. Keeps the global progress
  pulse but suppresses per-output spinner overlays, which
  were the cause of the layout-jump on tile-based pages
  in zzpower and are equally undesirable here.
* **`shiny` floor bumped to `>= 1.9.0`.** Required for
  `useBusyIndicators()`; covers `bindCache()` (1.6.0) and
  `ExtendedTask` (1.8.0) by reach.
* **DT API modernised.** Replaced the deprecated
  `DT::dataTableOutput` and `DT::renderDataTable` aliases
  with the current `DT::DTOutput` and `DT::renderDT`
  across thirteen files (ten R modules plus three
  `inst/app/*.R` panels).
* **Package citation.** Added `inst/CITATION` with a
  `bibentry` and an explicit plain-text `textVersion`
  reading 'Thomas, R.G. (2026). zzedc: ...'. Consumers
  should display `citation('zzedc')$textVersion` rather
  than `format(citation, style = 'text')`, because the
  default formatter ignores `textVersion` and produces a
  reformatted author block.

## Testing

* **`testServer()` smoke tests.** New
  `inst/tinytest/test_module_server.R` exercises three
  module servers end-to-end through `shiny::testServer()`:
  `auth_server` (login button populates session reactive
  values), `data_server` (sample data source produces a
  50-row, 9-column data frame), and
  `quality_dashboard_server` (metric outputs render from a
  seeded SQLite fixture). Adds 10 assertions to the suite
  covering the reactive flow rather than just helper
  functions and UI structure.

* **`testServer()` coverage for refactored modules.** New
  `inst/tinytest/test_module_server_refactored.R` exercises
  six additional module servers (`audit_log_viewer`,
  `user_management`, `data_correction`, `version_history`,
  `backup_restore`, `admin_dashboard`) at depth-of-1 reactive
  flow. Adds 13 assertions, bringing the full tinytest suite
  to **3112 assertions, 0 failures**.

## Build & CRAN-readiness

* **EDC-tab sample-data scaffolding.** `launch_zzedc()` now
  copies a default `forms/blfieldlist.R`, `forms/renderpanels.R`,
  and `forms/save.R` from `inst/extdata/forms/` into the
  working directory on first run when no `forms/` directory
  exists. A bare `launch_zzedc()` call lands a working
  demonstration EDC tab; users replace the stubs with their
  study's actual case-report-form scaffolding. The friendly
  setup-card panel in `inst/app/edc.R` remains as a safety
  net for users who delete the files manually.

* **Vignette build mystery resolved.** Three vignettes
  (`content-author-guide`, `demonstration-trial-via-gsheets`,
  `technical-lead-guide`) had been silently failing to land
  HTML in `inst/doc/` of the built tarball even though
  `R CMD build` reported `creating vignettes ... OK`. Root
  cause: pre-rendered `.pdf` companions for those three
  vignettes had been committed to `vignettes/`.
  `tools:::find_vignette_product()` selects a single canonical
  output per vignette source and, when both `.pdf` and
  `.html` exist for the same stem, deterministically prefers
  `.pdf` (first ext in `c("pdf", "html", "tex")`). The
  `.pdf` was then stripped by `.Rbuildignore`'s `^.*\.pdf$`
  rule, leaving no canonical output and silently dropping
  the corresponding HTML. Build artifacts removed,
  `.gitignore` rules added, and the recipe in `docs/claude.md`
  updated to instruct ad-hoc PDF renders to write outside
  `vignettes/`. **`R CMD check --no-tests` now reports
  Status: OK (0 errors, 0 warnings, 0 notes)** with all 9
  vignettes landing in `inst/doc/`.

# zzedc v0.5.0

* Initial public release.
