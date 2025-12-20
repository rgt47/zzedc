#' Advanced Validation Rules System
#'
#' Provides a domain-specific language (DSL) for defining and executing
#' data validation rules for clinical trial data.
#'
#' @name validation_rules
#' @docType package
NULL

#' @keywords internal
safe_scalar_val <- function(x, default = NA_character_) {
  if (is.null(x) || length(x) == 0) default
  else if (length(x) > 1) paste(x, collapse = "; ")
  else as.character(x)
}

#' Initialize Validation Rules System
#' @return List with success status
#' @export
init_validation_rules <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS validation_rules (
        rule_id INTEGER PRIMARY KEY AUTOINCREMENT,
        rule_code TEXT UNIQUE NOT NULL,
        rule_name TEXT NOT NULL,
        rule_category TEXT NOT NULL,
        rule_type TEXT NOT NULL,
        severity TEXT DEFAULT 'ERROR',
        target_field TEXT,
        target_form TEXT,
        condition_expression TEXT NOT NULL,
        error_message TEXT NOT NULL,
        is_active INTEGER DEFAULT 1,
        execution_order INTEGER DEFAULT 100,
        created_at TEXT DEFAULT (datetime('now')),
        created_by TEXT NOT NULL,
        updated_at TEXT,
        updated_by TEXT
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS validation_results (
        result_id INTEGER PRIMARY KEY AUTOINCREMENT,
        rule_id INTEGER NOT NULL,
        record_id TEXT,
        subject_id TEXT,
        form_name TEXT,
        field_name TEXT,
        field_value TEXT,
        validation_status TEXT NOT NULL,
        error_message TEXT,
        validated_at TEXT DEFAULT (datetime('now')),
        validated_by TEXT,
        resolved INTEGER DEFAULT 0,
        resolved_at TEXT,
        resolved_by TEXT,
        resolution_notes TEXT,
        FOREIGN KEY (rule_id) REFERENCES validation_rules(rule_id)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS validation_rule_sets (
        set_id INTEGER PRIMARY KEY AUTOINCREMENT,
        set_code TEXT UNIQUE NOT NULL,
        set_name TEXT NOT NULL,
        set_description TEXT,
        is_active INTEGER DEFAULT 1,
        created_at TEXT DEFAULT (datetime('now')),
        created_by TEXT NOT NULL
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS validation_set_rules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        set_id INTEGER NOT NULL,
        rule_id INTEGER NOT NULL,
        execution_order INTEGER,
        FOREIGN KEY (set_id) REFERENCES validation_rule_sets(set_id),
        FOREIGN KEY (rule_id) REFERENCES validation_rules(rule_id),
        UNIQUE(set_id, rule_id)
      )
    ")

    list(success = TRUE, message = "Validation rules system initialized")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Rule Categories
#' @return Named character vector
#' @export
get_validation_rule_categories <- function() {
  c(
    REQUIRED = "Required field validation",
    RANGE = "Value range validation",
    FORMAT = "Format/pattern validation",
    CROSS_FIELD = "Cross-field validation",
    DATE = "Date validation",
    LOGIC = "Business logic validation",
    CONSISTENCY = "Data consistency",
    COMPLETENESS = "Completeness checks"
  )
}

#' Get Rule Types
#' @return Named character vector
#' @export
get_validation_rule_types <- function() {
  c(
    NOT_NULL = "Field must not be null",
    RANGE_CHECK = "Value must be within range",
    REGEX_MATCH = "Value must match pattern",
    DATE_RANGE = "Date must be within range",
    COMPARISON = "Compare two fields",
    CONDITIONAL = "Conditional validation",
    LOOKUP = "Value must be in list",
    CUSTOM = "Custom expression"
  )
}

#' Get Severity Levels
#' @return Named character vector
#' @export
get_validation_severities <- function() {
  c(
    ERROR = "Blocks data entry",
    WARNING = "Warning but allows entry",
    INFO = "Informational message"
  )
}

#' Create Validation Rule
#' @param rule_code Unique rule code
#' @param rule_name Rule name
#' @param rule_category Category
#' @param rule_type Type
#' @param condition_expression Validation expression
#' @param error_message Error message
#' @param created_by User creating rule
#' @param severity Severity level
#' @param target_field Target field
#' @param target_form Target form
#' @param execution_order Order of execution
#' @return List with success status
#' @export
create_validation_rule <- function(rule_code, rule_name, rule_category,
                                    rule_type, condition_expression,
                                    error_message, created_by,
                                    severity = "ERROR",
                                    target_field = NULL,
                                    target_form = NULL,
                                    execution_order = 100) {
  tryCatch({
    if (missing(rule_code) || rule_code == "") {
      return(list(success = FALSE, error = "rule_code is required"))
    }
    if (missing(condition_expression) || condition_expression == "") {
      return(list(success = FALSE, error = "condition_expression is required"))
    }

    valid_types <- names(get_validation_rule_types())
    if (!rule_type %in% valid_types) {
      return(list(success = FALSE,
                  error = paste("Invalid rule_type:", rule_type)))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      INSERT INTO validation_rules (
        rule_code, rule_name, rule_category, rule_type, severity,
        target_field, target_form, condition_expression, error_message,
        execution_order, created_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      rule_code, rule_name, rule_category, rule_type, severity,
      safe_scalar_val(target_field), safe_scalar_val(target_form),
      condition_expression, error_message, as.integer(execution_order),
      created_by
    ))

    rule_id <- DBI::dbGetQuery(con, "SELECT last_insert_rowid() as id")$id[1]

    list(success = TRUE, rule_id = rule_id, message = "Rule created")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Validation Rules
#' @param rule_category Optional category filter
#' @param rule_type Optional type filter
#' @param target_form Optional form filter
#' @param include_inactive Include inactive rules
#' @return List with rules
#' @export
get_validation_rules <- function(rule_category = NULL, rule_type = NULL,
                                  target_form = NULL, include_inactive = FALSE) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    query <- "SELECT * FROM validation_rules WHERE 1=1"
    params <- list()

    if (!include_inactive) {
      query <- paste(query, "AND is_active = 1")
    }
    if (!is.null(rule_category)) {
      query <- paste(query, "AND rule_category = ?")
      params <- append(params, list(rule_category))
    }
    if (!is.null(rule_type)) {
      query <- paste(query, "AND rule_type = ?")
      params <- append(params, list(rule_type))
    }
    if (!is.null(target_form)) {
      query <- paste(query, "AND target_form = ?")
      params <- append(params, list(target_form))
    }

    query <- paste(query, "ORDER BY execution_order, rule_code")

    if (length(params) > 0) {
      rules <- DBI::dbGetQuery(con, query, params = params)
    } else {
      rules <- DBI::dbGetQuery(con, query)
    }

    list(success = TRUE, rules = rules, count = nrow(rules))
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Record Validation Result
#' @param rule_id Rule ID
#' @param validation_status PASS or FAIL
#' @param validated_by User validating
#' @param record_id Optional record ID
#' @param subject_id Optional subject ID
#' @param form_name Optional form name
#' @param field_name Optional field name
#' @param field_value Optional field value
#' @param error_message Optional error message
#' @return List with success status
#' @export
record_validation_result <- function(rule_id, validation_status, validated_by,
                                      record_id = NULL, subject_id = NULL,
                                      form_name = NULL, field_name = NULL,
                                      field_value = NULL, error_message = NULL) {
  tryCatch({
    if (!validation_status %in% c("PASS", "FAIL")) {
      return(list(success = FALSE,
                  error = "validation_status must be PASS or FAIL"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      INSERT INTO validation_results (
        rule_id, record_id, subject_id, form_name, field_name,
        field_value, validation_status, error_message, validated_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      rule_id, safe_scalar_val(record_id), safe_scalar_val(subject_id),
      safe_scalar_val(form_name), safe_scalar_val(field_name),
      safe_scalar_val(field_value), validation_status,
      safe_scalar_val(error_message), validated_by
    ))

    list(success = TRUE, message = "Validation result recorded")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Validation Results
#' @param rule_id Optional rule filter
#' @param subject_id Optional subject filter
#' @param validation_status Optional status filter
#' @param include_resolved Include resolved results
#' @return List with results
#' @export
get_validation_results <- function(rule_id = NULL, subject_id = NULL,
                                    validation_status = NULL,
                                    include_resolved = FALSE) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    query <- "SELECT * FROM validation_results WHERE 1=1"
    params <- list()

    if (!include_resolved) {
      query <- paste(query, "AND resolved = 0")
    }
    if (!is.null(rule_id)) {
      query <- paste(query, "AND rule_id = ?")
      params <- append(params, list(rule_id))
    }
    if (!is.null(subject_id)) {
      query <- paste(query, "AND subject_id = ?")
      params <- append(params, list(subject_id))
    }
    if (!is.null(validation_status)) {
      query <- paste(query, "AND validation_status = ?")
      params <- append(params, list(validation_status))
    }

    query <- paste(query, "ORDER BY validated_at DESC")

    if (length(params) > 0) {
      results <- DBI::dbGetQuery(con, query, params = params)
    } else {
      results <- DBI::dbGetQuery(con, query)
    }

    list(success = TRUE, results = results, count = nrow(results))
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Resolve Validation Error
#' @param result_id Result ID
#' @param resolved_by User resolving
#' @param resolution_notes Notes on resolution
#' @return List with success status
#' @export
resolve_validation_error <- function(result_id, resolved_by, resolution_notes) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      UPDATE validation_results
      SET resolved = 1, resolved_at = ?, resolved_by = ?, resolution_notes = ?
      WHERE result_id = ?
    ", params = list(
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      resolved_by, resolution_notes, result_id
    ))

    list(success = TRUE, message = "Validation error resolved")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Create Validation Rule Set
#' @param set_code Unique set code
#' @param set_name Set name
#' @param created_by User creating set
#' @param set_description Optional description
#' @return List with success status
#' @export
create_validation_rule_set <- function(set_code, set_name, created_by,
                                        set_description = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      INSERT INTO validation_rule_sets (set_code, set_name, set_description,
                                        created_by)
      VALUES (?, ?, ?, ?)
    ", params = list(set_code, set_name, safe_scalar_val(set_description),
                     created_by))

    set_id <- DBI::dbGetQuery(con, "SELECT last_insert_rowid() as id")$id[1]

    list(success = TRUE, set_id = set_id, message = "Rule set created")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Add Rule to Set
#' @param set_id Set ID
#' @param rule_id Rule ID
#' @param execution_order Optional execution order
#' @return List with success status
#' @export
add_rule_to_set <- function(set_id, rule_id, execution_order = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      INSERT INTO validation_set_rules (set_id, rule_id, execution_order)
      VALUES (?, ?, ?)
    ", params = list(
      set_id, rule_id,
      if (is.null(execution_order)) NA_integer_ else as.integer(execution_order)
    ))

    list(success = TRUE, message = "Rule added to set")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Rule Sets
#' @param include_inactive Include inactive sets
#' @return List with rule sets
#' @export
get_validation_rule_sets <- function(include_inactive = FALSE) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    if (include_inactive) {
      sets <- DBI::dbGetQuery(con, "SELECT * FROM validation_rule_sets")
    } else {
      sets <- DBI::dbGetQuery(con, "
        SELECT * FROM validation_rule_sets WHERE is_active = 1
      ")
    }

    list(success = TRUE, rule_sets = sets, count = nrow(sets))
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Validation Statistics
#' @return List with statistics
#' @export
get_validation_statistics <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    rule_stats <- DBI::dbGetQuery(con, "
      SELECT
        COUNT(*) as total_rules,
        SUM(is_active) as active_rules
      FROM validation_rules
    ")

    result_stats <- DBI::dbGetQuery(con, "
      SELECT
        COUNT(*) as total_results,
        SUM(CASE WHEN validation_status = 'PASS' THEN 1 ELSE 0 END) as passed,
        SUM(CASE WHEN validation_status = 'FAIL' THEN 1 ELSE 0 END) as failed,
        SUM(resolved) as resolved
      FROM validation_results
    ")

    by_severity <- DBI::dbGetQuery(con, "
      SELECT severity, COUNT(*) as count
      FROM validation_rules WHERE is_active = 1
      GROUP BY severity
    ")

    list(
      success = TRUE,
      rules = as.list(rule_stats),
      results = as.list(result_stats),
      by_severity = by_severity
    )
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}
