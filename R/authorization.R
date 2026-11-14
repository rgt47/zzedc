#' Server-Side Authority Checks (21 CFR Part 11 §11.10(g))
#'
#' Before this, no sensitive operation in the package (approving or
#' rejecting a data correction, invalidating an electronic signature,
#' locking a form design, changing a user's role) had any
#' server-side role check -- the only guards were incidental (a
#' self-approval block in `data_correction.R`) or client-side (the
#' role dropdown in `user_management_module.R` narrowed by
#' `.assignable_roles()`, which a direct function call bypasses
#' entirely). `require_role()` is the shared, reusable gate for
#' those call sites.
#'
#' @name authorization
#' @keywords internal
NULL

#' Normalize a role display string for `.ROLE_TIER` lookup
#'
#' Role strings are stored and displayed with a space
#' (`"Data Manager"`), but `.ROLE_TIER`'s names use an underscore
#' (`data_manager`). Before this helper existed, `.assignable_roles()`
#' only lowercased the input and never replaced spaces, so
#' `.ROLE_TIER[tolower("Data Manager")]` looked up `"data manager"`,
#' never matched `"data_manager"`, and silently fell back to the
#' tier-3 (`coordinator`) default -- confirmed directly:
#' `.assignable_roles("Data Manager")` returned only `"Monitor"`
#' instead of the tier-2 set `.assignable_roles("StudyManager")`
#' returns. This normalizes both that call site and
#' [require_role()] the same way, so the fix applies everywhere
#' `.ROLE_TIER` is consulted.
#'
#' @param role A role display string (e.g. `"Data Manager"`), or
#'   `NULL`/`""`.
#' @return The lowercased, underscore-joined form used as
#'   `.ROLE_TIER`'s names (e.g. `"data_manager"`).
#' @keywords internal
.normalize_role_name <- function(role) {
  tolower(gsub("\\s+", "_", trimws(role %||% "")))
}

#' Require that a role is one of an allowed set
#'
#' A reusable authority check for sensitive operations, returning
#' this package's universal `list(success=, error=)` shape on denial
#' so callers can `if (!is.null(denied)) return(denied)` without any
#' new error-handling convention. Unlike `.assignable_roles()`'s
#' tier-based "who can assign which roles" question, this checks
#' plain allow-list membership, which is the right model for "who may
#' perform this specific operation" (e.g. approving a correction is
#' not naturally expressed as a tier comparison).
#'
#' @param actor_role The role string of the user attempting the
#'   operation (e.g. `"Coordinator"`). Matched case-insensitively and
#'   space/underscore-insensitively via [.normalize_role_name()].
#' @param allowed_roles Character vector of role strings permitted to
#'   perform the operation (same normalization applied).
#' @param action_label Short description of the operation, used only
#'   in the denial message (e.g. `"approve a data correction"`).
#' @return `NULL` if `actor_role` is allowed; otherwise
#'   `list(success = FALSE, error = <message>)`.
#' @keywords internal
require_role <- function(actor_role, allowed_roles, action_label) {
  normalized_actor <- .normalize_role_name(actor_role)
  normalized_allowed <- vapply(allowed_roles, .normalize_role_name, character(1))

  if (normalized_actor %in% normalized_allowed) {
    return(NULL)
  }

  list(
    success = FALSE,
    error = paste0(
      "Role '", actor_role %||% "(none)", "' is not authorized to ", action_label,
      ". Allowed roles: ", paste(allowed_roles, collapse = ", "), "."
    )
  )
}


#' Is a User Unblinded for a Study?
#'
#' Blinding is a grant table (`study_unblinding_grants`,
#' R/setup_wizard_utils.R's `.create_randomization_tables()`), not a
#' role string: the same login role (e.g. "PI") can be blinded or
#' unblinded for a given study depending on whether a live grant
#' exists, matching how trials run "Blinded PI" / "Unblinded PI" as
#' the same person rather than two different roles. A grant is live
#' iff its `revoked_date IS NULL`; revocation inserts a new state via
#' `UPDATE ... SET revoked_date = ...` rather than deleting the row,
#' so who was ever unblinded, and when, stays part of the record.
#'
#' @param conn A DBI connection or pool.
#' @param study_id The study.
#' @param user_id The user whose blinding status is being checked.
#'   `NULL`/`NA`/`""` is always blinded.
#' @return `TRUE`/`FALSE`.
#' @export
is_unblinded <- function(conn, study_id, user_id) {
  if (is.null(user_id) || is.na(user_id) || !nzchar(user_id)) {
    return(FALSE)
  }
  row <- DBI::dbGetQuery(conn, "
    SELECT 1 FROM study_unblinding_grants
    WHERE study_id = ? AND user_id = ? AND revoked_date IS NULL
  ", params = list(study_id, user_id))
  nrow(row) > 0
}


#' Require That a User Be Unblinded for a Study
#'
#' The [is_unblinded()] counterpart to [require_role()]: same
#' `list(success=, error=)` denial shape, so callers compose both
#' checks the same way (e.g. "must be a Coordinator AND unblinded").
#'
#' @param conn A DBI connection or pool.
#' @param study_id The study.
#' @param user_id The user attempting the operation.
#' @param action_label Short description of the operation, used only
#'   in the denial message (e.g. `"view the treatment assignment"`).
#' @return `NULL` if unblinded; otherwise
#'   `list(success = FALSE, error = <message>)`.
#' @export
require_unblinded <- function(conn, study_id, user_id, action_label) {
  if (is_unblinded(conn, study_id, user_id)) {
    return(NULL)
  }
  list(
    success = FALSE,
    error = paste0(
      "You are blinded for this study and may not ", action_label, "."
    )
  )
}
