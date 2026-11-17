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
#' @return `TRUE`/`FALSE`. Also `FALSE` (not an error) when this
#'   database has no randomization tables yet -- the overwhelming
#'   majority of zzedc studies, including every one that is not a
#'   randomized trial, have never run
#'   [migrate_add_randomization_tables()], and "nobody is unblinded"
#'   is the correct answer for them, not a crash. This function is
#'   called unconditionally while rendering any CRF form with a
#'   `randomization_group` field (`inst/app/edc.R`), so it must never
#'   throw.
#' @export
is_unblinded <- function(conn, study_id, user_id) {
  if (is.null(user_id) || is.na(user_id) || !nzchar(user_id)) {
    return(FALSE)
  }
  if (!.randomization_tables_exist(conn)) {
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


#' Require an Authenticated Session Before a Write-Triggering Handler Proceeds
#'
#' `output$ui`'s `user_input$authenticated` switch (`inst/app/edc.R`) only
#' decides what gets *rendered*; it does nothing to stop the
#' `observeEvent()`/`downloadHandler()` a rendered button is bound to from
#' also being reachable directly, since Shiny dispatches an input event to
#' its bound observer regardless of whether the element that would normally
#' send it is currently shown to that session. Confirmed directly: CRF
#' submission (`observeEvent(input$submitcrf, ...)`) and randomization
#' (`observeEvent(input$randomize_subject_btn, ...)`) had no authentication
#' check of their own at all, so a crafted
#' `Shiny.setInputValue('submitcrf', 1)` sent over an unauthenticated
#' session's websocket -- trivial from the browser console, no exploit
#' tooling needed -- would still write a real, fabricated entry or trigger a
#' real randomization. This is the one access-control layer every such
#' handler needs (21 CFR Part 11 §11.10(d): "Limiting system access to
#' authorized individuals").
#'
#' Unlike [require_role()]/[require_unblinded()], which return a
#' `list(success=, error=)` for the caller to act on (used from both
#' reactive and plain function contexts), this is reactive-context-only: an
#' unauthenticated session's denial is first recorded as an `ACCESS` audit
#' event -- required by §11.10(e)'s audit-trail obligation, since a check
#' that blocks silently with nothing logged leaves no record that an
#' unauthorized attempt was ever made -- and then [shiny::req()] halts the
#' calling block exactly as any other failed `req()` does, so nothing after
#' this call in the same `observeEvent()`/`downloadHandler()` runs.
#'
#' @param user_input The session's shared `reactiveValues` object
#'   (`inst/app/server.R`), carrying `authenticated`.
#' @param session The current Shiny session, for the denial's recorded IP
#'   address and session token (via [session_audit_context()]).
#' @param db_path The study database's file path, for recording the denial
#'   (passed to [log_audit_event_extended()], which connects on its own).
#' @param action_label Short description of the blocked action, recorded in
#'   the denial's `details` (e.g. `"submit a CRF entry"`).
#' @return `TRUE`, invisibly, once the session is confirmed authenticated.
#'   Does not return otherwise -- see above.
#' @export
require_authenticated_action <- function(user_input, session, db_path, action_label) {
  if (isTRUE(user_input$authenticated)) {
    return(invisible(TRUE))
  }

  .log_access_denied(session, db_path, action_label,
                     reason = "not authenticated", user_id = "unauthenticated")
  shiny::req(FALSE)
}


#' Record a Denied Access Attempt (internal)
#'
#' Shared by [require_authenticated_action()] and the module guard
#' built by `.module_access_guard()`: one `ACCESS`/`DENIED` audit event
#' (`SECURITY` category, `warning` severity) carrying the blocked
#' action and the reason. A failure to write the record is swallowed;
#' callers halt the denied action regardless of the outcome.
#'
#' @param session The Shiny session (for address and session token), or
#'   `NULL`.
#' @param db_path Study database path, a function returning one, or
#'   `NULL` for the configured default.
#' @param action_label Short description of the blocked action.
#' @param reason Why it was blocked.
#' @param user_id Who attempted it.
#' @return `NULL`, invisibly.
#' @keywords internal
.log_access_denied <- function(session, db_path, action_label, reason, user_id) {
  tryCatch({
    path <- if (is.function(db_path)) db_path() else db_path
    audit_ctx <- if (!is.null(session)) {
      session_audit_context(session)
    } else {
      list(ip_address = NULL, session_id = NULL)
    }
    log_audit_event_extended(
      event_type = "ACCESS", event_category = "SECURITY",
      table_name = NA_character_, operation = "DENIED", severity = "warning",
      details = jsonlite::toJSON(
        list(action = action_label, reason = reason),
        auto_unbox = TRUE
      ),
      user_id = user_id,
      ip_address = audit_ctx$ip_address, session_id = audit_ctx$session_id,
      db_path = path
    )
  }, error = function(e) NULL)
  invisible(NULL)
}


#' Access Guard for a Mounted Shiny Module (internal)
#'
#' The Admin, Compliance and Corrections module trees are mounted once,
#' at first login, and stay mounted for the rest of the Shiny session:
#' Shiny cannot unmount a module. Logout (`inst/app/auth.R`) and
#' automatic logoff ([enable_session_timeout()]) clear the session's
#' identity, but every output and observer in those trees stays
#' registered and reachable from the browser. Each sensitive module
#' therefore checks the current user itself, through this one guard,
#' before it renders data or acts on an input.
#'
#' The current user is resolved reactively. When `user_session` (the
#' app's per-session `reactiveValues`) is supplied, its
#' `authenticated` flag must be `TRUE`. `user` and `role` (plain values
#' or reactives) override the session's `username` and `role`; without
#' a session, a non-empty `user` stands for authentication. A missing
#' or empty user always denies: a module mounted with no identity at
#' all shows and does nothing.
#'
#' @param user_session The session's login state, or `NULL`.
#' @param user,role The current user and role, as values or reactives,
#'   or `NULL` to take them from `user_session`.
#' @param allowed_roles Roles permitted by default (matched as in
#'   [require_role()]), or `NULL` for any authenticated user.
#' @param db_path Database path (or function returning it) for the
#'   denial audit record.
#' @param session The Shiny session.
#' @return A list of three functions:
#'   * `authorized(roles = allowed_roles)`: reactive `TRUE`/`FALSE`.
#'   * `require()`: silent [shiny::req()] for renders, reactives and
#'     passive observers. Returns the current user's list
#'     (`user`, `role`) invisibly.
#'   * `require_action(action_label, roles = allowed_roles)`: for
#'     input-triggered actions and downloads. A denial is first recorded
#'     as an `ACCESS`/`DENIED` audit event, then halts like `req()`. A
#'     signed-in user denied for their role also sees a notification
#'     giving the reason.
#' @keywords internal
.module_access_guard <- function(user_session = NULL, user = NULL, role = NULL,
                                 allowed_roles = NULL, db_path = NULL,
                                 session = shiny::getDefaultReactiveDomain()) {
  resolve <- function(x) if (is.function(x)) x() else x
  present <- function(x) {
    !is.null(x) && length(x) == 1 && !is.na(x) && nzchar(as.character(x))
  }

  current <- function() {
    from_session <- !is.null(user_session)
    u <- resolve(user)
    if (is.null(u) && from_session) u <- user_session$username %||% user_session$user_id
    r <- resolve(role)
    if (is.null(r) && from_session) r <- user_session$role
    authenticated <- if (from_session) isTRUE(user_session$authenticated) else TRUE
    list(user = u, role = r, authenticated = authenticated && present(u))
  }

  denial_reason <- function(who, roles) {
    if (!isTRUE(who$authenticated)) return("not authenticated")
    if (is.null(roles)) return(NULL)
    if (!present(who$role)) return("no role")
    denied <- require_role(who$role, roles, "use this function")
    if (is.null(denied)) NULL else denied$error
  }

  authorized <- function(roles = allowed_roles) {
    is.null(denial_reason(current(), roles))
  }

  list(
    authorized = authorized,
    require = function() {
      who <- current()
      shiny::req(is.null(denial_reason(who, allowed_roles)))
      invisible(who[c("user", "role")])
    },
    require_action = function(action_label, roles = allowed_roles) {
      who <- current()
      reason <- denial_reason(who, roles)
      if (!is.null(reason)) {
        .log_access_denied(
          session, db_path, action_label, reason,
          user_id = if (present(who$user)) as.character(who$user) else "unauthenticated"
        )
        # A signed-in user with the wrong role is told why nothing
        # happened; a signed-out session gets no response.
        if (isTRUE(who$authenticated) && !is.null(session)) {
          tryCatch(
            shiny::showNotification(paste0("Not permitted: ", reason),
                                    type = "error", session = session),
            error = function(e) NULL
          )
        }
        shiny::req(FALSE)
      }
      invisible(who[c("user", "role")])
    }
  )
}
