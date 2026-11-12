# zzedc Data Security Summary for IRB and Information Security Review
*2026-11-11 15:16 PST*

zzedc is an open-source electronic data capture application (R and
Shiny) for clinical research. This page describes how a deployment
configured with its `regulated` security profile protects study data.
The deploying study team completes the bracketed fields.

**Deployment:** [study, host, backend, zzedc version]

## What is encrypted, and how

| Data | Protection |
|---|---|
| Study database, DuckDB backend | AES-256-GCM, by the DuckDB database engine, every page of the file |
| Study database, SQLite backend | AES-256 in the SQLCipher scheme, by an RSQLite build with SQLite3MultipleCiphers (the standard CRAN build cannot encrypt and is refused) |
| Study database, MySQL/MariaDB | InnoDB tablespace encryption on the server; zzedc confirms every study table is encrypted |
| Study database, PostgreSQL | Encryption of the server's storage (disk, cloud provider, or encrypting distribution), recorded by the deployer: [mechanism] |
| Backups | AES-256-CTR with HMAC-SHA256; key derived from a passphrase (bcrypt-pbkdf) held separately from the database key |
| Exports | Same as backups, under a password of at least 12 characters chosen at export |
| Browser to server | HTTPS (TLS) at a reverse proxy; the application refuses sessions that did not arrive over HTTPS |
| Application to database server | TLS with server certificate verification (`verify-full` / `VERIFY_IDENTITY`) |
| Identifiers in analysis exports | Replaced by keyed pseudonyms (HMAC-SHA256); the key is held apart from analysts. Pseudonymized data are still identifiable to the key holder and are treated as identifiable |

## Where keys live

The database key (256 bits, random) is supplied when the application
starts, from [an environment variable on the server, readable only by
the service account / a secrets manager / AWS KMS]. It is never stored
in the application's configuration or beside the database; the
application refuses to start if a key is written into its
configuration. Each start records in the audit log that the key was
loaded, and from where, without the key itself. Keys are held by
[two named custodians] and rotated [schedule]. Without the key the
database cannot be read by anyone, including the study team: a lost
key means lost data, so the key is kept in two places under separate
custody.

## Fail-closed behavior

Under the `regulated` profile the application does not start if it
cannot show that the database is encrypted, if a server connection
does not use verified TLS, or if the key is written into configuration;
it does not write an unencrypted backup of an unencrypted database.
These conditions stop the application with an error rather than
producing a warning.

## Access and accountability

Named user accounts with roles; lockout after repeated failed logins;
automatic logoff after inactivity; password expiry. Every change to
data, users, and configuration is recorded in a hash-chained audit log
in which any alteration or deletion is detectable.

## How a reviewer can verify encryption on the deployed instance

1. **Startup record.** Ask for the most recent `COMPLIANCE_CHECK`
   audit entry. It states the security profile, backend, whether the
   database is encrypted at rest and on what basis (verified by
   zzedc, verified from the server, or attested by the deployer),
   TLS status, key source, and whether HTTPS is required.
2. **Qualification report.** Ask for the output of
   `run_validation_suite()` run on the production host. IQ-008 checks
   the deployed database under the active profile; OQ-011 to OQ-020
   test the security controls.
3. **Direct check (file backends).** With the application stopped, in
   R on the server, in the study directory, with the key in
   `DB_ENCRYPTION_KEY`:

   ```r
   dbc <- zzedc::app_database_config(config::get(file = "config.yml"))
   zzedc::verify_database_encryption(
     zzedc::app_database_path(dbc),
     key = Sys.getenv("DB_ENCRYPTION_KEY"),
     adapter = zzedc::create_db_adapter(dbc)
   )
   ```

   It reports encrypted only if the file cannot be opened without the
   key and can be opened with it. An attempt to open the file with a generic SQLite or
   DuckDB tool and no key should fail.
4. **HTTPS.** Load the application's address with `http://`; it
   should redirect to `https://` or refuse.

## Limits

Encryption at rest protects copies of the files (stolen disks,
backups, misplaced copies). It does not protect data from someone who
controls the running server or holds a valid user account; those are
addressed by host security and access control. For PostgreSQL, the
statement that storage is encrypted is the deployer's, not a check
performed by zzedc.

**Contact:** [study data manager, information security contact]
