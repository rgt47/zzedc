# HIPAA Encryption Worksheet for a zzedc Deployment (Template)
*2026-11-11 15:16 PST*

**Purpose.** A template for the covered entity's (or business
associate's) risk-analysis record on the encryption specifications of
the HIPAA Security Rule: 45 CFR 164.312(a)(2)(iv), encryption and
decryption of ePHI at rest, and 164.312(e)(2)(ii), encryption in
transmission. Both are addressable under the rule in force at this
revision: the entity must implement each, or document why it is not
reasonable and appropriate and what equivalent measure is used
instead. A pending rulemaking (NPRM, 2025-01-06) would make both
required; completing section 2 with "implemented" satisfies either
version.

Fill in the bracketed fields. Attach the evidence listed in section 4.

## 1. Deployment

| Field | Value |
|---|---|
| Study / system name | [ ] |
| Covered entity or business associate | [ ] |
| zzedc version | [from the `COMPLIANCE_CHECK` record, field `zzedc_version`] |
| Hosting (institutional server, cloud provider, region) | [ ] |
| Database backend | [DuckDB / SQLite with cipher build / PostgreSQL / MySQL or MariaDB] |
| Security profile | [must read `regulated`] |
| Completed by, date | [ ] |

## 2. Specification decisions

### 2.1 Encryption at rest, 164.312(a)(2)(iv)

| Question | Answer |
|---|---|
| Implemented? | [Yes / No, with alternative in 2.3] |
| Mechanism | [DuckDB AES-256-GCM / SQLCipher-scheme AES-256 / InnoDB tablespace encryption / host volume or provider encryption: name it] |
| Basis for the claim | [package-enforced and verified / server-verified / server-attested: from the `at_rest_mechanism` field] |
| If server-attested: who attests, and on what evidence | [for example the provider's encryption setting and key ID, screenshots or configuration export attached] |
| Key location | [environment variable / secrets manager / AWS KMS: from `key_source`; never the key itself] |
| Key custodians (at least two, separate custody) | [ ] |
| Rotation schedule | [ ] (`rotate_database_key()`) |
| Backups encrypted? | [Yes: `ZZEDC_BACKUP_PASSPHRASE` set, or backups of an encrypted database] |
| Exports containing ePHI encrypted? | [Yes: export password policy] |

### 2.2 Encryption in transmission, 164.312(e)(2)(ii)

| Question | Answer |
|---|---|
| Browser to application | [HTTPS at reverse proxy; certificate issuer; TLS versions allowed] |
| Application to database | [Not applicable (in-process DuckDB or SQLite) / TLS with `verify-full` or `VERIFY_IDENTITY`: from the `tls` field] |
| Transfers of exports and backups | [method, for example SFTP or institutional file share with TLS] |

### 2.3 If either specification is not implemented

| Question | Answer |
|---|---|
| Which specification | [ ] |
| Why encryption is not reasonable and appropriate | [ ] |
| Equivalent alternative measure | [ ] |
| Residual risk accepted by (name, role, date) | [ ] |

Note: under the `regulated` profile zzedc will not start on storage it
cannot show to be encrypted, so 2.3 normally applies only to a
deployment run under `standard`, which should itself be justified here.

## 3. Risk assessment of the encryption controls

| Threat | Likelihood | Impact | Control | Residual risk |
|---|---|---|---|---|
| Theft or loss of the database file or disk | [ ] | [ ] | Encryption at rest; key held elsewhere | [ ] |
| Theft of a backup | [ ] | [ ] | Encrypted backups | [ ] |
| Interception between browser and server | [ ] | [ ] | HTTPS required | [ ] |
| Interception between application and database server | [ ] | [ ] | Verified TLS required | [ ] |
| Disclosure of the key (for example in a configuration file) | [ ] | [ ] | `check_key_custody()` refuses keys in `config.yml`; key access recorded | [ ] |
| Loss of the key | [ ] | [ ] | Two custodians; previous keys kept for retained backups | [ ] |
| Compromise of the running server (data decrypted in memory) | [ ] | [ ] | Not addressed by encryption at rest; host hardening, access control | [ ] |

## 4. Evidence to attach

1. The startup `COMPLIANCE_CHECK` audit record from the production
   instance (`get_audit_trail(filters = list(event_type =
   "COMPLIANCE_CHECK"))`), showing `profile: regulated` and
   `at_rest: yes`.
2. The IQ/OQ/PQ report from `run_validation_suite()` on the
   production host, including IQ-008 and OQ-011 to OQ-020.
3. For a server-attested backend: the attestation text in
   `config.yml` and the provider or host evidence it refers to.
4. The reverse proxy configuration (HTTPS).
5. The key custody record (who holds the key, where, since when).
