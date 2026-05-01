---
name: gdpr-and-cfr-part11
description: Canonical regulatory compliance reference for ZZedc, mapping GDPR articles and 21 CFR Part 11 sections to verified package implementations
type: reference
---

# ZZedc Regulatory Compliance: GDPR and 21 CFR Part 11
*2026-04-30 15:44 PDT*

This document is the canonical compliance reference for the ZZedc
package. It supersedes the four overlapping summary documents
previously kept in `docs/compliance/` (now archived to
`docs/archive/compliance/`). Where those documents disagreed about
implementation status, the claims here are reconciled against the
current code in `R/` as of 2026-04-30.

## Reading guide

Each feature is classified as one of:

- **`Implemented`** — an exported R function operates on the
  feature; tinytest coverage exists; code is substantive (not a
  `stop('not yet implemented')` stub).
- **`Partial`** — function exists with a material caveat: an
  environment-dependent prerequisite, a missing transport layer
  (the function persists intent to a database row but performs
  no outbound delivery), absent or incidental test coverage, or a
  parallel orphan implementation.
- **`Documented only`** — a database table, schema flag, or UI
  label exists; no exported function operates on it; the
  regulatory claim is aspirational rather than technical.
- **`Not implemented`** — neither code nor schema elements exist
  in the audited file set.

Claims are cited as `R/<file>:<line>` and refer to the function
definition site at the time this document was written.

## Headline counts

Across 50 audited features mapped to GDPR articles or 21 CFR
Part 11 sections:

| Status | Count |
|---|---:|
| Implemented | 35 |
| Partial | 8 |
| Documented only | 6 |
| Not implemented | 1 |

We do not report a single 'compliance percentage'. The previous
summary documents quoted figures of 35%, 65%, 75%, and 90% with
no shared denominator; the per-feature table below is the
authoritative substitute.

## 21 CFR Part 11

### Audit trail (§11.10(e))

| Feature | Status | Implementation |
|---|---|---|
| Hash-chained immutable audit trail | Implemented | `R/audit_logging.R:151` `log_audit_event`; `R/audit_logging.R:340` `verify_audit_integrity` (chain verification with GENESIS sentinel at line 373) |
| Extended audit event taxonomy | Implemented | `R/audit_enhanced.R:26` `get_audit_event_types`; `R/audit_enhanced.R:472` `log_audit_event_extended` |
| Audit anomaly detection | Implemented | `R/audit_enhanced.R:589` `detect_audit_anomalies` |
| Audit search and statistics | Implemented | `R/audit_enhanced.R:766` `search_audit_trail`; `R/audit_enhanced.R:875` `get_audit_statistics` |
| Audit report export (PDF/CSV) | Implemented | `R/audit_logging.R:525` `export_audit_report`; `R/audit_logging.R:433` `create_audit_report` |

The audit chain is the load-bearing mechanism for §11.10(e)
('use of secure, computer-generated, time-stamped audit trails'
and 'when changes are made... record changes shall not obscure
previously recorded information'). `verify_audit_integrity()`
walks the chain end-to-end and reports any break; this is the
function a regulator should be pointed at to substantiate the
'continuity of record' claim.

The chain is correctness-preserving by construction; the claim
that 'audit trail integrity is 100% on this deployment' requires
running `verify_audit_integrity()` against the live database. The
package does not assert that this has been run on any particular
instance.

### Record-level controls (§11.10(c), §11.10(j))

| Feature | Status | Implementation |
|---|---|---|
| Record version control | Implemented | `R/version_control.R:136` `create_record_version`; `R/version_control.R:435` `compare_versions`; `R/version_control.R:573` `restore_record_version`; `R/version_control.R:650` `verify_version_integrity` |
| Record locking and unlocking | Implemented | `R/version_control.R:824` `lock_record`; `R/version_control.R:921` `unlock_record` |
| Data correction workflow with approval | Implemented | `R/data_correction.R:231` `create_correction_request`; `R/data_correction.R:468` `approve_correction`; `R/data_correction.R:568` `reject_correction`; `R/data_correction.R:671` `apply_correction`; `R/data_correction.R:1355` `verify_correction_integrity` |
| Correction override workflow | Implemented | `R/data_correction.R:821` `request_correction_override`; `R/data_correction.R:932` `approve_override` |

### Electronic signatures (§11.50, §11.70, §11.100, §11.200)

| Feature | Status | Implementation |
|---|---|---|
| Apply / verify / chain signatures | Implemented | `R/electronic_signatures.R:238` `apply_electronic_signature`; `R/electronic_signatures.R:547` `verify_electronic_signature`; `R/electronic_signatures.R:1128` `verify_signature_chain` |
| Signature meanings and statements | Implemented | `R/electronic_signatures.R:171` `get_signature_meanings`; `R/electronic_signatures.R:195` `get_signature_statement` |
| Signature requirement checking | Implemented | `R/electronic_signatures.R:652` `check_signature_requirements`; `R/electronic_signatures.R:740` `invalidate_signature` |
| Duplicate signature path in `cfr_part11_extensions.R` | Partial | `R/cfr_part11_extensions.R:335` `create_electronic_signature` and `R/cfr_part11_extensions.R:410` `verify_cfr_signature` are a parallel, orphaned implementation with no dedicated tests; the canonical path is `R/electronic_signatures.R`. See the 'Cross-cutting concerns' section below. |

### System validation (§11.10(a))

| Feature | Status | Implementation |
|---|---|---|
| IQ / OQ / PQ framework | Implemented | `R/validation_framework.R:74` `run_iq_tests`; `R/validation_framework.R:305` `run_oq_tests`; `R/validation_framework.R:628` `run_pq_tests`; `R/validation_framework.R:916` `run_validation_suite` |

The framework executes IQ/OQ/PQ checks in code. The
*organizational* artefacts that complete a Part 11 validation
package (Validation Master Plan, signed validation report, traceability
matrix to user requirements) are operational, not technical;
they are out of scope for this package.

### Change control (§11.10(k))

| Feature | Status | Implementation |
|---|---|---|
| Change request, impact assessment, approval, implementation, verification | Implemented | `R/change_control.R:195` `create_change_request`; `R/change_control.R:281` `add_impact_assessment`; `R/change_control.R:354` `add_change_approval`; `R/change_control.R:419` `add_implementation_step`; `R/change_control.R:473` `verify_implementation_step` |

### Training records (§11.10(i))

| Feature | Status | Implementation |
|---|---|---|
| User training records | Documented only | Schema only: `R/cfr_part11_extensions.R:140` defines a `user_training` table; statistics are read at `R/cfr_part11_extensions.R:612`. There is no exported function to record training events, attest competency, or block sign-off based on training status. |

This is a gap. §11.10(i) requires that 'persons who develop,
maintain, or use electronic record/electronic signature systems
have the education, training, and experience to perform their
assigned tasks.' The schema is in place; an implementation
should provide `record_training()`, `verify_training_current()`,
and integration with `apply_electronic_signature()` to refuse
signing when training is expired or absent.

### Operational system checks (§11.10(f))

| Feature | Status | Implementation |
|---|---|---|
| Operational system checks | Documented only | The previous compliance summaries mapped §11.10(f) to the form-validation rules in `R/validation_rules.R`. There is no module dedicated to operational system checks distinct from form validation; whether form-validation rules satisfy §11.10(f) for a given deployment is a regulatory-strategy decision, not a code claim. |

### Authority checks (§11.10(g), §11.10(h))

| Feature | Status | Implementation |
|---|---|---|
| Multi-factor authentication | Not verified at this revision | The previous summary documents claimed MFA capability; the relevant code lives in `R/auth_module.R`, which was outside the scope of the audit that produced this document. Treat this claim as unverified until `auth_module.R` is audited separately. |

## GDPR

### Data subject rights (Articles 15, 16, 17, 18, 20, 21)

| Right | Article | Status | Implementation |
|---|---|---|---|
| Right of access (DSAR) | Art. 15 | Implemented | `R/dsar.R:344` `create_dsar_request`; `R/dsar.R:542` `verify_subject_identity`; `R/dsar.R:852` `create_dsar_response`; `R/dsar.R:943` `complete_dsar_request`; `R/dsar.R:1006` `extend_dsar_deadline` |
| Right to rectification | Art. 16 | Implemented | `R/rectification.R:272` `create_rectification_request`; `R/rectification.R:537` `review_rectification_item`; `R/rectification.R:614` `apply_rectification_item`; `R/rectification.R:915` `complete_rectification_request` |
| Right to erasure | Art. 17 | Implemented | `R/erasure.R:640` `create_erasure_request`; `R/erasure.R:1012` `execute_erasure_item`; `R/erasure.R:1275` `complete_erasure_request` |
| Legal hold (Art. 17 ↔ §11.10(c) reconciliation) | Art. 17 | Implemented | `R/erasure.R:341` `create_legal_hold`; `R/erasure.R:435` `release_legal_hold`; `R/erasure.R:503` `check_legal_hold` |
| Third-party erasure notification (Art. 19) | Art. 19 | Partial | `R/erasure.R:1100` `add_erasure_third_party`; `R/erasure.R:1170` `notify_erasure_third_party`; `R/erasure.R:1231` `confirm_erasure_third_party`. The `notify_*` function persists notification intent to a database row but does not transmit (no email, HTTP, or fax delivery). |
| Right to restriction | Art. 18 | Implemented | `R/restriction.R:337` `create_restriction_request`; `R/restriction.R:813` `apply_restriction_item`; `R/restriction.R:973` `check_restriction_status`; `R/restriction.R:1044` `log_processing_attempt`; `R/restriction.R:1542` `activate_restriction_request` |
| Right to data portability | Art. 20 | Implemented | `R/portability.R:395` `create_portability_request`; `R/portability.R:863` `generate_portability_export`; `R/portability.R:1149` `initiate_controller_transfer`; `R/portability.R:1432` `complete_portability_request` |
| Right to object | Art. 21 | Implemented | `R/objection.R:271` `create_objection_request`; `R/objection.R:569` `stop_processing_activity`; `R/objection.R:710` `opt_out_marketing`; `R/objection.R:870` `uphold_objection`; `R/objection.R:946` `override_objection` |

The data-subject-rights modules are the strongest implementation
area in the package: each right has its own module with substantive
function coverage and tinytest assertions in the 60–160 range per
module.

### Lawful basis and consent (Articles 6, 7, 9)

| Feature | Status | Implementation |
|---|---|---|
| Consent recording, granular purposes | Implemented | `R/consent.R:247` `create_consent_purpose`; `R/consent.R:415` `record_consent`; `R/consent.R:942` `check_consent`; `R/consent.R:1108` `refresh_consent` |
| Consent withdrawal (Art. 7(3)) | Implemented | `R/consent.R:607` `withdraw_consent`; `R/consent.R:676` `withdraw_all_consents`; `R/consent.R:746` `create_withdrawal_request`; `R/consent.R:849` `process_withdrawal_request` |

### Storage limitation (Article 5(1)(e))

| Feature | Status | Implementation |
|---|---|---|
| Retention policies and enforcement | Implemented | `R/retention.R:295` `create_retention_policy`; `R/retention.R:543` `register_retention_record`; `R/retention.R:724` `get_expired_records`; `R/retention.R:981` `delete_retention_record`; `R/retention.R:1049` `anonymize_retention_record` |
| Retention legal hold and extension | Implemented | `R/retention.R:1119` `extend_retention`; `R/retention.R:1203` `apply_legal_hold`; `R/retention.R:1278` `release_retention_hold` |
| Retention review workflow | Implemented | `R/retention.R:836` `create_retention_review`; `R/retention.R:904` `complete_retention_review` |

### Breach notification (Articles 33, 34)

| Feature | Status | Implementation |
|---|---|---|
| Breach intake, timeline, 72-hour deadline check | Implemented | `R/breach_notification.R:176` `report_breach_incident`; `R/breach_notification.R:241` `update_breach_status`; `R/breach_notification.R:702` `check_72_hour_deadline`; `R/breach_notification.R:531` `add_timeline_event` |
| Breach risk assessment | Implemented | `R/breach_notification.R:497` `add_breach_risk_assessment`; `R/breach_notification.R:405` `assess_subject_notification`; `R/breach_notification.R:318` `assess_authority_notification` |
| Outbound notifications (DPO, supervisory authority, data subjects) | Partial | `R/breach_notification.R:287` `notify_dpo`; `R/breach_notification.R:359` `notify_supervisory_authority`; `R/breach_notification.R:447` `notify_data_subjects`. These functions persist notification intent to `breach_notifications` and `breach_timeline` rows; they do not transmit notifications by any external channel. The 72-hour Art. 33 obligation is satisfied operationally, not by this code alone. |

### Privacy impact assessment (Article 35)

| Feature | Status | Implementation |
|---|---|---|
| DPIA workflow | Implemented | `R/privacy_impact.R:192` `create_pia_assessment`; `R/privacy_impact.R:331` `add_risk_assessment`; `R/privacy_impact.R:441` `calculate_overall_risk`; `R/privacy_impact.R:483` `submit_pia_for_review`; `R/privacy_impact.R:508` `approve_pia` |

### Compliance reporting

| Feature | Status | Implementation |
|---|---|---|
| GDPR compliance scoring report | Partial | `R/gdpr_database_extensions.R:316` `generate_gdpr_compliance_report`; `R/gdpr_database_extensions.R:388` `calculate_compliance_score`. Function exists; no dedicated tinytest coverage. |
| CFR Part 11 compliance scoring report | Partial | `R/cfr_part11_extensions.R:573` `generate_cfr_compliance_report`; `R/cfr_part11_extensions.R:641` `calculate_cfr_compliance_score`. Function exists; no dedicated tinytest coverage. |

The internal scoring functions exist but are not the source of
the headline counts in this document; they are provided as
informational outputs to operators rather than as authoritative
metrics.

### Records-of-processing and data minimization (Articles 5(1)(c), 30)

| Feature | Status | Implementation |
|---|---|---|
| Article 30 register | Documented only | `R/gdpr_database_extensions.R:20` `add_gdpr_tables` defines a `processing_activities` table; no exported function inserts, queries, or exports the register. |
| Data minimization log | Documented only | `R/gdpr_database_extensions.R:20` defines a `data_minimization_log` table; no exported function operates on it. |

These are gaps. The previous summary documents marked both as
'complete' on the basis of the schema; this is misleading.
Implementation should provide `register_processing_activity()`,
`update_processing_activity()`, and `export_article_30_register()`
for the register, and `log_minimization_decision()` plus query
helpers for the minimization log.

### International transfers (Chapter V)

| Feature | Status | Implementation |
|---|---|---|
| International transfer impact / SCC tracking / adequacy lookup | Documented only | A boolean `international_transfers` column at `R/gdpr_database_extensions.R:119` and a UI label in `R/privacy_module.R:239`. No transfer impact assessment function, no Standard Contractual Clauses tracking, no adequacy decision lookup, no enumerated lawful-transfer mechanism. |

This is a genuine gap. The previous documents called this
'Framework Complete' on the basis of the column and label;
that overstates the implementation. A controller relying on
ZZedc to substantiate Chapter V compliance would have to
implement transfer-impact assessments out-of-band.

## Cross-cutting concerns

### Encryption at rest

`R/encryption_utils.R:87` `connect_encrypted` and
`R/db_connection.R:338` `connect_encrypted_db` provide AES-256
encryption when the package is run against a SQLCipher-enabled
RSQLite. The default RSQLite distribution from CRAN does **not**
include SQLCipher; the test suite at `inst/tinytest/test_encryption.R:31`
uses a `has_sqlcipher_support()` predicate to skip on
unsupported environments. Deployments must explicitly link
RSQLite against SQLCipher (for example via the
SQLite3MultipleCiphers fork or a custom-compiled SQLCipher build)
to obtain at-rest encryption.

The headline classification of this feature is therefore
**Partial**: the code is correct, but the package alone does
not deliver encryption. Operators must verify their RSQLite build.

`R/encryption_utils.R:22` `generate_db_key` and
`R/encryption_utils.R:59` `verify_db_key` for key generation are
**Implemented** independent of SQLCipher availability.

AWS KMS integration in `R/aws_kms_utils.R:45` `setup_aws_kms`
and `R/aws_kms_utils.R:139` `rotate_encryption_key` is
**Partial**: callable when AWS credentials are configured; no
integration test runs against a live KMS endpoint.

### Two electronic-signature implementations

There are two parallel implementations of electronic signatures
in the codebase: the canonical `R/electronic_signatures.R`
(which has 74 tinytest assertions and is referenced from the
Shiny modules and audit pipeline), and a parallel
`R/cfr_part11_extensions.R::create_electronic_signature` /
`verify_cfr_signature` pair (which has no dedicated tests and is
not referenced from the canonical signature pipeline). Either
the duplicate path should be deprecated and removed, or it
should be reconciled with the canonical path. Until then, an
auditor reading the source could reasonably ask which path
governs Part 11 §11.50/§11.70/§11.100/§11.200 claims; the
answer is `R/electronic_signatures.R`.

### Outbound notification transport

Three regulatory obligations require *outbound* communication:

- GDPR Art. 33 — notification to the supervisory authority within 72 hours of a personal-data breach.
- GDPR Art. 34 — notification to data subjects when a breach is high-risk.
- GDPR Art. 19 — notification to recipients to whom personal data has been disclosed when erasure or rectification has occurred.

The package implements the *intake, classification, timeline
tracking, and persistence* of notification intent for all three.
It does **not** implement the transport. `notify_dpo()`,
`notify_supervisory_authority()`, `notify_data_subjects()`, and
`notify_erasure_third_party()` insert rows; they do not send
email, post to an HTTP endpoint, or interface with any postal
service. Operationally, the controller must satisfy the
transport requirement by other means and record the dispatch
back into the system; the system can then verify timeliness via
`check_72_hour_deadline()`.

This is a deliberate scope decision: the package does not own
the messaging stack. It should be documented to operators rather
than papered over by 'Framework Complete' language.

### Dual-compliance: regulatory hold ↔ legal hold

The Shiny privacy module checks a `dual_compliance_config` flag
at `R/privacy_module.R:357` and halts erasure with a
'regulatory hold' at `R/privacy_module.R:505`. The legal-hold
mechanism in `R/erasure.R:341` (`create_legal_hold`) operates on
a separate `legal_holds` table. There are therefore two answers
to 'is this record on a regulatory hold?': a config-gated UI
behavior and a database table. They are not unit-tested
together. A future revision should pick one source of truth.

## What this document does not assert

- That multi-factor authentication is enforced. The MFA claim
  resides in `R/auth_module.R`, which has not been audited at
  this revision.
- That the audit chain integrity is 100% on any particular
  deployment. The chain is correct by construction; the
  assertion of integrity at runtime requires an explicit call
  to `verify_audit_integrity()`.
- That the validation framework constitutes a Part 11
  Validation Master Plan. The framework executes IQ/OQ/PQ
  checks in code; the organizational artefacts are out of
  scope for the package.
- That the package on its own satisfies operational obligations
  including: signed validation reports, IRB or supervisory
  authority approvals, Data Processing Agreements, Standard
  Contractual Clauses, breach notification dispatch, training
  attestations, or paper records.

## Open work

The companion document `regulatory-compliance-implementation-roadmap.md`
contains a delta-only list of regulatory features that are not
yet implemented or that remain Partial. That document is the
single source of truth for 'what is left'; this document is the
single source of truth for 'what is in place today'.

## References

Audit basis: review of `R/cfr_part11_extensions.R`,
`R/electronic_signatures.R`, `R/data_correction.R`,
`R/protocol_compliance.R`, `R/audit_logging.R`,
`R/audit_enhanced.R`, `R/version_control.R`,
`R/change_control.R`, `R/study_closeout.R`,
`R/adverse_events.R`, `R/validation_framework.R`,
`R/gdpr_database_extensions.R`, `R/dsar.R`, `R/erasure.R`,
`R/portability.R`, `R/rectification.R`, `R/restriction.R`,
`R/retention.R`, `R/consent.R`, `R/breach_notification.R`,
`R/privacy_impact.R`, `R/objection.R`,
`R/encryption_utils.R`, `R/aws_kms_utils.R`,
`R/db_connection.R`, `R/privacy_module.R`, and the
corresponding test files in `inst/tinytest/`. Audit date:
2026-04-30.

---
*Source: ~/Dropbox/prj/sfw/05-zzedc/zzedc/docs/compliance/gdpr-and-cfr-part11.md*
