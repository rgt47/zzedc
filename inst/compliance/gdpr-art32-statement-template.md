# GDPR Article 32 Statement for a zzedc Deployment (Template)
*2026-11-11 15:16 PST*

**Purpose.** A template for the controller's (or processor's)
statement of technical measures under Article 32 GDPR for a study
whose data are captured in zzedc. It can be used in the record of
processing activities (Article 30), a data protection impact
assessment (Article 35), or a data processing agreement annex.
Replace the bracketed text; delete measures that do not apply.

---

**Processing operation:** [study name, purpose, categories of data
subjects, categories of personal data including special categories
under Article 9]

**Controller:** [ ] **Processor(s) and hosting:** [ ]

## 1. Pseudonymization and encryption (Art. 32(1)(a))

**Encryption at rest.** The study database is encrypted with
[DuckDB's AES-256-GCM / the SQLCipher scheme, AES-256 / InnoDB
tablespace encryption / host volume encryption: name it]. The software
is configured with the `regulated` security profile, under which it
refuses to start if it cannot show the database to be encrypted
(verified on the file, from the database server, or [for PostgreSQL]
on the basis of a recorded attestation: [text of the attestation]).
Each start of the application records the security configuration in
force in the audit log.

**Encryption in transit.** Users reach the application only over
HTTPS, terminated at [reverse proxy, host]. [The connection between
the application and the database server uses TLS with server
certificate verification.]

**Encryption of copies.** Backups are encrypted (AES-256-CTR with
HMAC-SHA256, key derived from a passphrase held separately from the
database key). Data exports containing personal data are encrypted
with a password of at least 12 characters, and any modification of an
encrypted export is detected on decryption.

**Pseudonymization.** Direct identifiers [list: for example subject
names, medical record numbers] are [not stored / stored only in
restricted tables]. Exports for analysis replace [list fields] with
keyed pseudonyms (HMAC-SHA256). The pseudonymization key is held
separately from the database key and from the analysts who receive
the export. Pseudonymized exports remain personal data (Art. 4(5));
they are not described as anonymous. Fields with few possible values
(for example age, sex, site) are [generalized / suppressed], not
pseudonymized, because pseudonymizing them does not prevent
re-identification.

**Keys.** Keys are supplied at runtime from [environment / secrets
manager / AWS KMS] and are never written into configuration files or
stored with the data; the software refuses a key written into its
configuration. Keys are held by [custodians], rotated [schedule], and
each load of the database key is recorded in the audit log.

## 2. Confidentiality, integrity, availability, resilience (Art. 32(1)(b))

- Access is limited to named user accounts with roles [list roles];
  accounts lock after [n] failed attempts; sessions end after [n]
  minutes of inactivity; passwords expire after [n] days.
- Every change to study data, users, and configuration is recorded in
  an audit log in which each entry is chained to the previous one by a
  cryptographic hash, so alteration or deletion of entries is
  detectable (`verify_audit_integrity()`).
- [Hosting: availability arrangements, redundancy, monitoring.]

## 3. Restoration after an incident (Art. 32(1)(c))

Backups are taken [schedule] and kept [location, retention]. A
restore is staged and applied before the application opens the
database, so a restore cannot be overwritten by the running
application. Restores were last tested on [date].

## 4. Regular testing (Art. 32(1)(d))

The installation, operational, and performance qualification suite
(`run_validation_suite()`) is run [at installation, after each
upgrade, and every n months], including tests of encryption at rest,
export and backup encryption, pseudonymization, key custody, and
HTTPS enforcement. The results are kept with [document reference].

## 5. Measures that are the controller's or processor's responsibility

Organizational measures (staff training and confidentiality
undertakings, access approval and review, incident response, breach
notification under Articles 33 and 34), physical security of the
hosting, operating system and network security, and the choice of
which fields to pseudonymize are not provided by the software and are
addressed in [document references].
