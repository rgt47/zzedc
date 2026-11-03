#' Real-data backing for the Reports, Data Explorer, and Export tabs
#'
#' `inst/app/report1.R`/`report2.R`/`report3.R`/`report4.R`/`data.R`/
#' `export.R` previously rendered unrelated placeholder content
#' (a random-number histogram, hardcoded "87% complete" stat cards,
#' a synthetic 50-row sample table, and export options such as
#' "Patient Demographics"/"Adverse Events" that do not exist in this
#' application's schema). These functions read the real
#' `data_entries`/`crf_definitions`/`designer_fields`/
#' `designer_field_options` tables so those tabs can show and export
#' what has actually been entered through the EDC tab.
#'
#' @name edc_reports
#' @keywords internal
NULL


#' Parse one `data_entries` row's `data_json` into a named list
#' @keywords internal
.parse_entry_fields <- function(x) {
  if (is.na(x) || !nzchar(x)) return(list())
  tryCatch(
    jsonlite::fromJSON(x, simplifyVector = TRUE),
    error = function(e) list()
  )
}


#' All data_entries rows, with data_json parsed
#'
#' @param conn A DBI connection (or pool object).
#' @param crf_code Optional: restrict to one form (matched
#'   case-insensitively against `data_entries.form_name`).
#' @param start_date,end_date Optional `Date`/character bounds
#'   (inclusive) on `created_date`.
#' @return A data frame with columns `entry_id`, `subject_id`,
#'   `form_name`, `created_date`, `created_by`, plus a list-column
#'   `fields` (one named list per row, the parsed `data_json`).
#'   Zero rows (with the right columns) when nothing matches,
#'   including when `data_entries` doesn't exist yet (it is only
#'   created lazily, on first submission via
#'   [ensure_data_entries_table()] -- a freshly initialized or
#'   freshly `setup_zzedc_from_gsheets()`-rebuilt database has no
#'   entries, and so no reason yet to have this table). Every
#'   caller of this function (Reports, Data Explorer, the
#'   tracking-ID prefill, the personal-statement draft) runs at
#'   ordinary session start, before anyone has necessarily
#'   submitted anything, so treating "table absent" as "zero
#'   entries" here -- rather than letting `dbGetQuery()` error --
#'   is the one fix point that protects all of them at once.
#' @keywords internal
get_data_entries <- function(conn, crf_code = NULL,
                              start_date = NULL, end_date = NULL) {
  empty <- data.frame(
    entry_id = character(0), subject_id = character(0),
    form_name = character(0), created_date = character(0),
    created_by = character(0), stringsAsFactors = FALSE
  )
  empty$fields <- list()
  if (!DBI::dbExistsTable(conn, "data_entries")) {
    return(empty)
  }

  clauses <- character(0)
  params <- list()
  if (!is.null(crf_code)) {
    clauses <- c(clauses, "LOWER(form_name) = LOWER(?)")
    params <- c(params, list(crf_code))
  }
  if (!is.null(start_date)) {
    clauses <- c(clauses, "DATE(created_date) >= DATE(?)")
    params <- c(params, list(as.character(start_date)))
  }
  if (!is.null(end_date)) {
    clauses <- c(clauses, "DATE(created_date) <= DATE(?)")
    params <- c(params, list(as.character(end_date)))
  }
  where <- if (length(clauses) > 0) {
    paste("WHERE", paste(clauses, collapse = " AND "))
  } else {
    ""
  }

  sql <- paste(
    "SELECT entry_id, subject_id, form_name, created_date, created_by,",
    "       data_json",
    "FROM data_entries", where,
    "ORDER BY created_date DESC"
  )
  rows <- if (length(params) > 0) {
    DBI::dbGetQuery(conn, sql, params = params)
  } else {
    DBI::dbGetQuery(conn, sql)
  }
  rows$fields <- lapply(rows$data_json, .parse_entry_fields)
  rows$data_json <- NULL
  rows
}


#' Every `tracking_id` currently recorded for one form
#'
#' @param conn A DBI connection (or pool object).
#' @param crf_code The form's `crf_code` (matched case-insensitively).
#' @return A character vector, one element per entry that has a
#'   non-blank `tracking_id`; `character(0)` if there are none.
#' @keywords internal
.existing_tracking_ids <- function(conn, crf_code) {
  entries <- get_data_entries(conn, crf_code = crf_code)
  ids <- vapply(entries$fields, function(f) {
    v <- f$tracking_id
    if (is.null(v) || length(v) == 0) "" else as.character(v)[1]
  }, character(1))
  ids[nzchar(ids)]
}


#' Next unused manuscripts tracking ID for a given year
#'
#' Scans existing `manuscripts` entries for IDs matching the form's
#' `PUB-<year>-<n>` convention (see
#' [tracking_id_prefix_for_form()]) and returns one past the
#' highest `n` seen for `year`, zero-padded to 3 digits to match the
#' IDs already in use (e.g. `"PUB-2026-004"`). IDs for other years,
#' or that do not match the pattern at all, are ignored. Returns
#' `"PUB-<year>-001"` when there are none yet for that year.
#'
#' @param conn A DBI connection (or pool object).
#' @param year A 4-digit year string or number; defaults to the
#'   current year.
#' @return A single tracking ID string.
#' @keywords internal
next_manuscript_tracking_id <- function(conn, year = NULL) {
  year <- as.character(year %||% format(Sys.Date(), "%Y"))
  ids <- .existing_tracking_ids(conn, "manuscripts")
  pattern <- sprintf("^PUB-%s-([0-9]+)$", year)
  matches <- ids[grepl(pattern, ids)]
  n <- if (length(matches) == 0) {
    0L
  } else {
    max(as.integer(sub(pattern, "\\1", matches)))
  }
  sprintf("PUB-%s-%03d", year, n + 1L)
}


#' Whether a tracking ID is already used by another entry on its form
#'
#' Only enforced for forms with a tracking-ID convention (currently
#' just `manuscripts`, see [tracking_id_prefix_for_form()]); always
#' `FALSE` for any other form, so this is a safe no-op to call from
#' a generic submit/live-flag path.
#'
#' @param conn A DBI connection (or pool object).
#' @param crf_code The form's `crf_code`.
#' @param value The `tracking_id` value to check.
#' @return `TRUE` if `value` already appears on another entry of
#'   this form, `FALSE` otherwise (including a blank `value`).
#' @keywords internal
tracking_id_already_used <- function(conn, crf_code, value) {
  if (is.null(tracking_id_prefix_for_form(crf_code)) ||
        is.null(value) || !nzchar(trimws(value))) {
    return(FALSE)
  }
  value %in% .existing_tracking_ids(conn, crf_code)
}


#' Entry counts per form, joined to the form's display name
#'
#' @param conn A DBI connection (or pool object).
#' @return A data frame with one row per form that has at least one
#'   `crf_definitions` entry: `crf_code`, `crf_name`, `n_entries`,
#'   `first_entry`, `last_entry` (the last two `NA` when
#'   `n_entries` is 0).
#' @keywords internal
summarize_entries_by_form <- function(conn) {
  forms <- get_active_crf_forms(conn)
  counts <- DBI::dbGetQuery(
    conn,
    paste(
      "SELECT LOWER(form_name) AS form_code, COUNT(*) AS n_entries,",
      "       MIN(created_date) AS first_entry,",
      "       MAX(created_date) AS last_entry",
      "FROM data_entries GROUP BY LOWER(form_name)"
    )
  )
  forms$.form_code <- tolower(forms$crf_code)
  merged <- merge(
    forms, counts,
    by.x = ".form_code", by.y = "form_code", all.x = TRUE
  )
  merged$n_entries[is.na(merged$n_entries)] <- 0L
  merged[order(merged$crf_id),
         c("crf_code", "crf_name", "n_entries", "first_entry", "last_entry")]
}


#' Validate every stored entry against its form's field metadata
#'
#' Reuses [validate_crf_submission()] (already exercised live by the
#' EDC tab's own submit handler) against the field data as actually
#' stored, rather than re-implementing a separate quality check.
#'
#' @param conn A DBI connection (or pool object).
#' @return `list(total=, n_valid=, n_required_missing=,
#'   n_invalid_choice=, n_unknown_form=, flagged=)`. `total` counts
#'   only entries whose form matches a current `crf_definitions` row
#'   (so `total == n_valid + ` the number of entries with at least
#'   one flagged field); `n_unknown_form` counts entries excluded
#'   from that (e.g. leftovers from a form that has since been
#'   removed or renamed) separately, so they do not simply vanish
#'   from the summary. `flagged` is a data frame with columns
#'   `entry_id`, `subject_id`, `form_name`, `kind`, `message` (one
#'   row per flagged field, not per entry).
#' @keywords internal
compute_data_quality_summary <- function(conn) {
  entries <- get_data_entries(conn)
  forms <- get_active_crf_forms(conn)

  metadata_cache <- new.env(parent = emptyenv())
  get_metadata <- function(form_name) {
    key <- tolower(form_name)
    if (!exists(key, envir = metadata_cache, inherits = FALSE)) {
      crf_row <- forms[tolower(forms$crf_code) == key, , drop = FALSE]
      meta <- if (nrow(crf_row) == 1) {
        get_crf_field_metadata(conn, crf_row$crf_id[1])
      } else {
        list()
      }
      assign(key, meta, envir = metadata_cache)
    }
    get(key, envir = metadata_cache, inherits = FALSE)
  }

  n_valid <- 0L
  n_required_missing <- 0L
  n_invalid_choice <- 0L
  n_unknown_form <- 0L
  flagged <- list()

  for (i in seq_len(nrow(entries))) {
    row <- entries[i, ]
    meta <- get_metadata(row$form_name)
    if (length(meta) == 0) {
      # An entry whose form_name does not match any current
      # crf_definitions row -- e.g. a leftover from the demo
      # scaffold (edc_visit_form) predating this study's real CRF
      # import. Excluded from both n_valid and the flagged count
      # below (there is no metadata to validate it against), and
      # also excluded from `total` so the three counts reconcile;
      # tracked separately as n_unknown_form instead of silently
      # vanishing from the summary.
      n_unknown_form <- n_unknown_form + 1L
      next
    }
    check <- validate_crf_submission(row$fields[[1]], meta)
    if (check$valid) {
      n_valid <- n_valid + 1L
      next
    }
    for (f in names(check$errors)) {
      err <- check$errors[[f]]
      if (err$kind == "required") n_required_missing <- n_required_missing + 1L
      if (err$kind == "invalid_choice") n_invalid_choice <- n_invalid_choice + 1L
      flagged[[length(flagged) + 1]] <- data.frame(
        entry_id = row$entry_id, subject_id = row$subject_id,
        form_name = row$form_name, kind = err$kind, message = err$message,
        stringsAsFactors = FALSE
      )
    }
  }

  list(
    total = nrow(entries) - n_unknown_form,
    n_valid = n_valid,
    n_required_missing = n_required_missing,
    n_invalid_choice = n_invalid_choice,
    n_unknown_form = n_unknown_form,
    flagged = if (length(flagged) > 0) do.call(rbind, flagged) else {
      data.frame(entry_id = character(), subject_id = character(),
                 form_name = character(), kind = character(),
                 message = character(), stringsAsFactors = FALSE)
    }
  )
}


#' Counts of stored values for every choice-type field with options
#'
#' @param conn A DBI connection (or pool object).
#' @return A data frame with columns `crf_code`, `field_code`,
#'   `field_label`, `option_label`, `n`, one row per option that has
#'   at least one matching stored value. Zero rows if no choice
#'   fields have both options and data.
#' @keywords internal
summarize_choice_field_values <- function(conn) {
  entries <- get_data_entries(conn)
  forms <- get_active_crf_forms(conn)
  out <- list()

  for (i in seq_len(nrow(forms))) {
    crf_row <- forms[i, ]
    meta <- get_crf_field_metadata(conn, crf_row$crf_id)
    choice_fields <- Filter(function(m) !is.null(m$choices), meta)
    if (length(choice_fields) == 0) next

    form_entries <- entries[tolower(entries$form_name) == tolower(crf_row$crf_code), ]
    if (nrow(form_entries) == 0) next

    for (field_code in names(choice_fields)) {
      m <- choice_fields[[field_code]]
      values <- vapply(form_entries$fields, function(f) {
        v <- f[[field_code]]
        if (is.null(v) || is.na(v)) NA_character_ else as.character(v)
      }, character(1))
      values <- values[!is.na(values) & nzchar(values)]
      if (length(values) == 0) next

      tab <- table(values)
      labels <- names(m$choices)[match(names(tab), m$choices)]
      labels[is.na(labels)] <- names(tab)[is.na(labels)]
      out[[length(out) + 1]] <- data.frame(
        crf_code = crf_row$crf_code, field_code = field_code,
        field_label = m$label, option_label = labels,
        n = as.integer(tab), stringsAsFactors = FALSE
      )
    }
  }

  if (length(out) == 0) {
    return(data.frame(crf_code = character(), field_code = character(),
                       field_label = character(), option_label = character(),
                       n = integer(), stringsAsFactors = FALSE))
  }
  do.call(rbind, out)
}


#' Flatten one form's entries into an export-ready data frame
#'
#' @param conn A DBI connection (or pool object).
#' @param crf_code The form to export.
#' @param start_date,end_date Optional date bounds, passed through
#'   to [get_data_entries()].
#' @return A data frame with `subject_id`, `created_date`,
#'   `created_by`, then one column per field defined on the form (in
#'   the form's own field order), each row one entry. Field columns
#'   are character; a field never entered for a given row is `NA`.
#'   Zero rows (with only the fixed columns) if the form has no
#'   entries in range.
#' @keywords internal
flatten_crf_entries_for_export <- function(conn, crf_code,
                                            start_date = NULL,
                                            end_date = NULL) {
  forms <- get_active_crf_forms(conn)
  crf_row <- forms[tolower(forms$crf_code) == tolower(crf_code), , drop = FALSE]
  if (nrow(crf_row) != 1) {
    stop("Unknown form code: ", crf_code)
  }
  meta <- get_crf_field_metadata(conn, crf_row$crf_id[1])
  entries <- get_data_entries(conn, crf_code = crf_code,
                               start_date = start_date, end_date = end_date)

  field_codes <- names(meta)
  base <- data.frame(
    subject_id = entries$subject_id,
    created_date = entries$created_date,
    created_by = entries$created_by,
    stringsAsFactors = FALSE
  )
  if (nrow(entries) == 0 || length(field_codes) == 0) {
    for (fc in field_codes) base[[fc]] <- character(0)
    return(base)
  }
  for (fc in field_codes) {
    base[[fc]] <- vapply(entries$fields, function(f) {
      v <- f[[fc]]
      if (is.null(v)) NA_character_ else as.character(v)
    }, character(1))
  }
  base
}


#' All data_entries flattened into one generic table for browsing
#'
#' Different forms have different fields, so there is no single set
#' of columns that fits every entry; each entry's field values are
#' instead collapsed into one readable `fields` text column
#' (`code=value; code=value; ...`), alongside the fixed columns every
#' entry has regardless of form. Used by the Data Explorer tab's
#' "ZZedc Tracker Data" source, where a generic cross-domain table is
#' more useful than a form-specific export.
#'
#' A blank field's stored value is not always a length-1 `NA`.
#' `NA_character_` round-trips through `jsonlite::toJSON()`/
#' `fromJSON()` as JSON `null` -> R `NULL`. A `dateInput()` cleared
#' to empty in the EDC tab round-trips as JSON `[]` -> R `list()`
#' (zero-length), not `NA` -- reproduced directly against the live
#' promotion-tracker deployment. `as.character()` on either is
#' `character(0)`, not a length-1 string, so mapping every field
#' through plain `as.character()` crashes as soon as any entry has
#' a blank optional field -- which most real entries do. A
#' multi-select field's value can likewise be longer than length 1;
#' that case is joined rather than dropped.
#'
#' @param conn A DBI connection (or pool object).
#' @return A data frame with `entry_id`, `subject_id`, `form_name`,
#'   `created_date`, `created_by`, `fields`.
#' @keywords internal
flatten_all_entries_for_explorer <- function(conn) {
  entries <- get_data_entries(conn)
  entries$fields <- vapply(entries$fields, function(f) {
    if (length(f) == 0) return("")
    values <- vapply(f, function(v) {
      if (length(v) == 0) return("")
      if (length(v) > 1) return(paste(as.character(v), collapse = ", "))
      if (is.na(v)) return("")
      as.character(v)
    }, character(1))
    paste(sprintf("%s=%s", names(f), values), collapse = "; ")
  }, character(1))
  entries
}


#' Compose a draft personal-statement-style summary from tracked data
#'
#' Produces HTML prose, organized the way a promotion self-assessment
#' typically is (research/publications, teaching, service), built
#' entirely from counts and breakdowns of what is actually in
#' `data_entries` -- it does not invent accomplishments, funding
#' amounts, or citation counts that are not tracked by this
#' application. Intended as a data-grounded first draft to revise,
#' not a finished document: a faculty member's actual self-assessment
#' also covers leadership roles, funding, and narrative context this
#' application has no way to know about.
#'
#' @param conn A DBI connection (or pool object).
#' @return A single HTML string (via [shiny::HTML()] at the call
#'   site, this function returns a plain character string of HTML).
#' @keywords internal
generate_personal_statement_draft <- function(conn) {
  entries <- get_data_entries(conn)
  by_form <- function(code) entries[tolower(entries$form_name) == code, ]

  esc <- function(x) {
    x <- gsub("&", "&amp;", x, fixed = TRUE)
    x <- gsub("<", "&lt;", x, fixed = TRUE)
    gsub(">", "&gt;", x, fixed = TRUE)
  }

  manuscripts <- by_form("manuscripts")
  courses <- by_form("courses")
  mentoring <- by_form("mentoring")
  grant_reviews <- by_form("grant_reviews")
  committees <- by_form("committees")
  journal_reviews <- by_form("journal_reviews")
  dsmb <- by_form("dsmb")

  field_values <- function(df, code) {
    if (nrow(df) == 0) return(character(0))
    vals <- vapply(df$fields, function(f) {
      v <- f[[code]]
      if (is.null(v) || is.na(v)) NA_character_ else as.character(v)
    }, character(1))
    vals[!is.na(vals) & nzchar(vals)]
  }

  status_counts <- function(df, code) {
    vals <- field_values(df, code)
    if (length(vals) == 0) return("none logged yet")
    tab <- sort(table(vals), decreasing = TRUE)
    paste(sprintf("%d %s", as.integer(tab), esc(names(tab))), collapse = ", ")
  }

  html <- character(0)
  html <- c(html, "<h3>Research and Scholarly Activities</h3>")
  html <- c(html, sprintf(
    "<p>Over the period covered by this tracker, %d manuscript%s %s been logged. Status breakdown: %s.</p>",
    nrow(manuscripts), if (nrow(manuscripts) == 1) "" else "s",
    if (nrow(manuscripts) == 1) "has" else "have",
    status_counts(manuscripts, "status")
  ))

  html <- c(html, "<h3>Teaching Activities</h3>")
  html <- c(html, sprintf(
    "<p>%d course offering%s %s been logged, totaling %s contact hours across %s students taught (sums of the Contact Hours and Student Count fields where entered).</p>",
    nrow(courses), if (nrow(courses) == 1) "" else "s",
    if (nrow(courses) == 1) "has" else "have",
    {
      hrs <- suppressWarnings(as.numeric(field_values(courses, "contact_hours")))
      if (length(hrs) == 0 || all(is.na(hrs))) "0" else format(sum(hrs, na.rm = TRUE))
    },
    {
      cnt <- suppressWarnings(as.numeric(field_values(courses, "student_count")))
      if (length(cnt) == 0 || all(is.na(cnt))) "0" else format(sum(cnt, na.rm = TRUE))
    }
  ))
  html <- c(html, sprintf(
    "<p>%d mentoring relationship%s %s been logged.</p>",
    nrow(mentoring), if (nrow(mentoring) == 1) "" else "s",
    if (nrow(mentoring) == 1) "has" else "have"
  ))

  html <- c(html, "<h3>Service Contributions</h3>")
  html <- c(html, sprintf(
    "<p>Grant review service: %d assignment%s logged, by role: %s.</p>",
    nrow(grant_reviews), if (nrow(grant_reviews) == 1) "" else "s",
    status_counts(grant_reviews, "role")
  ))
  html <- c(html, sprintf(
    "<p>Committee service: %d membership%s logged, by scope: %s.</p>",
    nrow(committees), if (nrow(committees) == 1) "" else "s",
    status_counts(committees, "scope")
  ))
  html <- c(html, sprintf(
    "<p>Journal peer review: %d assignment%s logged, by recommendation: %s.</p>",
    nrow(journal_reviews), if (nrow(journal_reviews) == 1) "" else "s",
    status_counts(journal_reviews, "recommendation")
  ))
  html <- c(html, sprintf(
    "<p>Data Safety Monitoring Board service: %d membership%s logged.</p>",
    nrow(dsmb), if (nrow(dsmb) == 1) "" else "s"
  ))

  html <- c(html, paste(
    "<p><em>This section is generated entirely from entries in the",
    "tracker as of the moment this report is viewed; it will read",
    "thin until the tracker is populated with real activity, and it",
    "does not include funding, leadership roles, citation counts, or",
    "other context your actual self-assessment should cover. Treat",
    "it as a data-grounded starting outline, not a finished",
    "statement.</em></p>"
  ))

  paste(html, collapse = "\n")
}
