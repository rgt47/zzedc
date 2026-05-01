---
name: regulatory-compliance-implementation-roadmap
description: Delta-only roadmap of regulatory features that are not yet implemented or that remain partially implemented in the ZZedc package
type: roadmap
---

# ZZedc Regulatory Compliance: Open Work
*2026-04-30 15:44 PDT*

This document lists regulatory features that are **not yet
implemented** or that remain **partially implemented** in the
package. It is a delta against the canonical compliance state
described in `gdpr-and-cfr-part11.md`. Items previously listed
in the December 2025 'unified implementation roadmap' that have
since shipped are no longer tracked here; the canonical document
records what is in place.

The full pre-shipment roadmap is preserved at
`docs/archive/compliance/regulatory-compliance-implementation-roadmap-2025-12.md`
for historical reference.

## How items are scoped

Each item below is one of:

- **Function gap** — a regulatory obligation has only schema
  support or no support; an exported R function is missing.
- **Transport gap** — a function exists that records intent in
  the database; an outbound delivery channel (email, HTTP,
  postal) is needed for the obligation to be satisfied.
- **Architectural debt** — the codebase contains parallel or
  inconsistent implementations of the same feature; one should
  be retired or the two reconciled.
- **Audit gap** — a feature is claimed in older documents but
  was outside the scope of the most recent implementation
  audit; the claim is unverified, not refuted.
- **Operational** — the obligation is real, but it falls
  outside the package boundary (deployment, training, paper
  records); listed here only to make the boundary explicit.

## 21 CFR Part 11

### F1. Training records and §11.10(i) competency gating
*Status:* Function gap. Schema and statistics query exist
(`R/cfr_part11_extensions.R:140` `user_training` table;
statistics at line 612) but no exported function records
training events, attests competency, or refuses an
electronic-signature operation when training is expired or
absent. Implementation should provide:

- `record_training(user_id, topic, completed_at, ...)`
- `verify_training_current(user_id, signature_meaning)`
- integration with `apply_electronic_signature()` to refuse
  signing when training is not current.

### F2. Operational system checks (§11.10(f)) as a discrete subsystem
*Status:* Function gap (or scope clarification needed). Older
summaries mapped §11.10(f) to the form-validation rules in
`R/validation_rules.R`. If §11.10(f) requires a subsystem
distinct from form validation, none exists. Decide: either
extend the canonical compliance document to argue that form
validation satisfies §11.10(f), or implement an explicit
operational-checks module.

### F3. Multi-factor authentication and device controls (§11.10(g), §11.10(h))
*Status:* Audit gap. The MFA claim resides in
`R/auth_module.R`, which has not been audited at the same
revision as the rest of the compliance code. The claim is
unverified; it should be audited and reconciled against
`gdpr-and-cfr-part11.md` before MFA is asserted as a
deployed control.

### F4. Duplicate electronic-signature implementation
*Status:* Architectural debt. Two parallel implementations
exist: the canonical `R/electronic_signatures.R` (74 tests,
referenced from the audit pipeline) and a parallel pair in
`R/cfr_part11_extensions.R:335` `create_electronic_signature`
and `R/cfr_part11_extensions.R:410` `verify_cfr_signature`
(no dedicated tests, not referenced from the canonical
pipeline). The duplicate path should be deprecated and
removed, or reconciled with the canonical path.

### F5. Backup and recovery procedure framework
*Status:* Function gap (or operational, depending on intent).
A Shiny module exists at `R/backup_restore_module.R`, but
there is no procedure-level framework with documented RTO/RPO
targets, scheduled-backup verification, or backup-integrity
checks tied to the audit chain. Decide whether this belongs
in the package or in deployment runbooks.

### F6. Regulatory submission package generation
*Status:* Function gap. There is no module that produces a
regulatory-submission package (combined system documentation,
validation reports, signature manifests, audit-chain export).
This was a stretch goal in the December 2025 roadmap.

## GDPR

### G1. Article 30 register management
*Status:* Function gap. A `processing_activities` table is
defined at `R/gdpr_database_extensions.R:20` but no exported
function inserts, updates, queries, or exports the register.
Implementation should provide:

- `register_processing_activity(name, purpose, lawful_basis, ...)`
- `update_processing_activity(activity_id, ...)`
- `export_article_30_register(format = c('json', 'pdf'))`

### G2. Data minimization log
*Status:* Function gap. A `data_minimization_log` table is
defined at `R/gdpr_database_extensions.R:20`. No exported
function operates on it.

### G3. International transfer assessments (Chapter V)
*Status:* Function gap. Only a boolean column
(`R/gdpr_database_extensions.R:119`) and a UI label
(`R/privacy_module.R:239`) exist. A controller relying on
ZZedc to substantiate Chapter V compliance has no in-package
support for transfer impact assessments, Standard Contractual
Clauses tracking, or adequacy decision lookup. Implementation
should provide enumerated transfer mechanisms, an SCC tracker,
and an adequacy-decision check.

### G4. Outbound notification transport (Articles 19, 33, 34)
*Status:* Transport gap. The functions
`notify_dpo()`, `notify_supervisory_authority()`,
`notify_data_subjects()`, and `notify_erasure_third_party()`
persist notification intent to database rows but do not deliver
notifications to any external channel. The 72-hour Article 33
obligation is therefore satisfied operationally rather than by
the package alone. Implementation options:

- Provide pluggable transports (SMTP, HTTP webhook, S3 export
  for human handoff) selectable via configuration.
- Record dispatch confirmations back into the system so
  `check_72_hour_deadline()` reflects actual transmit time.

### G5. AWS KMS live-integration validation
*Status:* Partial. `R/aws_kms_utils.R:45` `setup_aws_kms`
and `R/aws_kms_utils.R:139` `rotate_encryption_key` are
callable, but no integration test runs against a live KMS
endpoint. The MySQL adapter has the same pattern (per
`docs/NEXT_STEPS.md` Tier 1 item 1); the same approach
(transient-credential CI job) is appropriate here.

## Cross-cutting

### X1. SQLCipher build dependency
*Status:* Operational documentation gap. The default RSQLite
distribution does not include SQLCipher. The package supports
encryption when run against a SQLCipher-enabled RSQLite (for
example via SQLite3MultipleCiphers or a custom build), but
the requirement is not surfaced to operators in the install
documentation. The technical-lead vignette should call this
out as a deployment prerequisite when encryption is required.

### X2. Dual-compliance regulatory-hold reconciliation
*Status:* Architectural debt. Two mechanisms answer 'is this
record on a hold?': a config-gated UI behavior at
`R/privacy_module.R:357`/`:505` and a `legal_holds` table
exercised by `R/erasure.R:341` `create_legal_hold`. They are
not unit-tested together. Pick one source of truth and
deprecate the other, or write the reconciliation explicitly.

### X3. Compliance-report test coverage
*Status:* Audit gap. The internal scoring functions
`generate_gdpr_compliance_report()` and
`generate_cfr_compliance_report()` exist but have no
dedicated tinytest coverage. Add tests so that the scoring
output is itself audited.

### X4. Live audit-chain integrity validation in deployment
*Status:* Operational. The audit chain is correct by
construction; the assertion that integrity is 100% on a
specific deployment requires running
`verify_audit_integrity()` against the live database. The
deployment runbook (technical-lead vignette) should require
this verification as part of go-live and on a recurring
schedule.

## Sequencing

The closure order suggested by `docs/NEXT_STEPS.md` (Tier 1
production-readiness then Tier 4 documentation hygiene then
Tier 3 CRAN submission) implies that the items in this
document fall mostly **after** Tier 3. The exceptions:

- F3 (MFA audit) and X3 (compliance-report tests) are
  cheap and worth closing before any external review of
  the canonical compliance document.
- F4 (duplicate signature path) is technical debt that is
  cheap to retire and removes a question an auditor would
  reasonably ask.
- X1 (SQLCipher documentation) is a documentation change,
  not code, and should be folded into the Tier 4 doc-hygiene
  pass.

The remaining items (G1–G5, F1, F2, F5, F6, X2) are scope
decisions that depend on whether the package is intended to
own each obligation or to delegate it to deployment.

---
*Source: ~/Dropbox/prj/sfw/05-zzedc/zzedc/docs/compliance/regulatory-compliance-implementation-roadmap.md*
