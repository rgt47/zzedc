#' Export Data with Integrity Verification and Optional Encryption
#'
#' Exports query results to multiple formats with cryptographic
#' integrity hashing. The export file is encrypted only when a
#' `password` is supplied; without one it is written in plaintext,
#' whatever the encryption state of the source database.
#'
#' @param query Character: SQL SELECT query to export
#' @param format Character: Output format ("csv", "xlsx", "json", default: "csv")
#' @param password Character: Optional password. When supplied, the
#'   export is written only in encrypted form (`.enc`, see
#'   `encrypt_export_file()`), and no plaintext copy is left in
#'   `export_dir`. Must be at least 12 characters.
#' @param include_hash Logical: Add SHA-256 hash file? (default: TRUE)
#' @param export_dir Character: Directory for exports (default: "./exports")
#' @param db_path Character: Path to database (optional, uses default if NULL)
#'
#' @return Character string with path to exported file (ending in
#'   `.enc` when `password` was supplied)
#'
#' @details
#' This function:
#' 1. Connects to the database
#' 2. Executes provided SQL query
#' 3. Exports to requested format (CSV, XLSX, JSON)
#' 4. If `password` is supplied, encrypts the export and removes the
#'    plaintext
#' 5. Generates a SHA-256 hash of the file actually written
#' 6. Logs export to audit trail
#' 7. Returns file path
#'
#' Earlier versions accepted `password` but ignored it, always writing
#' a plaintext file.
#'
#' Formats:
#' - csv: Comma-separated values (default)
#' - xlsx: Microsoft Excel workbook
#' - json: JSON array format
#'
#' Hash files (.sha256) enable verification using verify_exported_data()
#'
#' @examples
#' \dontrun{
#'   # Export all subjects (plaintext file)
#'   file_path <- export_encrypted_data(
#'     query = "SELECT * FROM subjects",
#'     format = "csv"
#'   )
#'
#'   # Export with password protection (encrypted .enc file)
#'   file_path <- export_encrypted_data(
#'     query = "SELECT * FROM mmse_assessments WHERE visit_label = 'Baseline'",
#'     format = "xlsx",
#'     password = "a long passphrase only the recipient knows"
#'   )
#'   decrypt_export_file(file_path, "a long passphrase only the recipient knows")
#' }
#'
#' @export
export_encrypted_data <- function(query, format = "csv", password = NULL,
                                   include_hash = TRUE, export_dir = "./exports",
                                   db_path = NULL) {
  if (!is.null(password)) {
    .check_export_password(password)
  }

  tryCatch({
    # Create export directory if needed
    if (!dir.exists(export_dir)) {
      dir.create(export_dir, recursive = TRUE, showWarnings = FALSE)
    }

    # Generate filename
    timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
    base_filename <- paste0("export_", timestamp)

    # Map format to extension
    ext <- switch(format,
      "csv" = "csv",
      "xlsx" = "xlsx",
      "json" = "json",
      "csv"  # default
    )

    final_file <- file.path(export_dir, paste0(base_filename, ".", ext))
    # With a password, the plaintext is staged outside export_dir so a
    # readable copy never appears where exports are collected.
    export_file <- if (is.null(password)) {
      final_file
    } else {
      tempfile(fileext = paste0(".", ext))
    }

    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)
    data <- DBI::dbGetQuery(conn, query)

    # Export based on format
    if (format == "csv") {
      utils::write.csv(data, export_file, row.names = FALSE)
    } else if (format == "xlsx") {
      writexl::write_xlsx(data, export_file)
    } else if (format == "json") {
      jsonlite::write_json(data, export_file, pretty = TRUE)
    }

    if (!is.null(password)) {
      staged_plaintext <- export_file
      on.exit(unlink(staged_plaintext), add = TRUE)
      export_file <- encrypt_export_file(
        staged_plaintext, password, output_path = paste0(final_file, ".enc")
      )
    }

    # Generate hash if requested
    if (include_hash) {
      file_content <- readBin(export_file, "raw", file.size(export_file))
      file_hash <- digest::digest(file_content, algo = "sha256")

      hash_file <- paste0(export_file, ".sha256")
      writeLines(file_hash, hash_file)
    }

    # Log to audit trail
    log_export_activity(
      file_path = export_file,
      query = query,
      format = format,
      hash_verified = include_hash
    )

    return(export_file)

  }, error = function(e) {
    stop("Export failed: ", e$message)
  })
}


.export_enc_magic <- charToRaw("ZZEDCENC")
.export_enc_version <- as.raw(1)
.export_enc_default_rounds <- 64L
.export_password_min_chars <- 12L

#' Validate an Export Password (internal)
#' @param password Character scalar.
#' @keywords internal
.check_export_password <- function(password) {
  if (!is.character(password) || length(password) != 1 || is.na(password)) {
    stop("Export password must be a single character string")
  }
  if (nchar(password) < .export_password_min_chars) {
    stop("Export password must be at least ", .export_password_min_chars,
         " characters")
  }
  invisible(TRUE)
}

#' Derive Encryption and MAC Keys from a Password (internal)
#' @keywords internal
.derive_export_keys <- function(password, salt, rounds) {
  material <- openssl::bcrypt_pbkdf(password, salt, rounds = rounds, size = 64L)
  list(enc = material[1:32], mac = material[33:64])
}

#' Encrypt an Export File with a Password
#'
#' Writes an encrypted copy of `input_path` using AES-256-CTR with an
#' HMAC-SHA256 tag over the whole file (encrypt-then-MAC). Keys are
#' derived from the password with bcrypt-pbkdf and a random 16-byte
#' salt.
#'
#' @param input_path Character: plaintext file to encrypt.
#' @param password Character: at least 12 characters.
#' @param output_path Character: destination (default
#'   `paste0(input_path, ".enc")`).
#' @param rounds Integer: bcrypt-pbkdf rounds (default 64, roughly half
#'   a second on current hardware). Stored in the file header.
#'
#' @return The output path, invisibly.
#'
#' @details
#' File layout: the 8-byte magic `"ZZEDCENC"`, a version byte, the
#' round count (4 bytes, big-endian), the 16-byte salt, the 16-byte
#' counter IV, the ciphertext, and a 32-byte HMAC-SHA256 tag computed
#' over everything before it.
#'
#' AES-GCM is not used because `openssl::aes_gcm_encrypt()` (openssl
#' R package 2.4.2) returns no authentication tag, and a modified
#' ciphertext decrypts without error; the separate HMAC provides the
#' integrity check GCM would otherwise supply.
#'
#' @examples
#' f <- tempfile(fileext = ".csv")
#' write.csv(data.frame(x = 1:3), f, row.names = FALSE)
#' enc <- encrypt_export_file(f, "correct horse battery staple")
#' out <- decrypt_export_file(enc, "correct horse battery staple")
#' read.csv(out)
#' unlink(c(f, enc, out))
#'
#' @export
encrypt_export_file <- function(input_path, password, output_path = NULL,
                                rounds = .export_enc_default_rounds) {
  .check_export_password(password)
  if (!file.exists(input_path)) {
    stop("File not found: ", input_path)
  }
  rounds <- as.integer(rounds)
  if (is.na(rounds) || rounds < 16L) {
    stop("rounds must be an integer of at least 16")
  }
  output_path <- output_path %||% paste0(input_path, ".enc")

  plaintext <- readBin(input_path, "raw", n = file.size(input_path))
  salt <- openssl::rand_bytes(16)
  iv <- openssl::rand_bytes(16)
  keys <- .derive_export_keys(password, salt, rounds)
  ciphertext <- if (length(plaintext) == 0) {
    raw(0)
  } else {
    as.raw(openssl::aes_ctr_encrypt(plaintext, key = keys$enc, iv = iv))
  }

  rounds_bytes <- writeBin(rounds, raw(), size = 4, endian = "big")
  body <- c(.export_enc_magic, .export_enc_version, rounds_bytes, salt, iv,
            ciphertext)
  tag <- as.raw(openssl::sha256(body, key = keys$mac))

  writeBin(c(body, tag), output_path)
  invisible(output_path)
}

#' Decrypt an Export File Created by `encrypt_export_file()`
#'
#' Checks the HMAC tag before decrypting, so a wrong password or any
#' modification of the file is reported as an error and no output is
#' written.
#'
#' @param input_path Character: `.enc` file.
#' @param password Character: the password used to encrypt it.
#' @param output_path Character: destination for the plaintext
#'   (default: `input_path` with the `.enc` suffix removed, in
#'   `tempdir()`, so decrypted data is not written next to the
#'   encrypted file by accident).
#'
#' @return The output path, invisibly.
#'
#' @export
decrypt_export_file <- function(input_path, password, output_path = NULL) {
  if (!file.exists(input_path)) {
    stop("File not found: ", input_path)
  }
  bytes <- readBin(input_path, "raw", n = file.size(input_path))
  header_len <- 8 + 1 + 4 + 16 + 16
  if (length(bytes) < header_len + 32 ||
      !identical(bytes[1:8], .export_enc_magic)) {
    stop("Not a zzedc encrypted export: ", input_path)
  }
  if (!identical(bytes[9], .export_enc_version)) {
    stop("Unsupported zzedc encrypted export version: ", as.integer(bytes[9]))
  }

  rounds <- readBin(bytes[10:13], "integer", size = 4, endian = "big")
  salt <- bytes[14:29]
  iv <- bytes[30:45]
  body <- bytes[seq_len(length(bytes) - 32)]
  tag <- bytes[(length(bytes) - 31):length(bytes)]

  keys <- .derive_export_keys(password, salt, rounds)
  expected <- as.raw(openssl::sha256(body, key = keys$mac))
  # Compare every byte rather than stopping at the first difference.
  if (sum(as.integer(xor(expected, tag))) != 0) {
    stop("Decryption failed: wrong password, or the file has been modified")
  }

  ct_len <- length(bytes) - 32 - header_len
  plaintext <- if (ct_len == 0) {
    raw(0)
  } else {
    ciphertext <- bytes[header_len + seq_len(ct_len)]
    openssl::aes_ctr_decrypt(ciphertext, key = keys$enc, iv = iv)
  }

  output_path <- output_path %||%
    file.path(tempdir(), sub("\\.enc$", "", basename(input_path)))
  writeBin(as.raw(plaintext), output_path)
  invisible(output_path)
}


#' Verify Exported Data Integrity
#'
#' Verifies exported data has not been tampered with using SHA-256 hash.
#'
#' @param file_path Character: Path to exported data file
#' @param hash_file Character: Path to hash file (auto-detected if NULL)
#'
#' @return List with verification results:
#'   - valid: Logical TRUE if hash matches
#'   - file_hash: Computed hash of file
#'   - stored_hash: Hash read from hash file
#'   - message: Detailed verification message
#'
#' @details
#' Compares SHA-256 hash of current file content with stored hash.
#' Detects:
#' - File tampering or corruption
#' - Missing hash file
#' - Hash mismatches
#'
#' @examples
#' \dontrun{
#'   verification <- verify_exported_data(
#'     file_path = "./exports/export_subjects_20251218_123456.csv"
#'   )
#'   if (verification$valid) {
#'     cat("Data integrity verified!\n")
#'   }
#' }
#'
#' @export
verify_exported_data <- function(file_path, hash_file = NULL) {
  tryCatch({
    results <- list(
      valid = FALSE,
      file_hash = NA_character_,
      stored_hash = NA_character_,
      message = ""
    )

    # Verify file exists
    if (!file.exists(file_path)) {
      results$message <- paste("File not found:", file_path)
      return(results)
    }

    # Auto-detect hash file if not provided
    if (is.null(hash_file)) {
      hash_file <- paste0(file_path, ".sha256")
    }

    # Verify hash file exists
    if (!file.exists(hash_file)) {
      results$message <- paste("Hash file not found:", hash_file)
      return(results)
    }

    # Calculate current hash
    file_content <- readBin(file_path, "raw", file.size(file_path))
    file_hash <- digest::digest(file_content, algo = "sha256")
    results$file_hash <- file_hash

    # Read stored hash
    stored_hash <- readLines(hash_file, n = 1)
    results$stored_hash <- stored_hash

    # Compare hashes
    results$valid <- identical(file_hash, stored_hash)
    results$message <- ifelse(
      results$valid,
      "Integrity verified: hash matches",
      "INTEGRITY FAILED: hash mismatch - file may have been modified"
    )

    return(results)

  }, error = function(e) {
    return(list(
      valid = FALSE,
      error = paste("Verification failed:", e$message)
    ))
  })
}


#' Get Export Activity History
#'
#' Retrieves audit trail of all data exports with optional filtering.
#'
#' @param filters List: Filter criteria (date_from, date_to, user, format, status)
#'
#' @return Data frame with export history records
#'
#' @details
#' Returns data frame with columns:
#' - export_id: Unique export identifier
#' - export_date: When export occurred
#' - user_id: Who performed export
#' - file_path: Location of exported file
#' - query: SQL query that was exported
#' - format: Export format used
#' - file_size: Size of exported file
#' - hash_verified: Whether hash verification was done
#' - status: Export status (success/failure)
#'
#' @examples
#' \dontrun{
#'   # Get all exports in last 7 days
#'   history <- get_export_history(
#'     filters = list(date_from = Sys.Date() - 7)
#'   )
#'
#'   # Get exports by user
#'   history <- get_export_history(
#'     filters = list(user = "jane_smith")
#'   )
#' }
#'
#' @keywords internal
#' @export
get_export_history <- function(filters = list()) {
  tryCatch({
    conn <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    # Build query with filters
    query <- "SELECT * FROM export_audit WHERE 1=1"

    if (!is.null(filters$date_from)) {
      filters$date_from <- as.character(filters$date_from)
      query <- paste0(query, " AND DATE(export_date) >= '", filters$date_from, "'")
    }

    if (!is.null(filters$date_to)) {
      filters$date_to <- as.character(filters$date_to)
      query <- paste0(query, " AND DATE(export_date) <= '", filters$date_to, "'")
    }

    if (!is.null(filters$user)) {
      query <- paste0(query, " AND user_id = '", filters$user, "'")
    }

    if (!is.null(filters$format)) {
      query <- paste0(query, " AND format = '", filters$format, "'")
    }

    if (!is.null(filters$status)) {
      query <- paste0(query, " AND status = '", filters$status, "'")
    }

    query <- paste0(query, " ORDER BY export_date DESC")

    # Execute query - only if table exists
    tryCatch({
      history <- DBI::dbGetQuery(conn, query)
    }, error = function(e) {
      history <- data.frame()
    })

    return(history)

  }, error = function(e) {
    warning("Error retrieving export history: ", e$message)
    return(data.frame())
  })
}


#' Get the Pseudonymization Key
#'
#' Returns the key used by `pseudonymize_values()` and
#' `selective_field_export()`. It is kept distinct from the database
#' encryption key so that a pseudonymized export does not depend on, or
#' reveal anything about, the key protecting the database.
#'
#' @return Raw vector of 32 bytes.
#'
#' @details
#' Resolution order:
#' 1. `ZZEDC_PSEUDONYM_KEY` environment variable (64 hex characters).
#' 2. Otherwise, derived from the database key returned by
#'    `get_encryption_key()` as HMAC-SHA256(db key,
#'    `"zzedc-pseudonymization-v1"`). This keeps pseudonyms stable for a
#'    study without a second secret to manage, while the domain
#'    separation means the two keys are not interchangeable.
#'
#' Pseudonyms stay linkable across exports only while this key is
#' unchanged. Rotating it, or rotating the database key when no
#' explicit pseudonymization key is set, produces new pseudonyms.
#'
#' @export
get_pseudonymization_key <- function() {
  explicit <- Sys.getenv("ZZEDC_PSEUDONYM_KEY", unset = "")
  if (nzchar(explicit)) {
    verify_db_key(explicit)
    return(.hex_to_raw(explicit))
  }
  db_key <- .hex_to_raw(get_encryption_key())
  as.raw(openssl::sha256(charToRaw("zzedc-pseudonymization-v1"), key = db_key))
}

#' Pseudonymize Values with HMAC-SHA256
#'
#' Replaces each value with a keyed hash. The same value always maps to
#' the same pseudonym under the same key, so records stay linkable, but
#' the original cannot be recovered without the key.
#'
#' @param x Vector of values; `NA` stays `NA`.
#' @param key Raw key (default `get_pseudonymization_key()`).
#'
#' @return Character vector of 64-character hex pseudonyms.
#'
#' @details
#' This is pseudonymization in the sense of GDPR Article 4(5): the
#' output is still personal data, because whoever holds the key can
#' re-identify by hashing candidate values. It is not encryption, and
#' it does not protect low-variety fields (age, sex, site, visit) even
#' from someone who lacks the key if the key leaks; generalize or
#' suppress such fields instead of pseudonymizing them. Apply it to
#' direct identifiers.
#'
#' @examples
#' k <- openssl::rand_bytes(32)
#' pseudonymize_values(c("SUBJ-001", "SUBJ-002", NA), key = k)
#'
#' @export
pseudonymize_values <- function(x, key = get_pseudonymization_key()) {
  out <- rep(NA_character_, length(x))
  present <- !is.na(x)
  if (any(present)) {
    out[present] <- as.character(
      openssl::sha256(as.character(x[present]), key = key)
    )
  }
  out
}

#' Export with Selected Fields Pseudonymized
#'
#' Exports data with the chosen columns replaced by HMAC-SHA256
#' pseudonyms (see `pseudonymize_values()`). Other columns are written
#' unchanged, and the export file itself is not encrypted.
#'
#' @param data_df Data frame: Data to export
#' @param fields_to_pseudonymize Character vector: Column names to
#'   pseudonymize. Use for direct identifiers only.
#' @param format Character: Output format ("csv", "xlsx", "json")
#' @param export_dir Character: Directory for exports (default: "./exports")
#' @param fields_to_encrypt Deprecated alias for
#'   `fields_to_pseudonymize`. The old name described the operation
#'   inaccurately: it never encrypted anything.
#'
#' @return Character string with path to exported file
#'
#' @details
#' Earlier versions computed `sha256(value || key)` under the database
#' encryption key and called the result "field-level encryption". That
#' construction is not a standard keyed hash, it is not reversible (so
#' it is not encryption), and it reused the database key. This version
#' uses HMAC-SHA256 under a separate pseudonymization key, so its
#' output values differ from those of earlier versions: exports made
#' before and after this change cannot be linked on pseudonymized
#' fields.
#'
#' A metadata file (`.metadata.json`) records which fields were
#' pseudonymized and the method used.
#'
#' @examples
#' \dontrun{
#'   file_path <- selective_field_export(
#'     data_df = subjects_data,
#'     fields_to_pseudonymize = c("subject_id", "initials"),
#'     format = "csv"
#'   )
#' }
#'
#' @keywords internal
#' @export
selective_field_export <- function(data_df, fields_to_pseudonymize = NULL,
                                   format = "csv", export_dir = "./exports",
                                   fields_to_encrypt = NULL) {
  if (!is.null(fields_to_encrypt)) {
    warning(
      "selective_field_export(): 'fields_to_encrypt' is deprecated; use ",
      "'fields_to_pseudonymize'. The fields are pseudonymized ",
      "(HMAC-SHA256), not encrypted.",
      call. = FALSE
    )
    fields_to_pseudonymize <- fields_to_pseudonymize %||% fields_to_encrypt
  }

  tryCatch({
    # Create export directory if needed
    if (!dir.exists(export_dir)) {
      dir.create(export_dir, recursive = TRUE, showWarnings = FALSE)
    }

    # Generate filename
    timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
    base_filename <- paste0("export_selective_", timestamp)

    ext <- switch(format, "csv" = "csv", "xlsx" = "xlsx", "json" = "json", "csv")
    export_file <- file.path(export_dir, paste0(base_filename, ".", ext))

    data_export <- data_df
    missing_fields <- setdiff(fields_to_pseudonymize, names(data_df))
    if (length(missing_fields) > 0) {
      stop("Fields not found in data: ", paste(missing_fields, collapse = ", "))
    }
    if (length(fields_to_pseudonymize) > 0) {
      key <- get_pseudonymization_key()
      for (field in fields_to_pseudonymize) {
        data_export[[field]] <- pseudonymize_values(data_export[[field]], key = key)
      }
    }

    # Export
    if (format == "csv") {
      utils::write.csv(data_export, export_file, row.names = FALSE)
    } else if (format == "xlsx") {
      writexl::write_xlsx(data_export, export_file)
    } else if (format == "json") {
      jsonlite::write_json(data_export, export_file, pretty = TRUE)
    }

    # Create metadata
    metadata <- list(
      export_file = basename(export_file),
      export_date = Sys.time(),
      format = format,
      pseudonymized_fields = fields_to_pseudonymize,
      pseudonymization_method = "HMAC-SHA256",
      file_encrypted = FALSE,
      total_rows = nrow(data_export),
      total_columns = ncol(data_export)
    )

    metadata_file <- paste0(export_file, ".metadata.json")
    jsonlite::write_json(metadata, metadata_file, pretty = TRUE)

    return(export_file)

  }, error = function(e) {
    stop("Selective export failed: ", e$message)
  })
}


#' Create Export Manifest
#'
#' Creates JSON manifest with export metadata and verification information.
#'
#' @param export_file_path Character: Path to exported data file
#' @param metadata List: Additional metadata to include
#'
#' @return Character string with path to manifest file
#'
#' @details
#' Manifest includes:
#' - File metadata (size, hash, row/column counts)
#' - Export metadata (who, when, why)
#' - Verification information (hash for integrity checking)
#' - Confidentiality classification
#'
#' @examples
#' \dontrun{
#'   manifest_path <- create_export_manifest(
#'     export_file_path = "./exports/export_subjects_20251218_123456.csv",
#'     metadata = list(
#'       study_id = "TOY-TRIAL-001",
#'       export_reason = "DSMB Review",
#'       exported_by = "john_doe"
#'     )
#'   )
#' }
#'
#' @keywords internal
#' @export
create_export_manifest <- function(export_file_path, metadata = list()) {
  tryCatch({
    # Verify file exists
    if (!file.exists(export_file_path)) {
      stop("Export file not found: ", export_file_path)
    }

    # Get file information
    file_info <- file.info(export_file_path)
    file_content <- readBin(export_file_path, "raw", file.size(export_file_path))
    file_hash <- digest::digest(file_content, algo = "sha256")

    # Count rows (basic approach for CSV)
    row_count <- NA_integer_
    if (tolower(tools::file_ext(export_file_path)) == "csv") {
      tryCatch({
        row_count <- nrow(utils::read.csv(export_file_path, nrows = -1))
      }, error = function(e) {
        row_count <<- NA_integer_
      })
    }

    # Count columns
    col_count <- NA_integer_
    if (tolower(tools::file_ext(export_file_path)) == "csv") {
      tryCatch({
        col_count <- ncol(utils::read.csv(export_file_path, nrows = 1))
      }, error = function(e) {
        col_count <<- NA_integer_
      })
    }

    # Create manifest
    manifest <- list(
      export_file = basename(export_file_path),
      export_path = export_file_path,
      export_date = Sys.time(),
      file_hash = file_hash,
      file_size = as.integer(file_info$size),
      row_count = row_count,
      column_count = col_count,
      format = tolower(tools::file_ext(export_file_path))
    )

    # Add user metadata if provided
    if (length(metadata) > 0) {
      manifest <- c(manifest, metadata)
    }

    # Write manifest
    manifest_file <- paste0(export_file_path, ".manifest.json")
    jsonlite::write_json(manifest, manifest_file, pretty = TRUE)

    return(manifest_file)

  }, error = function(e) {
    stop("Manifest creation failed: ", e$message)
  })
}


#' Log Export Activity (Internal)
#'
#' Records export activity to audit trail database table.
#'
#' @keywords internal
log_export_activity <- function(file_path, query, format, hash_verified) {
  tryCatch({
    conn <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    # Create export_audit table if doesn't exist
    prepare_auto_increment(conn, "export_audit", "export_id")
    DBI::dbExecute(conn, sprintf("
      CREATE TABLE IF NOT EXISTS export_audit (
        export_id %s,
        export_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        user_id TEXT,
        file_path TEXT NOT NULL,
        query TEXT,
        format TEXT,
        file_size INTEGER,
        hash_verified BOOLEAN,
        status TEXT DEFAULT 'success'
      )
    ", auto_increment_ddl("export_audit", "export_id")))

    # Insert audit record
    DBI::dbExecute(conn, "
      INSERT INTO export_audit
      (export_date, file_path, query, format, hash_verified, status)
      VALUES (?, ?, ?, ?, ?, 'success')
    ", list(
      Sys.time(),
      file_path,
      query,
      format,
      hash_verified
    ))

  }, error = function(e) {
    warning("Failed to log export activity: ", e$message)
  })
}
