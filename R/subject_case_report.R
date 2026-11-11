# Subject Case Report (21 CFR Part 11 Sec 11.10(b))
#
# Sec 11.10(b) requires the ability to generate a complete and
# accurate copy of records in both human-readable and electronic
# form. Before this file, no single function assembled a complete
# case record for one subject: CRF data, its audit trail, and its
# electronic signatures each had their own retrieval function
# (get_data_entries(), get_audit_trail(), get_record_signatures()),
# but nothing joined them per subject. This was flagged, scoped, and
# deliberately deferred as a follow-up in the Part 11 remediation
# plan's Phase 7 (the two report functions that silently truncated
# at 50 rows were fixed directly in that phase; this feature was
# sized similarly to Phase 1 and treated as its own piece of work).
# generate_subject_case_report() closes that gap, following the same
# output_file/format("txt"/"json") convention and the same
# txt-report-is-never-truncated rule established by
# generate_signature_report() (R/electronic_signatures.R).


#' Generate a complete case report for one subject (Sec 11.10(b))
#'
#' Assembles every `data_entries` row for one subject, across every
#' form, in chronological order, together with that row's own audit
#' trail (`audit_log`, filtered to `table_name = "data_entries"` and
#' that row's `entry_id`) and its electronic signatures (including
#' invalidated ones, since a complete record must show a signature
#' was revoked, not omit it). Field values are rendered under their
#' form's human-readable labels (from `designer_fields.field_label`
#' via [get_crf_field_metadata()]) rather than raw field codes, the
#' same way [flatten_crf_entries_for_export()] already does for a
#' single form.
#'
#' @param subject_id The subject identifier
#'   (`data_entries.subject_id`).
#' @param output_file Path to write the report to.
#' @param format `"txt"` (human-readable; default) or `"json"`
#'   (machine-readable, complete nested structure). Neither format
#'   truncates: every entry, every audit event, and every signature
#'   for the subject is included.
#' @param organization,prepared_by Report header fields, matching
#'   [generate_signature_report()]'s convention.
#' @param db_path Character: database path (optional).
#' @return List with `success`; on success also `output_file` and
#'   `entry_count`; on failure, `error`.
#'
#' @examples
#' \dontrun{
#' generate_subject_case_report(
#'   subject_id = "SITE01-003",
#'   output_file = "SITE01-003_case_report.txt"
#' )
#' }
#' @export
generate_subject_case_report <- function(subject_id,
                                          output_file,
                                          format = "txt",
                                          organization = "Clinical Research Organization",
                                          prepared_by = "Compliance Officer",
                                          db_path = NULL) {
  if (is.null(subject_id) || !nzchar(trimws(subject_id %||% ""))) {
    return(list(success = FALSE, error = "subject_id is required"))
  }

  tryCatch({
    conn <- connect_encrypted_db(db_path = db_path)
    on.exit(DBI::dbDisconnect(conn), add = TRUE)

    entries <- get_data_entries(conn, subject_id = subject_id)
    # Chronological, not get_data_entries()'s default most-recent-first:
    # a case report reads as a history, oldest visit to most recent.
    if (nrow(entries) > 0) {
      entries <- entries[order(entries$created_date), , drop = FALSE]
    }

    forms <- get_active_crf_forms(conn)
    field_label_cache <- list()
    field_labels_for <- function(form_name) {
      key <- tolower(form_name %||% "")
      if (!is.null(field_label_cache[[key]])) {
        return(field_label_cache[[key]])
      }
      crf_row <- forms[tolower(forms$crf_code) == key, , drop = FALSE]
      labels <- if (nrow(crf_row) == 1) {
        meta <- get_crf_field_metadata(conn, crf_row$crf_id[1])
        stats::setNames(
          vapply(meta, function(m) m$label %||% NA_character_, character(1)),
          names(meta)
        )
      } else {
        character(0)
      }
      field_label_cache[[key]] <<- labels
      labels
    }

    case_entries <- lapply(seq_len(nrow(entries)), function(i) {
      row <- entries[i, ]
      labels <- field_labels_for(row$form_name)

      field_rows <- lapply(names(row$fields[[1]]), function(fc) {
        v <- row$fields[[1]][[fc]]
        value <- if (is.null(v) || length(v) == 0) {
          ""
        } else if (length(v) > 1) {
          paste(as.character(v), collapse = ", ")
        } else if (is.na(v)) {
          ""
        } else {
          as.character(v)
        }
        list(
          field_code = fc,
          field_label = unname(labels[fc]) %||% fc,
          value = value
        )
      })

      audit_rows <- get_audit_trail(
        filters = list(table_name = "data_entries", record_id = row$entry_id),
        db_path = db_path
      )
      signatures <- get_record_signatures(
        table_name = "data_entries", record_id = row$entry_id,
        include_invalid = TRUE, db_path = db_path
      )

      list(
        entry_id = row$entry_id,
        form_name = row$form_name,
        visit_label = row$visit_label %||% NA_character_,
        visit_date = row$visit_date %||% NA_character_,
        created_date = row$created_date,
        created_by = row$created_by,
        fields = field_rows,
        audit_trail = audit_rows,
        signatures = signatures
      )
    })

    if (identical(format, "json")) {
      report_data <- list(
        report_type = "Subject Case Report",
        organization = organization,
        generated_at = as.character(Sys.time()),
        prepared_by = prepared_by,
        subject_id = subject_id,
        entry_count = length(case_entries),
        entries = case_entries
      )
      jsonlite::write_json(report_data, output_file, pretty = TRUE,
                           auto_unbox = TRUE, na = "null")
    } else {
      lines <- c(
        "===============================================================================",
        "                         SUBJECT CASE REPORT",
        "                      21 CFR Part 11 Sec 11.10(b)",
        "===============================================================================",
        "",
        paste("Organization:", organization),
        paste("Generated:", Sys.time()),
        paste("Prepared By:", prepared_by),
        paste("Subject ID:", subject_id),
        paste("Total Entries:", length(case_entries)),
        ""
      )

      if (length(case_entries) == 0) {
        lines <- c(lines, "No data_entries records found for this subject.")
      }

      for (ce in case_entries) {
        lines <- c(lines,
          "-------------------------------------------------------------------------------",
          sprintf("ENTRY: %s  (form: %s)", ce$entry_id, ce$form_name),
          "-------------------------------------------------------------------------------",
          if (!is.na(ce$visit_label)) paste("  Visit:", ce$visit_label) else NULL,
          if (!is.na(ce$visit_date)) paste("  Visit Date:", ce$visit_date) else NULL,
          paste("  Created:", ce$created_date, "by", ce$created_by),
          "",
          "  Fields:"
        )
        if (length(ce$fields) == 0) {
          lines <- c(lines, "    (no fields recorded)")
        } else {
          for (fr in ce$fields) {
            lines <- c(lines, sprintf("    %-30s %s", paste0(fr$field_label, ":"), fr$value))
          }
        }

        lines <- c(lines, "", "  Electronic Signatures:")
        if (nrow(ce$signatures) == 0) {
          lines <- c(lines, "    (none)")
        } else {
          for (i in seq_len(nrow(ce$signatures))) {
            s <- ce$signatures[i, ]
            status <- if (isTRUE(s$is_valid == 1)) "VALID" else "INVALIDATED"
            lines <- c(lines, sprintf("    [%s] %s signed by %s (%s) at %s",
                                      status, s$signature_meaning,
                                      s$signer_full_name, s$signer_user_id,
                                      s$signed_at))
          }
        }

        lines <- c(lines, "", "  Audit Trail:")
        if (nrow(ce$audit_trail) == 0) {
          lines <- c(lines, "    (no audit events recorded)")
        } else {
          # Complete, not a bounded preview -- same Sec 11.10(b) rule
          # applied to generate_signature_report()'s txt output and
          # the two truncation fixes in electronic_signatures.R/
          # data_correction.R.
          for (i in seq_len(nrow(ce$audit_trail))) {
            a <- ce$audit_trail[i, ]
            lines <- c(lines, sprintf("    %s  %-10s  %s  %s",
                                      a$timestamp, a$event_type,
                                      a$user_id %||% "",
                                      a$operation %||% ""))
          }
        }
        lines <- c(lines, "")
      }

      writeLines(lines, output_file)
    }

    list(success = TRUE, output_file = output_file,
         entry_count = length(case_entries))

  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}
