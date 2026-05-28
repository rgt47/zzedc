# Google Sheets Change Monitor: Design and Implementation

*2026-05-28 16:13 PDT*

This document describes the design and implementation of the Google
Sheets change monitor added to ZZedc for the Prazosin Sleep Study
(Large), protocol PRAZ-L-2026. It is written in two registers: a
technical section using database and systems terminology, followed by a
plain-language section written for the data scientist and study staff
who will operate the system day to day.

---

## Part 1: Technical Description (Database Expert Register)

### Background and motivation

ZZedc supports a Google Sheets workbook as a bootstrap seed source for
three configuration tables: the principal registry (`Study_Users`), the
field metadata catalogue (`Data_Dictionary`), and the constraint
definition table (`validation_rules`). In the multi-site prazosin trial,
site coordinators hold editor-level ACL grants on the `validation_rules`
tab of their per-site workbook. This arrangement allows non-technical
staff to author and propose business-rule changes in a familiar
spreadsheet interface.

Without a change-detection layer, the only path from sheet to database
was a manual, full-table re-import via `setup_zzedc_from_gsheets()` or
`sync_dsl_rules_from_gsheets()`. Both operations write directly to the
live `dsl_validation_rules` relation. Neither supports a review gate
between the external mutation source (the sheet) and the operational
constraint store.

The modification described here introduces that gate.

### Design constraint: non-destructive staging

The central design constraint is that a proposed change must not
activate until it has been reviewed and approved. The existing import
path presented a structural obstacle: `save_dsl_rule_to_db()`, the
internal upsert function, immediately overwrites `rule_dsl` on UPDATE
and sets `is_active` from the incoming record. Calling it with
`is_active = FALSE` would stage the new DSL but deactivate the current
rule, creating a window in which a live clinical trial form operates
without its validated constraint set.

Two remediation patterns were evaluated:

1. **In-place staging column**: add a `proposed_dsl TEXT` column to
   `dsl_validation_rules` and leave `rule_dsl` immutable until
   approval. On approval, copy `proposed_dsl` to `rule_dsl` and
   recompile. This avoids a second table but conflates two distinct
   states (live rule, pending proposal) in a single row, complicates
   audit queries, and requires a schema migration to the production
   table.

2. **Separate proposal relation**: introduce a `dsl_rule_proposals`
   table that holds the full proposal alongside a snapshot of the
   current `rule_dsl` at staging time. The live relation is read-only
   during the review window. On approval, an atomic UPDATE/INSERT
   rebuilds the live row from the proposal record. On rejection, the
   live row is untouched.

Pattern 2 was implemented. It preserves the integrity of the live
constraint store, supports independent querying of the proposal log,
and requires no migration of the existing `dsl_validation_rules` DDL.

### Schema: `dsl_rule_proposals`

```sql
CREATE TABLE IF NOT EXISTS dsl_rule_proposals (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  proposal_id     TEXT UNIQUE NOT NULL,   -- rule_id + staging timestamp
  rule_id         TEXT NOT NULL,
  change_type     TEXT NOT NULL,          -- 'NEW', 'MODIFIED', 'DELETED'
  proposed_dsl    TEXT,
  current_dsl     TEXT,                   -- snapshot at staging; NULL for NEW
  field_code      TEXT,
  form_code       TEXT,
  rule_name       TEXT,
  error_message   TEXT,
  severity        TEXT,
  rule_category   TEXT,
  sheet_id        TEXT NOT NULL,
  staged_by       TEXT NOT NULL,
  staged_at       TEXT NOT NULL,
  status          TEXT NOT NULL DEFAULT 'PENDING',
  reviewed_by     TEXT,
  reviewed_at     TEXT,
  review_comments TEXT
);
```

The `proposal_id` is a surrogate key constructed from `rule_id` and a
compacted timestamp. `current_dsl` records the DSL expression active in
`dsl_validation_rules` at the moment of staging; this snapshot is used
in the audit log diff and in the notification body.

### Change detection

`diff_gsheets_rules()` performs a read-side diff by:

1. Fetching the sheet tab via `googlesheets4::read_sheet()`.
2. Querying `SELECT rule_id, rule_dsl FROM dsl_validation_rules` from
   the encrypted SQLite connection.
3. Computing set membership and string equality to classify each row as
   `NEW` (present in sheet, absent in DB), `MODIFIED` (present in both,
   DSL strings differ), or `DELETED` (present in DB, absent from sheet).

The diff operates on `rule_dsl` content, not on row metadata (names,
severity, category). A coordinator changing only a rule name without
altering the DSL expression does not generate a proposal. This is
intentional: the constraint definition is the auditable artefact; cosmetic
fields are updated on approval as a side effect.

`DELETED` rows are flagged in the function output but never
automatically staged. Removals from the constraint catalogue in a live
trial require explicit data-scientist intervention.

### Staging and idempotency

`stage_gsheets_proposals()` is idempotent for content: if a `PENDING`
proposal already exists for a given `rule_id` with an identical
`proposed_dsl`, the row is not duplicated and the staging count is not
incremented. If the DSL has changed since the last poll (coordinator
revised the proposal before the manager reviewed it), the existing
`PENDING` row is updated in place. This prevents proposal accumulation
across poll intervals while preserving a single reviewable state per
rule.

### Approval and database rebuild

`approve_proposals()` performs the following steps within a single
database connection for each approved `proposal_id`:

1. Fetches the proposal row and validates `status = 'PENDING'`.
2. Compiles the proposed DSL to R and SQL validator expressions via the
   existing `parse_dsl_rule()` → `generate_r_validator()` /
   `generate_sql_check()` pipeline.
3. Issues an `UPDATE` or `INSERT` to `dsl_validation_rules`:
   - Sets `rule_dsl` to `proposed_dsl`.
   - Overwrites `compiled_r` and `compiled_sql` with the freshly
     compiled expressions.
   - Sets `is_active = 1`, `approval_status = 'APPROVED'`,
     `approved_by`, `approved_at`, `version += 1`.
4. Updates the `dsl_rule_proposals` row to `status = 'APPROVED'`.
5. Writes a `log_dsl_rule_action()` entry with `action =
   'APPROVED_FROM_SHEET'`, capturing `current_dsl` as `old_value` and
   `proposed_dsl` as `new_value`.

`reject_proposals()` updates the proposal status to `'REJECTED'` and
writes a `REJECTED_FROM_SHEET` audit entry. The live rule row is not
accessed.

### Notification architecture

The notifier is a dependency-injected function: `poll_gsheets_and_stage()`
accepts a `notifier` argument with signature `function(proposals)` where
`proposals` is a data frame of pending rows. The default implementation
(`default_proposal_notifier()`) appends a plain-text summary to a log
file whose path is resolved from the `ZZEDC_PROPOSAL_LOG` environment
variable. This design decouples the transport mechanism from the
detection and staging logic; a production deployment substitutes a
`blastula`-based SMTP function with no changes to the core polling code.

### Cron integration

The poll function is designed for unattended execution. It returns
`NULL` silently when no changes are detected, avoiding spurious log
entries on no-op runs. SMTP credentials and the sheet ID are resolved
exclusively from environment variables; no secrets appear in the script
or the cron table.

### Audit trail

All state transitions -- staging, approval, rejection -- write to the
existing `dsl_rule_change_log` relation via `log_dsl_rule_action()`.
The proposals table itself constitutes a secondary, human-readable
audit record of the coordinator's change history and the manager's
review decisions.

---

## Part 2: Plain-Language Description (Data Scientist Register)

### What was the problem?

Coordinators at each recruitment site now have editor access to a
Google Sheet tab that lists the data quality checks for their site.
Before this change, the only way to get a coordinator's edit into the
ZZedc database was for you to run a manual sync command. There was no
checkpoint: if you ran the sync, the coordinator's change went live
immediately, whether or not it was correct.

For a running clinical trial, that is not safe. A poorly worded rule
could block coordinators from saving valid data, or an incorrectly
relaxed rule could allow out-of-range values to enter the database
without triggering an error.

### What was built?

Three pieces were added:

**1. A staging table in the database.**
When the monitor detects a coordinator's edit in the sheet, it does not
touch the live validation rules. Instead it writes the proposed change
to a separate holding table called `dsl_rule_proposals`. The live rule
stays active and unchanged. Think of it as an inbox for proposed
changes: items sit there until someone acts on them.

**2. A polling script and a notifier.**
A script runs on the study server every 15 minutes. It reads the sheet,
compares it with what is currently in the database, and for any row
that has changed, writes a proposal to the staging table and triggers a
notification. By default the notification is a plain-text log file. For
production use you supply a short function that sends an email to the
study manager instead (a `blastula` example is in the technical guide).

**3. Approval and rejection commands.**
When the manager receives the notification and has reviewed the
proposed change, they call one of two R functions:

- `approve_proposals()`: the change goes live. The rule in the database
  is replaced with the coordinator's version, the rule's compiled
  checking code is regenerated, and the change is recorded in the audit
  log with the manager's name and the date.
- `reject_proposals()`: the proposal is dismissed with a recorded
  reason. The live rule is not changed. You will need to tell the
  coordinator their proposal was not accepted and why.

### What you need to do to set this up

1. Create `~/prj/praz-large/poll_rules.R` with the two-line script
   shown in Section 7a.2 of the technical guide.
2. Add the cron entry from Section 7a.2 to the server's crontab.
3. Set `PRAZ_SHEET_ID` in the server environment.
4. Decide on the notifier. For testing, the default log file is fine.
   For production, wire in the email notifier and set the five SMTP
   environment variables listed in Section 7a.5.
5. Run `init_proposals_table(db_path = 'data/praz-large.db')` once to
   create the staging table. (The poll script does this automatically
   on its first run, but doing it manually first confirms the database
   connection is working.)

### What happens when a coordinator makes a change

1. Coordinator edits a row in their `validation_rules` tab and saves.
2. Within 15 minutes (or whatever your cron interval is) the poll
   script detects the change.
3. The proposal lands in `dsl_rule_proposals` with `status = PENDING`.
4. The notifier fires: either a log entry is written or an email is sent
   to the study manager.
5. The live rule in ZZedc is **not changed at this point**.
6. Manager reviews the proposal and calls `approve_proposals()` or
   `reject_proposals()`.
7. If approved: the rule is updated in the database, recompiled, and
   activated. The next coordinator session that loads the form will
   enforce the new rule.
8. If rejected: the live rule stays as-is. You communicate the reason
   to the coordinator.

### What does not change

The existing `sync_dsl_rules_from_gsheets()` and
`setup_zzedc_from_gsheets()` functions are unchanged. They still bypass
the review queue and write directly to the live rules table. Use them
for the initial setup and for bulk updates that you are performing
yourself, not for routine coordinator-proposed changes.

---

## Files modified or created

| File | Change |
|---|---|
| `R/gsheets_monitor.R` | New file; 6 exported functions |
| `NAMESPACE` | 6 new `export()` entries |
| `vignettes/prazosin-large/prazosin-large-technical-guide.Rmd` | New Section 7a (5 subsections), 2 troubleshooting entries |
| `vignettes/prazosin-large/prazosin-large-user-guide.Rmd` | New Section 9, expanded coordinator workflow description, 2 troubleshooting entries, 3 glossary entries |
