# zzedc (development version)

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
