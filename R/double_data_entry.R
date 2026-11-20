#' Double Data Entry (DDE)
#'
#' Per-field double data entry: any CRF field flagged
#' `designer_fields.require_double_entry = TRUE` requires two
#' independent, full submissions of the whole form (same subject/
#' form, linked by `data_entries.dde_group_id`) before it is settled.
#' Combines REDCap's "different user by default, reviewer is neither
#' entry person" rules with OpenClinica's "check item-by-item at
#' second-entry save time, three immediate resolution choices"
#' design, at field granularity (see `~/.claude/plans/
#' soft-orbiting-acorn.md`, Part B, for the full design rationale).
#'
#' A form with no flagged field is entirely unaffected: every function
#' here is a no-op (or simply not called) when
#' [flagged_dde_fields()] returns an empty vector.
#'
#' @name double_data_entry
#' @keywords internal
NULL


#' Which Fields on a Form Require Double Entry (internal)
#'
#' @param metadata A field-metadata list as returned by
#'   [get_crf_field_metadata()] (each element carries
#'   `require_double_entry`).
#' @return Character vector of `field_code`s with
#'   `require_double_entry = TRUE`. `character(0)` for an ordinary,
#'   single-keyed form.
#' @keywords internal
flagged_dde_fields <- function(metadata) {
  flagged <- vapply(metadata, function(m) isTRUE(m$require_double_entry %||% FALSE),
                    logical(1))
  names(metadata)[flagged]
}


#' Generate a New `dde_group_id` (internal)
#'
#' Mirrors `db_insert_data_entry()`'s own `entry_id` generation
#' convention (timestamp + random suffix, sanitized to
#' `[A-Za-z0-9-]`), under a distinct prefix so a `dde_group_id` is
#' never mistaken for an `entry_id` at a glance.
#'
#' @return A single character string.
#' @keywords internal
generate_dde_group_id <- function() {
  id <- paste0(
    "DDE-", format(Sys.time(), "%Y%m%d%H%M%OS3", tz = "UTC"),
    "-", sample.int(9999L, 1L)
  )
  gsub("[^A-Za-z0-9-]", "", id)
}


#' Decide a Submission's Role in a Double-Data-Entry Pair (internal)
#'
#' The one decision point every double-entry-flagged submission passes
#' through before it is saved. Runs the blind probe
#' ([db_get_dde_first_entry()], which never selects `data_json`) to
#' find whether a settled, not-yet-superseded first entry already
#' exists for this `subject_id`/`form_name`. Does **not** itself fetch
#' the first entry's field values -- that happens only in
#' [dde_check_discrepancies()], and only once this function has
#' already decided the submission is in fact a second entry.
#'
#' @param conn A DBI connection (or pool object).
#' @param subject_id,form_name Identify the (subject, form) pair (see
#'   [db_get_dde_first_entry()]).
#' @param created_by The user making *this* submission.
#' @return A list:
#'   * `role`: `"first"` or `"second"`.
#'   * `group_id`: the `dde_group_id` to save this entry under -- a
#'     freshly generated one for `"first"`, the existing group's for
#'     `"second"`.
#'   * `first_entry_id`: `NULL` for `"first"`; the first entry's
#'     `entry_id` for `"second"`.
#'   * `blocked_same_user`: `TRUE` when `"second"` and `created_by`
#'     matches the first entry's `created_by` -- REDCap's default
#'     "different user" enforcement. The caller must refuse the
#'     submission in this case, not save it.
#' @keywords internal
dde_decide_role <- function(conn, subject_id, form_name, created_by) {
  first <- db_get_dde_first_entry(conn, subject_id, form_name)
  if (nrow(first) == 0) {
    return(list(role = "first", group_id = generate_dde_group_id(),
                first_entry_id = NULL, blocked_same_user = FALSE))
  }
  list(
    role = "second",
    group_id = first$dde_group_id[1] %||% generate_dde_group_id(),
    first_entry_id = first$entry_id[1],
    blocked_same_user = identical(as.character(first$created_by[1]),
                                  as.character(created_by))
  )
}


#' Normalize a Field List the Same Way an Insert Would (internal)
#'
#' An in-memory `field_data` list (straight from Shiny inputs) and a
#' saved row's `data_json` (round-tripped through
#' `jsonlite::toJSON()`/`fromJSON()` by [db_insert_data_entry()]) can
#' disagree on type even when the value is the same -- e.g. `5` vs.
#' `"5"` -- which would otherwise register as a false discrepancy.
#' Round-tripping the in-memory list through the identical
#' `toJSON(..., auto_unbox = TRUE, null = "null")` /
#' `fromJSON(..., simplifyVector = FALSE)` pair before diffing puts
#' both sides through the same normalization.
#'
#' @param field_data A named list of field values.
#' @return The same list, round-tripped through JSON.
#' @keywords internal
.dde_normalize_fields <- function(field_data) {
  jsonlite::fromJSON(
    as.character(jsonlite::toJSON(field_data, auto_unbox = TRUE, null = "null")),
    simplifyVector = FALSE
  )
}


#' Item-Level Discrepancy Check for a Second DDE Entry (internal)
#'
#' Diffs a second entry's in-memory `field_data` against the first
#' entry's already-saved `data_json`, restricted to only the fields
#' flagged `require_double_entry = TRUE` -- a mismatch on any other
#' field is not checked at all and simply stands, identical to
#' ordinary single entry today. This is the one place a second DDE
#' entry's save path reads the first entry's `data_json`
#' ([db_get_dde_first_entry_values()]); nothing upstream of this call
#' (deciding the submission is a second entry at all, or rendering its
#' form) ever fetches it.
#'
#' Reuses [diff_field_lists()] (`R/version_control.R`), the same
#' per-field diff engine [compare_versions()] uses between two stored
#' version snapshots, rather than a second diff implementation.
#'
#' @param conn A DBI connection (or pool object).
#' @param first_entry_id The first entry's `entry_id` (from
#'   [dde_decide_role()]).
#' @param field_data The second entry's submitted field values
#'   (in-memory, not yet saved).
#' @param flagged_fields Character vector of field codes requiring
#'   double entry (from [flagged_dde_fields()]).
#' @return A list:
#'   * `first_values`: the first entry's full saved field list (for
#'     the caller to build a resolution UI from, e.g. to show "entry
#'     #1 said X" once a discrepancy is already known to exist --
#'     never shown before this point).
#'   * `discrepancies`: a named list (by field) of
#'     `list(field=, version_a_value=, version_b_value=, change_type=)`
#'     for each flagged field whose value differs. Empty when the two
#'     entries agree on every flagged field.
#' @keywords internal
dde_check_discrepancies <- function(conn, first_entry_id, field_data,
                                    flagged_fields) {
  first_values <- db_get_dde_first_entry_values(conn, first_entry_id)
  normalized_second <- .dde_normalize_fields(field_data)
  discrepancies <- diff_field_lists(first_values, normalized_second,
                                    fields = flagged_fields)
  list(first_values = first_values, discrepancies = discrepancies)
}


#' Valid In-Save DDE Discrepancy Resolution Choices
#' @keywords internal
.dde_resolution_choices <- c("keep_second", "revert_first", "flag_for_review")


#' Apply In-Save Resolutions to a Second Entry's Field Data (internal)
#'
#' Implements the three immediate choices OpenClinica's model offers
#' the second enterer for each flagged, mismatched field:
#'   * `"keep_second"` -- leave the second entry's own value as keyed.
#'   * `"revert_first"` -- overwrite the second entry's value with the
#'     first entry's, so the saved row agrees with entry #1 for this
#'     field (and so no future diff between the two rows will ever
#'     show this field again).
#'   * `"flag_for_review"` -- leave the second entry's value as keyed
#'     (same as `"keep_second"`), but marks the field as still open so
#'     it surfaces in [list_dde_discrepancies()]'s reconciliation
#'     queue until resolved there.
#' A discrepant field with no resolution supplied defaults to
#' `"flag_for_review"` -- silence is never treated as an implicit
#' choice to keep or revert a value nobody actually decided on.
#'
#' @param field_data The second entry's field values (will be mutated
#'   for `"revert_first"` fields).
#' @param first_values The first entry's saved field values.
#' @param discrepancies The `discrepancies` list from
#'   [dde_check_discrepancies()].
#' @param resolutions Named list/character vector, by field code, of
#'   one of [.dde_resolution_choices]. Fields not named here, among
#'   those in `discrepancies`, default to `"flag_for_review"`.
#' @return A list:
#'   * `field_data`: the (possibly mutated) field values to save.
#'   * `resolution_detail`: a named list (by field) of
#'     `list(choice=, first_value=, second_value=)`, suitable for
#'     merging into the second entry's audit record
#'     (`db_insert_data_entry()`'s `audit_extra`).
#'   * `pending_fields`: character vector of fields resolved
#'     `"flag_for_review"` -- still open, destined for the
#'     reconciliation queue.
#' @keywords internal
apply_dde_resolutions <- function(field_data, first_values, discrepancies,
                                  resolutions = list()) {
  resolution_detail <- list()
  pending_fields <- character(0)
  for (field in names(discrepancies)) {
    choice <- resolutions[[field]] %||% "flag_for_review"
    if (!choice %in% .dde_resolution_choices) {
      stop("Invalid DDE resolution choice '", choice, "' for field '", field,
           "'. Must be one of: ", paste(.dde_resolution_choices, collapse = ", "))
    }
    second_value <- field_data[[field]]
    first_value <- first_values[[field]]
    if (choice == "revert_first") {
      field_data[[field]] <- first_value
    } else if (choice == "flag_for_review") {
      pending_fields <- c(pending_fields, field)
    }
    resolution_detail[[field]] <- list(
      choice = choice,
      first_value = first_value,
      second_value = second_value
    )
  }
  list(field_data = field_data, resolution_detail = resolution_detail,
       pending_fields = pending_fields)
}


#' List Open Double-Data-Entry Discrepancies (Reconciliation Queue)
#'
#' Enumerates every `dde_group_id` with a flagged field that still
#' differs between its two saved `data_entries` rows and has not
#' already been resolved -- the data behind the Corrections tab's
#' "DDE Reconciliation" view (`R/data_correction_module.R`). A field
#' resolved at save time (`"keep_second"` or `"revert_first"`, see
#' [apply_dde_resolutions()]) never appears here: `"revert_first"`
#' makes the saved rows agree outright, and `"keep_second"` is an
#' accepted, intentional difference, not an open question. Only
#' `"flag_for_review"` fields, or a field never resolved at save time
#' at all (if that discrepancy-check step was somehow skipped), show
#' up -- and only until a `DDE_DISCREPANCY` correction for that
#' specific field has been `APPLIED` (checked against
#' `correction_requests`, not re-resolved a second way).
#'
#' A group whose non-canonical entry is already `superseded_by`
#' something (see [close_dde_group_if_resolved()]) is fully resolved
#' and excluded entirely, regardless of what the raw values say.
#'
#' @param conn A DBI connection (or pool object).
#' @param dde_group_id Optional: restrict to one group.
#' @return A data frame, one row per (group, field) still open, with
#'   `dde_group_id`, `first_entry_id`, `second_entry_id`, `field_code`,
#'   `first_value`, `second_value`. Zero rows if nothing is open.
#' @keywords internal
#' @export
list_dde_discrepancies <- function(conn, dde_group_id = NULL) {
  query <- paste(
    "SELECT dde_group_id, entry_id, created_by, created_date, data_json",
    "FROM data_entries",
    "WHERE dde_group_id IS NOT NULL AND superseded_by IS NULL"
  )
  params <- list()
  if (!is.null(dde_group_id)) {
    query <- paste(query, "AND dde_group_id = ?")
    params <- list(dde_group_id)
  }
  query <- paste(query, "ORDER BY dde_group_id, created_date ASC")
  rows <- if (length(params)) {
    DBI::dbGetQuery(conn, query, params = params)
  } else {
    DBI::dbGetQuery(conn, query)
  }
  if (nrow(rows) == 0) {
    return(data.frame(
      dde_group_id = character(0), first_entry_id = character(0),
      second_entry_id = character(0), field_code = character(0),
      first_value = character(0), second_value = character(0),
      stringsAsFactors = FALSE
    ))
  }

  applied_dde <- DBI::dbGetQuery(conn, "
    SELECT record_id, field_name FROM correction_requests
    WHERE correction_reason = 'DDE_DISCREPANCY' AND status = 'APPLIED'
  ")

  out <- list()
  for (gid in unique(rows$dde_group_id)) {
    pair <- rows[rows$dde_group_id == gid, , drop = FALSE]
    if (nrow(pair) < 2) next # a lone entry is not yet a pair at all
    first <- pair[1, ]
    second <- pair[2, ]
    first_values <- jsonlite::fromJSON(first$data_json[1] %||% "{}", simplifyVector = FALSE)
    second_values <- jsonlite::fromJSON(second$data_json[1] %||% "{}", simplifyVector = FALSE)

    crf_form <- tryCatch({
      DBI::dbGetQuery(conn,
        "SELECT form_name FROM data_entries WHERE entry_id = ?",
        list(first$entry_id[1]))$form_name[1]
    }, error = function(e) NA_character_)
    flagged <- tryCatch(.dde_flagged_fields_for_form(conn, crf_form), error = function(e) character(0))

    diff <- diff_field_lists(first_values, second_values, fields = flagged)
    for (field in names(diff)) {
      already_applied <- nrow(applied_dde) > 0 &&
        any(applied_dde$record_id == first$entry_id[1] & applied_dde$field_name == field)
      if (already_applied) next
      out[[length(out) + 1]] <- data.frame(
        dde_group_id = gid,
        first_entry_id = first$entry_id[1],
        second_entry_id = second$entry_id[1],
        field_code = field,
        first_value = diff[[field]]$version_a_value,
        second_value = diff[[field]]$version_b_value,
        stringsAsFactors = FALSE
      )
    }
  }
  if (length(out) == 0) {
    return(data.frame(
      dde_group_id = character(0), first_entry_id = character(0),
      second_entry_id = character(0), field_code = character(0),
      first_value = character(0), second_value = character(0),
      stringsAsFactors = FALSE
    ))
  }
  do.call(rbind, out)
}


#' Which Fields a Form Flags for Double Entry, by Form Name (internal)
#'
#' [list_dde_discrepancies()] only has a saved row's `form_name`
#' (`data_entries.form_name`, lower-cased `crf_code`) to work from, not
#' a `crf_id` -- this resolves one to the other via
#' `get_active_crf_forms()` and then [get_crf_field_metadata()]/
#' [flagged_dde_fields()], the same path `inst/app/edc.R` uses when a
#' form is actually on screen.
#'
#' @param conn A DBI connection (or pool object).
#' @param form_name A `data_entries.form_name` value (lower-case
#'   `crf_code`).
#' @return Character vector of flagged field codes; `character(0)` if
#'   the form cannot be resolved or has none.
#' @keywords internal
.dde_flagged_fields_for_form <- function(conn, form_name) {
  if (is.na(form_name) || !nzchar(form_name)) return(character(0))
  forms <- get_active_crf_forms(conn)
  idx <- which(tolower(forms$crf_code) == tolower(form_name))
  if (length(idx) == 0) return(character(0))
  metadata <- get_crf_field_metadata(conn, forms$crf_id[idx[1]])
  flagged_dde_fields(metadata)
}


#' Reviewer-Separation Guard for a DDE Discrepancy Request (internal)
#'
#' REDCap's Data Comparison Tool rule: the person resolving a queued
#' discrepancy must be *neither* of the two users who made the two
#' entries, a stricter, DDE-specific check than
#' `approve_correction()`/`apply_correction()`'s existing "requester
#' can't approve their own request" rule (which only blocks the
#' *requester*, and only from approving -- not applying -- their own
#' request). Implemented here as a separate guard the Corrections
#' module (`R/data_correction_module.R`) calls in addition to the
#' ordinary role check, only for requests whose
#' `correction_reason == "DDE_DISCREPANCY"`; it changes nothing about
#' `approve_correction()`/`apply_correction()` themselves, or about
#' how an ordinary correction is reviewed.
#'
#' @param conn A DBI connection (or pool object).
#' @param dde_group_id The group the discrepancy belongs to.
#' @param actor The user attempting to approve or apply the request.
#' @return `NULL` if `actor` may proceed; otherwise
#'   `list(success = FALSE, error = <message>)`, matching this
#'   package's other denial shapes.
#' @keywords internal
require_dde_reviewer_separation <- function(conn, dde_group_id, actor) {
  entry_users <- DBI::dbGetQuery(conn, "
    SELECT DISTINCT created_by FROM data_entries WHERE dde_group_id = ?
  ", list(dde_group_id))$created_by

  if (as.character(actor) %in% as.character(entry_users)) {
    return(list(
      success = FALSE,
      error = paste0(
        "'", actor, "' made one of the two double-data-entry submissions ",
        "for this group and may not approve or apply its reconciliation -- ",
        "a third reviewer is required."
      )
    ))
  }
  NULL
}


#' Supersede the Non-Canonical Entry Once a DDE Group Is Fully Resolved
#'
#' Called after a `DDE_DISCREPANCY` correction is successfully
#' `APPLIED` (`R/data_correction_module.R`'s `apply_btn` handler). The
#' first entry (chronologically earliest, non-superseded row in the
#' group) is always the correction's target/canonical record (see
#' `apply_correction()`'s `record_id`); if re-running
#' [list_dde_discrepancies()] for this group now finds no remaining
#' open field, the second entry's row is marked `superseded_by` the
#' first -- kept for audit, per this package's insert-only design, not
#' deleted.
#'
#' @param conn A DBI connection (or pool object).
#' @param dde_group_id The group to check.
#' @return `TRUE` if the group was (already, or just now) fully
#'   resolved and the non-canonical row is marked superseded; `FALSE`
#'   if discrepancies remain open.
#' @keywords internal
close_dde_group_if_resolved <- function(conn, dde_group_id) {
  remaining <- list_dde_discrepancies(conn, dde_group_id = dde_group_id)
  if (nrow(remaining) > 0) return(FALSE)

  rows <- DBI::dbGetQuery(conn, "
    SELECT entry_id, created_date, superseded_by FROM data_entries
    WHERE dde_group_id = ? ORDER BY created_date ASC
  ", list(dde_group_id))
  if (nrow(rows) < 2) return(FALSE)

  first_id <- rows$entry_id[1]
  for (i in seq(2, nrow(rows))) {
    if (is.na(rows$superseded_by[i])) {
      db_mark_entry_superseded(conn, rows$entry_id[i], first_id)
    }
  }
  TRUE
}
