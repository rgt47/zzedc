# zzedc (development version)

## Data and safety monitoring plans (Phase 1)

* New: storage, validation, and lifecycle of a study's data and
  safety monitoring plan, for the draft NIH policy update
  NOT-OD-27-006 (design: `docs/nih-dsm-monitoring-plan-design-2026-11-23.md`,
  not shipped). Functions: `dsm_validate_spec()`, `dsm_import_spec()`,
  `dsm_export_spec()`, `dsm_transition()`, `dsm_record_ico_decision()`,
  `dsm_plan_status()`, `dsm_plan_in_effect()`, `dsm_plan_history()`,
  and `migrate_add_dsm_tables()`.
* A plan version is an immutable row in `dsm_plan_versions`, so an
  electronic signature on it stays valid (signature verification
  re-hashes the whole row); the lifecycle is the append-only
  `dsm_plan_events`, from which the status is derived. Each event and
  its `DSM_PLAN_STATUS` audit record commit together.
* Lifecycle: draft, internal review, signed (an `APPROVED_BY`
  signature by a PI), submitted (with the user-entered submission
  date), then either the institute's decision as reported by the user
  (approved or revise) or, after the configured number of days with no
  decision (`zzedc.dsm_deemed_approval_days`, default 30;
  `zzedc.dsm_deemed_approval_day_type`, calendar by default), a move
  into effect that needs a `CERTIFIED_BY` attestation. zzedc never
  marks a plan approved by itself. A version put into effect
  supersedes the previous one in the same transaction.
* Specs are canonical JSON (sorted keys, full-precision numbers), so
  the spec hash survives export and re-import; YAML is read and
  written when the `yaml` package is installed. Validation reports
  every problem with its path. Risk categories are configuration
  (`zzedc.dsm_risk_categories`).
* Audit event types `DSM_PLAN_STATUS`, `RISK_INDICATOR_RUN`, and
  `RISK_THRESHOLD_BREACH` are added; `migrate_add_dsm_tables()` runs
  `migrate_audit_event_types()` for existing databases. A new test
  block verifies the migration on DuckDB with a real hash chain.
* Plan authors work in a spreadsheet: `dsm_generate_workbook()` writes
  an Excel workbook (sheets Plan, Risks, Indicators, Stopping rules,
  with drop-down lists for categories, levels, yes/no, grains,
  threshold units, and roles), optionally filled from an existing plan
  version for an amendment; `dsm_import_workbook()` reads it, or a
  directory of CSV files with the same names, into a new draft
  version, storing the file's SHA-256, and reports every problem by
  sheet, row, and column. Thresholds on `percent` rows are entered in
  percent (15 means 15%) and stored as proportions; a value strictly
  between 0 and 1 is refused as ambiguous.
* Amendments: `dsm_register_amendment()` registers a draft version
  (usually imported from a workbook generated from the version in
  effect) as an amendment of class `prior_approval` or
  `report_at_interval`, with a required summary and rationale. A
  `report_at_interval` amendment takes effect after the PI's signature;
  a `prior_approval` amendment only after the institute's approval is
  recorded, with no deemed-approval path. `dsm_amendments()` lists a
  study's amendments with the date each took effect, optionally within
  a reporting period.
* Optional activity gate: with the option
  `zzedc.dsm_require_plan_in_effect` set to `TRUE`,
  `randomize_next_subject()` and the first `db_insert_data_entry()`
  for a subject are refused unless a monitoring-plan version is in
  effect. The option is off by default under every security profile;
  when off, the check returns before any database access.
* Not yet: Google Sheets as a source, risk indicators, and reports. Not supported
  on ClickHouse. The inserts use `RETURNING`, which MySQL/MariaDB does
  not support, as elsewhere in the package's newer modules.
* Tests: `inst/tinytest/test_dsm_plan.R` (60 assertions),
  `inst/tinytest/test_dsm_workbook.R` (23),
  `inst/tinytest/test_dsm_amendments_gate.R` (27), plus 8 in
  `test_migrate-audit-event-types.R`.

## Electronic signatures: the application could not sign, and missing records could be signed

* **No signature could be applied through the application.** The
  Compliance tab offered lowercase meanings (`approved_by`), which
  `apply_electronic_signature()` rejects as invalid. The module test
  set `CREATED_BY` directly, so it never exercised the offered
  choices. The form now offers the codes the function accepts. (Verified
  by execution.)
* **Signatures could be applied to records that do not exist.** For a
  missing table or record, `compute_record_hash()` hashes a placeholder
  string, and the signature succeeded, bound to nothing.
  `apply_electronic_signature()` now refuses, writes no signature, and
  logs the attempt as `FAILED_VALIDATION`. (Verified by execution.)
* The form offered three fixed tables (`subjects`, `demographics`,
  `cognitive_assessments`) that a study may not have. It now offers
  the signable tables that exist in the database: by default
  `data_entries`, `subjects`, `adverse_events` and
  `protocol_deviations`, configurable with the
  `zzedc.signable_tables` option. The server also refuses a table
  outside that list, since the choice list is only a client-side
  restriction.
* Regression test: `inst/tinytest/test_signature_ui_record.R` (13
  assertions; 9 fail on the previous source).

## Electronic signatures: correct passwords were rejected

* **Signing rejected every correct password wherever the installation
  salt is non-empty**, which includes every installation created by
  `launch_zzedc()`. With an empty salt the salted and unsalted hashes
  coincide, so signing worked there.
  `verify_password_for_signature()`, which `apply_electronic_signature()`
  uses for re-authentication, compared an unsalted SHA-256 of the
  password with the stored hash, while the login, the setup wizard,
  and user management store SHA-256 of the password followed by the
  installation salt (`resolve_auth_salt()`). (Verified by execution
  with a user hashed by the application's rule, under a configured
  salt and under the default salt.) The tests did not catch it because
  their fixtures built unsalted hashes, matching the defect.
* The verifier now applies the login's rule, with the installation
  salt by default and an optional `salt` argument. The fixtures in
  `test_electronic-signatures.R`, `test_cfr-compliance-module.R`, and
  `test_subject_case_report.R` now build hashes the way the
  application does.
* Not changed here: failed signing attempts are logged but still do
  not count toward account lockout.
* Regression test: `inst/tinytest/test_signature_salt.R` (9
  assertions; on the previous source the 4 correct-password checks
  fail).

## Adverse events: every write is audited in the same transaction

* **Five of the six adverse event writers wrote no audit record.**
  `add_ae_followup()`, `update_ae_causality()`, `upgrade_to_sae()`,
  `record_sae_notification()`, and `resolve_adverse_event()` changed
  `adverse_events`, `sae_details`, and `ae_followups` without any
  entry in `audit_log`. `create_adverse_event()` wrote one through
  `log_audit_event()`, on a separate connection, inside a `tryCatch()`
  that discarded any error, so a failed audit write (even under the
  `regulated` profile) left the event stored and reported success.
  (Verified by execution: zero audit records from the five writers;
  an event stored with only a warning when the audit tables were
  absent.)
* Each writer now makes its changes and their audit records through
  `.append_audit_record()` inside one `.with_db_transaction()`, so a
  change commits only with its audit record. Follow-ups written as
  part of an update (causality, upgrade, notification, resolution)
  are in the same transaction as the update, and are audited too.
  A failed audit write now rolls the change back and returns
  `success = FALSE`, under every security profile.
* `upgrade_to_sae()` was not atomic: the AE update, the SAE details,
  and the follow-up were separate statements, the follow-up on its own
  connection, with its result ignored. A failure part-way could leave
  an AE marked serious with no SAE details. All three now commit or
  roll back together, and the update requires the event to be
  non-serious at the time of writing.
* `record_sae_notification()` returned `success = TRUE` for an
  `sae_id` that does not exist. It now returns `success = FALSE` with
  'SAE not found'.
* Regression test: `inst/tinytest/test_ae_audit.R` (25 assertions;
  14 fail on the previous source).

## Protocol compliance: every write is audited in the same transaction

* **Seven of the eight protocol compliance writers wrote no audit
  record.** `create_protocol()`, `add_protocol_visit()`,
  `schedule_subject_visit()`, `complete_subject_visit()`,
  `review_protocol_deviation()`, `add_eligibility_criterion()`, and
  `check_subject_eligibility()` wrote to their tables with no entry in
  `audit_log`. `create_protocol_deviation()` wrote one through
  `log_audit_event()` on a separate connection, inside a `tryCatch()`
  that discarded any error. (Verified by execution.)
* Each writer now makes its changes and their audit records through
  `.append_audit_record()` in one `.with_db_transaction()`. A failed
  audit write rolls the change back and returns `success = FALSE`.
* `complete_subject_visit()` was not atomic. The visit was written
  first; the timing deviation for an out-of-window visit was created
  on a separate connection, and if that failed the visit was kept
  unlinked while the result still reported `deviation_created = TRUE`.
  The visit, the deviation, and the link now commit together.
* `review_protocol_deviation()` returned `success = TRUE` for a
  `deviation_id` that does not exist. It now returns
  `success = FALSE`.
* `add_protocol_visit()`, `schedule_subject_visit()`, and
  `add_eligibility_criterion()` gain an optional last argument
  (`created_by`, `scheduled_by`, `created_by`) naming the user for the
  audit record. Existing calls are unaffected.
* Regression test: `inst/tinytest/test_protocol_audit.R` (26
  assertions; 15 fail on the previous source).

## DuckDB: adverse events could not be upgraded or resolved

* **On DuckDB, `upgrade_to_sae()` and `resolve_adverse_event()`
  failed for any adverse event that had a follow-up, and
  `review_protocol_deviation()` failed for any deviation linked to a
  visit,** with "Violates foreign key constraint because key ... is
  still referenced by a foreign key in a different table". The
  columns they update (`adverse_events.is_serious`,
  `adverse_events.status`, `protocol_deviations.review_status`) were
  indexed, and DuckDB rewrites an update of an indexed column on a
  row that a foreign key references as a delete followed by an insert,
  which its foreign-key checking rejects. This is the limitation
  already worked around for `correction_requests(status)`. (Verified
  by execution on `main`; SQLite was unaffected.)
* On DuckDB these three indexes are no longer created, and
  `init_adverse_events()` and `init_protocol_compliance()` drop them
  from a database initialized earlier. Other backends keep them.
* Regression test: `inst/tinytest/test_ae_deviation_duckdb.R` (13
  assertions; 7 fail on the previous source).

## Eligibility: missing data no longer makes a subject eligible

* **`check_subject_eligibility()` reported a subject eligible when
  the data for a criterion was missing.** A criterion whose field was
  absent from `subject_data` was skipped, so a subject with no value
  for an inclusion criterion (or an exclusion criterion) passed. A
  field present with value `NA` instead made the function fail with
  an error. (Verified by execution: `eligible = TRUE` for an
  `age >= 18` inclusion criterion with `subject_data = list()`.)
* A criterion that names a field is now indeterminate when the value
  is absent, `NULL`, `NA`, or empty, or the comparison cannot be
  evaluated. Any indeterminate criterion makes the check
  indeterminate: `eligible = FALSE`, `indeterminate = TRUE`, and the
  criteria are listed in `indeterminate_criteria`; the message says
  eligibility cannot be determined. The stored check records
  `overall_eligible = 0`.
* Criteria with no field (manual criteria, such as informed consent)
  are not evaluated, as before, and are now listed in
  `manual_criteria`. Each entry of `criteria_results` has a `status`
  of `EVALUATED`, `INDETERMINATE`, or `MANUAL`.
* Regression test: `inst/tinytest/test_eligibility_missing.R` (21
  assertions; 13 fail on the previous source).

## Test suite: the `skip()` helpers never skipped

* **Every `skip()` in the test suite was a silent no-op.**
  `inst/tinytest/_setup.R` defined `skip()` and four `skip_if_*()`
  helpers as calls to `exit_file()`. Test files `source()` that file
  into the global environment, where `exit_file` resolves to
  tinytest's exported stub, which only returns its message, so the
  helpers neither ended the file nor the block, and code written after
  a `skip()` ran. The helpers are removed (the `skip_if_*()` ones had
  no callers), and `_setup.R` documents the alternatives.
* Call sites: the 15 empty blocks in `test_quality-dashboard.R` are
  now structural checks of `quality_dashboard_ui()` (namespaced ids,
  each server output present with an output binding, card headers);
  the four empty module-UI stubs in `test_phase1-modules.R` now build
  `user_management_ui()`, `backup_restore_ui()`,
  `audit_log_viewer_ui()`, and `admin_dashboard_ui()`; empty backup
  and audit stubs are removed; the `skip()` in the wizard end-to-end
  test, whose assertions always ran and pass, is removed; and the
  unreachable DuckDB guard in `test_db-adapter.R` is an assertion.
* **The quality dashboard's QC flags panel was never filled.** The
  new output-binding check found `qc_flags_container` rendered as a
  plain `div` while `quality_dashboard_server()` assigns it with
  `renderUI()`; Shiny binds outputs only to output elements, so the
  panel stayed at "Loading QC status...". It is now a `uiOutput()`
  with the same placeholder. (Verified structurally, in the rendered
  HTML; not exercised in a browser.)
* Regression test: `inst/tinytest/test_setup-helpers.R` fails if a
  `_setup.R` helper calls `exit_file()` or the removed helpers are
  defined.

## ClickHouse adapter: the default port is the native port, 9000

* **A default ClickHouse configuration could not connect.**
  `default_db_config("clickhouse")`, the setup wizard's
  `build_adapter_config("clickhouse", ...)`, and the generated
  ClickHouse config template all defaulted `port` to 8123, ClickHouse's
  HTTP port. The adapter connects through `RClickhouse`, which speaks
  the native TCP protocol on port 9000, so every default configuration
  failed with `fail to connect` (reproduced against ClickHouse 26.10
  with both ports open). All three now default to 9000; an explicit
  `port` is still honored. The adapter's roxygen and the
  `create_db_adapter()` example now show 9000.
* The fallback to the HTTP `clickhouse` package, used only when
  `RClickhouse` is not installed, still defaults to 8123 when `port` is
  unset. A configuration built by `default_db_config()` now sets 9000,
  so that fallback needs an explicit `port = 8123`.
* Regression tests in `inst/tinytest/test_db-clickhouse-args.R`.

## ClickHouse adapter: compression is configurable and defaults to `"none"`

* **The ClickHouse adapter could not run a query against a current
  ClickHouse server.** `ClickHouseAdapter$connect()` and `$pool()`
  never passed `compression` to `RClickhouse`, whose default, `"lz4"`,
  fails against ClickHouse 26.10 with `unsupported compression method
  144` on the first query. Reproduced locally against
  `clickhouse/clickhouse-server:26.10` with RClickhouse 0.6.12; it had
  gone unnoticed because the ClickHouse CI job never ran (it is
  manual-only and failed earlier, at authentication).
* New `clickhouse$compression` setting, `"none"` (default) or `"lz4"`,
  passed by both `connect()` and `pool()` through one internal helper.
  Any other value is an error. `default_db_config("clickhouse")` and
  the generated ClickHouse config template set it to `"none"`, and
  `compression` is a recognized `default_db_config()` override.
* The adapter now passes the database as `dbname` instead of
  RClickhouse's deprecated `db`, which warned on every connection.
* Regression test: `inst/tinytest/test_db-clickhouse-args.R` (needs no
  server).

## ClickHouse adapter: `query()` and `execute()` with `params` work

* **Parameterized queries failed on ClickHouse.** RClickhouse
  implements no parameter binding, and the base adapter passed
  `params` straight to `DBI::dbGetQuery()`/`dbExecute()`, so the `?`
  placeholders reached the server unchanged (`Cannot parse expression
  of type String here: ?, ...`). `ClickHouseAdapter` now overrides
  `query()` and `execute()` to interpolate `params` with
  `DBI::sqlInterpolate()`, quoting each value through the
  connection's own methods (verified against ClickHouse 26.10 for
  embedded quotes, backslashes, `NA`, numbers, dates, and a `?` inside
  a string literal). A pool is checked out for the call and returned.
* The backend suite's three ClickHouse skips (transaction commit,
  rollback, uniqueness constraints) used `skip()`, which was a no-op
  (see "Test suite: the `skip()` helpers never skipped" above); the
  rollback and constraint assertions therefore ran and failed on
  ClickHouse. They now `return()` from the callback.
* With these and the compression fix, every `test_db-*` file passes
  against a local ClickHouse 26.10 server (143 results, 0 failures).

## Portfolio review follow-up: F-NEW8 and F-NEW1 confirmed already fixed; documentation regenerated

* **F-NEW8** (Google Sheets form loader bypassing encryption) and
  **F-NEW1** (Admin/Compliance/Corrections module access surviving
  logout) were both flagged in the 2026-11-16 portfolio reconciliation
  as needing an owner design decision before being fixed. Re-checked by
  direct reproduction (not just inspection) on 2026-11-20: both were
  already fixed the next day, 2026-11-17, before this review ever
  happened -- the reconciliation note was simply stale. F-NEW8 gained
  one additional regression assertion here (the 0-byte-file side
  effect on a nonexistent explicit `db_path`, a narrower leftover not
  covered by the existing F-NEW8 test block). F-NEW1 needed no new
  test: `test_module_auth_guard.R` already exercises exactly this
  scenario (mounts every affected module, flips `authenticated` from
  `TRUE` to `FALSE` mid-session the way a real logout does, asserts
  writes/renders are blocked) and already passes.
* `man/get_data_entries.Rd` regenerated (a codoc mismatch for
  `canonical_dde_only`, added earlier without re-running `roxygen2`)
  and `man/update_second_entry_for_dde_resolution.Rd` added (the same
  gap, for a function added in the same earlier pass).

## `initialize_encrypted_database()`'s `$success` no longer hides a silently unencrypted SQLite database (F1)

* **`success = TRUE` for an unencrypted SQLite database, closed.**
  Under the `standard` security profile with
  `security.accept_unencrypted_sqlite: true` (an explicit deployer
  opt-in), or under the `development` profile, `initialize_encrypted_
  database()`'s SQLite path (`init_encrypted_sqlite_database()`)
  created a genuinely plaintext database and returned `success =
  TRUE, encrypted = FALSE`. A caller that checked only `$success` --
  the natural thing to check -- had no way to learn that encryption
  had silently not happened; it had to separately inspect
  `$encrypted`. `regulated`, and `standard` without the opt-in, were
  already correct (`.enforce_sqlite_at_rest()` throws, and
  `success = FALSE` was already returned there).
* **The fix.** On SQLite, `$success` now mirrors `$encrypted`:
  `TRUE` only when the database was both created and actually
  encrypted at rest. For the "created but left unencrypted" case
  (`standard` + opt-in, or `development`), `$success` is now
  `FALSE`, but `$path`, `$key`, and `$encrypted` remain populated and
  usable -- the file genuinely was created, and `$success = FALSE`
  here means only "not encrypted," not "nothing was created."
  `$message` now says plainly that `success` is `FALSE` for that
  reason, not because creation failed. `$error` continues to be set
  only on an actual creation failure, so `is.null(result$error)` (or
  checking that `$key`/`$path` are non-NULL) is the right way for a
  caller to ask "did this call produce something I can use," leaving
  `$success`/`$encrypted` for "is it actually encrypted." DuckDB and
  the server backends are unchanged: `$success` there continues to
  mean only that creation did not fail.
* **Callers updated.** Three production call sites that gated on
  `$success` to decide whether creation itself failed now check
  `$error` instead, so they keep working under the opt-in/development
  cases exactly as before while still surfacing the true encryption
  state via the nested result they already return
  (`migrate_to_encrypted()` in `R/db_migration.R`, the REDCap importer
  in `R/redcap_import.R`, the Google Sheets setup path in
  `R/validation_gsheets_integration.R`), plus the IQ-004 "Database
  Initialization" installation-qualification check in
  `R/validation_framework.R`, which qualifies that creation succeeds,
  not that encryption is active (a security-profile/OQ concern
  checked elsewhere). Roughly 45 tinytest files construct a
  throwaway SQLite database via this function as pure test setup
  under the suite's default `development` profile; of those, 18 had
  an incidental `$success` assertion on that setup call and were
  updated to check `$error` (or, in `test_encryption.R`, to assert
  the new success/encrypted contract directly where the test's
  actual subject is `initialize_encrypted_database()` itself). The
  authoritative security-profile tests
  (`test_security_profile.R`, `test_encryption_default_backend.R`,
  `test_db-adapter-phase-c.R`) were rewritten to the new contract and
  extended with an explicit `standard` + opt-in regression case. The
  `regulated` and no-opt-in refusal paths, and the genuinely encrypted
  case, were already correct and are unchanged.

## Fourth-pass fixes to double data entry and reporting, found by a fourth round of review

* **The discrepancy-resolution modal's reload/data-loss gap, closed.**
  The second entry used to be held only in a Shiny `reactiveVal` until
  the modal was confirmed, so dismissing it (a browser reload, say)
  lost the second entry and its audit trail entirely, with no record
  that entry #1's value was ever shown on screen -- and because
  nothing had been saved yet, the same user could reload and re-key a
  value that now matched entry #1, with no trace the two had ever
  disagreed, defeating the blind-entry design. The second entry is
  now saved immediately when a discrepancy is first detected, every
  flagged field defaulted to `"flag_for_review"`
  (`apply_dde_resolutions()` with no resolutions supplied), *before*
  the modal is shown; `update_second_entry_for_dde_resolution()` (new)
  only *upgrades* that already-saved row once the enterer actually
  picks a resolution, never inserting a second time. A reload now
  simply leaves the field open in the reconciliation queue -- nothing
  lost -- and a reload-then-resubmit is refused as a genuine third
  submission (`dde_decide_role()`'s `already_paired` guard), closing
  the blinding bypass. Covered by a new regression test exercising
  both the "abandoned modal" state and a real resolution upgrade.
* **`data_entries` readers double-counting a DDE pair, closed.** No
  reader excluded the non-canonical (second) row of a double-data-entry
  pair, so every aggregate count, export, and Data Explorer listing
  double-counted every double-entered subject/form.
  `get_data_entries()` gained `canonical_dde_only` (default `FALSE`,
  unchanged for tracking-ID bookkeeping and the subject case report,
  which both still need every row), excluding the non-canonical row
  via `dde_group_id` and entry order -- filtering on `superseded_by`
  alone cannot work, since an unresolved pair has it `NULL` on both
  rows. Set to `TRUE` in `compute_data_quality_summary()`,
  `summarize_choice_field_values()`, `flatten_crf_entries_for_export()`,
  and `flatten_all_entries_for_explorer()`; `summarize_entries_by_form()`
  (its own raw SQL query, not routed through `get_data_entries()`)
  fixed the same way directly. The Manuscripts report's drill-through
  and row-count-aligned `entry_id` lookup (`inst/app/report6.R`,
  `inst/app/report_drilldown.R`) updated to match. Covered by a new
  regression test inserting a DDE pair and checking every affected
  reader's count.
* Part C's one previously-unverified risk (draft-resume plus a
  mid-edit display-setting toggle) was re-verified live against a
  fresh scratch study: saved a draft, toggled to 2-column layout and
  expanded tooltips mid-edit, confirmed the already-typed values
  survived the re-render, finished and submitted, and confirmed via a
  direct database query that `data_json` held every field correctly.
  Not a bug.

## Third-pass fixes to double data entry, found by a second round of review

* `update_first_entry_for_dde_resolution()` wrote the recorded
  `second_value` to the canonical entry for **both** `"keep_second"`
  *and* `"revert_first"` resolutions. For `"revert_first"` that
  `second_value` is the pre-resolution, *rejected* value, so a
  settled, already-correct canonical entry was overwritten with the
  value the reconciliation just rejected -- the opposite of the
  previous ("second-pass") fix's own intent. `"revert_first"` needs no
  change to the canonical entry at all (it was never wrong); only
  `"keep_second"` does. Reproduced live in the browser (entry #1 held
  "100", a conflicting "222" was submitted and reverted, entry #1 was
  confirmed unchanged at "100" afterward, not corrupted to "222") and
  covered by a new test that calls the function directly with a
  `"revert_first"` resolution and checks the canonical entry.
* The reconciliation queue's `superseded_by` marker was previously
  only ever set after a queued `DDE_DISCREPANCY` correction was
  applied; a pair fully resolved at save time (no field left
  `"flag_for_review"`) was never superseded at all. The confirm-
  resolution handler (`inst/app/edc.R`) now calls
  `close_dde_group_if_resolved()` itself right after a fully-resolved
  save. Also reordered that handler to insert the second entry
  *before* updating the canonical entry, so a late failure leaves the
  second entry safely saved and the field visible in the
  reconciliation queue, rather than risking losing the second entry
  entirely.
* `nzchar(NA)` is `TRUE` in R (confirmed directly) -- the blank-
  Subject-ID guard's `!nzchar(trimws(as.character(...)))` alone let a
  genuinely missing (`NA`, not just `""`) tracking ID straight
  through; `is.na()` is now checked explicitly first.
* `list_dde_discrepancies()` swallowed any error resolving a form's
  flagged fields (not just the ordinary "no such form" case, which
  needs no error handling at all) into `character(0)`, which
  `close_dde_group_if_resolved()` would read as "nothing open, safe to
  supersede" -- a transient failure could have silently closed a group
  that still had a real, undetected discrepancy. The error now
  propagates.
* `migrate_correction_reasons()`'s rebuilt tables used a hardcoded
  `INTEGER PRIMARY KEY` instead of `auto_increment_ddl()`, which on
  DuckDB has no `DEFAULT nextval(...)` (unlike SQLite's ROWID-aliasing
  magic) -- an ordinary insert that omits the id column entirely,
  exactly what `create_correction_request()` does, would fail outright
  after migration. The DuckDB regression test previously inserted
  explicit ids by hand and could not see this; rewritten to build the
  old schema with the real `auto_increment_ddl()` (what
  `init_data_correction()` itself would have created) and insert
  through the real `create_correction_request()`/`approve_correction()`
  API before and after migrating. Separately confirmed (not just
  inspected) that `ensure_data_entries_table()`'s plain `ALTER TABLE
  ADD COLUMN` migration for `dde_group_id`/`superseded_by` succeeds on
  DuckDB with existing rows and the `subject_id` index in place.

## Double data entry (DDE), per field, with immediate discrepancy detection and a reconciliation queue

* Per-*field* opt-in: a new `designer_fields.require_double_entry`
  boolean (`R/crf_designer.R`, migrated onto an existing database the
  same idempotent describe-then-ALTER way `widget_file`/`help_detail`
  were), settable via `add_form_field()`/`add_form_field_by_code()`
  alongside `is_required`. Finer-grained than either reference tool
  this design was checked against: REDCap's DDE module is
  project-wide, OpenClinica's is per-form.
* **Capture.** A form with any flagged field requires two independent,
  full submissions of the same Subject ID (`inst/app/edc.R`'s
  `submitcrf` handler), linked by a new, nullable
  `data_entries.dde_group_id` -- both rows are ordinary, complete
  (`is_complete = 1`) `data_entries` rows, never routed through the
  draft/"Save and Finish Later" machinery, which is hidden entirely
  for a flagged form (`output$savedraftcrf_ui`) since completing a
  resumed draft would otherwise bypass DDE's group-linking and diff.
  Different users are required by default (REDCap's default); the
  second submission's form-load path never fetches the first entry's
  `data_json` at all (only its `entry_id`/`created_by`, via the blind
  probe `db_get_dde_first_entry()`) -- there is nothing in the DOM or
  server-side reactive state for the second enterer to see or recover,
  a stronger guarantee than disabling copy/paste on a visible value.
* **Immediate per-item check**, flagged fields only: at second-entry
  save time, `R/double_data_entry.R`'s `dde_check_discrepancies()`
  diffs the in-memory second submission against the first entry's
  saved values (fetched only here), reusing
  `R/version_control.R`'s `diff_field_lists()` -- the same per-field
  diff engine `compare_versions()` uses, extracted so there is one
  diff implementation, not two. A mismatch on a field that is *not*
  flagged is never checked. A flagged mismatch surfaces immediately in
  a modal with three choices (`apply_dde_resolutions()`): keep the
  second entry's value, revert to the first entry's, or leave both and
  flag for reconciliation review. The first two are recorded directly
  in the second entry's own audit record (`db_insert_data_entry()`'s
  new `audit_extra` parameter) -- no separate correction request for a
  discrepancy resolved in the moment. The first entry is kept in
  agreement for every `"keep_second"`/`"revert_first"` field too
  (`update_first_entry_for_dde_resolution()`), with its own `"UPDATE"`
  audit record -- an earlier draft of this change recorded the
  resolution choice only in the second entry's audit trail and left
  the canonical first entry's stored value untouched, which both gave
  a reporting/export read of the canonical record the wrong value for
  a `"keep_second"` field and left that field surfacing in the
  reconciliation queue forever (its live diff against the first entry
  never went to zero); caught before merge by re-reading the design
  against the implementation, not by the manual walkthrough, which had
  only exercised `"flag_for_review"`.
* **Reconciliation queue**: a new "DDE Reconciliation" view in the
  Corrections tab (`R/data_correction_module.R`), listing every open
  `dde_group_id`/field left "flag for review"
  (`list_dde_discrepancies()`). Resolving one files a correction
  request through the existing `create_correction_request()` /
  `approve_correction()` / `apply_correction()` workflow with a new
  reason, `DDE_DISCREPANCY`. A new, narrower guard,
  `require_dde_reviewer_separation()`, blocks either of the two
  entry's users from approving or applying a `DDE_DISCREPANCY`
  request specifically (REDCap's "reviewer is neither entry person"
  rule) without changing `approve_correction()`/`apply_correction()`'s
  existing self-approval behavior for any other correction. Enforced
  inside `approve_correction()`/`apply_correction()` themselves
  (`.require_dde_reviewer_separation_for_request()`), failing closed
  on a lookup error, so a scripted caller going directly to either
  function is covered the same as the Shiny module -- an earlier
  draft of this guard lived only in the Corrections module's own
  closure and both failed open (`tryCatch(..., error = function(e)
  NULL)`, i.e. "allow") and never applied outside that one UI path.
  Once a group's last open discrepancy is applied, the non-canonical
  entry is marked `superseded_by` the canonical one (a new, nullable
  `data_entries` column) -- kept for audit, never deleted, per this
  package's insert-only design.
* A flagged form refuses a submission with a blank Subject ID (it
  would otherwise fall back to `save_crf_entry()`'s own
  auto-generated, always-unique subject ID, silently defeating DDE
  pairing -- each such submission would be "the first entry" of its
  own group that can never be completed) and refuses a third
  submission once a subject/form's pair is already complete
  (`dde_decide_role()`'s new `already_paired`, backed by
  `db_count_dde_group_entries()`).
* `correction_requests.correction_reason` carries its own hardcoded
  `CHECK(correction_reason IN (...))` list, independent of
  `get_correction_reasons()`; adding `DDE_DISCREPANCY` to the latter
  without also migrating the former left every reconciliation request
  rejected at the database layer with a raw `CHECK constraint failed`
  error (caught during this pass's own manual walkthrough, not left
  for a user to find). `migrate_correction_reasons()`
  (`R/data_correction.R`) rebuilds `correction_requests` (and its two
  FK-dependent tables, `correction_history`/`correction_overrides`,
  unchanged) with the current reason list, mirroring
  `migrate_audit_event_types()`'s SQLite/DuckDB table-rebuild strategy
  (no `ALTER ... DROP/ADD CONSTRAINT` on either backend) and
  PostgreSQL/MySQL's direct `ALTER TABLE` (the latter inspected, not
  verified against a live server, same disclosure
  `migrate_audit_event_types()` makes). Runs automatically,
  idempotently, at the top of `init_data_correction()`, which is
  itself already called at every app session start
  (`inst/app/gsheets_server_integration.R:380`) -- confirmed by
  reading that call site, not assumed. An initial version of this
  migration's DuckDB path reused the SQLite rebuild's rename-based
  strategy directly; tested against a hand-built old-schema DuckDB
  database with real `correction_history`/`correction_overrides` rows
  and failed with DuckDB's documented "Dependency Error: Cannot alter
  entry ... because there are entries that depend on it" (the same
  limitation `migrate_audit_event_types()`'s own comment warns against
  repeating). Replaced with that function's actual DuckDB strategy --
  copy all three tables to unconstrained staging tables, drop the
  three originals, recreate them with the updated `CHECK`, copy the
  data back in -- and re-verified against the same hand-built database
  (data preserved, a new `DDE_DISCREPANCY` request accepted
  afterward, a second migration run a no-op).
* `add_form_field()` previously always included `require_double_entry`
  in its `INSERT`, which would fail outright (not just silently drop
  the flag) on any database where `init_crf_designer()`'s own
  migration had not re-run since this column was introduced; it now
  checks for the column first, the same way `get_crf_field_metadata()`
  already guards its own `SELECT`. `setup_wizard_utils.R`'s two
  `data_entries` `CREATE TABLE` statements (the other schema-creation
  path besides `R/db_data_entries.R`'s `ensure_data_entries_table()`,
  found the same way the equivalent check for `designer_fields` was
  done) now also declare `dde_group_id`/`superseded_by` for a
  brand-new database.
* **Cosmetic gap, since fixed**: the Corrections tab's
  DDE-Reconciliation-queue "File Correction Request" hand-off used to
  lose the Field dropdown's pre-selection (it came up showing "Select
  field...", needing one manual click). The actual cause was exactly
  the suspected race -- `output$field_picker`'s `renderUI()` rebuilds
  the `<select>` from scratch on the same `crf_context()` recompute a
  separate `updateSelectInput()` was targeting, even when deferred via
  `session$onFlushed()`. Fixed by having `field_picker`'s own
  `renderUI()` read the pending field and bake it into the
  `selectInput()`'s `selected` argument directly, so the choices and
  the selection are set together in one render rather than two
  competing writers. Covered by a new regression test driving the
  module's pending reactiveVal directly and checking the rendered
  `<select>` HTML for the pre-selected `<option>`.
* **Documented, not built this pass** (open decisions from the design,
  made explicit rather than left as implementation accidents): an
  unreconciled discrepancy is intended to block a future "Lock Visit"
  control, but no such control exists yet anywhere in this app to wire
  that into. A coarser project- or form-wide bulk "require double
  entry on every field" toggle (REDCap-style convenience) was
  considered and deliberately not built -- a thin helper over the same
  per-field flag would be a reasonable later addition.
* **Known gaps, disclosed rather than fixed this pass; both since
  fixed, see "Fourth-pass fixes" above**:
  - ~~If the discrepancy-resolution modal is dismissed by reloading
    the browser...~~ fixed: the second entry is now saved immediately
    with a safe default, before the modal ever renders.
  - ~~Readers downstream of `data_entries`... double-count a
    `superseded_by` row...~~ fixed: `get_data_entries(canonical_dde_only
    = TRUE)` and its callers.
  - `tracking_id_already_used()`'s duplicate-tracking-ID check (today
    only enforced for the `manuscripts` form's `PUB-YYYY-N`
    convention) would reject a DDE second entry on any future form
    that both flags a field for double entry and carries a tracking-ID
    convention, since the second entry deliberately reuses the first
    entry's Subject ID. No current form combines the two, so this has
    not been reachable in practice, but the interaction was not
    resolved.

## A per-session "Display" control: dark mode, multi-column CRF layout, expanded tooltips

* A gear-icon "Display" popover, reachable from every tab (not gated
  behind any role -- it is a display preference, not a privileged
  action), holds three independent, session-only settings: dark mode,
  the EDC form's column count (1/2/3), and field-help-text verbosity
  (minimal/expanded). None of the three is persisted to the database
  or `localStorage`: this app is typically used on shared site/clinic
  machines (`content-author-guide.Rmd`), so a display preference
  sticking to one person's browser indefinitely is the wrong default.
  Added `.zzedc_display_settings_control()` and
  `.zzedc_dark_mode_overrides()` (`R/rgtlab_theme.R`), mounted by both
  `inst/app/ui.R` and `inst/app/gsheets_ui_integration.R`; the three
  inputs are mirrored into a `display_settings` `reactiveValues`
  (`inst/app/server.R`) by observers in
  `gsheets_server_integration.R`'s `create_enhanced_server()`.
* **Dark mode** is `bslib::input_dark_mode(mode = "light")` wired to
  the existing `bs_theme()` -- `bs_theme()`'s own theme colors flip
  automatically, but several hardcoded light-mode values (the
  `--rgt-*` custom properties, `.card-header`/`.well`/
  `table.dataTable thead th`'s literal hex colors) do not;
  `.zzedc_dark_mode_overrides()` supplies the missing
  `[data-bs-theme="dark"]` rules. Visually confirmed: navbar, form
  cards, the EDC form panel, and a `DT::datatable()`-based report all
  stay legible after toggling.
* **Multi-column CRF layout.** `designer_fields` has long had
  `field_row`/`field_column`/`field_width` columns, set at form-design
  time and already used to `ORDER BY` in
  `get_crf_field_metadata()` -- but never read into the metadata list
  that function returns, so nothing could act on them.
  `get_crf_field_metadata()` now includes all three, and
  `renderPanel()` (`R/renderpanels.R`) gains a `columns` argument:
  `columns > 1` groups the already-ordered field list into the
  already-ordered field list's contiguous runs of equal `field_row`,
  splits any run longer than `columns` into chunks of at most
  `columns` fields, and wraps each chunk in `shiny::fluidRow()` with
  one `shiny::column()` per field, width scaled from that field's
  `field_width` percentage against the chunk's total. A form whose
  fields were each given their own `field_row` (as some imports
  annotate every field) still renders one field per visual row
  regardless of `columns` -- the cap only ever reduces how many
  fields share a row, it never combines fields the form's own author
  put on separate rows. `columns <= 1` (the default) returns the
  original flat, one-field-per-line stack -- byte-identical to
  calling `renderPanel()` without the argument at all.
* **Expanded tooltip mode.** Every field already got an
  always-present hover icon with help text. `tooltip_mode =
  "expanded"` additionally renders that help text as a permanently
  visible `shiny::tags$small()` beneath the input -- strictly
  additive, the hover icon is never removed. `tooltip_mode =
  "minimal"` (the default) is unchanged.
* `renderPanel()` also gains an `extra_tags` argument: a named list,
  keyed by field name, of extra UI (e.g. a custom field widget's
  trigger control) to attach to that exact field. This replaces
  `inst/app/edc.R`'s previous pattern of splicing extra UI into
  `renderPanel()`'s returned list by position, which broke once
  `columns > 1` meant that list was no longer one element per field.
* The dynamic-CRF `renderPanel()` call site in `inst/app/edc.R`
  (`output$edc_crf_fields`, the one driving every study-defined form)
  now reads `columns`/`tooltip_mode` from the session's
  `display_settings`, live (not `isolate()`d), so a Display-preference
  change applies immediately. The other call site
  (`renderPanel(blfieldlist)`, the legacy demo `forms/*.R` scaffold
  inside `output$ui`) is deliberately left untouched: it has no
  `field_metadata` to act on (`columns`/`tooltip_mode` are no-ops on
  that path regardless, per `renderPanel()`'s own roxygen), and it
  sits inside a different `renderUI` with no snapshot/restore of its
  own -- wiring it in without that would re-render the legacy form on
  every preference change and silently drop whatever was typed.
  Toggling a preference re-renders the current form's
  fields, which would otherwise silently discard whatever the viewer
  had already typed (and, for a resumed "Save and Finish Later"
  draft, risk saving blanks over it on the next save); a snapshot/
  restore pass (`output$edc_crf_fields`, guarded by "is this a
  same-form re-render, not an actual form switch or first render")
  captures every field's current value before the re-render and
  restores it via `fill_crf_field_inputs()` once the new DOM exists,
  re-applying a resumed draft's `tracking_id` lock as well. A `file`
  field's chosen upload cannot be restored this way (no
  `updateFileInput()` exists) -- the same pre-existing limitation
  `fill_crf_field_inputs()` already documents for the draft-resume
  path. The "same-form re-render" guard is by `crf_id`, not by what
  triggered the re-render, so it also protects (as a side effect, not
  requested this pass) the pre-existing `randomize_refresh()` bump
  after a successful Randomize click, which previously re-rendered
  the whole form and silently discarded every other field's typed-in
  value too.
* Left for later, not built this pass: letting a study designer
  *cap* a form's column count (so a dense form can force 2-column
  display regardless of a viewer's 1-column preference) -- this
  pass's columns setting is purely a per-viewer preference, as the
  plan's "open decision" explicitly allowed.

## A CRF form that takes more than one sitting can now be saved as "Incomplete" and resumed

* Previously every CRF submission was all-or-nothing: `save_crf_entry()`
  always called `db_insert_data_entry()` with `is_complete = TRUE`
  hard-coded, even though the `data_entries` schema already carried an
  `is_complete` column (default `0`) that nothing ever set to `FALSE`.
  A form that could not be finished in one sitting had no good option:
  submit partial data as if final and "correct" the rest in later
  (misusing a workflow for changing an existing settled value, not
  giving a field its first value), or keep a browser session open
  indefinitely, which Shiny does not support across a real gap and
  loses every keystroke on disconnect.
* The EDC tab's CRF form now has a second action, "Save and Finish
  Later", alongside "Submit entry". It accepts whatever subset of
  fields is currently filled in -- it still runs
  `validate_crf_submission()`'s type/choice/format checks on whatever
  IS present, just not the required-field check -- and saves with
  `is_complete = FALSE`. Tracking-ID uniqueness and this form's
  cross-field DSL rules are record-*completeness* checks and
  deliberately do not run on a draft save; they still run, as before,
  at full "Submit" time.
* New `db_update_incomplete_data_entry()` (`R/db_data_entries.R`) is
  the update path a second save of the same draft needs:
  `db_insert_data_entry()` is insert-only by design (one row per
  `entry_id`, audited as a single `INSERT`), so a second "Save and
  Finish Later" on the same entry now updates that one row's
  `data_json`/`is_complete`/`modified_date`/`modified_by` in place
  (its own `"UPDATE"` audit record, distinct from the original
  `INSERT`) instead of creating a second row. It refuses -- returns
  `success = FALSE`, does not silently no-op -- an attempt to update a
  row that is already `is_complete = 1`; that path belongs to the
  correction workflow (`create_correction_request()`/
  `approve_correction()`/`apply_correction()`), not this function,
  and nothing about this change alters that workflow's own behavior
  on a settled record.
* **Resume key: `entry_id`, via a "Continue" row action, not
  `tracking_id`.** `save_crf_entry()`'s existing timestamp-based
  `subject_id` fallback (for a form with no `tracking_id` field, or a
  blank one) makes `tracking_id` an unreliable key to resume a draft
  by, and reusing it would also have required teaching
  `tracking_id_already_used()` to exclude a draft's own row from its
  duplicate check. `crf_entries_table` (the EDC tab's own entries
  list, already scoped to the currently selected form) instead gets a
  "Continue" button on any row still `is_complete = 0`, in place of
  that row's "Request Correction" button -- a draft has no settled
  value yet to correct, so `create_correction_request()` now refuses
  one directly (and the Corrections tab's CRF-aware field picker shows
  a message instead of letting one through) regardless of how it is
  reached. Because "Continue" only ever appears for the form already
  on screen, resuming fills the existing inputs directly via new
  `fill_crf_field_inputs()` (`R/edc_dynamic_forms.R`, the mirror image
  of the existing `reset_crf_field_inputs()`) rather than re-rendering
  the form -- the same length-aware blank-value coercion already used
  by the report/export flattening functions, applied in the opposite
  direction. A resumed draft's `tracking_id` input is disabled for the
  rest of that resume (`shinyjs::disable()`): the row's real key
  (`subject_id`) is fixed at its original insert and never changed by
  `db_update_incomplete_data_entry()`, so letting the visible
  `tracking_id` field drift out of sync with it would be silently
  misleading, not merely cosmetic.
* **Cross-user resume is allowed, matching REDCap/Medidata Rave
  precedent** (per the design plan this follows; see its own note
  below on that citation's verification status) -- any user with
  access to the form may continue a draft someone else started,
  consistent with those tools treating "Incomplete" as a real, shared
  record state, not a personal scratch pad.
* **Visibility of a draft elsewhere in the app**, decided per
  call site rather than uniformly:
  - `flatten_crf_entries_for_export()` (the Export tab) now excludes
    any `is_complete = 0` row by default (`get_data_entries()`'s new
    `include_incomplete` argument) -- an export is a record of
    finished data, and an unlabeled draft mixed in would be
    indistinguishable from a finished entry with blank optional
    fields.
  - `summarize_entries_by_form()` (the Reports tab's per-form stat
    cards) now counts only `is_complete = 1` rows, for the same
    reason: an aggregate count that includes an unfinished record
    overstates how much real data exists.
  - `flatten_all_entries_for_explorer()` (the Data Explorer tab, an
    admin-level raw listing) still includes a draft -- deliberately,
    not an oversight -- but now adds a `status` column
    (`"Incomplete"`/`"Complete"`) so one is never mistaken for a
    finished record there.
  - `crf_entries_table` (the EDC tab's own entries list) gained the
    same `Status` column.
  - `generate_personal_statement_draft()` and the Subject Case Report
    (`generate_subject_case_report()`) were deliberately left
    unchanged for this pass -- both still count/include every row
    regardless of `is_complete`. Revisit if a draft's appearance in
    either turns out to matter in practice.
* **No staleness policy for an abandoned draft** -- matching
  REDCap/Rave precedent, intentionally: an incomplete row nobody ever
  returns to finish just sits there, with no expiry or cleanup job.
* **No schema migration.** `is_complete`, `modified_date`, and
  `modified_by` already existed on `data_entries` in every
  schema-creation path (`ensure_data_entries_table()`,
  `create_core_tables()`/`setup_wizard_utils.R`, and the ClickHouse
  branch of each) before this change; nothing here adds a column.
  `db_insert_data_entry()` remains the only writer of `data_entries`
  in the package (confirmed by grep), so every existing row's
  `is_complete` already reflects its caller's own explicit intent --
  there is nothing to backfill on an existing study database either.
* A note on this feature's design citation: the plan this follows
  states that REDCap's and Medidata Rave's "Incomplete" form-status
  behavior was "checked directly" via web search -- that claim was
  not actually true of the search that had already run as of the
  plan's own writing. A web search run during this implementation
  pass (not REDCap's own official documentation, but several
  institutional user guides -- University of Utah, UNMC, University
  of Alberta -- that agree with each other) confirms the core
  behavior this design follows for REDCap specifically: "Incomplete"
  is a real saved status a form can be left in, the record stays
  open and can be reopened from the Record Status Dashboard (or the
  Classic-project record dropdown) to add or change data, and nothing
  about leaving a form Incomplete discards what was already entered.
  Medidata Rave's behavior was not checked at all in this pass, by
  web search or otherwise, and remains unverified; the design treats
  it as following the same pattern on the strength of general EDC
  domain knowledge, not a checked source. The design built here is
  sound on its own technical merits regardless of either citation's
  status. The plan file's "checked directly" wording should still be
  corrected to reflect this -- confirmed for REDCap now, still
  unverified for Rave.

## The Compliance tab errored on every study, old or new

* `init_electronic_signatures()` existed but nothing in
  `launch_zzedc()`'s own startup path ever called it -- unlike
  `data_entries`/`edc_users`/`user_training`/`audit_log`, which are
  all ensured there before the app starts. Opening the Compliance
  tab on any study, freshly wizard-created or years old, failed with
  "Catalog Error: Table with name electronic_signatures does not
  exist!" the moment its dashboard tried to read signatures.
  `launch_zzedc()` now initializes it alongside audit logging, the
  same idempotent `CREATE TABLE IF NOT EXISTS` pattern as the rest of
  the checklist. Reproduced live against a real study.
* Fixing that uncovered two more of the same class in the Compliance
  dashboard's other queries. Its audit-trail query read from
  `enhanced_audit_trail`, a table nothing in the package ever
  created; its columns (`timestamp`, `user_id`) are exactly
  `audit_log`'s, so the query now reads from `audit_log` instead. Its
  system-validation query read from `system_validation`, which also
  had no `CREATE TABLE` anywhere and no writer of any kind (the same
  gap `user_training` had before an earlier fix) -- new
  `ensure_system_validation_table()` closes it, wired into
  `launch_zzedc()`'s startup checklist alongside
  `ensure_user_training_table()`. There is still no UI for recording
  a validation run; this only stops the dashboard's read from
  failing.

## A cleared field crashed the Manuscripts report and the Export tab

* `flatten_crf_entries_for_export()` coerced each field's stored
  value with a plain `as.character(v)`, which assumed a blank value
  is always a length-1 `NA`. A cleared `dateInput()` (and similarly
  cleared optional fields) round-trips through
  `jsonlite::toJSON()`/`fromJSON()` as a zero-length `list()`, not
  `NA` -- JSON has no `NA`, only `null` or `[]` -- so
  `as.character(list())` returned `character(0)`, and `vapply()`
  rejected it outright ("values must be length 1, but FUN(X[[1]])
  result is length 0"), crashing every form's row with such a field
  for both the Manuscripts report and the Export tab.
  `flatten_all_entries_for_explorer()` already had the correct
  length-aware coercion for this; `flatten_crf_entries_for_export()`
  now has the same one. Reproduced live against a real study's
  manuscripts entries.

## Optional self-approval for single-user deployments

* `approve_correction()`'s "someone else must approve" rule
  (§11.10(g)) assumed a second reviewer exists. A single-user
  deployment -- a solo researcher's own tracker, a one-account study
  registered with `zzedc::launch_lab()` -- has no one else, so every
  correction request was a dead end: created, never approvable.
  `resolve_allow_self_approval()` (option `zzedc.allow_self_approval`,
  environment variable `ZZEDC_ALLOW_SELF_APPROVAL`, or `security:
  allow_self_approval:` in `config.yml`; default `FALSE`) lets the
  deployer opt in. Approval, its role check, and its audit trail are
  otherwise unchanged; a self-approval is recorded in the audit
  details, never silent.

## Reports link to the entries behind a count

* Activity Summary's per-form entry count, Domain Breakdown's
  per-field-value count, and the Personal Statement draft's count
  clauses (manuscripts, courses, mentoring, grant/committee/journal
  reviews, DSMB) are now links. Clicking one opens a modal listing
  the matching `data_entries` rows (narrowed to one field's value for
  Domain Breakdown), each with a "Review" button. There is no direct
  in-place editor for a submitted entry (every change goes through
  `create_correction_request()`/`approve_correction()`/
  `apply_correction()`, per R/data_correction.R's 21 CFR Part 11
  design), so "Review" starts a correction request on that entry --
  the same Corrections-tab hand-off the EDC tab's "Request
  Correction" button already uses. The Manuscripts report, which
  already lists every entry individually rather than a count, gets a
  "Review" button per row instead of a count to drill through.
  `summarize_choice_field_values()` gains an `option_value` column
  (the raw stored value, alongside the existing display label) for
  this filter to use.

## Two crashes found in a live browser walkthrough

* Every browser session crashed at startup under the default
  (`regulated`) security profile: `session_https_status()`'s
  `shiny::isolate()` wrapped only the `session$clientData` lookup,
  not the `$url_protocol`/`$url_hostname` field reads that followed,
  so a real session (not the plain-list fixture the existing tests
  used) failed with "Can't access reactive value 'url_protocol'
  outside of reactive consumer." Both reads now happen inside the
  `isolate()`.
* `approve_correction()`, `reject_correction()`, and
  `apply_correction()` all failed on DuckDB with "Constraint Error:
  Violates foreign key constraint because key ... is still referenced
  by a foreign key in a different table," for every correction
  request, blocking the entire workflow on DuckDB (the default
  backend for new studies). `correction_history` and
  `correction_overrides` both hold a `FOREIGN KEY` on
  `correction_requests.request_id`; DuckDB can only update an indexed
  column in place when nothing references the row, and otherwise
  rewrites the `UPDATE` as a `DELETE` + `INSERT`, which trips its
  documented "Over-Eager Constraint Checking in Foreign Keys"
  limitation on the `DELETE` half before the `INSERT` half restores
  the row. `init_data_correction()` no longer creates the
  `idx_corrections_status` index on DuckDB (and drops it from a study
  initialized before this fix); SQLite and PostgreSQL, which update
  the indexed column in place, are unaffected and keep the index.

## Corrections: reachable from the CRF, and reachable once approved

* The EDC tab's entries table gains a per-row "Request Correction"
  action that hands the row's `entry_id` to the Corrections tab's
  Create Request view, pre-filled with `table_name = "data_entries"`
  and that record. `data_correction_server()` gains a
  `pending_entry_id` argument for this hand-off.
* Create Request's "Field Name" and "Corrected Value" inputs, for a
  `data_entries` record, are now a dropdown of that record's own CRF
  fields and a typed widget drawn from the same field metadata
  `renderPanel()` already uses elsewhere (select/radio/numeric/date/
  etc.), with the proposed value validated against the field's own
  choices/required/type before a request is created. Any other table
  keeps the previous free-text inputs.
* Once a request moved past PENDING, there was no way to select it
  back into the review panel: only the Pending Review table's
  row-selection fed it, and that table lists PENDING requests only.
  An approved request a user found via My Requests or All Corrections
  had no path to the Apply button. Both tables now have their own
  row-selection handler and a review panel (My Requests reuses the
  previously unwired `request_details` output; All Corrections gains
  a new `review_panel_all`).

## Newer DuckDB required; package snapshot moved forward

* `DESCRIPTION` now requires `duckdb (>= 2.0.0)`. On duckdb 1.5.4.1,
  the version `renv.lock` pinned, `COPY FROM DATABASE` fails with a
  foreign-key error when a database has foreign keys (DuckDB issue
  #24215). `rotate_database_key()` failed on that error in its test
  on Linux, on the audit tables' foreign key, and passes on 2.0.0;
  `set_encryption_for_existing_db()` uses the same copy. Before 1.5.6,
  `DBI::dbIsValid()` on a driver also opened the database (see the
  next entry).
* The Posit Package Manager snapshot in the `Dockerfile` (and so in
  CI, which reads it from there) moves from 2026-07-05 to 2026-11-01,
  and `renv.lock` is re-pinned against it: 57 packages change version
  (among them duckdb 1.5.4.1 to 2.0.0, arrow 24.0.0 to 26.0.0,
  writexl 1.5.4 to 2.0.1, curl 7.1.0 to 8.1.0, rlang 1.2.0 to 1.3.0),
  `rdtools` is added as a new dependency, none is removed, and
  `zzalloc` stays at the same GitHub commit. R stays at 4.6.0.

## Replaced and short-lived DuckDB adapters release the file

* `get_db_adapter(force_new = TRUE)` shuts down the cached adapter it
  replaces when both are DuckDB adapters on the same file, so the old
  adapter no longer keeps a second instance on the file beside the new
  one. A replaced adapter on a different file is left open, since the
  application's pool may still use it.
* `migrate_between_backends()`, `export_to_files()`,
  `import_from_files()` and `compare_databases()` shut down the
  adapters they create before returning. The other places that create
  an adapter either shut it down already (`create_wizard_database()`,
  `check_database_initialized()`, the launcher, the Google Sheets form
  loader, key rotation), never open a connection through it (the
  adapters passed to `verify_database_encryption()` and
  `check_storage_encryption()`, `adapter_from_config()`), or are
  long-lived (the cached adapter and the application's pool).

## A DuckDB adapter keeps one instance until `shutdown()`

* The duckdb package releases a database instance when its last
  connection closes, and a later connection on the same driver opens a
  new one. The DuckDB adapter did not notice: before duckdb 1.5.6,
  `DBI::dbIsValid()` on a driver opened the database to answer and so
  reported a released instance as valid (fixed upstream in duckdb-r
  #2754). After the first connection of an adapter closed, every
  later `connect()` therefore opened its own instance, and connections
  open at the same time each attached the encrypted study file. Two
  instances writing and checkpointing one file corrupted it. On Linux
  with duckdb 1.5.4.1, the version `renv.lock` pins, this aborted R CMD
  check in `test_first_run_fixes.R` ('MarkBlockAsModified called with
  already modified block id'); run alone, the Google Sheets import
  into an encrypted DuckDB study failed every time with 'Could not
  read enough bytes' or 'block was written with a mode that is not
  recognized'. The adapter now holds one connection of its own from
  the moment it creates the instance until `shutdown()`, so every
  connection and pool connection shares that instance (tested with
  duckdb 1.5.4.1 and 2.0.0). Because the file stays open until `shutdown()`, the two
  places that create a short-lived second adapter release it at once:
  `connect_encrypted_db(key = ...)` with a key other than the
  configured one, and the keyed check in `verify_database_encryption()`.
  `setup_zzedc_from_gsheets()` and `setup_zzedc_from_csv()` shut down
  the adapter they create when no matching one was cached.

## Admin, Compliance and Corrections check the signed-in user after logout

* The Admin, Compliance and Corrections modules are mounted at first
  login and stay mounted for the rest of the browser session, but
  carried no check of their own. After logout or automatic logoff,
  the same session could still use them: in testing, the user
  management panel created a new `Admin` account (the role check was
  skipped when no role was known), reset a password and deactivated an
  account; the audit-trail viewer kept the loaded trail; the
  unblinding-grant table and the compliance summaries still rendered.
  Each of `admin_dashboard_server()`, `user_management_server()`,
  `backup_restore_server()`, `audit_log_viewer_server()`,
  `randomization_admin_server()`, `system_config_server()`,
  `cfr_compliance_server()` and `data_correction_server()` now checks
  the current user through one internal guard before it renders data
  or acts on an input. Without a signed-in user nothing renders, data
  already loaded is dropped from the session, and actions do not run;
  a blocked action is recorded as an `ACCESS`/`DENIED` audit event. A
  signed-in user blocked for their role sees a 'Not permitted'
  notification. A module mounted with no identity at all now shows
  and does nothing.
* The Corrections module enforces the reviewer roles (`Admin`, `PI`,
  `StudyManager`, `Data Manager`) on the server for approve, reject
  and apply. Applying a correction previously checked no role at all,
  so a `Coordinator` could apply an approved change.
  `apply_correction()` gains `applier_role`, checked like
  `approve_correction()`'s `reviewer_role` (`NULL` still skips it).
* The randomization admin panel requires `Admin` to save the scheme
  and grant or revoke unblinded access, and `Admin` or `PI` for an
  emergency unblind, the roles the underlying functions already check.
* Staging a database restore in the Backup & Restore panel now
  requires the `Admin` role. A restore replaces every study record at
  the next start, and the panel previously let any signed-in user
  stage one.
* `cfr_compliance_server()`, `data_correction_server()`,
  `user_management_server()` and `system_config_server()` gain a
  `user_session` argument; the application passes its login state.

## DuckDB by default; 'standard' refuses unhonored SQLite encryption

Owner decisions of 2026-11-17 (encryption plan, Section 7, decisions
1, 2 and 4).

* **Breaking: plaintext SQLite under `standard` needs an opt-in
  (F1).** On a SQLite driver that cannot encrypt
  (`sqlite_cipher_available()` is `FALSE`, as with stock CRAN
  RSQLite), `initialize_encrypted_database()` now returns
  `success = FALSE` under the default `standard` profile, with an
  error naming DuckDB and the opt-in, and creates no file; it
  previously returned `success = TRUE, encrypted = FALSE` with a
  warning. `connect_encrypted()`, `connect_encrypted_db()` (with or
  without a key), the SQLite adapter, `create_wizard_database()`, and
  the application's startup check (`check_storage_encryption()`) stop
  with the same error. Plaintext proceeds only when
  `security.accept_unencrypted_sqlite` is true; it is read from the
  option `zzedc.accept_unencrypted_sqlite`, the environment variable
  `ZZEDC_ACCEPT_UNENCRYPTED_SQLITE`, or `config.yml` (top level or
  under `default:`), in that order, by the new
  `resolve_accept_unencrypted_sqlite()`. With it, a notice states
  that full-disk encryption is the deployer's responsibility, and
  results report `encrypted = FALSE`. Existing SQLite deployments
  running under `standard` must add the opt-in or move to DuckDB.
  `development` is unchanged (plaintext allowed); `regulated` is
  unchanged (refused, whatever the opt-in).
* **DuckDB, encrypted, is the default backend for new studies.**
  `launch_zzedc()` without `backend` (non-interactive),
  `create_default_config()`, `generate_sample_config()`,
  `default_db_config()` without `backend` (which now needs a key from
  `encryption_key` or `DB_ENCRYPTION_KEY`), the setup wizard
  (`create_wizard_config()`, `wizard_adapter_config()`,
  `complete_wizard_setup()`, which generates and returns
  `encryption_key` when none is supplied), `init()`,
  `create_wizard_database()` and `initialize_default_database()`
  without a backend, and `setup_zzedc_from_csv()` /
  `setup_zzedc_from_gsheets()` given only a new `db_path` (new
  `backend` argument; a generated key is returned as `key`) all
  create DuckDB. If the `duckdb` package is not installed they stop
  with an install hint; there is no fallback to SQLite. Existing
  deployments are unaffected: a `config.yml` naming a backend keeps
  it, one naming none is still read as SQLite, and an existing
  database file keeps its format. `describe_backends()` lists DuckDB
  first.
* **No RSQLite cipher fork.** The SQLite3MultipleCiphers build stays a
  documented, unsupported route (`vignette("technical-lead-guide")`,
  Section 3.2).
* **Google Sheets form loader (F-NEW8).** `load_gsheets_forms()`
  (`inst/app/gsheets_form_loader.R`) now opens the study database
  through an adapter built from the application configuration, or,
  for an explicit `db_path`, from the file's detected format with
  `DB_ENCRYPTION_KEY`. It previously sent `cfg$database$path` (or a
  hard-coded `data/zzedc_gsheets.db`) down the SQLite-only path
  whatever the configured backend, so a DuckDB study was opened as
  SQLite without its key, and plaintext SQLite under `standard` was
  read with only a warning. Without a configuration or `db_path` it
  now stops instead of guessing a path.
* `connect_encrypted_db()` and `initialize_encrypted_database()` no
  longer treat every failure to build the configured adapter as "no
  backend configured"; only a `config.yml` without a `database:`
  section falls back to the SQLite path.
* The setup wizard's Database step has a checkbox to accept
  unencrypted SQLite under `standard`, recorded in `config.yml`.
  Configuration writers now write
  `security.accept_unencrypted_sqlite` (default `false`).

## REDCap audit replay verifies

* `replay_redcap_audit()` (used by `import_redcap_to_zzedc_db()`)
  hashed replayed REDCap events with its own recipe, so
  `verify_audit_integrity()` reported every imported record, and every
  later record, as tampered in any migrated study; its own
  `chain_validates` checked only the links and reported success. It
  now appends through the shared locked writer, in one transaction (a
  failure leaves no partial history), and `chain_validates` is
  `verify_audit_integrity()` on the whole trail. Records are
  timestamped when written (UTC); the REDCap event's time, id, label,
  and client address are kept in `details`. Databases already imported
  with the old code cannot be repaired in place (the trail is
  append-only) and should be re-imported.
* `verify_audit_integrity()` accepts an open connection (`conn`).

## Reads of participant records are audited

* **`log_record_read()`** writes one hash-chained audit record
  (`SELECT`, `EXPORT`, or `REPORT_GENERATED`) per retrieval of
  participant-level data, with the user, client address, session,
  screen, number of records, and the subject identifiers disclosed.
  Field values are not copied into the record. Wired into the Data
  Explorer (`data_server()` gains `user_id`; loads, refreshes, and both
  downloads), the Export Center (preview and download), the EDC
  entries list, the data-quality report's flagged entries, and
  `generate_subject_case_report()` (recorded before the file is
  written). Under `regulated` a read that cannot be recorded is an
  error, so nothing is shown or written; otherwise a warning.
* **`get_record_access_log()`** lists those records, optionally for
  one subject (exact match) or one user, for an accounting of access
  (HIPAA 164.308(a)(1)(ii)(D)).
* The Data Explorer's Refresh button now re-reads the database; it
  previously only showed a notification.
* Not covered: viewing the audit trail itself, and aggregate reports
  (Activity Summary, Domain Breakdown, Personal Statement), which show
  counts rather than participant records.

## Audit trail: coverage, fail-closed writes, protection, review

A review against 21 CFR 11.10(e) and HIPAA 164.312(b) found the audit
trail missed the core clinical data and could be removed or rewritten.

* **Case report form entries are audited.** `db_insert_data_entry()`
  (and so the EDC tab's save) wrote study data with no audit record.
  Each entry is now saved with an `INSERT` audit record holding the
  submitted values, user, time, client address, and session, in the
  same transaction: if the audit record cannot be written, the entry
  is not saved.

* **Failed audit writes are errors under `regulated`.**
  `log_audit_event()`, `log_audit_event_extended()`, and
  `log_audit_action()` previously warned and carried on. Login events
  that cannot be recorded now fail the login under `regulated`.

* **Append-only audit tables.** Triggers reject `UPDATE` and `DELETE`
  on `audit_log`, `audit_chain` (except its verification columns), and
  `audit_events` on SQLite, PostgreSQL, and MySQL/MariaDB; installed at
  every start. DuckDB has no triggers. `cleanup_audit_logs()`, which
  deleted old audit records and broke the chain, now refuses.

* **External checkpoints** (`audit_checkpoint()`,
  `verify_audit_checkpoints()`; `audit.checkpoint_dir`,
  `ZZEDC_AUDIT_CHECKPOINT_KEY`). A rewrite that recomputes every hash
  passes `verify_audit_integrity()`; it does not pass a keyed
  checkpoint stored outside the database. See `?audit_protection`.

* **One chain writer** (`R/audit_append.R`), serialized on PostgreSQL
  (advisory lock) and MySQL/MariaDB (locking read) so concurrent writes
  cannot fork the chain. The extended writer had no transaction and
  numbered the chain by `COUNT(*)`.

* **Sign-in events.** Successful logins, attempts on unknown, inactive,
  or locked accounts, automatic logoffs, and session ends are recorded,
  with client address and session token (`session_audit_context()`).
  Previously only wrong passwords and lockouts were.

* **Automatic logoff works.** `enable_session_timeout()` was never
  called, referred to an out-of-scope `input`, and reset its own clock
  when it showed its warning, so sessions never timed out. Under
  `regulated`, the fallback login path (no lockout, no audit) is no
  longer served.

* **Audit viewer.** The Admin tab's viewer read a table (`audit_trail`)
  that nothing wrote, and showed 20 randomly generated "sample"
  entries when its query failed. It now reads `audit_log` and shows an
  error instead. Audit content is HTML-escaped: the table and detail
  view rendered it as raw HTML, so a username typed at a failed login
  could run script in an administrator's browser.

* `get_audit_trail()` binds all filters as parameters (they were pasted
  into the SQL).

* OQ-019 and OQ-020 qualify the new controls. The startup
  `COMPLIANCE_CHECK` record reports the audit protection and
  checkpoint configuration.

* **`apply_correction()` now applies the correction.** It marked a
  request `APPLIED` and wrote an audit record of the change without
  changing the stored value. It now updates the field (a table column,
  or a field inside `data_entries.data_json`), keeping numeric and
  logical types, and in the same transaction marks the request applied
  and writes an `UPDATE` audit record with old value, new value,
  reason, and approver. A request whose original value no longer
  matches the record is refused, as is a second application. Record
  locks are honored: the lock check tested a field `check_record_lock()`
  does not return, so locked records could be corrected; a locked
  record now needs an approved override. Audit, signature, version,
  user, and correction tables, primary keys, and `data_json` as a whole
  cannot be corrected. The prior and corrected states are stored as
  record versions.

* Known, not changed: reads of records are not logged.

## Encryption plan completed: backups, HTTPS, keys, server databases, evidence

Phases 1.1, 1.3, 1.4, 2.1, 3.1, 4, and 6 of
`docs/encryption-compliance-plan-2026-11-10.md`.

* **Encrypted backups.** Set `ZZEDC_BACKUP_PASSPHRASE` (at least 12
  characters, held apart from the database key) and backups are
  written as `.db.enc` or `.db.gz.enc` (AES-256-CTR with HMAC-SHA256).
  Under `regulated`, an unencrypted backup of an unencrypted database
  is refused. Restore accepts encrypted and compressed backups.

* **The Backup tab's Download button works** (it did nothing). Each
  download is recorded as an `EXPORT` audit event.

* **HTTPS.** New `security.https_only` setting; HTTPS is always
  required under `regulated`. Sessions that did not arrive over HTTPS
  are blocked. `X-Forwarded-Proto` is trusted only from a reverse
  proxy on the same machine. A proxy template is installed at
  `system.file("templates", "nginx-zzedc.conf", package = "zzedc")`.

* **Key management** (`?key_management`). `check_key_custody()`
  refuses (under `regulated`) or warns about a database key written
  into `config.yml`; `log_key_access()` records each load of the key
  in the audit log, without the key; `rotate_database_key()`
  re-encrypts a DuckDB database under a new key (and a SQLite database
  on a cipher-enabled RSQLite).

* **PostgreSQL and MySQL/MariaDB under `regulated`** (previously
  always refused). MySQL/MariaDB: zzedc asks InnoDB whether every
  table of the study database is encrypted. PostgreSQL: the deployer
  records the storage encryption in `database.at_rest_attestation`,
  and zzedc labels it as attested, not verified. Both require
  `sslmode: verify-full`/`verify-ca` or `ssl_mode:
  VERIFY_IDENTITY`/`VERIFY_CA`, and the live connection must use TLS.
  See `?server_encryption`.

* **Startup compliance record.** Each application start writes a
  `COMPLIANCE_CHECK` audit event with the profile, backend, at-rest
  state and its basis, TLS, key source, DuckDB extension settings, and
  HTTPS requirement (`compliance_self_check()`,
  `record_compliance_check()`).

* **Operational qualification of the security controls**: OQ-011 to
  OQ-018 in `run_oq_tests()`.

* **Compliance documents** installed in
  `system.file("compliance", package = "zzedc")`: a responsibility
  matrix (Part 11, HIPAA 164.312, GDPR Art. 32(1)), a HIPAA encryption
  worksheet, a GDPR Article 32 statement template, and an IRB security
  summary.

* The technical-lead guide now gives the steps for building RSQLite
  with SQLite3MultipleCiphers (not tested by zzedc's own suite).

* The content-author guide's Google Sheets link pointed at a
  redirected address; corrected.

## Encryption: false claims removed, security profiles added

Phase 0 of `docs/encryption-compliance-plan-2026-11-10.md`. Several
functions claimed encryption they did not provide; each now reports
or enforces the true state.

* **New `security.profile` setting** (`development`, `standard`,
  `regulated`; built-in default `standard`). Under `regulated`,
  storage that cannot be shown to be encrypted at rest is refused,
  including at Shiny app startup, and an AWS KMS failure is an error
  instead of a fallback. Configuration templates, the setup wizard, and
  the bundled `config.yml` now write `regulated`. See
  `?resolve_security_profile`.

* **`initialize_encrypted_database()`** reported "created and
  encrypted" for plaintext SQLite files on stock CRAN RSQLite (which
  ignores the key). It now returns `encrypted` and says plainly when the
  database is not encrypted; under `regulated` it refuses and removes
  the file.

* **`verify_database_encryption()`** used a byte-statistics test that
  also failed correctly encrypted files. It now requires the file to be
  unreadable without the key and readable with it, for SQLite and
  DuckDB. New fields `readable_without_key` and `backend`; new
  argument `key`.

* **`set_encryption_for_existing_db()`** never rewrote the file. It
  now encrypts DuckDB files in place (verified before the swap, with a
  plaintext backup) and stops with an error on stock RSQLite.

* **`export_encrypted_data(password = )`** ignored the password. It
  now writes only an encrypted `.enc` file (AES-256-CTR with
  HMAC-SHA256, bcrypt-pbkdf); see `encrypt_export_file()` and
  `decrypt_export_file()`. Passwords must be at least 12 characters.

* **`selective_field_export()`** now pseudonymizes with HMAC-SHA256
  under a separate key (`pseudonymize_values()`,
  `get_pseudonymization_key()`). Argument `fields_to_encrypt` is
  deprecated in favor of `fields_to_pseudonymize`. **Pseudonyms differ
  from those produced by earlier versions**, so exports made before and
  after cannot be linked on those fields. A misspelled field name is now
  an error rather than being left unprotected.

* **Adapters** gain `encryption_capabilities()`, reporting at-rest and
  in-transit encryption separately. `supports_encryption()` now means
  "zzedc encrypts stored data" and is `FALSE` for PostgreSQL, MySQL,
  and ClickHouse (it was `TRUE` on the strength of TLS). The SQLite
  adapter now applies its key before other statements and in its
  connection pool.

* **`test_encryption()`** now errors, rather than warns, on a plaintext
  file.

* **Validation suite.** New IQ-008 judges the deployment's storage
  encryption under the active profile. Functional IQ/OQ/PQ checks run
  their temporary databases under a scoped `development` profile and no
  longer leave the cached database adapter pointing at a deleted file.
  IQ-003's message no longer claims "Encryption working" for a
  key-format check.

* New exported helpers: `sqlite_file_is_encrypted()`,
  `sqlite_cipher_available()`, `check_storage_encryption()`,
  `get_security_profile()`.

* `get_db_path()` treats an empty `ZZEDC_DB_PATH` as unset.

## Follow-up fixes: passwords, restore, Google Sheets, first-run screen

* **One password-salt rule (`resolve_auth_salt()`).** The launcher's
  default administrator could not log in whenever `ZZEDC_SALT` was set,
  and users created or reset in the Admin tab could not log in when the
  configuration named no salt variable, because each path used a
  different salt. The launcher, login, change-password form, and user
  management now share one rule. `initialize_default_database()` gains
  a `salt` argument.

* **Restore is staged and applied at the next start**
  (`request_database_restore()`, `apply_pending_restore()`), instead of
  copying over the open database and closing the shared pool. The
  replaced database and its write-ahead log are kept in
  `pre_restore_<timestamp>/`.

* Backups: SQLite backups use `VACUUM INTO`; the compress option now
  compresses (it produced uncompressed `.gz` files); backups go to the
  study's `backups/` folder, not the installed package's directory.
  The Backup tab accepts only files in its backup folder (browser-sent
  paths could name any file).

* **Google Sheets import works on every backend.** The application's
  Google Sheets actions now call `setup_zzedc_from_gsheets()` (they
  sourced a script the application directory does not contain). It
  gains `adapter_config` and `create_database = FALSE`, which imports
  into an existing study and skips existing users and forms.

* Imported forms (Google Sheets, REDCap) now get a matching
  `designer_forms` row: their fields violated the foreign key, which
  SQLite ignored and DuckDB and PostgreSQL rejected.
  `create_designer_form()` assigns ids above existing ones.

* `launch_setup_wizard()` opens on a choice between the wizard and the
  console commands (`show_choice = FALSE` skips it).

* New `setup_zzedc_from_csv()`: the Google Sheets import, reading
  `Study_Users.csv`, `Data_Dictionary.csv`, and `validation_rules.csv`
  from a folder. (The technical-lead guide documented it before it
  existed.) Both importers now skip validation rules already present
  when importing into an existing study, honor the `active` column, and
  accept an optional `form_name` column.

* The bundled example study (`inst/extdata/adhd_trial`) is converted to
  the three-table format and loads with `setup_zzedc_from_csv()`.

* Removed: the legacy Google Sheets builders (`inst/app/gsheets_*_builder.R`,
  `inst/app/gsheets_integration.R`), the scripts that used them
  (`inst/scripts/setup/setup_from_gsheets.R`, `setup_menu.R`), and the
  application's "Run Traditional Setup" button, which could not run.

## Choosing the database when a study is created

* `launch_zzedc()` gains `backend`, `profile`, and `setup` arguments.
  With no `config.yml`, an interactive session is shown a comparison of
  the databases and asked to choose (or to open the setup wizard).
  DuckDB setup checks for the encryption key, installs DuckDB's
  extensions, and only then writes `config.yml`.
  `create_default_config()` gains `backend` and `profile` and now
  writes the `regulated` profile by default (it wrote none before).

* New `describe_backends()`: one comparison of the backends, used by
  the console prompt, the wizard's tooltips, and the documentation.

* **The setup wizard is reachable and creates the study.** New
  `launch_setup_wizard()` (also `launch_zzedc(setup = TRUE)`). The wizard
  gains a security-profile choice and a Database step with tooltips, a
  comparison table, and a profile compatibility check. Its final step
  previously created nothing; it now calls `complete_wizard_setup()`.

* `create_wizard_config()` writes under `default:`, so `config::get()`
  can read it (it could not), and quotes free-text values.
  `complete_wizard_setup()` accepts `db_backend`, `db_encryption_key`,
  `db_settings`, `security_profile`, and `install_extensions`.
  The launch script changes to the study directory first.

## The Shiny application uses the configured database backend

* The application previously always opened SQLite with RSQLite,
  whatever `config.yml` said. `inst/app/global.R` now builds its pool
  from the configured adapter (new `app_database_config()`,
  `app_database_path()`), applies the security profile to that backend,
  and caches the adapter so package functions reach the same database.
  `launch_zzedc()` initializes and migrates on the configured backend.
  Encrypted DuckDB under the `regulated` profile now works end to end.

* **One DuckDB instance per adapter.** Each `DuckDBAdapter$connect()`
  created its own in-process instance, so package functions and the
  application's pool could attach the same file through separate
  instances. Connections and the pool now share one instance; new
  `shutdown()` method (a no-op on other backends) releases it.

* **Audit tables are created at launch.** The launcher never created
  `audit_log`, so security events (login lockouts and unlocks) were not
  recorded in freshly launched deployments.

* `connect_encrypted_db()` opens a plaintext SQLite file without a key
  (the security profile still applies) instead of failing for want of
  `DB_ENCRYPTION_KEY`.

* The Admin tab's backup, restore, and database-information panels now
  use the study database rather than a fixed `./data/zzedc.db`. File
  backup is refused with an explanation on server backends; DuckDB is
  checkpointed before copying.

* The `standard` profile's warning is emitted immediately, so it
  appears in a running application's log.

* `create_wizard_database()`, `initialize_default_database()` gain an
  `adapter_config` argument.

## DuckDB: extensions offline, and a pool concurrency fix

* **The encrypted DuckDB connection pool could not open a second
  concurrent connection** ("Unique file handle conflict"): every pool
  connection re-ran `ATTACH` on a shared instance. It now attaches once
  and each connection selects the attached database.

* New `duckdb.extension_directory` and `duckdb.allow_extension_download`
  settings. Under the `regulated` profile, runtime extension downloads
  are disallowed by default. New `install_duckdb_extensions()`
  pre-installs `httpfs` and `icu` and verifies an offline load; new
  `duckdb_extension_download_allowed()` reports the policy. Extensions
  load when a connection opens, so a missing one fails at startup.

# zzedc 0.8.0

## Correctness fixes: the audit trail

The 21 CFR Part 11 audit trail could not detect tampering with an
audit record's content. Three separate faults combined to produce that.

* **The hash was not reproducible from the row it described.** Both
  writers hashed `Sys.time()` while letting the `timestamp` column take
  the database's `CURRENT_TIMESTAMP` default, so the value inside the
  hash was never recorded anywhere: a different clock, in a different
  rendering. Nobody could recompute the hash of a stored row, which is
  why nothing ever tried. The timestamp is now generated once, hashed,
  and written to the column.

* **Two writers hashed different field sets into the same table.**
  `log_audit_event()` hashed eight fields; `log_audit_event_extended()`
  hashed eleven, adding `ip_address`, `session_id` and
  `event_category`, the last of which is stored in `audit_events`
  rather than `audit_log` and so could never be recovered when reading
  a row back. One verifier cannot check two constructions. Both now
  build the content through a shared `.audit_hash_content()`, over
  columns that all live in `audit_log`.

* **`verify_audit_integrity()` never recomputed a hash.** It compared
  each record's `previous_hash` against the prior record's stored
  `record_hash` and stopped, which establishes that the linkage fields
  agree with one another and nothing about the content. Rewriting who
  performed an action, which record it touched, whether it was an
  UPDATE or a SELECT, or when it happened, all went undetected, and the
  function then wrote `verified = 1` into `audit_chain`, recording a
  false attestation. It now recomputes each hash from the stored row
  and reports offending records in a new `tampered_records` element.

Two further faults in the same function:

* The `start_id` and `end_id` clauses were appended after `ORDER BY`,
  which is a syntax error, so every ranged call failed and was
  swallowed by the error handler.
* The `GENESIS` check was applied to the first row of whatever set was
  returned, so verifying a sub-range always reported a spurious failure
  on its first record. It now applies only at the head of the chain.

Audit rows written by earlier versions cannot be content-verified,
because the timestamp behind their hash was never stored. They will be
reported as tampered. This is accurate rather than a regression: those
hashes never attested to anything.

## Correctness fixes: the other integrity verifiers

The same pattern held in three more places. Each selected or could have
selected the content behind a hash, then compared only the linkage
fields, which establishes that those fields agree with one another and
nothing about what they are supposed to bind.

* **`verify_correction_integrity()`** reported "All correction request
  hashes verified" without verifying a hash. A correction request
  records a change to a stored clinical value, so its content is the
  entire point: the field, the original value, the value it was changed
  to, the stated reason and who asked could all be rewritten
  undetected. It now recomputes each hash and reports offenders in
  `tampered_records`. These hashes were already reproducible, since the
  timestamp behind them was stored.

* **`verify_version_integrity()`** selected only the three linkage
  columns, so it could not have checked content even in principle. It
  now selects the snapshot and recomputes.

* **`create_record_version()`** had the audit trail's fault: it hashed
  `Sys.time()` while letting `changed_at` take the database default, so
  no version hash could be recomputed from its row. The timestamp is
  now generated once, hashed, and stored. Versions written by earlier
  releases cannot be content-verified, for the same reason as the audit
  rows.

## Tests

* New `test_audit_chain_integrity.R`: the hash recomputes from a stored
  row; a clean trail verifies; rewriting the acting user, the record
  acted on, the operation, or the timestamp is each detected and named;
  rows from both writers verify under one rule; and a sub-range
  verifies without a spurious failure.

# zzedc 0.7.0

## Correctness fixes

* **`verify_signature_chain()` did not verify the signatures.** It
  compared each row's `previous_signature_hash` against the prior row's
  stored `signature_hash` and stopped there. That establishes only that
  the linkage fields agree with one another; it never recomputed a
  signature's hash from its content, so the content was never checked
  against the hash that is supposed to bind it.

  The consequence is that the signed record could be rewritten and the
  function would still return `is_valid = TRUE` with the message
  "Signature chain integrity verified". Demonstrated on a four-signature
  ledger: replacing the signer, downgrading a signature's meaning from
  approval to review, repointing a signature at a different subject
  record, and moving a timestamp were each undetected, because none of
  them touches a stored hash. For a 21 CFR Part 11 control whose entire
  purpose is to make such a change detectable, reporting integrity in
  those circumstances is worse than reporting nothing.

  Verification now recomputes each signature's SHA-256 from the stored
  content in the same field order `sign_record()` used to construct it,
  and compares it with the recorded hash. The linkage check is retained.
  The result gains a `tampered_records` element listing signatures whose
  content does not match their hash, alongside the existing
  `invalid_records` for broken links, and the failure message
  distinguishes the two.

* **`execute_erasure_item()` did not re-check the legal hold.** The
  hold was consulted only when an erasure item was created, where it
  sets the item's initial status. Execution checked nothing but that
  the item was `APPROVED`, so the sequence create, approve, place hold,
  execute erased data that was under preservation. A litigation or
  regulatory hold exists to stop deletion from the moment it is placed,
  which puts the check immediately before the erasure, not only at
  intake. The hold is now re-checked at execution; a held item is
  refused, returned to `ON_HOLD` with the hold's reason, and the
  refusal is written to the erasure audit log as
  `ITEM_BLOCKED_BY_HOLD`.

## Tests

* New `test_signature_chain.R` rebuilds the ledger in plain SQLite,
  mirroring the schema and hash construction, and asserts that an
  untampered chain verifies while each of the four tampering cases
  above is caught.
* `test_erasure.R` gains a case for a hold placed after approval, which
  fails against the previous sources.

## Known, not changed

* Passwords for electronic signatures are hashed with unsalted SHA-256
  in `verify_password_for_signature()`, while `auth_module.R` salts via
  the `ZZEDC_SALT` environment variable. The two schemes are
  inconsistent, and an unsalted single-round hash is weak for a
  credential guarding a Part 11 signature. Changing it is a migration,
  not an edit, since existing stored hashes would have to be rehashed,
  so it is recorded here rather than done.

# zzedc v0.6.2

## Permissions hierarchy implementation

* **`studymanager` role added.** `setup_default_dsl_permissions()` now
  includes `studymanager` with full configuration-write and approval
  authority (`can_create=1, can_edit=1, can_approve=1, can_activate=1,
  can_delete=0`). `StudyManager` is also registered in `edc_roles`
  during `create_wizard_database()`.
* **`migrate_add_studymanager_role()` (new export).** Idempotent
  migration that adds the `studymanager` permission row and `edc_roles`
  entry to databases initialized before v0.6.2.
* **Non-escalation enforcement in user management UI.** New unexported
  helpers `.ROLE_TIER` and `.assignable_roles()` in
  `user_management_module.R`. `user_management_server()` now accepts an
  `actor_role` argument; role choices in the add/edit modals are
  filtered to roles strictly below the acting user's tier.
  `admin_dashboard_server()` passes `user_session$role` as the actor.
* **Approval authority check in `approve_user_proposals()` and
  `reject_user_proposals()`.** Both functions now look up the
  reviewer's role in `edc_users` and return an `auth` error if the
  role is not `admin`, `pi`, or `studymanager`.
* **PI account separated from sysadmin in config template.** The
  `zzedc_config_template.yml` and the prazosin-large technical guide
  now define a `pi:` section alongside `admin:`. When `pi_username` is
  present and distinct from `admin_username`, `create_wizard_database()`
  inserts a separate PI-role account. The admin account is documented
  as a technical sysadmin not used for day-to-day study operations.

# zzedc v0.6.1

## Access model correction and user-roster change monitor

* **Coordinator sheet access corrected.** Site coordinators now hold
  editor access to the `Study_Users` tab of their per-site workbook
  only. `Data_Dictionary` and `validation_rules` are viewer-only for
  coordinators, enforced via Google Sheets tab protection. The previous
  design had coordinators editing `validation_rules`, which is
  incorrect: that tab is managed exclusively by the data scientist.
* **User-roster change detection and approval.** Four new exported
  functions: `diff_gsheets_users()`, `get_pending_user_proposals()`,
  `approve_user_proposals()`, `reject_user_proposals()`. A
  `user_proposals` staging relation holds proposed roster changes
  without touching the live `edc_users` table until a credentialled
  reviewer approves.
* **`poll_gsheets_and_stage()` updated.** Now monitors `Study_Users`
  across all four per-site workbooks (resolved from per-site
  environment variables) rather than the `validation_rules` tab.
* **Permissions hierarchy analysis and construction guide.**
  `docs/gsheets-monitor-design.md` expanded to cover: the four-tier
  standard EDC permission hierarchy; REDCap's project-rights model at
  this trial scale; four identified gaps in the current ZZedc role
  model (missing `StudyManager` role, absent non-escalation
  enforcement, PI cannot author rules directly, Tier 0 / application
  admin conflation); and a step-by-step construction guide for
  initializing the correct hierarchy via the Google Sheets seed-import
  pathway.

# zzedc v0.6.0

## Google Sheets change monitor and approval workflow

* **`R/gsheets_monitor.R` (new file).** Introduces a non-destructive
  staging layer between coordinator-authored sheet edits and the live
  validation-rule constraint store. Seven exported functions:
  `diff_gsheets_rules()`, `stage_gsheets_proposals()`,
  `get_pending_proposals()`, `default_proposal_notifier()`,
  `approve_proposals()`, `reject_proposals()`, and the cron-facing
  orchestrator `poll_gsheets_and_stage()`.
* **`dsl_rule_proposals` staging table.** Proposed changes from the
  Google Sheet land in this new relation with `status = 'PENDING'`.
  The live `dsl_validation_rules` row is not touched until the study
  manager approves. Approval atomically rewrites and recompiles the
  live rule; rejection records the decision with no effect on active
  constraints.
* **Pluggable notifier.** `poll_gsheets_and_stage()` accepts a
  `notifier` argument (`function(proposals)`) so the transport
  mechanism (log file, email, webhook) can be swapped without altering
  the detection and staging logic. The default notifier writes a
  plain-text summary to `ZZEDC_PROPOSAL_LOG`.
* **Audit trail.** All state transitions (staging, approval,
  rejection) write to the existing `dsl_rule_change_log` relation via
  `log_dsl_rule_action()`.
* **Prazosin-large vignettes updated.** Technical guide: new Section
  7.3 (coordinator sheet access), Section 7a (five-subsection change
  monitor workflow including cron setup, `blastula` email example,
  approval commands, environment variable reference). User guide: new
  Section 9 (site configuration sheet), updated approval-loop
  description, troubleshooting entries, and glossary terms.
* **Design document.** `docs/gsheets-monitor-design.md` describes
  the implementation in both database-expert and data-scientist-
  accessible registers.

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
  with consistent showcase icons, theme colors, and
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
* **Card standardization.** All `div(class = "card", ...)`
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
