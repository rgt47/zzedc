#' Right to Data Portability System
#'
#' GDPR Article 20 compliant data portability system.
#' Enables data subjects to receive their personal data in a structured,
#' commonly used, machine-readable format and transmit it to another controller.
#'
#' @name portability
#' @docType package
NULL

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

#' Safe Scalar Conversion for Portability System
#'
#' Converts values to scalar character, handling NULL and vectors.
#'
#' @param x Value to convert
#' @param default Default value if NULL or empty
#' @return Character scalar
#' @keywords internal
safe_scalar_portability <- function(x, default = NA_character_) {
  if (is.null(x) || length(x) == 0) {
    default
  } else if (length(x) > 1) {
    paste(x, collapse = "; ")
  } else {
    as.character(x)
  }
}

#' Safe Integer Conversion for Portability System
#'
#' Converts values to integer scalar, handling NULL.
#'
#' @param x Value to convert
#' @param default Default value if NULL or empty
#' @return Integer scalar
#' @keywords internal
safe_int_portability <- function(x, default = NA_integer_) {
  if (is.null(x) || length(x) == 0) {
    default
  } else {
    as.integer(x)
  }
}

#' Generate Portability Request Number
#'
#' Generates a unique portability request number.
#'
#' @return Character string in format PORT-TIMESTAMP-RANDOM
#' @keywords internal
generate_portability_number <- function() {
  timestamp <- format(Sys.time(), "%Y%m%d%H%M%S")
  random <- paste0(sample(c(0:9, LETTERS), 6, replace = TRUE), collapse = "")
  paste0("PORT-", timestamp, "-", random)
}

# ============================================================================
# INITIALIZATION
# ============================================================================

#' Initialize Portability System Tables
#'
#' Creates the database tables required for GDPR Article 20
#' Right to Data Portability compliance.
#'
#' Tables created:
#' - portability_requests: Main portability request tracking
#' - portability_datasets: Individual datasets included in export
#' - portability_exports: Generated export files
#' - portability_transfers: Direct controller-to-controller transfers
#' - portability_history: Audit trail for all actions
#'
#' @return List with success status and message
#' @export
#'
#' @examples
#' \dontrun{
#' init_portability()
#' }
init_portability <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS portability_requests (
        request_id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_number TEXT UNIQUE NOT NULL,
        dsar_request_id INTEGER,
        subject_id TEXT,
        subject_email TEXT NOT NULL,
        subject_name TEXT NOT NULL,
        request_type TEXT NOT NULL,
        legal_basis TEXT NOT NULL,
        target_controller TEXT,
        target_controller_contact TEXT,
        preferred_format TEXT DEFAULT 'JSON',
        status TEXT DEFAULT 'RECEIVED',
        received_date TEXT NOT NULL,
        due_date TEXT NOT NULL,
        completed_date TEXT,
        requested_by TEXT NOT NULL,
        reviewed_by TEXT,
        reviewed_at TEXT,
        review_notes TEXT,
        rejection_reason TEXT,
        exception_ground TEXT,
        request_hash TEXT NOT NULL,
        previous_hash TEXT,
        created_at TEXT DEFAULT (datetime('now')),
        FOREIGN KEY (dsar_request_id) REFERENCES dsar_requests(request_id)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS portability_datasets (
        dataset_id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_id INTEGER NOT NULL,
        table_name TEXT NOT NULL,
        data_category TEXT NOT NULL,
        record_count INTEGER DEFAULT 0,
        data_source TEXT NOT NULL,
        is_provided_by_subject INTEGER DEFAULT 1,
        is_derived INTEGER DEFAULT 0,
        is_eligible INTEGER DEFAULT 1,
        ineligibility_reason TEXT,
        status TEXT DEFAULT 'PENDING',
        included_in_export INTEGER DEFAULT 0,
        dataset_hash TEXT NOT NULL,
        created_at TEXT DEFAULT (datetime('now')),
        FOREIGN KEY (request_id) REFERENCES portability_requests(request_id)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS portability_exports (
        export_id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_id INTEGER NOT NULL,
        export_format TEXT NOT NULL,
        file_name TEXT NOT NULL,
        file_path TEXT,
        file_size_bytes INTEGER,
        record_count INTEGER,
        datasets_included TEXT,
        generated_at TEXT NOT NULL,
        generated_by TEXT NOT NULL,
        download_count INTEGER DEFAULT 0,
        last_downloaded_at TEXT,
        expires_at TEXT,
        is_encrypted INTEGER DEFAULT 0,
        encryption_method TEXT,
        checksum TEXT NOT NULL,
        export_hash TEXT NOT NULL,
        created_at TEXT DEFAULT (datetime('now')),
        FOREIGN KEY (request_id) REFERENCES portability_requests(request_id)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS portability_transfers (
        transfer_id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_id INTEGER NOT NULL,
        export_id INTEGER,
        target_controller TEXT NOT NULL,
        target_contact TEXT NOT NULL,
        transfer_method TEXT NOT NULL,
        transfer_status TEXT DEFAULT 'PENDING',
        initiated_at TEXT,
        initiated_by TEXT,
        completed_at TEXT,
        confirmation_received INTEGER DEFAULT 0,
        confirmation_date TEXT,
        confirmation_reference TEXT,
        failure_reason TEXT,
        transfer_hash TEXT NOT NULL,
        created_at TEXT DEFAULT (datetime('now')),
        FOREIGN KEY (request_id) REFERENCES portability_requests(request_id),
        FOREIGN KEY (export_id) REFERENCES portability_exports(export_id)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS portability_history (
        history_id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_id INTEGER NOT NULL,
        dataset_id INTEGER,
        export_id INTEGER,
        transfer_id INTEGER,
        action TEXT NOT NULL,
        action_details TEXT,
        performed_by TEXT NOT NULL,
        performed_at TEXT DEFAULT (datetime('now')),
        history_hash TEXT NOT NULL,
        previous_history_hash TEXT,
        FOREIGN KEY (request_id) REFERENCES portability_requests(request_id)
      )
    ")

    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_portability_requests_status
                         ON portability_requests(status)")
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_portability_requests_subject
                         ON portability_requests(subject_id)")
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_portability_datasets_request
                         ON portability_datasets(request_id)")
    DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_portability_exports_request
                         ON portability_exports(request_id)")

    list(success = TRUE, message = "Portability system initialized successfully")

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# REFERENCE DATA
# ============================================================================

#' Get Portability Request Types
#'
#' Returns valid portability request types.
#'
#' @return Named character vector of request types
#' @export
#'
#' @examples
#' types <- get_portability_request_types()
get_portability_request_types <- function() {
  c(
    RECEIVE = "Receive data in portable format",
    TRANSMIT = "Transmit data to another controller",
    BOTH = "Receive and transmit data"
  )
}

#' Get Portability Legal Bases
#'
#' Returns valid legal bases for portability under Article 20(1).
#'
#' @return Named character vector of legal bases
#' @export
#'
#' @examples
#' bases <- get_portability_legal_bases()
get_portability_legal_bases <- function() {
  c(
    CONSENT = "Processing based on consent (Article 6(1)(a) or 9(2)(a))",
    CONTRACT = "Processing necessary for contract performance (Article 6(1)(b))"
  )
}

#' Get Portability Export Formats
#'
#' Returns supported export formats for portable data.
#'
#' @return Named character vector of export formats
#' @export
#'
#' @examples
#' formats <- get_portability_export_formats()
get_portability_export_formats <- function() {
  c(
    JSON = "JSON (JavaScript Object Notation)",
    CSV = "CSV (Comma-Separated Values)",
    XML = "XML (Extensible Markup Language)",
    XLSX = "Excel Spreadsheet"
  )
}

#' Get Portability Statuses
#'
#' Returns valid status values for portability requests.
#'
#' @return Named character vector of status values
#' @export
#'
#' @examples
#' statuses <- get_portability_statuses()
get_portability_statuses <- function() {
  c(
    RECEIVED = "Request received",
    UNDER_REVIEW = "Under review",
    APPROVED = "Request approved",
    PARTIALLY_APPROVED = "Partially approved (some data ineligible)",
    DATA_PREPARED = "Data prepared for export",
    EXPORTED = "Data exported",
    TRANSFER_PENDING = "Transfer to controller pending",
    TRANSFER_COMPLETE = "Transfer completed",
    COMPLETED = "Request completed",
    REJECTED = "Request rejected"
  )
}

#' Get Transfer Methods
#'
#' Returns valid transfer methods for controller-to-controller transfers.
#'
#' @return Named character vector of transfer methods
#' @export
#'
#' @examples
#' methods <- get_transfer_methods()
get_transfer_methods <- function() {
  c(
    SECURE_EMAIL = "Secure encrypted email",
    SECURE_FTP = "Secure FTP transfer",
    API = "Direct API transfer",
    SECURE_LINK = "Secure download link",
    PHYSICAL_MEDIA = "Encrypted physical media"
  )
}

#' Get Portability Exceptions
#'
#' Returns valid exception grounds under Article 20(4).
#'
#' @return Named character vector of exception grounds
#' @export
#'
#' @examples
#' exceptions <- get_portability_exceptions()
get_portability_exceptions <- function() {
  c(
    RIGHTS_OF_OTHERS = "Would adversely affect rights and freedoms of others",
    NOT_PROVIDED_BY_SUBJECT = "Data not provided by data subject",
    NOT_AUTOMATED = "Processing not by automated means",
    WRONG_LEGAL_BASIS = "Processing not based on consent or contract",
    TECHNICALLY_INFEASIBLE = "Direct transmission technically not feasible"
  )
}

#' Get Data Source Types
#'
#' Returns valid data source types for eligibility determination.
#'
#' @return Named character vector of data source types
#' @export
#'
#' @examples
#' sources <- get_data_source_types()
get_data_source_types <- function() {
  c(
    PROVIDED = "Actively provided by data subject",
    OBSERVED = "Observed from data subject activity",
    DERIVED = "Derived or inferred by controller",
    THIRD_PARTY = "Received from third party"
  )
}

# ============================================================================
# REQUEST MANAGEMENT
# ============================================================================

#' Create Portability Request
#'
#' Creates a new GDPR Article 20 portability request with hash-chain integrity.
#'
#' @param subject_email Email address of the data subject
#' @param subject_name Name of the data subject
#' @param request_type Type from get_portability_request_types()
#' @param legal_basis Legal basis from get_portability_legal_bases()
#' @param requested_by User ID creating the request
#' @param subject_id Optional subject identifier
#' @param dsar_request_id Optional link to related DSAR request
#' @param target_controller Optional target controller for TRANSMIT requests
#' @param target_controller_contact Optional contact for target controller
#' @param preferred_format Preferred export format (default JSON)
#'
#' @return List with success status, request details or error message
#' @export
#'
#' @examples
#' \dontrun{
#' request <- create_portability_request(
#'   subject_email = "john@example.com",
#'   subject_name = "John Doe",
#'   request_type = "RECEIVE",
#'   legal_basis = "CONSENT",
#'   requested_by = "dpo"
#' )
#' }
create_portability_request <- function(subject_email,
                                        subject_name,
                                        request_type,
                                        legal_basis,
                                        requested_by,
                                        subject_id = NULL,
                                        dsar_request_id = NULL,
                                        target_controller = NULL,
                                        target_controller_contact = NULL,
                                        preferred_format = "JSON") {
  tryCatch({
    if (missing(subject_email) || is.null(subject_email) || subject_email == "") {
      return(list(success = FALSE, error = "subject_email is required"))
    }
    if (missing(subject_name) || is.null(subject_name) || subject_name == "") {
      return(list(success = FALSE, error = "subject_name is required"))
    }
    if (missing(request_type) || is.null(request_type) || request_type == "") {
      return(list(success = FALSE, error = "request_type is required"))
    }
    if (missing(legal_basis) || is.null(legal_basis) || legal_basis == "") {
      return(list(success = FALSE, error = "legal_basis is required"))
    }

    valid_types <- names(get_portability_request_types())
    if (!request_type %in% valid_types) {
      return(list(
        success = FALSE,
        error = paste("Invalid request_type. Must be one of:",
                     paste(valid_types, collapse = ", "))
      ))
    }

    valid_bases <- names(get_portability_legal_bases())
    if (!legal_basis %in% valid_bases) {
      return(list(
        success = FALSE,
        error = paste("Invalid legal_basis. Must be one of:",
                     paste(valid_bases, collapse = ", "))
      ))
    }

    if (request_type %in% c("TRANSMIT", "BOTH") &&
        (is.null(target_controller) || target_controller == "")) {
      return(list(success = FALSE,
                  error = "target_controller required for TRANSMIT requests"))
    }

    valid_formats <- names(get_portability_export_formats())
    if (!preferred_format %in% valid_formats) {
      return(list(
        success = FALSE,
        error = paste("Invalid preferred_format. Must be one of:",
                     paste(valid_formats, collapse = ", "))
      ))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    request_number <- generate_portability_number()
    received_date <- format(Sys.Date(), "%Y-%m-%d")
    due_date <- format(Sys.Date() + 30, "%Y-%m-%d")

    previous_hash <- NA_character_
    last_request <- DBI::dbGetQuery(con, "
      SELECT request_hash FROM portability_requests
      ORDER BY request_id DESC LIMIT 1
    ")
    if (nrow(last_request) > 0) {
      previous_hash <- last_request$request_hash[1]
    }

    hash_content <- paste(
      request_number,
      safe_scalar_portability(subject_id),
      subject_email,
      subject_name,
      request_type,
      legal_basis,
      received_date,
      requested_by,
      safe_scalar_portability(previous_hash),
      sep = "|"
    )
    request_hash <- digest::digest(hash_content, algo = "sha256")

    DBI::dbExecute(con, "
      INSERT INTO portability_requests (
        request_number, dsar_request_id, subject_id, subject_email,
        subject_name, request_type, legal_basis, target_controller,
        target_controller_contact, preferred_format, status,
        received_date, due_date, requested_by, request_hash, previous_hash
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      request_number,
      safe_int_portability(dsar_request_id),
      safe_scalar_portability(subject_id),
      subject_email,
      subject_name,
      request_type,
      legal_basis,
      safe_scalar_portability(target_controller),
      safe_scalar_portability(target_controller_contact),
      preferred_format,
      "RECEIVED",
      received_date,
      due_date,
      requested_by,
      request_hash,
      safe_scalar_portability(previous_hash)
    ))

    request_id <- DBI::dbGetQuery(con, "SELECT last_insert_rowid() as id")$id[1]

    log_portability_action(
      request_id = request_id,
      action = "REQUEST_CREATED",
      action_details = paste("Portability request created. Type:", request_type,
                            "- Legal basis:", legal_basis),
      performed_by = requested_by
    )

    list(
      success = TRUE,
      request_id = request_id,
      request_number = request_number,
      status = "RECEIVED",
      due_date = due_date,
      message = "Portability request created successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Log Portability Action
#'
#' Logs an action to the portability audit history with hash-chain.
#'
#' @param request_id Request ID
#' @param action Action performed
#' @param action_details Details of the action
#' @param performed_by User who performed the action
#' @param dataset_id Optional dataset ID
#' @param export_id Optional export ID
#' @param transfer_id Optional transfer ID
#'
#' @return List with success status
#' @keywords internal
log_portability_action <- function(request_id,
                                    action,
                                    action_details,
                                    performed_by,
                                    dataset_id = NULL,
                                    export_id = NULL,
                                    transfer_id = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    previous_hash <- NA_character_
    last_history <- DBI::dbGetQuery(con, "
      SELECT history_hash FROM portability_history
      WHERE request_id = ?
      ORDER BY history_id DESC LIMIT 1
    ", params = list(request_id))

    if (nrow(last_history) > 0) {
      previous_hash <- last_history$history_hash[1]
    }

    performed_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    hash_content <- paste(
      request_id,
      safe_int_portability(dataset_id),
      safe_int_portability(export_id),
      safe_int_portability(transfer_id),
      action,
      action_details,
      performed_by,
      performed_at,
      safe_scalar_portability(previous_hash),
      sep = "|"
    )
    history_hash <- digest::digest(hash_content, algo = "sha256")

    DBI::dbExecute(con, "
      INSERT INTO portability_history (
        request_id, dataset_id, export_id, transfer_id, action,
        action_details, performed_by, performed_at, history_hash,
        previous_history_hash
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      request_id,
      safe_int_portability(dataset_id),
      safe_int_portability(export_id),
      safe_int_portability(transfer_id),
      action,
      action_details,
      performed_by,
      performed_at,
      history_hash,
      safe_scalar_portability(previous_hash)
    ))

    list(success = TRUE)

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# DATASET MANAGEMENT
# ============================================================================

#' Add Portability Dataset
#'
#' Adds a dataset to be considered for portability export.
#'
#' @param request_id Request ID
#' @param table_name Table containing the data
#' @param data_category Category of data
#' @param data_source Source type from get_data_source_types()
#' @param added_by User adding the dataset
#' @param record_count Number of records
#' @param is_provided_by_subject Whether data was provided by subject
#' @param is_derived Whether data is derived/inferred
#'
#' @return List with success status and dataset details
#' @export
#'
#' @examples
#' \dontrun{
#' dataset <- add_portability_dataset(
#'   request_id = 1,
#'   table_name = "subjects",
#'   data_category = "CONTACT",
#'   data_source = "PROVIDED",
#'   added_by = "dpo"
#' )
#' }
add_portability_dataset <- function(request_id,
                                     table_name,
                                     data_category,
                                     data_source,
                                     added_by,
                                     record_count = 0,
                                     is_provided_by_subject = TRUE,
                                     is_derived = FALSE) {
  tryCatch({
    if (missing(request_id) || is.null(request_id)) {
      return(list(success = FALSE, error = "request_id is required"))
    }
    if (missing(table_name) || is.null(table_name) || table_name == "") {
      return(list(success = FALSE, error = "table_name is required"))
    }
    if (missing(data_category) || is.null(data_category) || data_category == "") {
      return(list(success = FALSE, error = "data_category is required"))
    }

    valid_sources <- names(get_data_source_types())
    if (!data_source %in% valid_sources) {
      return(list(
        success = FALSE,
        error = paste("Invalid data_source. Must be one of:",
                     paste(valid_sources, collapse = ", "))
      ))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    request <- DBI::dbGetQuery(con, "
      SELECT request_id, status FROM portability_requests
      WHERE request_id = ?
    ", params = list(request_id))

    if (nrow(request) == 0) {
      return(list(success = FALSE, error = "Request not found"))
    }

    is_eligible <- TRUE
    ineligibility_reason <- NULL

    if (data_source == "DERIVED" || is_derived) {
      is_eligible <- FALSE
      ineligibility_reason <- "Derived/inferred data not eligible per Article 20"
    } else if (data_source == "THIRD_PARTY" && !is_provided_by_subject) {
      is_eligible <- FALSE
      ineligibility_reason <- "Data not provided by data subject"
    }

    hash_content <- paste(
      request_id,
      table_name,
      data_category,
      data_source,
      record_count,
      is_provided_by_subject,
      is_derived,
      is_eligible,
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      sep = "|"
    )
    dataset_hash <- digest::digest(hash_content, algo = "sha256")

    DBI::dbExecute(con, "
      INSERT INTO portability_datasets (
        request_id, table_name, data_category, record_count, data_source,
        is_provided_by_subject, is_derived, is_eligible, ineligibility_reason,
        dataset_hash
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      request_id,
      table_name,
      data_category,
      record_count,
      data_source,
      as.integer(is_provided_by_subject),
      as.integer(is_derived),
      as.integer(is_eligible),
      safe_scalar_portability(ineligibility_reason),
      dataset_hash
    ))

    dataset_id <- DBI::dbGetQuery(con, "SELECT last_insert_rowid() as id")$id[1]

    log_portability_action(
      request_id = request_id,
      dataset_id = dataset_id,
      action = "DATASET_ADDED",
      action_details = paste("Dataset added:", table_name, "-", data_category,
                            "- Eligible:", is_eligible),
      performed_by = added_by
    )

    list(
      success = TRUE,
      dataset_id = dataset_id,
      is_eligible = is_eligible,
      ineligibility_reason = ineligibility_reason,
      message = if (is_eligible) {
        "Dataset added and eligible for portability"
      } else {
        paste("Dataset added but not eligible:", ineligibility_reason)
      }
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Review Portability Dataset
#'
#' Reviews a dataset for eligibility.
#'
#' @param dataset_id Dataset ID
#' @param is_eligible Whether dataset is eligible
#' @param reviewed_by User reviewing
#' @param ineligibility_reason Reason if not eligible
#'
#' @return List with success status
#' @export
#'
#' @examples
#' \dontrun{
#' review_portability_dataset(
#'   dataset_id = 1,
#'   is_eligible = TRUE,
#'   reviewed_by = "admin"
#' )
#' }
review_portability_dataset <- function(dataset_id,
                                        is_eligible,
                                        reviewed_by,
                                        ineligibility_reason = NULL) {
  tryCatch({
    if (missing(dataset_id) || is.null(dataset_id)) {
      return(list(success = FALSE, error = "dataset_id is required"))
    }
    if (!is_eligible && (is.null(ineligibility_reason) ||
                          ineligibility_reason == "")) {
      return(list(success = FALSE,
                  error = "ineligibility_reason required when not eligible"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    dataset <- DBI::dbGetQuery(con, "
      SELECT dataset_id, request_id, status FROM portability_datasets
      WHERE dataset_id = ?
    ", params = list(dataset_id))

    if (nrow(dataset) == 0) {
      return(list(success = FALSE, error = "Dataset not found"))
    }

    new_status <- if (is_eligible) "APPROVED" else "INELIGIBLE"

    DBI::dbExecute(con, "
      UPDATE portability_datasets
      SET is_eligible = ?, ineligibility_reason = ?, status = ?
      WHERE dataset_id = ?
    ", params = list(
      as.integer(is_eligible),
      safe_scalar_portability(ineligibility_reason),
      new_status,
      dataset_id
    ))

    log_portability_action(
      request_id = dataset$request_id[1],
      dataset_id = dataset_id,
      action = paste0("DATASET_", new_status),
      action_details = if (is_eligible) {
        "Dataset approved for export"
      } else {
        paste("Dataset marked ineligible:", ineligibility_reason)
      },
      performed_by = reviewed_by
    )

    list(
      success = TRUE,
      status = new_status,
      message = paste("Dataset", tolower(new_status))
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# EXPORT GENERATION
# ============================================================================

#' Generate Portability Export
#'
#' Generates an export file containing the subject's portable data.
#'
#' @param request_id Request ID
#' @param export_format Format from get_portability_export_formats()
#' @param generated_by User generating the export
#' @param output_dir Directory to save export file
#' @param encrypt Whether to encrypt the export (default FALSE)
#' @param expiry_days Days until export expires (default 30)
#'
#' @return List with success status and export details
#' @export
#'
#' @examples
#' \dontrun{
#' export <- generate_portability_export(
#'   request_id = 1,
#'   export_format = "JSON",
#'   generated_by = "dpo",
#'   output_dir = tempdir()
#' )
#' }
generate_portability_export <- function(request_id,
                                         export_format,
                                         generated_by,
                                         output_dir,
                                         encrypt = FALSE,
                                         expiry_days = 30) {
  tryCatch({
    if (missing(request_id) || is.null(request_id)) {
      return(list(success = FALSE, error = "request_id is required"))
    }
    if (missing(output_dir) || is.null(output_dir) || !dir.exists(output_dir)) {
      return(list(success = FALSE, error = "Valid output_dir is required"))
    }

    valid_formats <- names(get_portability_export_formats())
    if (!export_format %in% valid_formats) {
      return(list(
        success = FALSE,
        error = paste("Invalid export_format. Must be one of:",
                     paste(valid_formats, collapse = ", "))
      ))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    request <- DBI::dbGetQuery(con, "
      SELECT request_id, request_number, subject_id, subject_name, status
      FROM portability_requests
      WHERE request_id = ?
    ", params = list(request_id))

    if (nrow(request) == 0) {
      return(list(success = FALSE, error = "Request not found"))
    }

    datasets <- DBI::dbGetQuery(con, "
      SELECT dataset_id, table_name, data_category, record_count
      FROM portability_datasets
      WHERE request_id = ? AND is_eligible = 1 AND status = 'APPROVED'
    ", params = list(request_id))

    if (nrow(datasets) == 0) {
      return(list(success = FALSE, error = "No eligible datasets for export"))
    }

    timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
    file_ext <- tolower(export_format)
    file_name <- paste0("portability_", request$request_number[1], "_",
                       timestamp, ".", file_ext)
    file_path <- file.path(output_dir, file_name)

    export_data <- list(
      metadata = list(
        request_number = request$request_number[1],
        subject_name = request$subject_name[1],
        subject_id = request$subject_id[1],
        generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
        format = export_format,
        gdpr_article = "Article 20 - Right to Data Portability"
      ),
      datasets = list()
    )

    total_records <- 0
    for (i in seq_len(nrow(datasets))) {
      ds <- datasets[i, ]
      export_data$datasets[[ds$table_name]] <- list(
        category = ds$data_category,
        record_count = ds$record_count,
        data = paste("[Data from", ds$table_name, "- placeholder]")
      )
      total_records <- total_records + ds$record_count
    }

    if (export_format == "JSON") {
      json_content <- jsonlite::toJSON(export_data, pretty = TRUE,
                                        auto_unbox = TRUE)
      writeLines(json_content, file_path)
    } else if (export_format == "CSV") {
      csv_lines <- c(
        paste("# Portability Export:", request$request_number[1]),
        paste("# Generated:", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
        paste("# Subject:", request$subject_name[1]),
        "",
        "table_name,data_category,record_count",
        apply(datasets[, c("table_name", "data_category", "record_count")],
              1, paste, collapse = ",")
      )
      writeLines(csv_lines, file_path)
    } else if (export_format == "XML") {
      xml_content <- paste0(
        '<?xml version="1.0" encoding="UTF-8"?>\n',
        '<portability_export>\n',
        '  <metadata>\n',
        '    <request_number>', request$request_number[1], '</request_number>\n',
        '    <subject_name>', request$subject_name[1], '</subject_name>\n',
        '    <generated_at>', format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
        '</generated_at>\n',
        '  </metadata>\n',
        '  <datasets>\n',
        paste(sapply(seq_len(nrow(datasets)), function(i) {
          paste0('    <dataset>\n',
                 '      <table_name>', datasets$table_name[i], '</table_name>\n',
                 '      <category>', datasets$data_category[i], '</category>\n',
                 '      <record_count>', datasets$record_count[i],
                 '</record_count>\n',
                 '    </dataset>\n')
        }), collapse = ""),
        '  </datasets>\n',
        '</portability_export>\n'
      )
      writeLines(xml_content, file_path)
    } else {
      writeLines(paste("Portability Export:", request$request_number[1]),
                 file_path)
    }

    file_size <- file.info(file_path)$size
    checksum <- digest::digest(file = file_path, algo = "sha256")

    generated_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
    expires_at <- format(Sys.Date() + expiry_days, "%Y-%m-%d")

    hash_content <- paste(
      request_id,
      export_format,
      file_name,
      checksum,
      generated_at,
      sep = "|"
    )
    export_hash <- digest::digest(hash_content, algo = "sha256")

    datasets_list <- paste(datasets$table_name, collapse = ";")

    DBI::dbExecute(con, "
      INSERT INTO portability_exports (
        request_id, export_format, file_name, file_path, file_size_bytes,
        record_count, datasets_included, generated_at, generated_by,
        expires_at, is_encrypted, checksum, export_hash
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      request_id,
      export_format,
      file_name,
      file_path,
      file_size,
      total_records,
      datasets_list,
      generated_at,
      generated_by,
      expires_at,
      as.integer(encrypt),
      checksum,
      export_hash
    ))

    export_id <- DBI::dbGetQuery(con, "SELECT last_insert_rowid() as id")$id[1]

    DBI::dbExecute(con, "
      UPDATE portability_datasets
      SET included_in_export = 1
      WHERE request_id = ? AND is_eligible = 1 AND status = 'APPROVED'
    ", params = list(request_id))

    DBI::dbExecute(con, "
      UPDATE portability_requests
      SET status = 'EXPORTED'
      WHERE request_id = ?
    ", params = list(request_id))

    log_portability_action(
      request_id = request_id,
      export_id = export_id,
      action = "EXPORT_GENERATED",
      action_details = paste("Export generated:", file_name, "-",
                            total_records, "records -",
                            nrow(datasets), "datasets"),
      performed_by = generated_by
    )

    list(
      success = TRUE,
      export_id = export_id,
      file_name = file_name,
      file_path = file_path,
      file_size_bytes = file_size,
      record_count = total_records,
      dataset_count = nrow(datasets),
      checksum = checksum,
      expires_at = expires_at,
      message = "Export generated successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Record Export Download
#'
#' Records when an export file is downloaded.
#'
#' @param export_id Export ID
#' @param downloaded_by User downloading
#'
#' @return List with success status
#' @export
#'
#' @examples
#' \dontrun{
#' record_export_download(export_id = 1, downloaded_by = "subject")
#' }
record_export_download <- function(export_id, downloaded_by) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    export <- DBI::dbGetQuery(con, "
      SELECT export_id, request_id, download_count FROM portability_exports
      WHERE export_id = ?
    ", params = list(export_id))

    if (nrow(export) == 0) {
      return(list(success = FALSE, error = "Export not found"))
    }

    downloaded_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    DBI::dbExecute(con, "
      UPDATE portability_exports
      SET download_count = download_count + 1, last_downloaded_at = ?
      WHERE export_id = ?
    ", params = list(downloaded_at, export_id))

    log_portability_action(
      request_id = export$request_id[1],
      export_id = export_id,
      action = "EXPORT_DOWNLOADED",
      action_details = paste("Download #", export$download_count[1] + 1),
      performed_by = downloaded_by
    )

    list(
      success = TRUE,
      download_count = export$download_count[1] + 1,
      downloaded_at = downloaded_at,
      message = "Download recorded"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# TRANSFER MANAGEMENT
# ============================================================================

#' Initiate Controller Transfer
#'
#' Initiates a direct transfer to another controller per Article 20(2).
#'
#' @param request_id Request ID
#' @param export_id Export ID to transfer
#' @param target_controller Target controller name
#' @param target_contact Contact at target controller
#' @param transfer_method Method from get_transfer_methods()
#' @param initiated_by User initiating transfer
#'
#' @return List with success status and transfer details
#' @export
#'
#' @examples
#' \dontrun{
#' transfer <- initiate_controller_transfer(
#'   request_id = 1,
#'   export_id = 1,
#'   target_controller = "Other Company",
#'   target_contact = "dpo@other.com",
#'   transfer_method = "SECURE_EMAIL",
#'   initiated_by = "dpo"
#' )
#' }
initiate_controller_transfer <- function(request_id,
                                          export_id,
                                          target_controller,
                                          target_contact,
                                          transfer_method,
                                          initiated_by) {
  tryCatch({
    if (missing(request_id) || is.null(request_id)) {
      return(list(success = FALSE, error = "request_id is required"))
    }
    if (missing(target_controller) || is.null(target_controller) ||
        target_controller == "") {
      return(list(success = FALSE, error = "target_controller is required"))
    }
    if (missing(target_contact) || is.null(target_contact) ||
        target_contact == "") {
      return(list(success = FALSE, error = "target_contact is required"))
    }

    valid_methods <- names(get_transfer_methods())
    if (!transfer_method %in% valid_methods) {
      return(list(
        success = FALSE,
        error = paste("Invalid transfer_method. Must be one of:",
                     paste(valid_methods, collapse = ", "))
      ))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    request <- DBI::dbGetQuery(con, "
      SELECT request_id, request_type FROM portability_requests
      WHERE request_id = ?
    ", params = list(request_id))

    if (nrow(request) == 0) {
      return(list(success = FALSE, error = "Request not found"))
    }

    if (!request$request_type[1] %in% c("TRANSMIT", "BOTH")) {
      return(list(success = FALSE,
                  error = "Request type does not include transmission"))
    }

    initiated_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    hash_content <- paste(
      request_id,
      safe_int_portability(export_id),
      target_controller,
      target_contact,
      transfer_method,
      initiated_at,
      sep = "|"
    )
    transfer_hash <- digest::digest(hash_content, algo = "sha256")

    DBI::dbExecute(con, "
      INSERT INTO portability_transfers (
        request_id, export_id, target_controller, target_contact,
        transfer_method, transfer_status, initiated_at, initiated_by,
        transfer_hash
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      request_id,
      safe_int_portability(export_id),
      target_controller,
      target_contact,
      transfer_method,
      "INITIATED",
      initiated_at,
      initiated_by,
      transfer_hash
    ))

    transfer_id <- DBI::dbGetQuery(con, "SELECT last_insert_rowid() as id")$id[1]

    DBI::dbExecute(con, "
      UPDATE portability_requests
      SET status = 'TRANSFER_PENDING'
      WHERE request_id = ?
    ", params = list(request_id))

    log_portability_action(
      request_id = request_id,
      export_id = export_id,
      transfer_id = transfer_id,
      action = "TRANSFER_INITIATED",
      action_details = paste("Transfer initiated to:", target_controller,
                            "via", transfer_method),
      performed_by = initiated_by
    )

    list(
      success = TRUE,
      transfer_id = transfer_id,
      transfer_status = "INITIATED",
      message = "Transfer initiated successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Complete Controller Transfer
#'
#' Records completion of a controller-to-controller transfer.
#'
#' @param transfer_id Transfer ID
#' @param completed_by User recording completion
#' @param confirmation_reference Optional reference from receiving controller
#'
#' @return List with success status
#' @export
#'
#' @examples
#' \dontrun{
#' complete_controller_transfer(
#'   transfer_id = 1,
#'   completed_by = "dpo",
#'   confirmation_reference = "REF-12345"
#' )
#' }
complete_controller_transfer <- function(transfer_id,
                                          completed_by,
                                          confirmation_reference = NULL) {
  tryCatch({
    if (missing(transfer_id) || is.null(transfer_id)) {
      return(list(success = FALSE, error = "transfer_id is required"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    transfer <- DBI::dbGetQuery(con, "
      SELECT transfer_id, request_id, transfer_status FROM portability_transfers
      WHERE transfer_id = ?
    ", params = list(transfer_id))

    if (nrow(transfer) == 0) {
      return(list(success = FALSE, error = "Transfer not found"))
    }

    if (transfer$transfer_status[1] == "COMPLETED") {
      return(list(success = FALSE, error = "Transfer already completed"))
    }

    completed_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    DBI::dbExecute(con, "
      UPDATE portability_transfers
      SET transfer_status = 'COMPLETED', completed_at = ?,
          confirmation_received = 1, confirmation_date = ?,
          confirmation_reference = ?
      WHERE transfer_id = ?
    ", params = list(
      completed_at,
      completed_at,
      safe_scalar_portability(confirmation_reference),
      transfer_id
    ))

    DBI::dbExecute(con, "
      UPDATE portability_requests
      SET status = 'TRANSFER_COMPLETE'
      WHERE request_id = ?
    ", params = list(transfer$request_id[1]))

    log_portability_action(
      request_id = transfer$request_id[1],
      transfer_id = transfer_id,
      action = "TRANSFER_COMPLETED",
      action_details = paste("Transfer completed.",
                            if (!is.null(confirmation_reference))
                              paste("Reference:", confirmation_reference)
                            else ""),
      performed_by = completed_by
    )

    list(
      success = TRUE,
      completed_at = completed_at,
      message = "Transfer completed successfully"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Fail Controller Transfer
#'
#' Records failure of a controller-to-controller transfer.
#'
#' @param transfer_id Transfer ID
#' @param failure_reason Reason for failure
#' @param failed_by User recording failure
#'
#' @return List with success status
#' @export
#'
#' @examples
#' \dontrun{
#' fail_controller_transfer(
#'   transfer_id = 1,
#'   failure_reason = "Target controller API unavailable",
#'   failed_by = "dpo"
#' )
#' }
fail_controller_transfer <- function(transfer_id,
                                      failure_reason,
                                      failed_by) {
  tryCatch({
    if (missing(transfer_id) || is.null(transfer_id)) {
      return(list(success = FALSE, error = "transfer_id is required"))
    }
    if (missing(failure_reason) || is.null(failure_reason) ||
        failure_reason == "") {
      return(list(success = FALSE, error = "failure_reason is required"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    transfer <- DBI::dbGetQuery(con, "
      SELECT transfer_id, request_id, transfer_status FROM portability_transfers
      WHERE transfer_id = ?
    ", params = list(transfer_id))

    if (nrow(transfer) == 0) {
      return(list(success = FALSE, error = "Transfer not found"))
    }

    DBI::dbExecute(con, "
      UPDATE portability_transfers
      SET transfer_status = 'FAILED', failure_reason = ?
      WHERE transfer_id = ?
    ", params = list(failure_reason, transfer_id))

    log_portability_action(
      request_id = transfer$request_id[1],
      transfer_id = transfer_id,
      action = "TRANSFER_FAILED",
      action_details = paste("Transfer failed:", failure_reason),
      performed_by = failed_by
    )

    list(
      success = TRUE,
      message = "Transfer failure recorded"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# REQUEST COMPLETION
# ============================================================================

#' Complete Portability Request
#'
#' Completes a portability request after all deliverables are done.
#'
#' @param request_id Request ID
#' @param completed_by User completing the request
#'
#' @return List with success status
#' @export
#'
#' @examples
#' \dontrun{
#' complete_portability_request(
#'   request_id = 1,
#'   completed_by = "dpo"
#' )
#' }
complete_portability_request <- function(request_id, completed_by) {
  tryCatch({
    if (missing(request_id) || is.null(request_id)) {
      return(list(success = FALSE, error = "request_id is required"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    request <- DBI::dbGetQuery(con, "
      SELECT request_id, request_type, status FROM portability_requests
      WHERE request_id = ?
    ", params = list(request_id))

    if (nrow(request) == 0) {
      return(list(success = FALSE, error = "Request not found"))
    }

    exports <- DBI::dbGetQuery(con, "
      SELECT COUNT(*) as count FROM portability_exports
      WHERE request_id = ?
    ", params = list(request_id))

    if (exports$count[1] == 0) {
      return(list(success = FALSE, error = "No exports generated for request"))
    }

    if (request$request_type[1] %in% c("TRANSMIT", "BOTH")) {
      transfers <- DBI::dbGetQuery(con, "
        SELECT transfer_status FROM portability_transfers
        WHERE request_id = ?
      ", params = list(request_id))

      if (nrow(transfers) == 0) {
        return(list(success = FALSE,
                    error = "No transfer initiated for TRANSMIT request"))
      }

      if (!any(transfers$transfer_status == "COMPLETED")) {
        return(list(success = FALSE,
                    error = "No completed transfers for TRANSMIT request"))
      }
    }

    completed_date <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    DBI::dbExecute(con, "
      UPDATE portability_requests
      SET status = 'COMPLETED', completed_date = ?
      WHERE request_id = ?
    ", params = list(completed_date, request_id))

    log_portability_action(
      request_id = request_id,
      action = "REQUEST_COMPLETED",
      action_details = "Portability request completed successfully",
      performed_by = completed_by
    )

    list(
      success = TRUE,
      status = "COMPLETED",
      completed_date = completed_date,
      message = "Portability request completed"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Reject Portability Request
#'
#' Rejects a portability request with documented reason.
#'
#' @param request_id Request ID
#' @param rejection_reason Reason for rejection (minimum 20 characters)
#' @param rejected_by User rejecting the request
#' @param exception_ground Exception ground from get_portability_exceptions()
#'
#' @return List with success status
#' @export
#'
#' @examples
#' \dontrun{
#' reject_portability_request(
#'   request_id = 1,
#'   rejection_reason = "Processing not based on consent or contract",
#'   rejected_by = "dpo",
#'   exception_ground = "WRONG_LEGAL_BASIS"
#' )
#' }
reject_portability_request <- function(request_id,
                                        rejection_reason,
                                        rejected_by,
                                        exception_ground = NULL) {
  tryCatch({
    if (missing(request_id) || is.null(request_id)) {
      return(list(success = FALSE, error = "request_id is required"))
    }
    if (missing(rejection_reason) || is.null(rejection_reason) ||
        nchar(rejection_reason) < 20) {
      return(list(success = FALSE,
                  error = "rejection_reason must be at least 20 characters"))
    }

    if (!is.null(exception_ground)) {
      valid_exceptions <- names(get_portability_exceptions())
      if (!exception_ground %in% valid_exceptions) {
        return(list(
          success = FALSE,
          error = paste("Invalid exception_ground. Must be one of:",
                       paste(valid_exceptions, collapse = ", "))
        ))
      }
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    request <- DBI::dbGetQuery(con, "
      SELECT request_id, status FROM portability_requests
      WHERE request_id = ?
    ", params = list(request_id))

    if (nrow(request) == 0) {
      return(list(success = FALSE, error = "Request not found"))
    }

    reviewed_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    DBI::dbExecute(con, "
      UPDATE portability_requests
      SET status = 'REJECTED', reviewed_by = ?, reviewed_at = ?,
          rejection_reason = ?, exception_ground = ?, completed_date = ?
      WHERE request_id = ?
    ", params = list(
      rejected_by,
      reviewed_at,
      rejection_reason,
      safe_scalar_portability(exception_ground),
      reviewed_at,
      request_id
    ))

    log_portability_action(
      request_id = request_id,
      action = "REQUEST_REJECTED",
      action_details = paste("Request rejected:", rejection_reason,
                            if (!is.null(exception_ground))
                              paste("- Exception:", exception_ground) else ""),
      performed_by = rejected_by
    )

    list(
      success = TRUE,
      status = "REJECTED",
      completed_date = reviewed_at,
      message = "Portability request rejected"
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# RETRIEVAL FUNCTIONS
# ============================================================================

#' Get Portability Request
#'
#' Retrieves a portability request by ID or request number.
#'
#' @param request_id Optional request ID
#' @param request_number Optional request number
#'
#' @return List with success status and request data
#' @export
#'
#' @examples
#' \dontrun{
#' request <- get_portability_request(request_id = 1)
#' }
get_portability_request <- function(request_id = NULL, request_number = NULL) {
  tryCatch({
    if (is.null(request_id) && is.null(request_number)) {
      return(list(success = FALSE,
                  error = "Either request_id or request_number required"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    if (!is.null(request_id)) {
      request <- DBI::dbGetQuery(con, "
        SELECT * FROM portability_requests WHERE request_id = ?
      ", params = list(request_id))
    } else {
      request <- DBI::dbGetQuery(con, "
        SELECT * FROM portability_requests WHERE request_number = ?
      ", params = list(request_number))
    }

    if (nrow(request) == 0) {
      return(list(success = FALSE, error = "Request not found"))
    }

    list(
      success = TRUE,
      request = request
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Portability Datasets
#'
#' Retrieves datasets for a portability request.
#'
#' @param request_id Request ID
#' @param eligible_only Only return eligible datasets (default FALSE)
#'
#' @return List with success status and datasets
#' @export
#'
#' @examples
#' \dontrun{
#' datasets <- get_portability_datasets(request_id = 1, eligible_only = TRUE)
#' }
get_portability_datasets <- function(request_id, eligible_only = FALSE) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    if (eligible_only) {
      datasets <- DBI::dbGetQuery(con, "
        SELECT * FROM portability_datasets
        WHERE request_id = ? AND is_eligible = 1
      ", params = list(request_id))
    } else {
      datasets <- DBI::dbGetQuery(con, "
        SELECT * FROM portability_datasets WHERE request_id = ?
      ", params = list(request_id))
    }

    list(
      success = TRUE,
      datasets = datasets,
      count = nrow(datasets)
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Portability Exports
#'
#' Retrieves exports for a portability request.
#'
#' @param request_id Request ID
#'
#' @return List with success status and exports
#' @export
#'
#' @examples
#' \dontrun{
#' exports <- get_portability_exports(request_id = 1)
#' }
get_portability_exports <- function(request_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    exports <- DBI::dbGetQuery(con, "
      SELECT * FROM portability_exports WHERE request_id = ?
    ", params = list(request_id))

    list(
      success = TRUE,
      exports = exports,
      count = nrow(exports)
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Portability Transfers
#'
#' Retrieves transfers for a portability request.
#'
#' @param request_id Request ID
#'
#' @return List with success status and transfers
#' @export
#'
#' @examples
#' \dontrun{
#' transfers <- get_portability_transfers(request_id = 1)
#' }
get_portability_transfers <- function(request_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    transfers <- DBI::dbGetQuery(con, "
      SELECT * FROM portability_transfers WHERE request_id = ?
    ", params = list(request_id))

    list(
      success = TRUE,
      transfers = transfers,
      count = nrow(transfers)
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Portability History
#'
#' Retrieves audit history for a portability request.
#'
#' @param request_id Request ID
#'
#' @return List with success status and history
#' @export
#'
#' @examples
#' \dontrun{
#' history <- get_portability_history(request_id = 1)
#' }
get_portability_history <- function(request_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    history <- DBI::dbGetQuery(con, "
      SELECT * FROM portability_history
      WHERE request_id = ?
      ORDER BY history_id ASC
    ", params = list(request_id))

    list(
      success = TRUE,
      history = history,
      count = nrow(history)
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Pending Portability Requests
#'
#' Retrieves all pending portability requests.
#'
#' @return List with success status and requests
#' @export
#'
#' @examples
#' \dontrun{
#' pending <- get_pending_portability_requests()
#' }
get_pending_portability_requests <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    requests <- DBI::dbGetQuery(con, "
      SELECT * FROM portability_requests
      WHERE status NOT IN ('COMPLETED', 'REJECTED')
      ORDER BY due_date ASC
    ")

    list(
      success = TRUE,
      requests = requests,
      count = nrow(requests)
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# STATISTICS AND REPORTING
# ============================================================================

#' Get Portability Statistics
#'
#' Returns comprehensive statistics for portability requests.
#'
#' @return List with statistics
#' @export
#'
#' @examples
#' \dontrun{
#' stats <- get_portability_statistics()
#' }
get_portability_statistics <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    request_stats <- DBI::dbGetQuery(con, "
      SELECT
        COUNT(*) as total,
        SUM(CASE WHEN status = 'RECEIVED' THEN 1 ELSE 0 END) as received,
        SUM(CASE WHEN status = 'EXPORTED' THEN 1 ELSE 0 END) as exported,
        SUM(CASE WHEN status = 'TRANSFER_COMPLETE' THEN 1 ELSE 0 END)
          as transferred,
        SUM(CASE WHEN status = 'COMPLETED' THEN 1 ELSE 0 END) as completed,
        SUM(CASE WHEN status = 'REJECTED' THEN 1 ELSE 0 END) as rejected
      FROM portability_requests
    ")

    dataset_stats <- DBI::dbGetQuery(con, "
      SELECT
        COUNT(*) as total,
        SUM(is_eligible) as eligible,
        SUM(CASE WHEN is_eligible = 0 THEN 1 ELSE 0 END) as ineligible,
        SUM(included_in_export) as exported
      FROM portability_datasets
    ")

    export_stats <- DBI::dbGetQuery(con, "
      SELECT
        COUNT(*) as total,
        SUM(download_count) as total_downloads,
        export_format, COUNT(*) as count
      FROM portability_exports
      GROUP BY export_format
    ")

    transfer_stats <- DBI::dbGetQuery(con, "
      SELECT
        COUNT(*) as total,
        SUM(CASE WHEN transfer_status = 'COMPLETED' THEN 1 ELSE 0 END)
          as completed,
        SUM(CASE WHEN transfer_status = 'FAILED' THEN 1 ELSE 0 END) as failed,
        SUM(CASE WHEN transfer_status = 'INITIATED' THEN 1 ELSE 0 END)
          as pending
      FROM portability_transfers
    ")

    type_stats <- DBI::dbGetQuery(con, "
      SELECT request_type, COUNT(*) as count
      FROM portability_requests
      GROUP BY request_type
    ")

    list(
      success = TRUE,
      requests = as.list(request_stats),
      datasets = as.list(dataset_stats),
      exports = export_stats,
      transfers = as.list(transfer_stats),
      by_type = type_stats
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Generate Portability Report
#'
#' Generates a compliance report for portability requests.
#'
#' @param output_file Output file path
#' @param format Report format: "txt" or "json"
#' @param organization Organization name
#' @param prepared_by Name of person preparing report
#'
#' @return List with success status
#' @export
#'
#' @examples
#' \dontrun{
#' generate_portability_report(
#'   output_file = "portability_report.txt",
#'   format = "txt",
#'   organization = "Healthcare Org",
#'   prepared_by = "DPO"
#' )
#' }
generate_portability_report <- function(output_file,
                                         format = "txt",
                                         organization = "Organization",
                                         prepared_by = "DPO") {
  tryCatch({
    stats <- get_portability_statistics()
    if (!stats$success) {
      return(list(success = FALSE, error = "Failed to get statistics"))
    }

    if (format == "json") {
      report_data <- list(
        report_type = "GDPR Article 20 Right to Data Portability Report",
        organization = organization,
        prepared_by = prepared_by,
        generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
        statistics = stats
      )
      writeLines(
        jsonlite::toJSON(report_data, pretty = TRUE, auto_unbox = TRUE),
        output_file
      )
    } else {
      lines <- c(
        "===============================================================================",
        "       GDPR ARTICLE 20 - RIGHT TO DATA PORTABILITY REPORT",
        "===============================================================================",
        "",
        paste("Organization:", organization),
        paste("Prepared by:", prepared_by),
        paste("Generated:", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
        "",
        "-------------------------------------------------------------------------------",
        "REQUEST SUMMARY",
        "-------------------------------------------------------------------------------",
        "",
        paste("Total Requests:", stats$requests$total),
        paste("  - Received:", stats$requests$received),
        paste("  - Exported:", stats$requests$exported),
        paste("  - Transferred:", stats$requests$transferred),
        paste("  - Completed:", stats$requests$completed),
        paste("  - Rejected:", stats$requests$rejected),
        "",
        "-------------------------------------------------------------------------------",
        "DATASETS",
        "-------------------------------------------------------------------------------",
        "",
        paste("Total Datasets:", stats$datasets$total),
        paste("  - Eligible:", stats$datasets$eligible),
        paste("  - Ineligible:", stats$datasets$ineligible),
        paste("  - Exported:", stats$datasets$exported),
        "",
        "-------------------------------------------------------------------------------",
        "TRANSFERS",
        "-------------------------------------------------------------------------------",
        "",
        paste("Total Transfers:", stats$transfers$total),
        paste("  - Completed:", stats$transfers$completed),
        paste("  - Failed:", stats$transfers$failed),
        paste("  - Pending:", stats$transfers$pending),
        "",
        "-------------------------------------------------------------------------------",
        "REQUESTS BY TYPE",
        "-------------------------------------------------------------------------------",
        ""
      )

      if (nrow(stats$by_type) > 0) {
        for (i in seq_len(nrow(stats$by_type))) {
          lines <- c(lines, paste(" ",
            stats$by_type$request_type[i], ":",
            stats$by_type$count[i]))
        }
      }

      lines <- c(lines,
        "",
        "-------------------------------------------------------------------------------",
        "COMPLIANCE NOTES",
        "-------------------------------------------------------------------------------",
        "",
        "GDPR Article 20 - Right to Data Portability:",
        "  - Applies to data provided by data subject",
        "  - Processing must be based on consent or contract",
        "  - Processing must be by automated means",
        "  - Data in structured, commonly used, machine-readable format",
        "",
        "Article 20(2) - Direct Transmission:",
        "  - Controller should transmit directly where technically feasible",
        "  - Subject has right to request direct transmission",
        "",
        "Article 20(4) - Rights of Others:",
        "  - Right shall not adversely affect rights of others",
        "  - Derived/inferred data may be excluded",
        "",
        "Supported Export Formats:",
        "  - JSON (JavaScript Object Notation)",
        "  - CSV (Comma-Separated Values)",
        "  - XML (Extensible Markup Language)",
        "  - XLSX (Excel Spreadsheet)",
        "",
        "===============================================================================",
        ""
      )

      writeLines(lines, output_file)
    }

    list(
      success = TRUE,
      output_file = output_file,
      message = paste("Report generated:", output_file)
    )

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}
