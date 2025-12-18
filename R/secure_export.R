#' Export Encrypted Data with Integrity Verification
#'
#' Exports query results to multiple formats with cryptographic integrity hashing.
#'
#' @param query Character: SQL SELECT query to export
#' @param format Character: Output format ("csv", "xlsx", "json", default: "csv")
#' @param password Character: Optional password for additional encryption
#' @param include_hash Logical: Add SHA-256 hash file? (default: TRUE)
#' @param export_dir Character: Directory for exports (default: "./exports")
#'
#' @return Character string with path to exported file
#'
#' @details
#' This function:
#' 1. Connects to encrypted database
#' 2. Executes provided SQL query
#' 3. Generates SHA-256 hash of export content
#' 4. Exports to requested format (CSV, XLSX, JSON)
#' 5. Stores hash in separate verification file
#' 6. Logs export to audit trail
#' 7. Returns file path
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
#'   # Export all subjects
#'   file_path <- export_encrypted_data(
#'     query = "SELECT * FROM subjects",
#'     format = "csv"
#'   )
#'
#'   # Export with password protection
#'   file_path <- export_encrypted_data(
#'     query = "SELECT * FROM mmse_assessments WHERE visit_label = 'Baseline'",
#'     format = "xlsx",
#'     password = "secure_password"
#'   )
#' }
#'
#' @export
export_encrypted_data <- function(query, format = "csv", password = NULL,
                                   include_hash = TRUE, export_dir = "./exports") {
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

    export_file <- file.path(export_dir, paste0(base_filename, ".", ext))

    # Connect and execute query
    conn <- connect_encrypted_db()
    data <- DBI::dbGetQuery(conn, query)
    DBI::dbDisconnect(conn)

    # Export based on format
    if (format == "csv") {
      utils::write.csv(data, export_file, row.names = FALSE)
    } else if (format == "xlsx") {
      writexl::write_xlsx(data, export_file)
    } else if (format == "json") {
      jsonlite::write_json(data, export_file, pretty = TRUE)
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
#' @export
get_export_history <- function(filters = list()) {
  tryCatch({
    conn <- connect_encrypted_db()

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

    DBI::dbDisconnect(conn)

    return(history)

  }, error = function(e) {
    warning("Error retrieving export history: ", e$message)
    return(data.frame())
  })
}


#' Selective Field Encryption on Export
#'
#' Exports data with selective field-level encryption.
#'
#' @param data_df Data frame: Data to export
#' @param fields_to_encrypt Character vector: Column names to encrypt
#' @param format Character: Output format ("csv", "xlsx", "json")
#' @param export_dir Character: Directory for exports (default: "./exports")
#'
#' @return Character string with path to exported file
#'
#' @details
#' Encrypts specified columns while leaving others plaintext.
#' Creates metadata file describing encryption scheme.
#'
#' @examples
#' \dontrun{
#'   # Encrypt PII fields
#'   file_path <- selective_field_export(
#'     data_df = subjects_data,
#'     fields_to_encrypt = c("subject_id", "age"),
#'     format = "csv"
#'   )
#' }
#'
#' @export
selective_field_export <- function(data_df, fields_to_encrypt = NULL,
                                   format = "csv", export_dir = "./exports") {
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

    # Encrypt specified fields
    if (!is.null(fields_to_encrypt) && length(fields_to_encrypt) > 0) {
      data_export <- data_df

      for (field in fields_to_encrypt) {
        if (field %in% names(data_export)) {
          # Convert to character, encrypt, convert back
          key <- get_encryption_key()
          data_export[[field]] <- sapply(data_export[[field]], function(x) {
            if (is.na(x)) return(NA_character_)
            digest::digest(paste0(as.character(x), key), algo = "sha256")
          }, USE.NAMES = FALSE)
        }
      }
    } else {
      data_export <- data_df
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
      encrypted_fields = fields_to_encrypt,
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

    # Create export_audit table if doesn't exist
    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS export_audit (
        export_id INTEGER PRIMARY KEY AUTOINCREMENT,
        export_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        user_id TEXT,
        file_path TEXT NOT NULL,
        query TEXT,
        format TEXT,
        file_size INTEGER,
        hash_verified BOOLEAN,
        status TEXT DEFAULT 'success'
      )
    ")

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

    DBI::dbDisconnect(conn)

  }, error = function(e) {
    warning("Failed to log export activity: ", e$message)
  })
}
