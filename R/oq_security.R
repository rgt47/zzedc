#' Operational Qualification Tests for the Security Controls (internal)
#'
#' Run by `run_oq_tests()` as OQ-011 to OQ-020. Each test exercises one
#' control from the encryption and compliance plan and is written so
#' that it fails against the behavior that control replaced (noted per
#' test). The tests use temporary files only and restore the security
#' profile they change.
#'
#' Not covered here, because they need infrastructure a qualification
#' run cannot assume: encryption on a live PostgreSQL or MySQL server,
#' and a cipher-enabled RSQLite. Those are qualified on the deployment
#' itself with the startup compliance record
#' (`compliance_self_check()`).
#'
#' @param verbose Logical: print progress.
#' @return A named list of results from `create_validation_result()`.
#' @keywords internal
.run_security_oq_tests <- function(verbose = TRUE) {
  results <- list()

  run_one <- function(id, name, code) {
    if (verbose) cat("  ", id, ": ", name, "... ", sep = "")
    t1 <- Sys.time()
    out <- tryCatch(code(), error = function(e) list(success = FALSE, message = conditionMessage(e)))
    res <- create_validation_result(
      test_id = id, test_name = name, category = "OQ",
      passed = isTRUE(out$success), message = out$message,
      duration_ms = as.numeric(difftime(Sys.time(), t1, units = "secs")) * 1000
    )
    if (verbose) cat(if (res$passed) "PASSED\n" else "FAILED\n")
    res
  }

  with_profile <- function(profile, code) {
    old <- options(zzedc.security_profile = profile)
    on.exit(options(old), add = TRUE)
    reset_encryption_warnings()
    force(code)
  }

  plain_db <- tempfile(fileext = ".db")
  on.exit(unlink(plain_db), add = TRUE)
  con <- DBI::dbConnect(RSQLite::SQLite(), plain_db)
  DBI::dbExecute(con, "CREATE TABLE subjects (id TEXT, initials TEXT)")
  DBI::dbExecute(con, "INSERT INTO subjects VALUES ('S-001', 'ABC')")
  DBI::dbDisconnect(con)

  # Replaced: the 'regulated' requirement did not exist; a plaintext
  # database opened silently.
  results$OQ_011 <- run_one("OQ-011", "Regulated profile refuses unencrypted storage", function() {
    refused <- with_profile("regulated", tryCatch({
      suppressMessages(check_storage_encryption(db_path = plain_db))
      FALSE
    }, error = function(e) TRUE))
    list(success = refused,
         message = if (refused) "Plaintext SQLite refused under 'regulated'"
                   else "Plaintext SQLite accepted under 'regulated'")
  })

  # Replaced: a byte-ratio heuristic reported plaintext files as
  # encrypted.
  results$OQ_012 <- run_one("OQ-012", "Encryption verification detects plaintext", function() {
    v <- verify_database_encryption(plain_db, key = generate_db_key())
    list(success = isFALSE(v$encrypted),
         message = paste("verify_database_encryption():", v$message))
  })

  # Replaced: the export password argument was ignored.
  results$OQ_013 <- run_one("OQ-013", "Export encryption and tamper detection", function() {
    f <- tempfile(fileext = ".csv")
    on.exit(unlink(c(f, paste0(f, ".enc"))), add = TRUE)
    writeLines("id,initials\nS-001,ABC", f)
    enc <- encrypt_export_file(f, "oq-export-passphrase-01")
    raw_enc <- readBin(enc, "raw", file.size(enc))
    no_plaintext <- length(grepRaw("S-001", raw_enc, fixed = TRUE)) == 0
    wrong_pw <- tryCatch({ decrypt_export_file(enc, "a-different-passphrase"); FALSE },
                         error = function(e) TRUE)
    raw_enc[length(raw_enc) - 40] <- xor(raw_enc[length(raw_enc) - 40], as.raw(1))
    tampered <- tempfile(fileext = ".enc")
    on.exit(unlink(tampered), add = TRUE)
    writeBin(raw_enc, tampered)
    tamper_caught <- tryCatch({ decrypt_export_file(tampered, "oq-export-passphrase-01"); FALSE },
                              error = function(e) TRUE)
    ok <- no_plaintext && wrong_pw && tamper_caught
    list(success = ok, message = sprintf(
      "ciphertext free of plaintext: %s; wrong password rejected: %s; modification rejected: %s",
      no_plaintext, wrong_pw, tamper_caught))
  })

  # Replaced: an unkeyed hash, reversible by hashing candidate IDs.
  results$OQ_014 <- run_one("OQ-014", "Pseudonymization is keyed", function() {
    k1 <- openssl::rand_bytes(32)
    k2 <- openssl::rand_bytes(32)
    p1 <- pseudonymize_values("S-001", key = k1)
    p2 <- pseudonymize_values("S-001", key = k2)
    unkeyed <- as.character(openssl::sha256("S-001"))
    ok <- !identical(p1, p2) && !identical(p1, unkeyed) &&
      identical(p1, pseudonymize_values("S-001", key = k1))
    list(success = ok, message = "HMAC-SHA256: stable under one key, differs across keys and from an unkeyed hash")
  })

  # Replaced: a key written into config.yml was used without comment.
  results$OQ_015 <- run_one("OQ-015", "Key custody: literal key in config refused", function() {
    literal <- list(database = list(encryption_key = generate_db_key()))
    reference <- list(database = list(encryption_key = "${DB_ENCRYPTION_KEY}"))
    refused <- with_profile("regulated", tryCatch({ check_key_custody(literal); FALSE },
                                                  error = function(e) TRUE))
    allowed <- with_profile("regulated", isTRUE(check_key_custody(reference)))
    list(success = refused && allowed,
         message = sprintf("literal key refused: %s; ${VAR} reference accepted: %s", refused, allowed))
  })

  # Replaced: backups were plaintext copies (and "compressed" backups
  # were not compressed).
  results$OQ_016 <- run_one("OQ-016", "Backup encryption and policy", function() {
    copy <- tempfile(fileext = ".db")
    file.copy(plain_db, copy)
    out <- finalize_backup_file(copy, compress = TRUE, passphrase = "oq-backup-passphrase-01")
    on.exit(unlink(c(copy, out)), add = TRUE)
    header <- readBin(out, "raw", 16)
    not_sqlite <- !identical(header[1:15], charToRaw("SQLite format 3"))
    refused <- with_profile("regulated", tryCatch({ check_backup_policy(FALSE, NULL); FALSE },
                                                  error = function(e) TRUE))
    list(success = grepl("\\.db\\.gz\\.enc$", out) && not_sqlite && refused,
         message = sprintf("encrypted backup written: %s; unencrypted backup refused under 'regulated': %s",
                           not_sqlite, refused))
  })

  # Replaced: no HTTPS requirement; a client could claim HTTPS with a
  # forwarded header.
  results$OQ_017 <- run_one("OQ-017", "HTTPS required and not spoofable", function() {
    fake <- function(protocol, host, fwd = NULL, remote = "203.0.113.5") {
      list(clientData = list(url_protocol = protocol, url_hostname = host),
           request = list(HTTP_X_FORWARDED_PROTO = fwd, REMOTE_ADDR = remote))
    }
    required <- with_profile("regulated", https_required(list()))
    spoof <- session_https_status(fake("http:", "edc.example.org", fwd = "https"))$ok
    proxy <- session_https_status(fake("http:", "edc.example.org", fwd = "https", remote = "127.0.0.1"))$ok
    direct <- session_https_status(fake("https:", "edc.example.org"))$ok
    ok <- required && !spoof && proxy && direct
    list(success = ok, message = sprintf(
      "required under 'regulated': %s; forwarded header from remote client rejected: %s; local proxy accepted: %s",
      required, !spoof, proxy))
  })

  # Replaced: server databases were refused outright under 'regulated'
  # with no route to qualification, and TLS settings were not checked.
  results$OQ_018 <- run_one("OQ-018", "Server database TLS and at-rest rules", function() {
    st_ok <- .server_storage_state("postgresql", list(sslmode = "verify-full",
                                                     at_rest_attestation = "volume encryption"),
                                   tls_live = TRUE)
    st_weak <- .server_storage_state("postgresql", list(sslmode = "require"), tls_live = TRUE)
    st_my <- .server_storage_state("mysql", list(ssl_mode = "VERIFY_IDENTITY"),
                                   tablespaces = data.frame(name = c("s/a", "s/b"),
                                                            encrypted = c(TRUE, FALSE)))
    weak_refused <- tryCatch({ .enforce_server_tls(st_weak, "postgresql", "regulated"); FALSE },
                             error = function(e) TRUE)
    ok <- identical(st_ok$at_rest_basis, "attested") && isTRUE(st_ok$tls_required_by_config) &&
      is.na(st_weak$at_rest) && weak_refused && isFALSE(st_my$at_rest)
    list(success = ok, message = paste(
      "attestation labeled as attested; sslmode 'require' refused under 'regulated':", weak_refused,
      "; unencrypted InnoDB tablespace detected:", isFALSE(st_my$at_rest)))
  })

  # Replaced: case report form entries were saved with no audit record,
  # and a failed audit write never stopped the change it described.
  results$OQ_019 <- run_one("OQ-019", "Data entry audited in the same transaction", function() {
    con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    ensure_data_entries_table(con)
    ok <- db_insert_data_entry(con, "OQ-SUBJ", "oq_form", list(v = 1), created_by = "oq")
    audited <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM audit_log WHERE record_id = ?",
                               params = list(ok$entry_id))$n == 1
    DBI::dbExecute(con, "ALTER TABLE audit_chain RENAME TO audit_chain_oq")
    bad <- db_insert_data_entry(con, "OQ-SUBJ-2", "oq_form", list(v = 2), created_by = "oq")
    rolled_back <- isFALSE(bad$success) &&
      DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM data_entries WHERE subject_id = 'OQ-SUBJ-2'")$n == 0
    list(success = isTRUE(ok$success) && audited && rolled_back,
         message = sprintf("entry audited: %s; entry refused when its audit record fails: %s",
                           audited, rolled_back))
  })

  # Replaced: audit records could be updated or deleted through the
  # application's account (and a purge function deleted them), and a
  # rewrite that recomputed the chain was undetectable.
  results$OQ_020 <- run_one("OQ-020", "Audit trail append-only and checkpointed", function() {
    con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    .ensure_audit_tables(con)
    for (k in 1:3) {
      .with_db_transaction(con, function(c) .append_audit_record(c, "UPDATE", "t", k, "oq", user_id = "oq"))
    }
    blocked <- tryCatch({ DBI::dbExecute(con, "DELETE FROM audit_log"); FALSE }, error = function(e) TRUE) &&
      tryCatch({ DBI::dbExecute(con, "UPDATE audit_log SET user_id = 'x'"); FALSE }, error = function(e) TRUE)
    dir <- tempfile("oq_cp_")
    on.exit(unlink(dir, recursive = TRUE), add = TRUE)
    cp <- audit_checkpoint(dir, key = "oq-checkpoint-key-000000", conn = con)
    line <- jsonlite::fromJSON(readLines(file.path(dir, "audit_checkpoints.jsonl"))[1])
    head_now <- DBI::dbGetQuery(con, "SELECT record_hash FROM audit_chain ORDER BY chain_order DESC LIMIT 1")$record_hash
    checkpointed <- identical(line$record_hash, head_now) &&
      identical(line$mac, as.character(openssl::sha256(.checkpoint_canonical(line), key = "oq-checkpoint-key-000000")))
    list(success = blocked && checkpointed && identical(audit_protection_status(con), "database triggers"),
         message = sprintf("update/delete blocked: %s; checkpoint of chain head written and keyed: %s",
                           blocked, checkpointed))
  })

  results
}
