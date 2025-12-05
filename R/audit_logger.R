#' Audit Logging System with Hash-Chaining
#'
#' Implements immutable, hash-chained audit logs for GDPR and 21 CFR Part 11 compliance.
#' Each log entry is cryptographically linked to the previous entry, making tampering detectable.

#' Initialize audit log
#'
#' Creates a reactive audit log storage with immutable properties.
#'
#' @return reactiveVal containing tibble of audit records
#' @export
#' @examples
#' \dontrun{
#' audit_log <- init_audit_log()
#' log_audit_event(audit_log, "user1", "LOGIN", "authentication", status = "success")
#' }
init_audit_log <- function() {
  reactiveVal(
    tibble::tibble(
      timestamp = Sys.time()[0],
      user_id = character(0),
      action = character(0),
      resource = character(0),
      old_value = character(0),
      new_value = character(0),
      status = character(0),
      error_message = character(0),
      record_hash = character(0),
      previous_hash = character(0)
    )
  )
}

#' Log an audit event
#'
#' Records an audit event with cryptographic chaining to previous record.
#'
#' @param audit_log reactiveVal object (from init_audit_log)
#' @param user_id Character - user performing action
#' @param action Character - action type (e.g., "LOGIN", "DATA_EXPORT", "FORM_SUBMISSION")
#' @param resource Character - what was affected (e.g., "authentication", "subject_123", "report_export")
#' @param old_value Character - previous value (for modifications)
#' @param new_value Character - new value (for modifications)
#' @param status Character - success/failure
#' @param error_message Character - error details if status == "failure"
#'
#' @return Invisibly returns the new record (including hash)
#' @export
#' @examples
#' \dontrun{
#' audit_log <- init_audit_log()
#' log_audit_event(
#'   audit_log,
#'   user_id = "john.doe",
#'   action = "LOGIN_ATTEMPT",
#'   resource = "authentication",
#'   status = "success"
#' )
#' }
log_audit_event <- function(
  audit_log,
  user_id,
  action,
  resource,
  old_value = "",
  new_value = "",
  status = "success",
  error_message = "") {

  current_log <- audit_log()

  # Get previous hash for chaining (empty string if first record)
  prev_hash <- if (nrow(current_log) > 0) {
    tail(current_log$record_hash, 1)
  } else {
    ""
  }

  # Create record with all identifying information
  record_data <- list(
    timestamp = Sys.time(),
    user_id = user_id,
    action = action,
    resource = resource,
    old_value = old_value,
    new_value = new_value,
    status = status,
    error_message = error_message
  )

  # Calculate hash: SHA256(previous_hash || timestamp || user_id || action || resource || status)
  # This chains each record to the previous one cryptographically
  hash_input <- paste0(
    prev_hash,
    "|",
    format(record_data$timestamp, "%Y-%m-%d %H:%M:%S"),
    "|",
    record_data$user_id,
    "|",
    record_data$action,
    "|",
    record_data$resource,
    "|",
    record_data$status,
    "|",
    record_data$old_value,
    "|",
    record_data$new_value
  )

  record_hash <- digest::digest(hash_input, algo = "sha256")

  # Create new record
  new_record <- tibble::tibble(
    timestamp = record_data$timestamp,
    user_id = record_data$user_id,
    action = record_data$action,
    resource = record_data$resource,
    old_value = record_data$old_value,
    new_value = record_data$new_value,
    status = record_data$status,
    error_message = record_data$error_message,
    record_hash = record_hash,
    previous_hash = prev_hash
  )

  # Append to log (immutable append pattern)
  updated_log <- dplyr::bind_rows(current_log, new_record)
  audit_log(updated_log)

  # Return new record invisibly (for verification)
  invisible(new_record)
}

#' Verify audit log integrity
#'
#' Validates that audit log hasn't been tampered with by checking hash chain.
#' Returns TRUE if all hashes are correctly chained, FALSE otherwise.
#'
#' @param audit_log reactiveVal or data.frame containing audit records
#'
#' @return Logical - TRUE if log integrity verified, FALSE if tampering detected
#' @export
verify_audit_log_integrity <- function(audit_log) {
  if (is.function(audit_log)) {
    log_data <- audit_log()
  } else {
    log_data <- audit_log
  }

  if (nrow(log_data) == 0) {
    return(TRUE)  # Empty log is valid
  }

  # Check first record has empty previous_hash
  if (log_data$previous_hash[1] != "") {
    return(FALSE)
  }

  # Check each record's hash matches its content
  for (i in seq_len(nrow(log_data))) {
    record <- log_data[i, ]

    # Recalculate expected hash
    prev_hash <- if (i == 1) "" else log_data$record_hash[i - 1]

    hash_input <- paste0(
      prev_hash,
      "|",
      format(record$timestamp, "%Y-%m-%d %H:%M:%S"),
      "|",
      record$user_id,
      "|",
      record$action,
      "|",
      record$resource,
      "|",
      record$status,
      "|",
      record$old_value,
      "|",
      record$new_value
    )

    expected_hash <- digest::digest(hash_input, algo = "sha256")

    # Verify this record's hash
    if (record$record_hash != expected_hash) {
      return(FALSE)
    }

    # Verify chain link
    if (i > 1 && record$previous_hash != log_data$record_hash[i - 1]) {
      return(FALSE)
    }
  }

  TRUE
}

#' Export audit log to file
#'
#' Saves audit log to CSV with hash verification included.
#'
#' @param audit_log reactiveVal or data.frame containing audit records
#' @param filepath Character - path to save audit log
#' @param include_verification Logical - include verification summary?
#'
#' @export
export_audit_log <- function(audit_log, filepath, include_verification = TRUE) {
  if (is.function(audit_log)) {
    log_data <- audit_log()
  } else {
    log_data <- audit_log
  }

  # Verify integrity before export
  is_valid <- verify_audit_log_integrity(log_data)

  # Add verification status to export
  export_data <- log_data %>%
    dplyr::mutate(
      export_time = Sys.time(),
      integrity_verified = is_valid
    )

  # Save to file
  write.csv(export_data, filepath, row.names = FALSE)

  # Log this export action (if audit_log is reactive)
  if (is.function(audit_log)) {
    log_audit_event(
      audit_log,
      user_id = "system",
      action = "AUDIT_EXPORT",
      resource = filepath,
      status = "success"
    )
  }

  invisible(is_valid)
}

#' Query audit log
#'
#' Filter audit log by various criteria.
#'
#' @param audit_log reactiveVal or data.frame containing audit records
#' @param user_id Character - filter by user (optional)
#' @param action Character - filter by action type (optional)
#' @param resource Character - filter by resource (optional)
#' @param start_date Date - start of date range (optional)
#' @param end_date Date - end of date range (optional)
#'
#' @return Filtered data.frame
#' @export
query_audit_log <- function(
  audit_log,
  user_id = NULL,
  action = NULL,
  resource = NULL,
  start_date = NULL,
  end_date = NULL) {

  if (is.function(audit_log)) {
    log_data <- audit_log()
  } else {
    log_data <- audit_log
  }

  result <- log_data

  if (!is.null(user_id)) {
    result <- result %>% dplyr::filter(user_id == !!user_id)
  }

  if (!is.null(action)) {
    result <- result %>% dplyr::filter(action == !!action)
  }

  if (!is.null(resource)) {
    result <- result %>% dplyr::filter(resource == !!resource)
  }

  if (!is.null(start_date)) {
    result <- result %>% dplyr::filter(timestamp >= !!start_date)
  }

  if (!is.null(end_date)) {
    result <- result %>% dplyr::filter(timestamp <= !!end_date)
  }

  result
}
