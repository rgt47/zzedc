# zzedc CRAN Readiness Audit
*2026-04-24 15:28 PDT (audit) · 2026-04-24 19:29 PDT (revision: E2/E3 fixed, partial work on E4) · 2026-04-30 16:55 PDT (revision: documentation consolidation)*

## Revision history

- **2026-05-08 10:14 PDT** — Folded rOpenSci Software Peer
  Review into the report as an optional editorial layer on
  Path C, applied per-sub-package: strong fit for
  `zzedc.import` (Data Lifecycle category, REDCap-bridge
  tooling), plausible-but-debate-likely for `zzedc.regulatory`
  (file `presubmission_inquiry` first), weak fit for
  `zzedc.core` (too generic), out-of-scope for `zzedc.shiny`
  (Shiny meta-packages with regulated-deployment claims face
  the steepest rOpenSci scope hurdle). Revised Path D to make
  explicit that JOSS — not rOpenSci — is the realistic
  editorial venue for the un-split zzedc, and that rOpenSci
  re-enters under Path C only for the bounded sub-packages.
  rOpenSci review counts as JOSS review under the partnership,
  so a single rOpenSci submission of `zzedc.import` would
  yield both the badge and a citable JOSS paper.
- **2026-05-08 09:18 PDT** — Revised Path C from
  "ship all 4 sub-packages to CRAN over ~6 weeks" to a
  phased version. Phase 1 ships `zzedc.import` and
  `zzedc.regulatory` to CRAN (~3-4 weeks; both have
  standalone library value beyond the zzedc app and address
  real CRAN ecosystem gaps). Phase 2 (`zzedc.core` +
  `zzedc.shiny`) defers to R-universe pending uptake-signal
  promotion criteria (downloads, reverse-deps, citations).
  The earlier all-at-once version assumed the CRAN-EDC gap
  is a supply gap (opportunity); the phasing protects against
  the alternative reading that it is a demand gap (REDCap
  dominance + regulated-deployment workflows conflict with
  `install.packages()`-style distribution).
- **2026-05-08 08:56 PDT** — Corrected framing on the
  "application vs. library" question. The earlier blanket claim
  that "CRAN packages are libraries; zzedc is an application,
  therefore it doesn't fit" is overstated. CRAN does host full
  Shiny applications (`radiant` family, `learnr`, `OpenSpecy`,
  `epitweetr`). The actual CRAN blockers for zzedc are scale
  (658 exports vs. radiant.model's ~25; 59k LOC; 899 man pages)
  and policy (the E-/W- list in this report), not architectural
  category. Verified via `tools::CRAN_package_db()` query on
  2026-05-08: `radiant`, `radiant.basics`, `radiant.data`,
  `radiant.design`, `radiant.model`, `radiant.multivariate` all
  active (versions 1.6.6-1.6.11). EDC-specific search confirms
  the gap: no full self-hosted EDC system exists on CRAN; the
  matches (`REDCapR`, `redcapAPI`, `REDCapTidieR`, `REDCapDM`,
  `REDCapCAST`, `REDCapExporter`, `redquack`, `tidyREDCap`,
  `EDCimport`, `dmtools`, `ReviewR`, `sdtm.oak`, `sdtmval`)
  all interface with REDCap or operate on extracted clinical
  data; none replace REDCap. zzedc is novel in the R ecosystem
  for this. Updated Path C below with a sketch of a 4-package
  split modeled on the radiant family.
- **2026-05-06 17:44 PDT** — Resolved the long-standing
  silent-vignette-drop. Three vignettes (`content-author-guide`,
  `demonstration-trial-via-gsheets`, `technical-lead-guide`)
  were silently failing to land HTML in `inst/doc/` of the built
  tarball even though `R CMD build` reported `creating
  vignettes ... OK`. Root cause: pre-rendered `.pdf` companions
  for those three vignettes had been committed into
  `vignettes/`. `tools:::find_vignette_product()` selects a
  single canonical output per vignette source and, in the
  tie-mtime case where both `.pdf` and `.html` exist, deterministically picks `.pdf` (the first ext in
  `c("pdf", "html", "tex")`). The `.pdf` was then stripped by
  `.Rbuildignore`'s `^.*\.pdf$` rule, leaving no canonical
  output to copy and silently dropping the corresponding HTML
  from `inst/doc/`. Fix: (a) deleted `vignettes/*.pdf` and
  `vignettes/*.html` (build artifacts); (b) added a
  `.gitignore` rule with the rationale; (c) updated
  `docs/claude.md` to instruct ad-hoc PDF renders to write
  outside `vignettes/`. Build now lands all 9 HTMLs.
  `R CMD check --no-tests` reports `Status: OK` (0 errors,
  0 warnings, 0 notes).
- **2026-04-30 16:55 PDT** — Documentation consolidation. Addressed
  W3 (excluded vignettes) and W4 (`references.bib` exclusion):
  vignette set reduced from 22 to 9 active files, with retired
  vignettes archived to `docs/archive/vignettes/` rather than
  excluded-but-shipped. The unused `references-edc.bib` was
  archived. The `bibliography:` directive was removed from the
  short-form whitepaper vignette; the long-form whitepaper and
  its bibliography now live in `docs/whitepaper/`. The references
  to `disaster-recovery`, `quickstart`, etc. as currently-built
  vignettes in W3/W4 below are stale; current build set is the
  9 vignettes in `vignettes/README.md`. Compliance documentation
  was reconciled into a single canonical reference at
  `docs/compliance/gdpr-and-cfr-part11.md` with `R/<file>:<line>`
  citations; four conflicting summary documents archived.
- **2026-04-24 15:28 PDT** — Initial audit. Identified blockers E1-E5,
  warnings W1-W8, notes N1-N7.
- **2026-04-24 19:29 PDT** — Addressed E2 (Sys.setenv restoration) and
  E3 (hardcoded `~/zzedc_instance` default) at the source level.
  Refactored encryption subsystem to thread keys through explicit
  `key` arguments (`connect_encrypted_db`, `initialize_encrypted_database`)
  rather than via process-wide env-var leak. Updated 30+ test sites
  across 22 test files to use the new contract. Removed
  `library(config)` from `tests/testthat/helper-test-setup.R` (was
  masking `base::get` and breaking ~163 tests). Test suite went from
  unrunnable due to cascading failures to **3052 passing / 1 failing
  / 40 skipped** (≥98.7% pass rate).
- **2026-04-24 19:40 PDT** — Addressed E1 (Suggests-as-Imports). Moved
  `bslib`, `bsicons`, `DT`, `plotly`, `shinydashboard`, and `R.utils`
  from Suggests to Imports in DESCRIPTION (these are used
  unconditionally in source). Added explicit `@importFrom`
  declarations in `R/zzedc-package.R` for the symbols used and
  regenerated NAMESPACE via `devtools::document()`. Cleaned up the
  test helper to no longer attach packages now in Imports. The 1
  remaining encryption test (an env-var-state assertion I added)
  fixed to be order-independent. **E1, E2, E3 fully addressed.**
- **2026-04-25** — Addressed E4 (top-level executable code).
  Identified one real offender via `parse()`-based static
  classification: `R/database_monitoring.R` had 19 top-level `cat()`
  calls printing a "Quick Start Commands" banner at every package
  load. Removed the banner. The remaining 18 files flagged by the
  initial heuristic were false positives (bare-roxygen `NULL` lines,
  not executable code). Final classifier reports zero remaining
  top-level non-assign expressions across all 19 files.
- **2026-04-25 16:40 PDT** — Moved the manuscript out of the package
  source tree to a separate research-output repository at
  `~/prj/res/33-zzedc-paper/zzedc_paper/` (mirroring the
  `prj/sfw/` ↔ `prj/res/` parallel pattern). Added `^manuscript$`
  and `^CRAN-readiness-report\.md$` to `.Rbuildignore` defensively.
  This eliminates a category of CRAN reviewer comments about
  unrelated content in the source tarball.
- **2026-04-25** — Addressed E5 (missing examples) in two stages.
  Stage 1: a two-round automated audit identified exports never
  referenced from vignettes (the user-facing documentation surface)
  and added `@keywords internal` to their roxygen blocks, while
  preserving an explicit allow-list of 41 always-public entry
  points and topic-only pages. **773 of 907 man pages marked
  internal** (was 0). Stage 2: hand-wrote `@examples` blocks for
  every remaining public page. Each example is biostat/clinician-
  audience-appropriate — realistic toy-trial scenarios with
  clinical-research vocabulary (subjects, visits, CRFs,
  validation rules, GDPR Articles, AE/SAE workflows) — and uses
  `\dontrun{}` for state-requiring calls (database, Shiny launch)
  and runnable examples for pure functions (`sort_data`,
  `filter_data_by_search`, `validate_field_value`,
  `create_default_config`). Result: **0 of 134 public man pages
  remain without examples** (down from 757). **E1, E2, E3, E4, E5
  fully addressed.** W1 (large NAMESPACE), W2 (package size), W3
  (excluded vignettes), and W4-W8 still outstanding but reduced
  in severity by the bulk internalization.

## Summary

**Recommendation: Do not submit zzedc as a single package in its
current form. Either split it (Path C, recommended) or skip CRAN
(Path D).**

This is a research-grade Shiny application packaged as a single
R package. It will fail multiple CRAN policies on a static read
alone, before `R CMD check --as-cran` is even attempted. The
blockers fall into two categories:

(i) **Policy violations** -- file-system writes, environment
modification, unconditional use of Suggests packages. Largely
addressed in waves through 2026-05; the remaining items are
documented inline below.

(ii) **Scale** -- 658 exports (vs. `radiant.model`'s ~25),
~59,000 lines of R, 899 man pages. A single package this wide
is reviewer-unfriendly regardless of category.

The earlier framing of a third "architectural mismatch" category
(applications vs. libraries) was overstated. CRAN does host full
Shiny applications: the `radiant` family (six active packages,
versions 1.6.6-1.6.11 as of 2026-05-08), `learnr`, `OpenSpecy`,
`epitweetr`. The category is fine; the scale is not. The
correct response is the radiant-style split sketched in Path C,
not a "this isn't allowed on CRAN" verdict.

A separate finding from the same 2026-05-08 CRAN search:
**no full self-hosted EDC system exists on CRAN today.** The
domain matches (`REDCapR`, `redcapAPI`, `REDCapTidieR`,
`REDCapDM`, `REDCapCAST`, `REDCapExporter`, `redquack`,
`tidyREDCap`, `EDCimport`, `dmtools`, `ReviewR`, `sdtm.oak`,
`sdtmval`) all either interface with REDCap or operate on
already-extracted SDTM data; none implement a self-hosted
capture system. zzedc would be the first. That is a real
strategic argument for a CRAN release of the library-shaped
parts, not just GitHub distribution.

The body of this report enumerates findings by severity and ends with a
proposed remediation path.

---

## Epistemic status

- **Verified by reading source**: NAMESPACE counts, DESCRIPTION fields,
  .Rbuildignore content, presence/absence of examples in man/, specific
  line numbers cited.
- **Verified by static grep**: presence of `Sys.setenv`, `<<-`, `library()`
  in source files, hardcoded paths.
- **Inferred (not verified)**: that `R CMD check --as-cran` will fail in
  the specific ways predicted. I did not run R CMD check during this
  audit; doing so on a 56k-LOC package with 907 man pages would take
  ~30+ minutes and produce noisy output. The findings below predict
  failures rather than confirm them. Verify by running:

  ```bash
  R CMD build .
  R CMD check --as-cran zzedc_1.0.0.tar.gz
  ```

  before any submission attempt.

---

## 1. Errors — must fix before submission

### E1. Suggests packages used unconditionally

**File**: multiple
**Severity**: hard CRAN reject.

`DESCRIPTION` lists `bslib`, `bsicons`, `plotly`, `DT`, `shinyTime`,
`shinyWidgets`, `shinydashboard`, `pool`, `paws`, `data.table`, `arrow`,
`httr`, `R.utils` under `Suggests`, but the source uses several of them
unconditionally:

- `R/validation_rules_module.R:14` calls `bslib::page_fluid(...)`
- `R/validation_rules_module.R:22` calls `bslib::navset_card_tab(...)`
- `R/data_module.R:294` calls `plotly::plot_ly() %>% plotly::add_text(...)`
- `R/data_module.R:99,123,291` use `plotlyOutput` / `renderPlotly` (these
  are also listed in `globalVariables`, masking the dependency)

CRAN policy (CRAN Repository Policy, "Packages should not have a hard
dependency on packages only listed in `Suggests`"): use of a Suggests
package must be guarded by `requireNamespace("pkg", quietly = TRUE)` or
the package must be moved to `Imports`.

**Fix**: move `bslib`, `bsicons`, `plotly`, `DT` to `Imports`. They are
core to the UI; calling them optional is fiction. For genuinely optional
backends (`paws`, `RPostgres`, `RClickhouse`, `duckdb`), keep in Suggests
but wrap every call site with `requireNamespace()`.

### E2. `Sys.setenv()` modifies user environment without restoration

**File**: `R/launch_zzedc.R:94`, `R/launch_zzedc.R:99`,
`R/db_migration.R:549`
**Severity**: hard CRAN reject.

```r
# launch_zzedc.R:94
Sys.setenv(ZZEDC_CONFIG_PATH = config_path)
# launch_zzedc.R:99
Sys.setenv(ZZEDC_WORK_DIR = normalizePath(getwd()))
# db_migration.R:549
Sys.setenv(DB_ENCRYPTION_KEY = new_key)
```

CRAN policy ("Writing R Extensions" §1.1.3.1): "Functions and code in
packages should not modify the global environment, including the user’s
environment variables, unless the user explicitly requests it and this
is essential to the functionality."

**Fix**: pass values as function arguments, or use
`withr::with_envvar()` for scoped setting, or guard with `on.exit()`
restoring the prior value. `launch_zzedc()` is interactive, so
`Sys.setenv` may be defensible if documented; the silent modification in
`db_migration.R` is not.

### E3. Hardcoded write to user home directory

**File**: `R/setup_wizard_utils.R:397`
**Severity**: hard CRAN reject for examples/tests; warning otherwise.

```r
complete_wizard_setup <- function(config_list,
                                  base_path = "~/zzedc_instance") {
```

The default writes outside `tempdir()`. CRAN policy: "The package code
and examples should not write anywhere on the user’s file system apart
from the R session’s temporary directory." This default will fail
`R CMD check` if any example or test exercises it.

**Fix**: change default to `tempfile()` or require `base_path` to be
passed explicitly with no default; document that interactive use should
supply a project directory.

### E4. Top-level executable code in R/ source files

**File**: 19 files (R/audit_viewer_module.R, R/backup_restore_module.R,
R/cfr_part11_extensions.R, R/database_monitoring.R, R/db_config.R,
R/db_migration.R, R/encryption_utils.R, R/error_handling.R,
R/gdpr_database_extensions.R, R/init.R, R/launch_zzedc.R, R/profiling.R,
R/setup_choice_module.R, R/setup_wizard_utils.R, R/validation_cache.R,
R/validation_dsl_sql_codegen.R, R/validation_framework.R,
R/validation_qc_engine.R, R/version_history_module.R).

These files contain `cat()` / `message()` / control-flow statements
outside function bodies. Code at the top level of files in `R/` runs at
package load time, which is forbidden for any non-trivial side effect.
Requires per-file inspection — most are likely false positives where
the `cat()` is inside a function and my heuristic flagged the file
because of frequency. The single file with 92 `cat()` calls
(`R/database_monitoring.R`) deserves explicit review.

**Fix**: move any genuinely top-level statements into `.onLoad()` /
`.onAttach()` (with packageStartupMessage, not cat) or into the
function body that needs them.

### E5. Missing examples on most exported functions

**Counts**: 679 exports / 907 man pages / 150 with `\examples` blocks /
13 with runnable (non-`\dontrun`/`\donttest`) examples.

CRAN policy ("Writing R Extensions" §1.1.5): "All user-level objects
in a package should be documented; if a package contains user-level
objects which are intended to be used by the user, the package should
contain examples for them."

83% of man pages have no examples; 98% of pages with examples wrap them
in `\dontrun`. CRAN reviewers will return the package with a request to
provide runnable examples for at least the canonical workflow.

**Fix**: provide one runnable example per *concept* (not per function);
mark the rest `@noRd` if they are not user-facing, or `@keywords
internal` to suppress index entries. With 679 exports, the right
question is whether all 679 truly need to be exported.

---

## 2. Warnings — should fix; CRAN may accept with NOTE/WARNING

### W1. Excessive export count

679 functions exported. For comparison: `dplyr` has ~270, `shiny` ~170,
`ggplot2` ~180. A single CRAN package with 679 exports is unusual and
will draw scrutiny: CRAN reviewers will ask whether the package is
trying to be a framework that should be split.

**Fix**: split into logical sub-packages (`zzedc.core`, `zzedc.gdpr`,
`zzedc.cfr11`, `zzedc.db`) or mark internal helpers `@keywords
internal` / `@noRd` so they do not appear in the package index.

### W2. Package source size

- 56,302 lines of R in `R/`
- 907 man pages
- 396 KB `renv.lock`
- 16 vignette source files (13 excluded from build)

CRAN typically warns above 5 MB tarball size and rejects above 10 MB
without justification. With this many man pages and vignettes the
built tarball is likely to approach or exceed 5 MB.

**Fix**: trim man pages (W1), exclude `setup_toy_trial.R` and the toy
trial fixtures from build, drop the 13 .Rbuildignored vignettes
entirely (move to a separate documentation site).

### W3. Vignette source files excluded from build

`vignettes/` contains 16 `.Rmd` files; `.Rbuildignore` excludes 13 of
them, leaving 3 actually built (`disaster-recovery`, `getting-started`,
`quickstart`). The 13 excluded files inflate the source tarball
without contributing to the installed package.

CRAN reviewers often question why source files are present but not
built — this looks like neglected drafts.

**Fix**: choose one of: (a) get the vignettes building; (b) move them
to a `pkgdown` site or a separate `inst/doc-extra/` directory; (c)
delete them.

### W4. `references.bib` excluded but vignettes may need it

`.Rbuildignore` excludes `vignettes/references.bib`. If any of the 3
built vignettes (`disaster-recovery`, `getting-started`, `quickstart`)
contains a `bibliography:` entry referencing this file, the vignette
will fail to render in CRAN's build.

**Fix**: read the YAML headers of the 3 built vignettes; if any cite
references, ship the .bib file.

### W5. `import(shiny)` imports the entire shiny namespace

`R/zzedc-package.R` line 2: `#' @import shiny`. This pulls all of
shiny's exported functions into zzedc's namespace, creating
masking risk and making the dependency surface harder to audit. CRAN
prefers `importFrom`.

**Fix**: replace `@import shiny` with explicit `@importFrom shiny ...`
declarations for each shiny function used. Static analysis can
generate the list (e.g., `lintr::object_usage_linter`).

### W6. `globalVariables()` declaration includes function names from Suggests

`R/zzedc-package.R` declares `plotlyOutput`, `renderPlotly`,
`ggplotly`, `nav_panel`, `navset_tab`, `shinyalert`,
`updatePasswordInput`, `dbConnect`, `dbDisconnect`, `dbWriteTable`,
`SQLite` as global variables. This is wrong — these are functions
from `plotly`, `bslib`, `shinyalert`, `shinyauthr`, `DBI`, `RSQLite`.
Declaring them as globals masks missing imports and will leave the
package unable to find them when those Suggests packages are absent.

**Fix**: replace each call site with `pkg::function()`; remove these
names from `globalVariables`.

### W7. Use of `<<-` super-assignment

`R/aws_kms_utils.R` lines 64, 77, 275, 276, 285, 286, 296, 308, 309,
317. These appear to be inside `tryCatch` handlers writing to a parent
`results` / `errors` / `recommendations` accumulator — likely correct
in scope, but `R CMD check` will not flag this as an error. Review
defensively; refactor to return values instead of mutating outer scope.

### W8. Version number for first CRAN release

`Version: 1.0.0` for what `NEWS.md` calls "Initial CRAN release". CRAN
permits this but reviewers sometimes view 1.0.0 as overconfident for a
first submission of a new package. `0.1.0` or `0.9.0` is a less
contentious starting point.

---

## 3. Notes — improvements, not blockers

### N1. License file

`LICENSE` is a 2-line custom note pointing to gnu.org. The DESCRIPTION
field is `License: GPL-3 + file LICENSE`. CRAN expects the LICENSE
file for "+ file LICENSE" packages to contain only year/copyright
information, *not* the GPL text. Either drop "+ file LICENSE" (use
`License: GPL-3` alone) or replace `LICENSE` with the standard CRAN
LICENSE template.

### N2. Hardcoded `~/.aws/credentials` reference

`R/aws_kms_utils.R:277`: appears in a help-message string, not as a
code path. Acceptable but worth noting in case CRAN's automated string
scan flags it.

### N3. NAMESPACE has 0 S3 methods registered

The package uses R6 (6 R6 classes) and S4 indirectly through DBI but
no S3 dispatch. Not a problem on its own; mention because reviewers
often check S3 method registration.

### N4. `setup_toy_trial.R` is an analysis script in the package root

`setup_toy_trial.R` (2.5 KB) lives at package root and is excluded by
`.Rbuildignore`. Move to `inst/scripts/` or `analysis/` for clarity.

### N5. `Depends: R (>= 4.1.0)`

Adequate (covers native pipe). Could be tightened to `R (>= 4.4.0)`
matching the user's stack, but 4.1.0 maximizes the install base.

### N6. `analysis/` directory at package root

Appears to be a zzcollab research-compendium artifact. `.Rbuildignored`,
so not in the tarball. Fine, but verify nothing in `analysis/` is
referenced by built vignettes or examples.

### N7. `Meta/` directory present

`Meta/` is a build artifact created by `R CMD build` / `R CMD check`.
Should be removed before submission and is .Rbuildignored — confirm.

---

## 4. What I did not check

- `R CMD check --as-cran` was not executed (see Epistemic status).
- Reverse-dependency safety: zzedc has no current dependents (it has
  not been on CRAN), so this is N/A for first submission.
- Vignette runtime and PDF rendering. The 3 built vignettes
  (`disaster-recovery`, `getting-started`, `quickstart`) need to render
  cleanly; CRAN runs vignettes as part of check.
- Test execution (`devtools::test()`). 52 test files exist under
  `tests/testthat/`; whether they currently pass is unknown.
- Win-builder and macOS builder. CRAN requires the package to build on
  Windows (winbuilder), macOS (macbuilder), and r-devel. Multi-platform
  testing is required pre-submission.
- `urlchecker::url_check()` on URLs in DESCRIPTION, vignettes,
  README, NEWS.

These constitute a separate "pre-submission verification" pass after
the static issues above are fixed.

---

## 5. Recommended remediation path

### Path A — Submit zzedc as-is (not recommended)

Estimated outcome: rejected at first review with a multi-page issue
list. Expected revision cycles before acceptance: 3-5.

### Path B — Fix policy violations, submit (still risky)

Address E1-E5 (1-2 days), W1 (1 day, mostly internal-tagging), W2-W4
(half day), then run `R CMD check --as-cran` and iterate. Estimated
to first submission: 1-2 weeks. Expected revision cycles: 2-3.

Risk: CRAN reviewers may reject on the grounds that zzedc is an
application, not a library, regardless of policy compliance. Their
discretion is broad.

### Path C — Phased radiant-style split (recommended)

Refactor into a thin core plus topical add-ons, modeled on the
`radiant` family. **Phase the CRAN releases**: ship the two
sub-packages with the clearest standalone value first; defer
the other two pending uptake data. This responds to a real
strategic uncertainty about whether the CRAN-EDC gap is a
*supply* gap (no one has shipped one yet — opportunity) or a
*demand* gap (REDCap dominates, regulated-deployment workflows
conflict with `install.packages()`-style distribution — the
gap exists for good reason). Phasing protects against the
demand-gap scenario without forfeiting the supply-gap upside.

#### Phase 1 — Ship to CRAN (~3-4 weeks)

These two sub-packages have clear standalone value beyond the
zzedc app and address real gaps in the existing CRAN ecosystem.

- **zzedc.import** (CRAN, ~15-25 exports). REDCap-import
  bridge, CSV ingest, instrument-library converters, the
  SDTM/REDCap schema mappings. Sits inside the existing
  REDCap-tooling ecosystem (REDCapR, REDCapTidieR, REDCapDM,
  redcapAPI) where CRAN is exactly the discovery surface
  that matters: reverse-dependency graphs, package search,
  transitive `Suggests`. Equivalent to `radiant.design` in role.
- **zzedc.regulatory** (CRAN, ~20-30 exports). 21 CFR Part 11
  and GDPR helpers, audit-trail builders, electronic-signature
  verification, retention-policy enforcement, the privacy/
  rectification/objection/restriction workflows. Generic
  enough that any clinical Shiny app could pull it; reuse
  potential extends well beyond zzedc itself. No Shiny
  dependency. Equivalent to `radiant.basics` in role.

Effort breakdown for Phase 1:

- Week 1: Mechanical extraction. Both sub-packages partition
  cleanly out of the existing module tree (the current
  `R/redcap_*.R`, `R/instrument_library*.R`, `R/audit_*.R`,
  `R/gdpr_*.R`, `R/privacy_*.R` files already cluster along
  these lines). Fan out Imports declarations, regen NAMESPACE.
- Week 2: Per-sub-package CRAN-prep — examples for every
  export, single-vignette per package, `R CMD check --as-cran`
  iteration to 0/0/0 or 0/0/1 (new-submission NOTE).
- Week 3: win-devel + mac-release submissions, address
  reviewer feedback if any. Submit `zzedc.regulatory` first
  (no upstream R-package dependency on REDCap-family);
  `zzedc.import` second.
- Week 4 buffer: revision cycle.

#### Phase 2 — Conditional, defer (R-universe in the meantime)

These two stay on R-universe for now. Promote to CRAN only if
Phase 1 sees adoption signal that justifies the maintenance
overhead.

- **zzedc.core** (R-universe, ~30-50 exports). DB adapters,
  encryption utilities, security primitives, config loaders.
  Mostly recombination of existing primitives (`pool`,
  `sodium`, `shinymanager`, `config`); standalone value as a
  CRAN library is uncertain because users who want these
  components separately would compose the upstream packages
  directly.
- **zzedc.shiny** (R-universe, ~50-80 exports). Shiny modules,
  `launch_zzedc()`, setup wizard, all UI. The "first
  self-hosted EDC on CRAN" framing collides hardest here with
  (a) the regulatory-deployment liability surface
  (`install.packages()` on Tuesday, run a real trial Wednesday
  — IT validation? IQ/OQ/PQ?), and (b) the dependency-
  maintenance treadmill for a 7+-package Shiny dependency
  surface. The radiant precedent shows it *can* be done; the
  question is whether the demand justifies the cost.

**Promotion criteria from R-universe to CRAN** (review at
+6 months and +12 months post-Phase-1-launch):

- Phase 1 packages combined CRAN downloads > 500/month,
  sustained, OR
- ≥3 reverse-dependents declared in CRAN packages, OR
- At least one independent academic citation of the manuscript
  attributable to CRAN-driven discovery, OR
- Concrete adopter request for CRAN-published versions.

If none of these trigger, Phase 2 stays on R-universe and the
manuscript cites R-universe + zenodo DOIs without apology.

#### Optional editorial layer — rOpenSci Software Peer Review

rOpenSci (`github.com/ropensci/software-review`) runs a
structured peer-review process for R packages: 2 reviewers,
public review threads, ~2-6 month timeline, results in a
catalogued package with the rOpenSci badge and optional fast-
track to a JOSS paper. This is orthogonal to CRAN — a package
can be on CRAN with or without rOpenSci review — but it is
the strongest R-software peer-review signal available and
worth pursuing for the bounded sub-packages where scope fit
is good.

Per-sub-package scope assessment:

- **zzedc.import** — strong fit ("Data Lifecycle" category;
  REDCap-bridge tooling sits next to existing rOpenSci-reviewed
  clinical data packages). Highest-confidence rOpenSci
  candidate in the family. Submit ~2-3 months after CRAN
  release of the package, once the API has stabilised under
  real use.
- **zzedc.regulatory** — plausible fit, scope debate likely.
  Bounded library, well-scoped, but the domain (21 CFR /
  GDPR for clinical data) is narrower than typical rOpenSci
  submissions. File a `presubmission_inquiry` issue first to
  test scope before committing the work.
- **zzedc.core** — weak fit; too generic, too much overlap
  with the `pool` / `sodium` / `shinymanager` primitives it
  recomposes. Skip rOpenSci for this one.
- **zzedc.shiny** — out of scope. Apps are accepted in
  principle but the bar for "novel + scientifically useful +
  not just yet another Shiny app" is high; an EDC system
  competes with REDCap as a known-quantity benchmark and
  reviewers will press hard on differentiation. JOSS (via
  Path D) is the realistic editorial venue for this layer.

The JOSS fast-track (rOpenSci review counts as JOSS review
under their partnership) means a single rOpenSci submission
of `zzedc.import` could yield both the badge and a citable
paper for the manuscript — a stronger combined signal than
either CRAN or JOSS alone.

#### Out of scope for CRAN, GitHub-only

- **zzedc.demo** (GitHub-only). Toy-trial fixtures,
  demonstration databases, the `demonstration-trial-via-gsheets`
  workflow, `inst/extdata/forms/` stubs, the wizard-based
  setup helpers that write to the user's working directory.
  Distributed via `devtools::install_github()`.

#### Strategic notes

The split mirrors `radiant`'s structure but inverts its
release ordering: radiant shipped the meta-package early and
factored out sub-packages as the codebase grew. zzedc factors
out the *bounded-value* sub-packages first and holds the
larger Shiny meta-package back until the gap-analysis
question is settled empirically.

This phased version replaces the earlier "ship all 4 to CRAN
in ~6 weeks" sketch (preserved in revision history). The
honest argument against the all-at-once version: it bets ~6
weeks of focused work on the assumption that CRAN-EDC absence
is an opportunity. Phase 1 gets the high-confidence value
(REDCap-bridge tooling, regulatory helpers as a generic
library) onto CRAN in ~3-4 weeks while keeping the Phase 2
bet open and reversible.

### Path D — Skip the split; publish the monolith via R-universe + JOSS

CRAN was never the only path. R-universe (run by rOpenSci, with
core engineering by Jeroen Ooms) auto-builds packages from
GitHub at `<username>.r-universe.dev/`, exposes the standard
`install.packages()` workflow, and accepts packages whose scale
or shape make a CRAN-policy fight burdensome — including
Shiny meta-packages with broad dependency surfaces. JOSS
(*Journal of Open Source Software*) reviews and DOI-stamps the
software through a structured but lightweight peer-review
process (~1-3 month turnaround), producing a citable academic
paper that the manuscript can reference directly.

This path keeps zzedc as a single package — no Path-C split,
no per-sub-package CRAN-prep tail. ~1-2 weeks to set up
R-universe distribution and prepare the JOSS submission
(`paper.md`, statement of need, summary of features).

**Editorial-venue note**: rOpenSci Software Peer Review (the
more rigorous alternative to JOSS) is **not** a fit for the
un-split zzedc — Shiny meta-packages face the steepest scope
hurdle in rOpenSci review, and an EDC system competes with
REDCap as a known-quantity benchmark in ways that complicate
the "novel + scientifically useful" scope criterion. **JOSS is
the realistic editorial venue under Path D.** rOpenSci review
re-enters the picture under Path C, applied to the bounded
sub-packages where scope fit is much stronger (see the
"Optional editorial layer" subsection of Path C above).

This is a defensible choice, but note the strategic tradeoff:
the EDC-on-CRAN gap (no self-hosted system exists there) is a
real distribution opportunity. R-universe-only means the
package is discovered through search / word-of-mouth / the
manuscript; CRAN-published means it appears in
`available.packages()` for every R user, which materially
affects clinical adoption.

**Recommendation**: Path C (phased split with rOpenSci review
of `zzedc.import`, ~3-4 weeks for Phase 1 + ~2-6 month review
queue for the editorial layer) if CRAN presence is
strategically important (institutional procurement, "available
on CRAN" signaling for clinical adopters, surfacing in
dependency graphs of REDCap-interface packages). Path D
(R-universe + JOSS for the un-split zzedc, ~1-2 weeks of
software work plus the JOSS review queue) if the priority is
publication speed and a citable DOI for the manuscript. The
two paths are not mutually exclusive: Path D first to lock in
the DOI, Path C in parallel for the bounded sub-packages.

---

## 6. Pre-submission checklist (for whichever path)

- [ ] All Suggests packages are either guarded with `requireNamespace`
      or moved to Imports (E1).
- [ ] No `Sys.setenv()` outside `withr::with_envvar()` or with
      `on.exit()` restoration (E2).
- [ ] No hardcoded paths outside `tempdir()` in defaults (E3).
- [ ] No top-level executable code in `R/*.R` (E4).
- [ ] At least one runnable example per exported function, or
      `@keywords internal` (E5).
- [ ] LICENSE file matches CRAN template or DESCRIPTION drops
      "+ file LICENSE" (N1).
- [ ] `R CMD build .` succeeds.
- [ ] `R CMD check --as-cran` produces 0 ERRORs, 0 WARNINGs,
      ≤1 NOTE (typically the "new submission" NOTE).
- [ ] `devtools::check_win_devel()` passes.
- [ ] `devtools::check_mac_release()` passes.
- [ ] `urlchecker::url_check()` passes.
- [ ] All 3 built vignettes render in <2 min on CI.
- [ ] All 52 test files pass with no skips except documented ones.
- [ ] Version number revised if appropriate (W8).
- [ ] `cran-comments.md` written explaining the package and any
      remaining NOTEs.

---

*End of report.*
