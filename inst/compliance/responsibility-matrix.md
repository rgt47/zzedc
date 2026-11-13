# zzedc Responsibility Matrix: 21 CFR Part 11, HIPAA 164.312, GDPR Article 32(1)
*2026-11-11 15:16 PST*

This matrix states, for each requirement, whether zzedc **enforces**
it (the software does it and refuses to run otherwise under the
`regulated` security profile), **supports** it (the software provides
the mechanism and the deployer must configure or operate it), or
leaves it to the **deployer** (an organizational, procedural, or
infrastructure control that no software package can satisfy). Each
row names the evidence: a qualification test ID from
`run_validation_suite()`, a function, or a document.

The matrix applies to a deployment that runs under the `regulated`
security profile (`security.profile: regulated` in `config.yml`).
Under `standard` or `development`, controls marked *enforces* are
reduced to warnings or switched off.

A software package cannot itself satisfy Part 11, HIPAA, or GDPR;
those regulate the organization that operates the system. The
supportable claim is that zzedc provides validated technical controls
supporting compliance when deployed in a supported security
configuration, with the deployer responsible for the rows marked
below.

The Part 11 rows summarize `docs/compliance/gdpr-and-cfr-part11.md`
in the source repository, which remains the detailed record for
those sections. Work on the remaining Part 11 gaps (plan Phase 5:
authority checks on every mutating function, a human-readable case
record export, documented workflow state machines) is in progress at
this revision; rows that depend on it say so.

## Supported security configurations

| Backend | At rest | Basis | In transit (database) |
|---|---|---|---|
| DuckDB with `encryption_key` | Encrypted by the DuckDB engine | Verified by zzedc on the file (keyless open must fail) | Not applicable (in-process) |
| SQLite with a cipher-enabled RSQLite | Encrypted by the SQLite cipher | Verified by zzedc on the file | Not applicable |
| MySQL/MariaDB with InnoDB encryption | Encrypted by the server | Verified by zzedc from InnoDB's tablespace report | TLS, `ssl_mode: VERIFY_IDENTITY` or `VERIFY_CA`, checked live |
| PostgreSQL | Encrypted by the host (volume, provider, or TDE distribution) | **Attested** by the deployer in `database.at_rest_attestation`; not verifiable by zzedc | TLS, `sslmode: verify-full` or `verify-ca`, checked live |
| SQLite on the CRAN RSQLite | **Not encrypted** | Refused under `regulated` | Not applicable |

Browser to application: HTTPS is required under `regulated` and
must be provided by a reverse proxy
(`system.file("templates", "nginx-zzedc.conf", package = "zzedc")`).

## 21 CFR Part 11

| Section | Requirement (abbreviated) | zzedc | Evidence |
|---|---|---|---|
| 11.10(a) | Validation | Supports | IQ/OQ/PQ: `run_validation_suite()`; IQ-008 (storage under the active profile); OQ-011 to OQ-020 (security controls). The validation plan, executed and signed report, and user-requirements traceability are the deployer's |
| 11.10(b) | Accurate, complete copies in human-readable and electronic form | Supports (partial) | Data and audit exports (`export_encrypted_data()`, `export_audit_report()`). A single per-subject case record is plan step 5.2, in progress |
| 11.10(c) | Protection of records for their retention period | Supports | Hash-chained, append-only audit log that zzedc never deletes (`verify_audit_integrity()`, OQ-007, OQ-020); record versioning and locking (OQ-005 to OQ-009); encrypted backups (OQ-016). Retention schedule and backup custody: deployer |
| 11.10(d) | Limiting system access to authorized individuals | Enforces | Authentication and role checks; lockout after failed attempts; session timeout; HTTPS required (OQ-017). Account provisioning and periodic access review: deployer |
| 11.10(e) | Secure, time-stamped audit trail | Enforces, with stated limits | Case report form entries are written with their audit record (submitted values, user, UTC time, client address, session) in one transaction, and are refused if it cannot be written (OQ-019); under `regulated` every failed audit write is an error. Hash chain (OQ-007); append-only triggers on SQLite, PostgreSQL, MySQL/MariaDB (OQ-020); external keyed checkpoints (`audit_checkpoint()`, `verify_audit_checkpoints()`); logins, failures, logoffs, and session ends recorded; audit viewer reads the chained log. Limits: DuckDB has no triggers (checkpoints only); a database administrator can drop triggers, so the application's database role must not own the schema on server backends (deployer); records after the latest checkpoint rely on the chain and triggers; viewing the audit trail itself is not recorded; triggers and locking on PostgreSQL and MySQL are not tested against live servers. Data corrections change the stored value and write the old value, new value, reason, and approver to the audit trail in one transaction, refusing a request whose original value no longer matches and honoring record locks (`apply_correction()`). Audit review procedure and checkpoint storage: deployer |
| 11.10(f) | Operational system checks (sequencing) | Supports (partial) | Correction and signature workflows; documentation and tests of each workflow's states are plan step 5.3, in progress |
| 11.10(g) | Authority checks | Supports (partial) | `require_role()`; extension to every mutating function is plan step 5.1, in progress |
| 11.10(h) | Device checks | Deployer | Not applicable to a browser application beyond authentication; terminal controls are institutional |
| 11.10(i) | Training of persons who develop, maintain, use | Deployer | Training records schema exists; no enforcement in zzedc (see `gdpr-and-cfr-part11.md`) |
| 11.10(j) | Written policies holding individuals accountable for signatures | Deployer | Policy document |
| 11.10(k) | Controls over system documentation | Supports | Change-control functions (`create_change_request()` and following). Document control: deployer |
| 11.30 | Open systems: additional measures such as encryption | Enforces when open | Encryption at rest (IQ-008, OQ-011, OQ-012), TLS to database servers (OQ-018), HTTPS (OQ-017), encrypted exports and backups (OQ-013, OQ-016) |
| 11.50, 11.70 | Signature manifestation and record linking | Supports | `apply_electronic_signature()`, `verify_signature_chain()` |
| 11.100 | Uniqueness of signatures | Supports | Unique user IDs; identity verification before account issue: deployer |
| 11.200 | Signature components (ID and password) | Supports | Signature path requires re-entry of credentials. Known limitation recorded in `vignette("technical-lead-guide")` Appendix C (signature-password hashing) |
| 11.300 | Controls for identification codes and passwords | Supports (partial) | Lockout after failed attempts; periodic expiry (11.300(b)); forced change of initial passwords (`must_change_password`, set for the default administrator). Minimum length is checked at setup only; a general complexity policy is not enforced. Loss management and device controls: deployer |

## HIPAA Security Rule, 45 CFR 164.312 (technical safeguards)

R = required, A = addressable under the rule in force at this
revision. A pending rulemaking (NPRM published 2025-01-06, not final
at this writing) would make encryption at rest and in transit
required; the configurations above already meet that proposal.

| Specification | R/A | zzedc | Evidence |
|---|---|---|---|
| (a)(2)(i) Unique user identification | R | Enforces | Per-user accounts; audit records carry the user ID |
| (a)(2)(ii) Emergency access procedure | R | Deployer | Procedure; zzedc supplies administrator accounts and restore (`request_database_restore()`) |
| (a)(2)(iii) Automatic logoff | A | Enforces | Logoff after `auth.session_timeout_minutes` of inactivity, recorded as a `LOGOUT` audit event (the timeout existed but was not active before 2026-11-11) |
| (a)(2)(iv) Encryption and decryption | A | Enforces under `regulated` | IQ-008, OQ-011, OQ-012; startup `COMPLIANCE_CHECK` audit record. See the worksheet `hipaa-encryption-worksheet.md` |
| (b) Audit controls | R | Enforces | Hash-chained, append-only audit log with external checkpoints (OQ-003, OQ-007, OQ-019, OQ-020); logins, failed logins, logoffs, session ends with client address; key loads (`log_key_access()`). Reads are recorded (`log_record_read()`): Data Explorer loads and downloads, Export Center previews and downloads, the EDC entries list, the data-quality report, and subject case reports, each with user, client address, session, and the subject identifiers disclosed (not the values); under `regulated` a read that cannot be recorded is not shown. `get_record_access_log()` lists who read a subject's records. The audit-trail viewer's own reads are not yet recorded. Regular review: deployer (164.308(a)(1)(ii)(D)) |
| (c)(2) Mechanism to authenticate ePHI | A | Supports | Audit hash chain; version integrity (OQ-008); export HMAC (OQ-013) |
| (d) Person or entity authentication | R | Enforces | Password authentication with lockout; identity proofing: deployer |
| (e)(2)(i) Transmission integrity controls | A | Supports | TLS (HTTPS, database TLS); integrity of exported files by HMAC |
| (e)(2)(ii) Transmission encryption | A | Enforces under `regulated` | HTTPS required (OQ-017); verified TLS to database servers (OQ-018) |

Administrative (164.308) and physical (164.310) safeguards, the risk
analysis, business associate agreements, and workforce sanctions are
the deployer's.

## GDPR Article 32(1)

| Item | zzedc | Evidence |
|---|---|---|
| (a) Pseudonymization | Supports | `pseudonymize_values()`, `selective_field_export()`: HMAC-SHA256 under a key held separately from the database key (OQ-014). Output remains personal data (Art. 4(5)). Choice of fields: controller |
| (a) Encryption | Enforces under `regulated` | At rest (IQ-008, OQ-011, OQ-012), exports (OQ-013), backups (OQ-016), in transit (OQ-017, OQ-018) |
| (b) Confidentiality, integrity, availability, resilience | Supports | Access control, audit chain, encrypted backups and staged restore. Hosting, redundancy, and capacity: deployer |
| (c) Timely restoration after an incident | Supports | `create_database_backup()`, `request_database_restore()`, `apply_pending_restore()`. Backup schedule, off-site copies, restore drills: deployer |
| (d) Regular testing and evaluation | Supports | `run_validation_suite()`; startup `COMPLIANCE_CHECK` record on every start. Testing schedule and review: deployer |

## Key custody (all three frameworks)

| Control | zzedc | Evidence |
|---|---|---|
| Key not stored with the data or in configuration | Enforces under `regulated` | `check_key_custody()` (OQ-015) |
| Separate keys per purpose | Supports | Database key, backup passphrase, export passwords, pseudonymization key are distinct (`?key_management`) |
| Key rotation | Supports | `rotate_database_key()` |
| Record of key use | Enforces | `log_key_access()` at every application start |
| Key escrow and loss recovery | Deployer | Keep keys in two places under separate custody; zzedc cannot recover a lost key |

## Evidence on a running deployment

At every start, the application writes a `COMPLIANCE_CHECK` event to
the audit log stating the profile, backend, whether storage is
encrypted and by what mechanism (package-enforced, server-verified,
server-attested, or none), TLS to the database, the key's source,
DuckDB extension settings, and whether HTTPS is required. Retrieve it
with:

```r
get_audit_trail(filters = list(event_type = "COMPLIANCE_CHECK"))
```
