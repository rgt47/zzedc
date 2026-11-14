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
#' DSL text fails to parse, or whose evaluation itself errors, does
#' not block submission (a malformed rule is a data-dictionary
#' authoring problem), but it raises a warning naming the rule so
#' the gap is visible rather than silent.
#'
#' Each validator is compiled with the rule's `field_code` as its
#' target, so field-less rules (`between 18 and 65`, `length == 7`,
#' `if gender == "Female" then required endif`) apply to that field.
#' When the target is blank the rule is skipped, unless it contains
#' a `required` node: plain range and comparison rules leave
#' required-ness to [validate_crf_submission()], whose "X is
#' required" message would otherwise be clobbered (both key errors
#' by `field_code`), while a conditional-required rule exists
#' precisely to fire on a blank target.
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
    has_field <- !is.na(rule$field_code) && nzchar(rule$field_code)

    ast <- tryCatch(parse_dsl_rule(rule$rule_dsl), error = function(e) e)
    if (inherits(ast, 'error')) {
      warning(sprintf('DSL rule %s not enforced: parse error: %s',
                      rule$rule_id, conditionMessage(ast)), call. = FALSE)
      next
    }

    # A blank target skips the rule unless the rule can demand a
    # value (`required`, typically inside an `if` guard): skipping
    # those made conditional-required rules unenforceable.
    target <- if (has_field) field_data[[rule$field_code]] else NULL
    if (has_field && .dsl_is_blank(target) &&
          !.dsl_ast_has_type(ast, 'required')) {
      next
    }

    result <- tryCatch({
      validator <- generate_validator_from_ast(
        ast, if (has_field) rule$field_code else NULL
      )
      validator(NULL, field_data)
    }, error = function(e) {
      warning(sprintf('DSL rule %s not enforced: evaluation error: %s',
                      rule$rule_id, conditionMessage(e)), call. = FALSE)
      TRUE
    })

    if (!isTRUE(result)) {
      key <- if (has_field) rule$field_code else rule$rule_id
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


#' Does an AST contain a node of a given type?
#' @keywords internal
#' @noRd
.dsl_ast_has_type <- function(ast, type) {
  if (!is.list(ast)) return(FALSE)
  if (identical(ast$type, type)) return(TRUE)
  any(vapply(ast, .dsl_ast_has_type, logical(1), type = type))
}
