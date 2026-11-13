# Audit records of reads (HIPAA 45 CFR 164.312(b); GDPR Art. 30/32).
#
# Writes were audited but disclosures were not: nothing recorded who
# opened the Data Explorer, previewed or downloaded an export, or
# generated a subject's case report. Each place the application shows
# or hands over participant-level records now writes one audit record
# per retrieval (not per render), naming the screen, the number of
# records, and the subject identifiers disclosed. Field values are not
# copied into the record: the audit trail would otherwise become a
# second, less protected copy of the data it describes.


.read_event_types <- c("SELECT", "EXPORT", "REPORT_GENERATED")


#' Record That Participant Records Were Read or Disclosed
#'
#' Writes one hash-chained audit record for one retrieval of
#' participant-level data: a screen loading records, an export
#' preview or download, or a generated report.
#'
#' @param conn A DBI connection or pool to the study database, or
#'   `NULL` (nothing is recorded, since nothing was read).
#' @param view Short name of the screen or function that read the
#'   records (for example `"data_explorer"`).
#' @param data The data frame that was disclosed, or `NULL`. Its
#'   `subject_id` column, when present, supplies the subject
#'   identifiers.
#' @param subject_ids Subject identifiers disclosed, when `data` has no
#'   `subject_id` column.
#' @param event_type `"SELECT"` (shown on screen), `"EXPORT"` (handed
#'   over as a file), or `"REPORT_GENERATED"`.
#' @param filters Optional named list of the selection criteria (form,
#'   date range), stored with the record.
#' @param user_id,ip_address,session_id Who read the records, and from
#'   where (see [session_audit_context()]).
#' @param table_name Table the records came from.
#' @return The new record's `audit_id`, invisibly; `NULL` when `conn`
#'   is `NULL`, when `data` has no rows and no subject was named
#'   (nothing was disclosed), or, outside the `regulated` profile, when the record
#'   could not be written (with a warning). Under `regulated` a record
#'   that cannot be written is an error, so a caller that logs before
#'   displaying shows nothing.
#' @export
log_record_read <- function(conn, view, data = NULL, subject_ids = NULL,
                            event_type = "SELECT", filters = NULL,
                            user_id = NULL, ip_address = NULL,
                            session_id = NULL, table_name = "data_entries") {
  if (is.null(conn)) return(invisible(NULL))
  if (!event_type %in% .read_event_types) {
    stop("event_type must be one of: ", paste(.read_event_types, collapse = ", "),
         call. = FALSE)
  }
  if (is.null(subject_ids) && is.data.frame(data) && "subject_id" %in% names(data)) {
    subject_ids <- data$subject_id
  }
  subject_ids <- sort(unique(as.character(subject_ids[!is.na(subject_ids)])))
  n_records <- if (is.data.frame(data)) nrow(data) else NA_integer_
  if (identical(n_records, 0L) && length(subject_ids) == 0) return(invisible(NULL))

  details <- as.character(jsonlite::toJSON(
    list(view = view, n_records = n_records,
         n_subjects = length(subject_ids), subject_ids = I(subject_ids),
         filters = filters),
    auto_unbox = TRUE, null = "null", na = "null", Date = "ISO8601"
  ))
  record_id <- if (length(subject_ids) == 1) subject_ids else NULL
  operation <- sprintf("%s: %s (%s record%s, %d subject%s)",
                       switch(event_type, SELECT = "Viewed", EXPORT = "Exported",
                              REPORT_GENERATED = "Report generated"),
                       view,
                       if (is.na(n_records)) "?" else n_records,
                       if (identical(n_records, 1L)) "" else "s",
                       length(subject_ids),
                       if (length(subject_ids) == 1) "" else "s")

  tryCatch({
    audit_id <- .with_db_transaction(conn, function(c) {
      .append_audit_record(c, event_type, table_name = table_name,
                           record_id = record_id, operation = operation,
                           details = details, user_id = user_id,
                           ip_address = ip_address, session_id = session_id)
    })
    invisible(audit_id)
  }, error = function(e) {
    if (get_security_profile() == "regulated") {
      stop("The read could not be recorded in the audit trail, so the records ",
           "are not shown: ", conditionMessage(e), call. = FALSE)
    }
    warning("Audit record of a read could not be written: ", conditionMessage(e),
            call. = FALSE)
    invisible(NULL)
  })
}


#' Who Has Read a Subject's Records
#'
#' Lists the audit records of reads, exports and reports (see
#' [log_record_read()]), optionally limited to those that disclosed one
#' subject's records or were made by one user. Supports an accounting
#' of disclosures and the review of access under HIPAA
#' 164.308(a)(1)(ii)(D).
#'
#' @param conn A DBI connection or pool to the study database.
#' @param subject_id Optional subject identifier.
#' @param user_id Optional user identifier.
#' @return A data frame with `timestamp`, `event_type`, `user_id`,
#'   `ip_address`, `view`, `n_records`, `n_subjects` and `operation`,
#'   most recent first.
#' @export
get_record_access_log <- function(conn, subject_id = NULL, user_id = NULL) {
  sql <- paste0(
    "SELECT timestamp, event_type, user_id, ip_address, operation, details ",
    "FROM audit_log WHERE event_type IN ('SELECT', 'EXPORT', 'REPORT_GENERATED') ",
    "AND details LIKE '{\"view\":%'"
  )
  params <- list()
  if (!is.null(user_id)) {
    sql <- paste(sql, "AND user_id = ?")
    params <- c(params, list(user_id))
  }
  sql <- paste(sql, "ORDER BY audit_id DESC")
  rows <- if (length(params)) DBI::dbGetQuery(conn, sql, params = params)
          else DBI::dbGetQuery(conn, sql)

  parsed <- lapply(rows$details, function(d) {
    tryCatch(jsonlite::fromJSON(d, simplifyVector = TRUE), error = function(e) list())
  })
  if (!is.null(subject_id)) {
    keep <- vapply(parsed, function(p) as.character(subject_id) %in% p$subject_ids,
                   logical(1))
    rows <- rows[keep, , drop = FALSE]
    parsed <- parsed[keep]
  }
  num <- function(p, f) {
    v <- p[[f]]
    if (is.null(v) || length(v) == 0) NA_real_ else as.numeric(v[1])
  }
  data.frame(
    timestamp = rows$timestamp,
    event_type = rows$event_type,
    user_id = rows$user_id,
    ip_address = rows$ip_address,
    view = vapply(parsed, function(p) as.character(p$view %||% NA_character_), character(1)),
    n_records = vapply(parsed, num, numeric(1), f = "n_records"),
    n_subjects = vapply(parsed, num, numeric(1), f = "n_subjects"),
    operation = rows$operation,
    stringsAsFactors = FALSE
  )
}
