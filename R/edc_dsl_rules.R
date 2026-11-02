#' Generic enforcement of a form's `dsl_validation_rules` at submit time
#'
#' The study data dictionary is meant to be the single source of
#' truth for a form's validation -- rules authored in the
#' `validation_rules` Google Sheets tab, imported into
#' `dsl_validation_rules` by [setup_zzedc_from_gsheets()]/
#' [sync_dsl_rules_from_gsheets()], parsed by [parse_dsl_rule()] and
#' compiled by [generate_validator()]. Until now nothing in the EDC
#' tab actually ran them: `inst/app/edc.R`'s submit handler never
#' queried this table at all, so eight real rules imported from this
#' package's own study data dictionaries sat in the database doing
#' nothing (confirmed directly against a live deployment).
#'
#' @name edc_dsl_rules
#' @keywords internal
NULL


#' Active, enforceable DSL rules for one form
#'
#' "Enforceable" means `is_active = 1` and either the rule doesn't
#' require approval, or it does and has already been approved --
#' the same gate `get_active_dsl_rules_for_form()`
#' (`R/validation_gsheets_integration.R`, part of the never-wired-in
#' rule-management module) already uses, so a rule imported straight
#' from the data dictionary (`requires_approval` defaults to
#' `FALSE` on import) is enforceable immediately, without needing
#' the orphaned approval workflow. Not a call to that function
#' directly: it always opens its own fresh
#' `connect_encrypted_db()` connection rather than accepting one, so
#' calling it from a reactive that re-runs on every keystroke would
#' open and close a new raw database connection that often, instead
#' of reusing the app's already-pooled `conn`; it also isn't
#' testable against an in-memory fixture the way a `conn`-accepting
#' function is. This also matches on `form_code` case-insensitively,
#' which that one does not.
#'
#' @param conn A DBI connection (or pool object).
#' @param crf_code The form's `crf_code` (matched case-insensitively
#'   against `dsl_validation_rules.form_code`).
#' @return A data frame with columns `rule_id`, `field_code`,
#'   `rule_dsl`, `error_message`; zero rows if the form has no
#'   enforceable rules.
#' @keywords internal
active_dsl_rules_for_form <- function(conn, crf_code) {
  DBI::dbGetQuery(
    conn,
    paste(
      "SELECT rule_id, field_code, rule_dsl, error_message",
      "FROM dsl_validation_rules",
      "WHERE LOWER(form_code) = LOWER(?)",
      "  AND is_active = 1",
      "  AND (requires_approval = 0 OR approval_status = 'APPROVED')"
    ),
    params = list(crf_code)
  )
}


#' Run a form's active DSL rules against a submission
#'
#' Each rule is compiled fresh via [generate_validator()] (cheap for
#' the handful of rules a form has, and avoids depending on
#' `compiled_r`/`compiled_sql` -- confirmed directly against a live
#' deployment that both are always `NULL`: the two functions meant
#' to populate them, `generate_r_validator()`/`generate_sql_check()`,
#' are called in two places but never defined anywhere in this
#' package, and both call sites silently swallow the resulting
#' "could not find function" error via `tryCatch()`). A rule whose
#' DSL text fails to parse, or whose evaluation itself errors, is
#' skipped rather than blocking every submission on that form -- a
#' malformed rule is a data-dictionary authoring problem, not
#' something an end user entering a manuscript should be stuck on.
#'
#' A rule's own `field_code` (e.g. `acceptance_date` for
#' `ACCEPT_AFTER_SUBMIT`) is required to be non-blank in
#' `field_data` before the rule is evaluated at all -- reproduced
#' directly: a bare, unguarded rule like `"student_count between 1
#' and 500"` evaluates `evaluate_comparison_node()`'s "Value is
#' missing" failure the moment the field is blank or simply absent,
#' which would otherwise nag with a DSL error before the user has
#' typed anything (live) and, worse, clobber
#' [validate_crf_submission()]'s own clearer "X is required" message
#' for the same field at submit time (both key the merged error list
#' by the same `field_code`). Required-ness is that function's job,
#' not this one's -- mirrors how the live view already excludes
#' `"required"`-kind errors for a field still being filled in.
#'
#' @param conn A DBI connection (or pool object).
#' @param crf_code The form's `crf_code`, or `NULL` to skip entirely
#'   (no rules are fetched or run).
#' @param field_data Named list of submitted field values.
#' @return Named list (by `field_code`) of `list(kind="dsl_rule",
#'   message=)` for each violated rule; empty list if none apply.
#'   When a rule names no `field_code` (NA), or more than one rule
#'   targets the same field, only the first violation for that key
#'   is kept -- callers needing every message should not assume
#'   one-error-per-field in general, but no rule imported from this
#'   package's own data dictionaries collides with another on the
#'   same field.
#' @keywords internal
validate_dsl_rules <- function(conn, crf_code, field_data) {
  errors <- list()
  if (is.null(crf_code)) return(errors)

  rules <- active_dsl_rules_for_form(conn, crf_code)
  if (nrow(rules) == 0) return(errors)

  for (i in seq_len(nrow(rules))) {
    rule <- rules[i, ]

    target <- field_data[[rule$field_code]]
    if (is.null(target) || all(is.na(target)) ||
          all(!nzchar(trimws(as.character(target))))) {
      next
    }

    result <- tryCatch({
      validator <- generate_validator(rule$rule_dsl)
      validator(NULL, field_data)
    }, error = function(e) TRUE)  # unparseable/broken rule: skip, don't block

    if (!isTRUE(result)) {
      key <- if (!is.na(rule$field_code) && nzchar(rule$field_code)) {
        rule$field_code
      } else {
        rule$rule_id
      }
      if (is.null(errors[[key]])) {
        message <- if (!is.na(rule$error_message) && nzchar(rule$error_message)) {
          rule$error_message
        } else if (is.character(result)) {
          result
        } else {
          sprintf("%s failed validation", key)
        }
        errors[[key]] <- list(kind = "dsl_rule", message = message)
      }
    }
  }
  errors
}
