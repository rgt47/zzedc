#' Validation DSL Google Sheets Integration
#'
#' Integrates the ZZedc Validation DSL with Google Sheets for non-technical
#' validation rule authoring. Enables clinical staff to define validation
#' rules in plain English syntax directly in Google Sheets.
#'
#' @keywords internal
#' @name validation_gsheets_integration
NULL

# ============================================================================
# Google Sheets Validation Rule Schema
# ============================================================================

#' Expected columns in the validation_rules Google Sheet
#' @keywords internal
VALIDATION_SHEET_SCHEMA <- list(

  required = c("rule_id", "field_code", "rule_dsl"),
  optional = c(
    "form_code", "rule_name", "error_message", "severity",
    "rule_category", "is_active", "requires_approval",
    "approved_by", "approved_at", "notes"
  ),
  defaults = list(
    severity = "ERROR",
    rule_category = "FIELD",
    is_active = TRUE,
    requires_approval = FALSE
  )
)

#' Severity levels for validation rules
#' @keywords internal
#' @export
get_dsl_severity_levels <- function() {
  c(
    ERROR = "Blocks data entry until corrected",
    WARNING = "Alerts user but allows save",
    INFO = "Informational message only"
  )
}

#' Rule categories for validation
#' @keywords internal
#' @export
get_dsl_rule_categories <- function() {
  c(
    FIELD = "Single field validation",
    CROSS_FIELD = "Compares multiple fields on same form",
    CROSS_FORM = "Validates across different forms",
    CROSS_VISIT = "Validates across visits (batch QC)",
    ELIGIBILITY = "Inclusion/exclusion criteria",
    SAFETY = "Safety-related validation"
  )
}

# ============================================================================
# Google Sheets Import Functions
# ============================================================================

#' Import Validation Rules from Google Sheets
#'
#' Reads validation rules defined in plain English DSL syntax from a
#' Google Sheet and imports them into the ZZedc database.
#'
#' @param sheet_id Google Sheet ID or URL
#' @param sheet_name Name of the sheet containing rules (default: "validation_rules")
#' @param imported_by User ID performing the import
#' @param validate_syntax If TRUE, validates DSL syntax before import
#' @param dry_run If TRUE, validates without importing
#'
#' @return List with import results including success count, errors, and warnings
#'
#' @details
#' The Google Sheet should have the following columns:
#' \itemize{
#'   \item \code{rule_id} - Unique identifier for the rule (required)
#'   \item \code{field_code} - Field this rule applies to (required)
#'   \item \code{rule_dsl} - Validation rule in DSL syntax (required)
#'   \item \code{form_code} - Form containing the field (optional)
#'   \item \code{rule_name} - Human-readable rule name (optional)
#'   \item \code{error_message} - Custom error message (optional)
#'   \item \code{severity} - ERROR, WARNING, or INFO (default: ERROR)
#'   \item \code{rule_category} - FIELD, CROSS_FIELD, etc. (default: FIELD)
#'   \item \code{is_active} - Whether rule is active (default: TRUE)
#'   \item \code{requires_approval} - Needs PI approval (default: FALSE)
#' }
#'
#' @examples
#' \dontrun{
#' # Import from Google Sheet
#' result <- import_validation_rules_from_gsheets(
#'   sheet_id = "1ABC...xyz",
#'   imported_by = "data_manager"
#' )
#'
#' # Dry run to validate syntax
#' result <- import_validation_rules_from_gsheets(
#'   sheet_id = "1ABC...xyz",
#'   dry_run = TRUE
#' )
#' }
#'
#' @export
import_validation_rules_from_gsheets <- function(
  sheet_id,
  sheet_name = "validation_rules",
  imported_by,
  validate_syntax = TRUE,
  dry_run = FALSE
) {
  if (!requireNamespace("googlesheets4", quietly = TRUE)) {
    return(list(
      success = FALSE,
      error = "Package 'googlesheets4' is required. Install with: install.packages('googlesheets4')"
    ))
  }

  results <- list(
    success = TRUE,
    imported = 0,
    skipped = 0,
    errors = list(),
    warnings = list(),
    rules = list()
  )

  tryCatch({
    rules_df <- googlesheets4::read_sheet(sheet_id, sheet = sheet_name)

    if (nrow(rules_df) == 0) {
      return(list(success = TRUE, imported = 0, message = "No rules found in sheet"))
    }

    missing_cols <- setdiff(VALIDATION_SHEET_SCHEMA$required, names(rules_df))
    if (length(missing_cols) > 0) {
      return(list(
        success = FALSE,
        error = paste("Missing required columns:", paste(missing_cols, collapse = ", "))
      ))
    }

    for (col in names(VALIDATION_SHEET_SCHEMA$defaults)) {
      if (!col %in% names(rules_df)) {
        rules_df[[col]] <- VALIDATION_SHEET_SCHEMA$defaults[[col]]
      }
    }

    for (i in seq_len(nrow(rules_df))) {
      row <- rules_df[i, ]
      rule_id <- as.character(row$rule_id)

      if (is.na(row$rule_dsl) || row$rule_dsl == "") {
        results$errors[[rule_id]] <- "Empty DSL rule"
        results$skipped <- results$skipped + 1
        next
      }

      if (validate_syntax) {
        parse_result <- validate_dsl_syntax(row$rule_dsl)
        if (!parse_result$valid) {
          results$errors[[rule_id]] <- paste("Syntax error:", parse_result$error)
          results$skipped <- results$skipped + 1
          next
        }
      }

      rule_record <- list(
        rule_id = rule_id,
        field_code = as.character(row$field_code),
        form_code = if ("form_code" %in% names(row)) as.character(row$form_code) else NA,
        rule_name = if ("rule_name" %in% names(row)) as.character(row$rule_name) else rule_id,
        rule_dsl = as.character(row$rule_dsl),
        error_message = if ("error_message" %in% names(row) && !is.na(row$error_message)) {
          as.character(row$error_message)
        } else {
          generate_default_error_message(row$rule_dsl, row$field_code)
        },
        severity = toupper(as.character(row$severity)),
        rule_category = toupper(as.character(row$rule_category)),
        is_active = as.logical(row$is_active),
        requires_approval = as.logical(row$requires_approval),
        imported_by = imported_by,
        imported_at = Sys.time()
      )

      if (!dry_run) {
        save_result <- save_dsl_rule_to_db(rule_record)
        if (!save_result$success) {
          results$errors[[rule_id]] <- save_result$error
          results$skipped <- results$skipped + 1
          next
        }
      }

      results$rules[[rule_id]] <- rule_record
      results$imported <- results$imported + 1
    }

    results$message <- sprintf(
      "Imported %d rules, skipped %d with errors",
      results$imported, results$skipped
    )

  }, error = function(e) {
    results$success <<- FALSE
    results$error <<- e$message
  })

  results
}

#' Validate DSL Syntax
#'
#' Checks if a DSL rule string is syntactically valid without executing it.
#'
#' @param rule_dsl DSL rule string to validate
#'
#' @return List with valid (logical) and error (character if invalid)
#'
#' @examples
#' \dontrun{
#' validate_dsl_syntax("between 18 and 65")
#' validate_dsl_syntax("if sex == 'Female' then pregnant required endif")
#' }
#'
#' @keywords internal
#' @export
validate_dsl_syntax <- function(rule_dsl) {
  tryCatch({
    ast <- parse_dsl_rule(rule_dsl)
    list(valid = TRUE, ast = ast)
  }, error = function(e) {
    list(valid = FALSE, error = e$message)
  })
}

#' Generate Default Error Message
#'
#' Creates a user-friendly error message from a DSL rule.
#'
#' @param rule_dsl DSL rule string
#' @param field_code Field code for context
#'
#' @return Character error message
#'
#' @keywords internal
generate_default_error_message <- function(rule_dsl, field_code) {
  rule_lower <- tolower(rule_dsl)

  if (grepl("^between", rule_lower)) {
    matches <- regmatches(rule_dsl, regexec("between\\s+([0-9.]+)\\s+and\\s+([0-9.]+)", rule_lower))
    if (length(matches[[1]]) == 3) {
      return(sprintf("%s must be between %s and %s", field_code, matches[[1]][2], matches[[1]][3]))
    }
  }

  if (grepl("^required", rule_lower)) {
    return(sprintf("%s is required", field_code))
  }

  if (grepl("^in\\s*\\(", rule_lower)) {
    return(sprintf("%s must be one of the allowed values", field_code))
  }

  if (grepl(">=|<=|>|<|==|!=", rule_dsl)) {
    return(sprintf("%s does not meet the validation criteria", field_code))
  }

  sprintf("Invalid value for %s", field_code)
}

# ============================================================================
# Database Storage Functions
# ============================================================================

#' Initialize DSL Rules Database Tables
#'
#' Creates the database tables for storing validation rules imported
#' from Google Sheets with role-based access control.
#'
#' @return List with success status
#'
#' @keywords internal
#' @export
init_dsl_rules_db <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS dsl_validation_rules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        rule_id TEXT UNIQUE NOT NULL,
        field_code TEXT NOT NULL,
        form_code TEXT,
        rule_name TEXT,
        rule_dsl TEXT NOT NULL,
        compiled_r TEXT,
        compiled_sql TEXT,
        error_message TEXT,
        severity TEXT DEFAULT 'ERROR',
        rule_category TEXT DEFAULT 'FIELD',
        is_active INTEGER DEFAULT 1,
        requires_approval INTEGER DEFAULT 0,
        approval_status TEXT DEFAULT 'PENDING',
        approved_by TEXT,
        approved_at TEXT,
        imported_by TEXT NOT NULL,
        imported_at TEXT NOT NULL,
        updated_by TEXT,
        updated_at TEXT,
        version INTEGER DEFAULT 1
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS dsl_rule_permissions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        role_name TEXT NOT NULL,
        can_view INTEGER DEFAULT 1,
        can_create INTEGER DEFAULT 0,
        can_edit INTEGER DEFAULT 0,
        can_delete INTEGER DEFAULT 0,
        can_approve INTEGER DEFAULT 0,
        can_activate INTEGER DEFAULT 0,
        created_at TEXT DEFAULT (datetime('now'))
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS dsl_rule_audit (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        rule_id TEXT NOT NULL,
        action TEXT NOT NULL,
        old_value TEXT,
        new_value TEXT,
        changed_by TEXT NOT NULL,
        changed_at TEXT DEFAULT (datetime('now')),
        reason TEXT
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS dsl_rule_approvals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        rule_id TEXT NOT NULL,
        version INTEGER NOT NULL,
        requested_by TEXT NOT NULL,
        requested_at TEXT NOT NULL,
        status TEXT DEFAULT 'PENDING',
        reviewed_by TEXT,
        reviewed_at TEXT,
        comments TEXT,
        FOREIGN KEY (rule_id) REFERENCES dsl_validation_rules(rule_id)
      )
    ")

    setup_default_dsl_permissions(con)

    list(success = TRUE, message = "DSL rules database initialized")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Setup Default DSL Permissions
#'
#' Configures role-based permissions for validation rule management.
#'
#' @param con Database connection
#'
#' @keywords internal
setup_default_dsl_permissions <- function(con) {
  permissions <- data.frame(
    role_name = c("admin", "pi", "data_manager", "coordinator", "monitor"),
    can_view = c(1, 1, 1, 1, 1),
    can_create = c(1, 0, 1, 0, 0),
    can_edit = c(1, 0, 1, 0, 0),
    can_delete = c(1, 0, 0, 0, 0),
    can_approve = c(1, 1, 0, 0, 0),
    can_activate = c(1, 1, 1, 0, 0),
    stringsAsFactors = FALSE
  )

  existing <- DBI::dbGetQuery(con, "SELECT role_name FROM dsl_rule_permissions")

  for (i in seq_len(nrow(permissions))) {
    if (!permissions$role_name[i] %in% existing$role_name) {
      DBI::dbExecute(con, "
        INSERT INTO dsl_rule_permissions
        (role_name, can_view, can_create, can_edit, can_delete, can_approve, can_activate)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      ", params = as.list(permissions[i, ]))
    }
  }
}

#' Save DSL Rule to Database
#'
#' Stores a parsed validation rule in the database with compiled R and SQL code.
#'
#' @param rule_record List containing rule data
#'
#' @return List with success status
#'
#' @keywords internal
save_dsl_rule_to_db <- function(rule_record) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    compiled_r <- tryCatch({
      ast <- parse_dsl_rule(rule_record$rule_dsl)
      generate_r_validator(ast)
    }, error = function(e) NA_character_)

    compiled_sql <- tryCatch({
      ast <- parse_dsl_rule(rule_record$rule_dsl)
      generate_sql_check(ast, rule_record$field_code)
    }, error = function(e) NA_character_)

    existing <- DBI::dbGetQuery(
      con,
      "SELECT id, version FROM dsl_validation_rules WHERE rule_id = ?",
      params = list(rule_record$rule_id)
    )

    if (nrow(existing) > 0) {
      new_version <- existing$version[1] + 1
      DBI::dbExecute(con, "
        UPDATE dsl_validation_rules SET
          field_code = ?, form_code = ?, rule_name = ?, rule_dsl = ?,
          compiled_r = ?, compiled_sql = ?, error_message = ?,
          severity = ?, rule_category = ?, is_active = ?,
          requires_approval = ?, updated_by = ?, updated_at = ?,
          version = ?
        WHERE rule_id = ?
      ", params = list(
        rule_record$field_code, rule_record$form_code, rule_record$rule_name,
        rule_record$rule_dsl, compiled_r, compiled_sql, rule_record$error_message,
        rule_record$severity, rule_record$rule_category, rule_record$is_active,
        rule_record$requires_approval, rule_record$imported_by,
        as.character(Sys.time()), new_version, rule_record$rule_id
      ))
    } else {
      DBI::dbExecute(con, "
        INSERT INTO dsl_validation_rules (
          rule_id, field_code, form_code, rule_name, rule_dsl,
          compiled_r, compiled_sql, error_message, severity, rule_category,
          is_active, requires_approval, imported_by, imported_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ", params = list(
        rule_record$rule_id, rule_record$field_code, rule_record$form_code,
        rule_record$rule_name, rule_record$rule_dsl, compiled_r, compiled_sql,
        rule_record$error_message, rule_record$severity, rule_record$rule_category,
        rule_record$is_active, rule_record$requires_approval,
        rule_record$imported_by, as.character(rule_record$imported_at)
      ))
    }

    log_dsl_rule_action(
      rule_id = rule_record$rule_id,
      action = if (nrow(existing) > 0) "UPDATE" else "CREATE",
      new_value = rule_record$rule_dsl,
      changed_by = rule_record$imported_by,
      con = con
    )

    list(success = TRUE)
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Log DSL Rule Action
#'
#' Records an audit entry for validation rule changes.
#'
#' @param rule_id Rule identifier
#' @param action Action performed
#' @param old_value Previous value
#' @param new_value New value
#' @param changed_by User ID
#' @param reason Optional reason
#' @param con Database connection
#'
#' @keywords internal
log_dsl_rule_action <- function(rule_id, action, old_value = NULL, new_value = NULL,
                                 changed_by, reason = NULL, con = NULL) {
  close_con <- FALSE
  if (is.null(con)) {
    con <- connect_encrypted_db()
    close_con <- TRUE
  }

  tryCatch({
    DBI::dbExecute(con, "
      INSERT INTO dsl_rule_audit (rule_id, action, old_value, new_value, changed_by, reason)
      VALUES (?, ?, ?, ?, ?, ?)
    ", params = list(rule_id, action, old_value, new_value, changed_by, reason))
  }, error = function(e) {
    warning("Failed to log DSL rule action: ", e$message)
  })

  if (close_con) DBI::dbDisconnect(con)
}

# ============================================================================
# Permission Checking Functions
# ============================================================================

#' Check DSL Rule Permission
#'
#' Verifies if a user has permission to perform an action on validation rules.
#'
#' @param user_role User's role
#' @param action Action to check (view, create, edit, delete, approve, activate)
#'
#' @return Logical indicating permission
#'
#' @keywords internal
#' @export
check_dsl_rule_permission <- function(user_role, action) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    column <- paste0("can_", tolower(action))
    valid_columns <- c("can_view", "can_create", "can_edit",
                       "can_delete", "can_approve", "can_activate")

    if (!column %in% valid_columns) {
      warning("Invalid action: ", action)
      return(FALSE)
    }

    query <- sprintf(
      "SELECT %s FROM dsl_rule_permissions WHERE role_name = ?",
      column
    )

    result <- DBI::dbGetQuery(con, query, params = list(tolower(user_role)))

    if (nrow(result) == 0) FALSE
    else as.logical(result[[1]][1])
  }, error = function(e) {
    warning("Permission check failed: ", e$message)
    FALSE
  })
}

#' Get User DSL Permissions
#'
#' Returns all DSL rule permissions for a user role.
#'
#' @param user_role User's role
#'
#' @return List of permissions
#'
#' @keywords internal
#' @export
get_user_dsl_permissions <- function(user_role) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    result <- DBI::dbGetQuery(con, "
      SELECT can_view, can_create, can_edit, can_delete, can_approve, can_activate
      FROM dsl_rule_permissions WHERE role_name = ?
    ", params = list(tolower(user_role)))

    if (nrow(result) == 0) {
      list(view = FALSE, create = FALSE, edit = FALSE,
           delete = FALSE, approve = FALSE, activate = FALSE)
    } else {
      list(
        view = as.logical(result$can_view[1]),
        create = as.logical(result$can_create[1]),
        edit = as.logical(result$can_edit[1]),
        delete = as.logical(result$can_delete[1]),
        approve = as.logical(result$can_approve[1]),
        activate = as.logical(result$can_activate[1])
      )
    }
  }, error = function(e) {
    list(view = FALSE, create = FALSE, edit = FALSE,
         delete = FALSE, approve = FALSE, activate = FALSE)
  })
}

# ============================================================================
# Rule Approval Workflow
# ============================================================================

#' Request Rule Approval
#'
#' Submits a validation rule for PI/Admin approval before activation.
#'
#' @param rule_id Rule identifier
#' @param requested_by User requesting approval
#' @param comments Optional comments
#'
#' @return List with success status
#'
#'
#' @examples
#' \dontrun{
#' # Submit a draft validation rule for two-person review.
#' request_dsl_rule_approval(
#'   rule_id   = 17,
#'   requester = "biostat_lead",
#'   rationale = "Adds cross-form check for visit-window violations"
#' )
#' }
#' @export
request_dsl_rule_approval <- function(rule_id, requested_by, comments = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    rule <- DBI::dbGetQuery(con, "
      SELECT version, requires_approval FROM dsl_validation_rules WHERE rule_id = ?
    ", params = list(rule_id))

    if (nrow(rule) == 0) {
      return(list(success = FALSE, error = "Rule not found"))
    }

    DBI::dbExecute(con, "
      INSERT INTO dsl_rule_approvals (rule_id, version, requested_by, requested_at, comments)
      VALUES (?, ?, ?, datetime('now'), ?)
    ", params = list(rule_id, rule$version[1], requested_by, comments))

    DBI::dbExecute(con, "
      UPDATE dsl_validation_rules SET approval_status = 'PENDING' WHERE rule_id = ?
    ", params = list(rule_id))

    log_dsl_rule_action(rule_id, "APPROVAL_REQUESTED", changed_by = requested_by, con = con)

    list(success = TRUE, message = "Approval requested")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Approve or Reject Rule
#'
#' PI or Admin reviews and approves/rejects a validation rule.
#'
#' @param rule_id Rule identifier
#' @param reviewer_id Reviewer user ID
#' @param reviewer_role Reviewer's role (must have approve permission)
#' @param decision APPROVE or REJECT
#' @param comments Review comments
#'
#' @return List with success status
#'
#'
#' @examples
#' \dontrun{
#' # Approve a pending validation rule (or reject with a comment).
#' review_dsl_rule(
#'   rule_id  = 17,
#'   reviewer = "data_manager",
#'   decision = "approved",
#'   comment  = "Tested on staging; ready for production"
#' )
#' }
#' @export
review_dsl_rule <- function(rule_id, reviewer_id, reviewer_role, decision, comments = NULL) {
  if (!check_dsl_rule_permission(reviewer_role, "approve")) {
    return(list(success = FALSE, error = "Insufficient permissions to approve rules"))
  }

  if (!toupper(decision) %in% c("APPROVE", "REJECT")) {
    return(list(success = FALSE, error = "Decision must be APPROVE or REJECT"))
  }

  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    pending <- DBI::dbGetQuery(con, "
      SELECT id FROM dsl_rule_approvals
      WHERE rule_id = ? AND status = 'PENDING'
      ORDER BY requested_at DESC LIMIT 1
    ", params = list(rule_id))

    if (nrow(pending) == 0) {
      return(list(success = FALSE, error = "No pending approval request found"))
    }

    DBI::dbExecute(con, "
      UPDATE dsl_rule_approvals SET
        status = ?, reviewed_by = ?, reviewed_at = datetime('now'), comments = ?
      WHERE id = ?
    ", params = list(toupper(decision), reviewer_id, comments, pending$id[1]))

    new_status <- if (toupper(decision) == "APPROVE") "APPROVED" else "REJECTED"
    is_active <- if (toupper(decision) == "APPROVE") 1 else 0

    DBI::dbExecute(con, "
      UPDATE dsl_validation_rules SET
        approval_status = ?, approved_by = ?, approved_at = datetime('now'),
        is_active = ?
      WHERE rule_id = ?
    ", params = list(new_status, reviewer_id, is_active, rule_id))

    log_dsl_rule_action(
      rule_id, paste0("APPROVAL_", toupper(decision)),
      changed_by = reviewer_id, reason = comments, con = con
    )

    list(success = TRUE, message = paste("Rule", tolower(decision), "d"))
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# Rule Retrieval Functions
# ============================================================================

#' Get Active Validation Rules for Form
#'
#' Retrieves all active, approved validation rules for a specific form.
#'
#' @param form_code Form code
#'
#' @return Data frame of active rules
#'
#' @keywords internal
#' @export
get_active_dsl_rules_for_form <- function(form_code) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbGetQuery(con, "
      SELECT rule_id, field_code, rule_name, rule_dsl, compiled_r,
             error_message, severity, rule_category
      FROM dsl_validation_rules
      WHERE (form_code = ? OR form_code IS NULL)
        AND is_active = 1
        AND (requires_approval = 0 OR approval_status = 'APPROVED')
      ORDER BY field_code, rule_id
    ", params = list(form_code))
  }, error = function(e) {
    data.frame()
  })
}

#' Get All DSL Rules
#'
#' Retrieves all validation rules with optional filtering.
#'
#' @param include_inactive Include inactive rules
#' @param include_pending Include pending approval rules
#' @param form_code Filter by form
#'
#' @return Data frame of rules
#'
#' @keywords internal
#' @export
get_all_dsl_rules <- function(include_inactive = FALSE,
                               include_pending = TRUE,
                               form_code = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    query <- "
      SELECT rule_id, field_code, form_code, rule_name, rule_dsl,
             error_message, severity, rule_category, is_active,
             requires_approval, approval_status, approved_by, approved_at,
             imported_by, imported_at, version
      FROM dsl_validation_rules
      WHERE 1=1
    "

    params <- list()

    if (!include_inactive) {
      query <- paste(query, "AND is_active = 1")
    }

    if (!include_pending) {
      query <- paste(query, "AND (requires_approval = 0 OR approval_status = 'APPROVED')")
    }

    if (!is.null(form_code)) {
      query <- paste(query, "AND (form_code = ? OR form_code IS NULL)")
      params <- append(params, form_code)
    }

    query <- paste(query, "ORDER BY form_code, field_code, rule_id")

    DBI::dbGetQuery(con, query, params = params)
  }, error = function(e) {
    data.frame()
  })
}

# ============================================================================
# Google Sheets Template Generation
# ============================================================================

#' Generate Validation Rules Template Sheet
#'
#' Creates a Google Sheet template with the correct structure for defining
#' validation rules. Includes example rules and documentation.
#'
#' @param sheet_name Name for the new Google Sheet
#' @param include_examples Include example validation rules
#'
#' @return List with sheet URL if successful
#'
#'
#' @examples
#' \dontrun{
#' # Generate a Google-Sheets-compatible template that the data
#' # manager can fill in with study-specific rules; later
#' # imported via `validation_gsheets_integration`.
#' tmpl <- create_validation_rules_template(
#'   output_path = tempfile(fileext = ".csv")
#' )
#' tmpl$path
#' }
#' @export
create_validation_rules_template <- function(sheet_name = "ZZedc_Validation_Rules",
                                              include_examples = TRUE) {
  if (!requireNamespace("googlesheets4", quietly = TRUE)) {
    return(list(
      success = FALSE,
      error = "Package 'googlesheets4' is required"
    ))
  }

  template_data <- data.frame(
    rule_id = character(0),
    field_code = character(0),
    form_code = character(0),
    rule_name = character(0),
    rule_dsl = character(0),
    error_message = character(0),
    severity = character(0),
    rule_category = character(0),
    is_active = logical(0),
    requires_approval = logical(0),
    notes = character(0),
    stringsAsFactors = FALSE
  )

  if (include_examples) {
    examples <- data.frame(
      rule_id = c("AGE_RANGE", "BP_SYS", "BP_DIA", "WEIGHT_CHANGE",
                  "PREG_SEX", "CONSENT_DATE", "VISIT_WINDOW"),
      field_code = c("age", "bp_systolic", "bp_diastolic", "weight",
                     "pregnant", "consent_date", "visit_date"),
      form_code = c("demographics", "vitals", "vitals", "vitals",
                    "demographics", "enrollment", "visits"),
      rule_name = c("Age eligibility", "Systolic BP range", "Diastolic BP range",
                    "Weight change limit", "Pregnancy requires female",
                    "Consent before enrollment", "Visit within window"),
      rule_dsl = c(
        "between 18 and 65",
        "between 80 and 200",
        "between 40 and 120",
        "within 10% of previous_weight",
        "if pregnant == 'Yes' then sex == 'Female' endif",
        "consent_date <= enrollment_date",
        "visit_date within 7 days of scheduled_date"
      ),
      error_message = c(
        "Age must be between 18 and 65 for study eligibility",
        "Systolic blood pressure must be between 80-200 mmHg",
        "Diastolic blood pressure must be between 40-120 mmHg",
        "Weight change exceeds 10% from previous visit",
        "Only female participants can be marked as pregnant",
        "Consent date must be on or before enrollment date",
        "Visit date must be within 7 days of scheduled date"
      ),
      severity = c("ERROR", "ERROR", "ERROR", "WARNING",
                   "ERROR", "ERROR", "WARNING"),
      rule_category = c("ELIGIBILITY", "FIELD", "FIELD", "CROSS_VISIT",
                        "CROSS_FIELD", "CROSS_FIELD", "CROSS_VISIT"),
      is_active = c(TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE),
      requires_approval = c(TRUE, FALSE, FALSE, FALSE, FALSE, TRUE, FALSE),
      notes = c(
        "Study inclusion criterion",
        "Standard vital signs range",
        "Standard vital signs range",
        "Flags for clinical review",
        "Logical consistency check",
        "Regulatory requirement",
        "Protocol compliance"
      ),
      stringsAsFactors = FALSE
    )
    template_data <- examples
  }

  tryCatch({
    ss <- googlesheets4::gs4_create(sheet_name, sheets = list(validation_rules = template_data))

    syntax_ref <- data.frame(
      syntax = c(
        "between X and Y", "X..Y", ">= X", "<= X", "> X", "< X",
        "== 'value'", "!= 'value'", "in('a', 'b', 'c')", "not in('x', 'y')",
        "required", "if COND then RULE endif", "if COND then RULE else RULE endif",
        "RULE and RULE", "RULE or RULE", "within N days of FIELD",
        "within N% of FIELD", "today", "today + N days"
      ),
      description = c(
        "Value must be between X and Y (inclusive)",
        "Shorthand for between (range)",
        "Value must be greater than or equal to X",
        "Value must be less than or equal to X",
        "Value must be greater than X",
        "Value must be less than X",
        "Value must equal the text 'value'",
        "Value must not equal the text 'value'",
        "Value must be one of the listed options",
        "Value must not be any of the listed options",
        "Field is required (cannot be empty)",
        "Apply rule only if condition is true",
        "Apply one rule if true, another if false",
        "Both rules must pass",
        "At least one rule must pass",
        "Date must be within N days of another date field",
        "Number must be within N% of another field value",
        "Current date reference",
        "Date arithmetic"
      ),
      example = c(
        "between 18 and 65", "1..100", ">= 18", "<= 200", "> 0", "< 300",
        "== 'Female'", "!= 'Unknown'", "in('Yes', 'No')", "not in('N/A', 'Missing')",
        "required", "if age >= 18 then consent required endif",
        "if sex == 'Female' then pregnant in('Yes','No') else pregnant == 'N/A' endif",
        ">= 0 and <= 100", "== 'Yes' or == 'No'",
        "visit_date within 7 days of scheduled_date",
        "weight within 10% of baseline_weight",
        "birth_date <= today", "due_date <= today + 30 days"
      ),
      stringsAsFactors = FALSE
    )
    googlesheets4::sheet_add(ss, sheet = "syntax_reference", .before = 1)
    googlesheets4::sheet_write(syntax_ref, ss, sheet = "syntax_reference")

    list(
      success = TRUE,
      sheet_id = ss,
      url = paste0("https://docs.google.com/spreadsheets/d/", ss),
      message = "Template created successfully"
    )
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

# ============================================================================
# Batch Sync Function
# ============================================================================

#' Sync Validation Rules from Google Sheets
#'
#' Performs a full synchronization of validation rules from Google Sheets,
#' updating the database with any changes.
#'
#' @param sheet_id Google Sheet ID
#' @param user_id User performing sync
#' @param user_role User's role for permission check
#'
#' @return List with sync results
#'
#' @keywords internal
#' @export
sync_dsl_rules_from_gsheets <- function(sheet_id, user_id, user_role) {
  if (!check_dsl_rule_permission(user_role, "edit")) {
    return(list(success = FALSE, error = "Insufficient permissions to sync rules"))
  }

  result <- import_validation_rules_from_gsheets(
    sheet_id = sheet_id,
    imported_by = user_id,
    validate_syntax = TRUE,
    dry_run = FALSE
  )

  if (result$success) {
    log_dsl_rule_action(
      rule_id = "BATCH_SYNC",
      action = "SYNC_FROM_GSHEETS",
      new_value = sprintf("Imported %d rules", result$imported),
      changed_by = user_id
    )
  }

  result
}


# ============================================================================
# End-to-end orchestrator
# ============================================================================

#' Set up a ZZedc study from a Google Sheets workbook
#'
#' One-call orchestrator that initialises an encrypted study
#' database, then imports the user roster, data dictionary
#' (CRF definitions and fields), and validation rules from a
#' Google Sheets workbook. Each tab in the workbook corresponds
#' to one of these artefacts.
#'
#' @param sheet_id Google Sheets ID or URL.
#' @param db_path  Path to the encrypted SQLite database to
#'   create. Required.
#' @param tabs     Named list of tab names. Defaults are
#'   `Study_Users`, `Data_Dictionary`, and `validation_rules`.
#'   Override entries to match the workbook's tab layout.
#' @param imported_by User ID recorded in the audit trail for the
#'   import. Defaults to `"setup_from_gsheets"`.
#' @param overwrite Logical. If `TRUE`, an existing database at
#'   `db_path` is overwritten. Defaults to `FALSE`.
#' @param dry_run  Logical. If `TRUE`, parses and validates the
#'   workbook without writing to the database. Defaults to
#'   `FALSE`.
#'
#' @return List with one element per stage (`database`, `users`,
#'   `forms`, `validation_rules`), each carrying its own
#'   `success` flag, counts, and error list. The top-level
#'   `success` is `TRUE` only if every stage succeeded. The
#'   encryption key (`key`) is included so the caller can
#'   register it with `Sys.setenv(DB_ENCRYPTION_KEY = ...)`
#'   before subsequent operations.
#'
#' @details
#' The Google Sheet must contain three tabs:
#'
#' \describe{
#'   \item{Study_Users}{Columns: `username`, `full_name`, `email`,
#'   `role`, `password_initial`. Optional: `site_id`, `active`.}
#'   \item{Data_Dictionary}{One row per field across all CRFs.
#'   Columns: `form_code`, `field_name`, `field_label`,
#'   `field_type`, `required`. Optional: `validation`,
#'   `description`, `field_order`.}
#'   \item{validation_rules}{Columns expected by
#'   [import_validation_rules_from_gsheets()]: `rule_id`,
#'   `field_code`, `rule_dsl` and the optional columns documented
#'   there.}
#' }
#'
#' Bidirectional sync of validation rules is available via
#' [sync_dsl_rules_from_gsheets()] for ongoing studies.
#'
#' @examples
#' \dontrun{
#' result <- setup_zzedc_from_gsheets(
#'   sheet_id = "1AbC...your-sheet-id...",
#'   db_path  = "~/zzedc_demonstration_trial/data/demonstration_trial.db"
#' )
#' Sys.setenv(DB_ENCRYPTION_KEY = result$key)
#' result$users$imported       # number of users imported
#' result$forms$imported_forms # number of CRFs created
#' result$validation_rules$imported  # number of rules imported
#' }
#'
#' @seealso
#' [import_validation_rules_from_gsheets()] for importing
#' validation rules only; [sync_dsl_rules_from_gsheets()] for
#' incremental synchronisation.
#'
#' @export
setup_zzedc_from_gsheets <- function(
  sheet_id,
  db_path,
  tabs = list(
    users           = "Study_Users",
    data_dictionary = "Data_Dictionary",
    validation      = "validation_rules"
  ),
  imported_by = "setup_from_gsheets",
  overwrite   = FALSE,
  dry_run     = FALSE
) {

  if (!requireNamespace("googlesheets4", quietly = TRUE)) {
    return(list(
      success = FALSE,
      error = paste("Package 'googlesheets4' is required.",
                    "Install with: install.packages('googlesheets4')")
    ))
  }
  if (missing(db_path) || is.null(db_path) || !nzchar(db_path)) {
    return(list(success = FALSE,
                error = "`db_path` is required."))
  }

  result <- list(
    success           = TRUE,
    sheet_id          = sheet_id,
    db_path           = db_path,
    dry_run           = dry_run,
    database          = list(success = FALSE),
    users             = list(success = FALSE, imported = 0),
    forms             = list(success = FALSE,
                              imported_forms  = 0,
                              imported_fields = 0),
    validation_rules  = list(success = FALSE, imported = 0),
    errors            = list()
  )

  # --- Stage 1: database ------------------------------------------
  if (dry_run) {
    result$database <- list(success = TRUE,
                            message = "dry_run: skipped database init")
    db_key <- NA_character_
  } else {
    init_res <- initialize_encrypted_database(
      db_path  = db_path,
      overwrite = overwrite
    )
    result$database <- init_res
    if (!isTRUE(init_res$success)) {
      result$success <- FALSE
      result$errors$database <- init_res$error
      return(result)
    }
    db_key <- init_res$key
    result$key <- db_key
    Sys.setenv(DB_ENCRYPTION_KEY = db_key)
  }

  # --- Stage 2: users ---------------------------------------------
  users_df <- tryCatch(
    googlesheets4::read_sheet(sheet_id, sheet = tabs$users),
    error = function(e) NULL
  )
  if (is.null(users_df) || nrow(users_df) == 0) {
    result$users$success <- TRUE
    result$users$message <- "No users found or tab missing"
  } else {
    # Programmatic user provisioning. The Shiny-internal
    # `save_user_to_db()` is bypassed because it expects a
    # reactive `db_pool` and an admin-UI signature.
    user_errors  <- list()
    n_imported   <- 0L
    salt_default <- "gsheets_setup_salt_change_in_production"
    user_conn    <- if (dry_run) NULL else
      tryCatch(connect_encrypted_db(db_path = db_path,
                                      key = db_key),
                error = function(e) NULL)
    if (!is.null(user_conn)) {
      on.exit(DBI::dbDisconnect(user_conn), add = TRUE)
      ensure_edc_users_table(user_conn)
    }
    for (i in seq_len(nrow(users_df))) {
      row <- users_df[i, ]
      if (dry_run) {
        n_imported <- n_imported + 1L
        next
      }
      if (is.null(user_conn)) {
        user_errors[[as.character(row$username)]] <-
          "encrypted connection unavailable"
        next
      }
      pw <- as.character(row$password_initial %||%
                           row$password %||% "ChangeMe!2026")
      pw_hash <- digest::digest(paste0(pw, salt_default),
                                  algo = "sha256")
      saved <- db_insert_user(
        conn          = user_conn,
        username      = as.character(row$username),
        password_hash = pw_hash,
        full_name     = as.character(row$full_name %||%
                                       row$username),
        email         = as.character(row$email %||% ""),
        role          = as.character(row$role),
        site_id       = as.character(row$site_id %||% "001"),
        active        = TRUE,
        created_by    = "gsheets_setup"
      )
      if (isTRUE(saved$success)) {
        n_imported <- n_imported + 1L
      } else {
        user_errors[[as.character(row$username)]] <- saved$error
      }
    }
    result$users <- list(
      success  = length(user_errors) == 0,
      imported = n_imported,
      errors   = user_errors
    )
    if (length(user_errors) > 0) result$success <- FALSE
  }

  # --- Stage 3: forms (data dictionary) ---------------------------
  dd <- tryCatch(
    googlesheets4::read_sheet(sheet_id, sheet = tabs$data_dictionary),
    error = function(e) NULL
  )
  if (is.null(dd) || nrow(dd) == 0) {
    result$forms$success <- TRUE
    result$forms$message <- "No data dictionary found or tab missing"
  } else {
    form_errors <- list()
    n_forms  <- 0L
    n_fields <- 0L
    for (form_code in unique(as.character(dd$form_code))) {
      fields <- dd[as.character(dd$form_code) == form_code, ]
      if (dry_run) {
        n_forms  <- n_forms + 1L
        n_fields <- n_fields + nrow(fields)
        next
      }
      crf <- tryCatch(
        create_crf_definition(
          crf_code   = toupper(form_code),
          crf_name   = paste(toupper(form_code), "Form"),
          created_by = imported_by
        ),
        error = function(e) list(success = FALSE, error = e$message)
      )
      if (!isTRUE(crf$success)) {
        form_errors[[form_code]] <- crf$error %||% "create_crf_definition failed"
        next
      }
      n_forms <- n_forms + 1L
      for (j in seq_len(nrow(fields))) {
        added <- tryCatch(
          add_form_field(
            design_id   = crf$crf_id,
            field_code  = as.character(fields$field_name[j]),
            field_label = as.character(fields$field_label[j]),
            field_type  = as.character(fields$field_type[j]),
            is_required = isTRUE(as.logical(fields$required[j]))
          ),
          error = function(e) list(success = FALSE, error = e$message)
        )
        if (isTRUE(added$success)) {
          n_fields <- n_fields + 1L
        } else {
          form_errors[[paste(form_code,
                              fields$field_name[j], sep = "/")]] <-
            added$error %||% "add_form_field failed"
        }
      }
    }
    result$forms <- list(
      success         = length(form_errors) == 0,
      imported_forms  = n_forms,
      imported_fields = n_fields,
      errors          = form_errors
    )
    if (length(form_errors) > 0) result$success <- FALSE
  }

  # --- Stage 4: validation rules ----------------------------------
  rules_res <- tryCatch(
    import_validation_rules_from_gsheets(
      sheet_id        = sheet_id,
      sheet_name      = tabs$validation,
      imported_by     = imported_by,
      validate_syntax = TRUE,
      dry_run         = dry_run
    ),
    error = function(e) list(success = FALSE, error = e$message,
                              imported = 0)
  )
  result$validation_rules <- rules_res
  if (!isTRUE(rules_res$success)) result$success <- FALSE

  result
}
