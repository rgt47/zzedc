#' Conditional Logic & Dependencies (Feature #30)
#'
#' Show/hide logic, field dependencies, and conditional validation
#' for CRF forms and fields.
#'
#' @name conditional_logic
#' @docType package
NULL

#' @keywords internal
safe_scalar_cl <- function(x, default = NA_character_) {
  if (is.null(x) || length(x) == 0) default
  else if (length(x) > 1) paste(x, collapse = "; ")
  else as.character(x)
}

#' Initialize Conditional Logic System
#' @return List with success status
#' @export
init_conditional_logic <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS field_conditions (
        condition_id INTEGER PRIMARY KEY AUTOINCREMENT,
        condition_name TEXT NOT NULL,
        form_id INTEGER,
        target_field_code TEXT NOT NULL,
        condition_type TEXT NOT NULL,
        source_field_code TEXT NOT NULL,
        operator TEXT NOT NULL,
        comparison_value TEXT,
        action_type TEXT NOT NULL,
        is_active INTEGER DEFAULT 1,
        execution_order INTEGER DEFAULT 1,
        created_at TEXT DEFAULT (datetime('now')),
        created_by TEXT NOT NULL
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS field_dependencies (
        dependency_id INTEGER PRIMARY KEY AUTOINCREMENT,
        parent_field_code TEXT NOT NULL,
        child_field_code TEXT NOT NULL,
        form_id INTEGER,
        dependency_type TEXT NOT NULL,
        dependency_rule TEXT,
        is_required_dependency INTEGER DEFAULT 0,
        created_at TEXT DEFAULT (datetime('now')),
        created_by TEXT NOT NULL
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS conditional_groups (
        group_id INTEGER PRIMARY KEY AUTOINCREMENT,
        group_name TEXT NOT NULL,
        form_id INTEGER,
        logic_operator TEXT DEFAULT 'AND',
        description TEXT,
        created_by TEXT NOT NULL
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS group_conditions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        group_id INTEGER NOT NULL,
        condition_id INTEGER NOT NULL,
        FOREIGN KEY (group_id) REFERENCES conditional_groups(group_id),
        FOREIGN KEY (condition_id) REFERENCES field_conditions(condition_id)
      )
    ")

    list(success = TRUE, message = "Conditional logic system initialized")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Condition Types
#' @return Named character vector
#' @export
get_condition_types <- function() {
  c(
    SHOW_HIDE = "Show or hide target field",
    ENABLE_DISABLE = "Enable or disable target field",
    REQUIRE = "Make target field required",
    VALIDATE = "Apply validation to target field",
    CALCULATE = "Calculate target field value"
  )
}

#' Get Operators
#' @return Named character vector
#' @export
get_condition_operators <- function() {
  c(
    EQUALS = "Equal to value",
    NOT_EQUALS = "Not equal to value",
    GREATER_THAN = "Greater than value",
    LESS_THAN = "Less than value",
    GREATER_EQUAL = "Greater than or equal",
    LESS_EQUAL = "Less than or equal",
    CONTAINS = "Contains value",
    NOT_CONTAINS = "Does not contain value",
    IS_EMPTY = "Is empty or null",
    IS_NOT_EMPTY = "Is not empty",
    IN_LIST = "Is in list of values",
    NOT_IN_LIST = "Is not in list of values"
  )
}

#' Get Action Types
#' @return Named character vector
#' @export
get_action_types <- function() {
  c(
    SHOW = "Show the target field",
    HIDE = "Hide the target field",
    ENABLE = "Enable the target field",
    DISABLE = "Disable the target field",
    REQUIRE = "Make target field required",
    OPTIONAL = "Make target field optional",
    SET_VALUE = "Set target field value",
    CLEAR = "Clear target field value"
  )
}

#' Get Dependency Types
#' @return Named character vector
#' @export
get_dependency_types <- function() {
  c(
    PARENT_CHILD = "Child depends on parent value",
    CASCADING = "Cascading field selection",
    MUTUAL_EXCLUSIVE = "Mutually exclusive fields",
    REQUIRED_IF = "Required if parent has value",
    VALIDATION = "Validation depends on parent"
  )
}

#' Create Field Condition
#' @param condition_name Name
#' @param target_field_code Target field
#' @param condition_type Type
#' @param source_field_code Source field
#' @param operator Operator
#' @param action_type Action type
#' @param created_by User creating
#' @param form_id Optional form ID
#' @param comparison_value Value to compare
#' @param execution_order Order
#' @return List with success status
#' @export
create_field_condition <- function(condition_name, target_field_code,
                                    condition_type, source_field_code,
                                    operator, action_type, created_by,
                                    form_id = NULL, comparison_value = NULL,
                                    execution_order = 1) {
  tryCatch({
    if (missing(condition_name) || condition_name == "") {
      return(list(success = FALSE, error = "condition_name is required"))
    }

    valid_types <- names(get_condition_types())
    if (!condition_type %in% valid_types) {
      return(list(success = FALSE,
                  error = paste("Invalid condition_type:", condition_type)))
    }

    valid_operators <- names(get_condition_operators())
    if (!operator %in% valid_operators) {
      return(list(success = FALSE,
                  error = paste("Invalid operator:", operator)))
    }

    valid_actions <- names(get_action_types())
    if (!action_type %in% valid_actions) {
      return(list(success = FALSE,
                  error = paste("Invalid action_type:", action_type)))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      INSERT INTO field_conditions (
        condition_name, form_id, target_field_code, condition_type,
        source_field_code, operator, comparison_value, action_type,
        execution_order, created_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      condition_name,
      if (is.null(form_id)) NA_integer_ else as.integer(form_id),
      target_field_code, condition_type, source_field_code, operator,
      safe_scalar_cl(comparison_value), action_type,
      as.integer(execution_order), created_by
    ))

    condition_id <- DBI::dbGetQuery(con,
      "SELECT last_insert_rowid() as id")$id[1]

    list(success = TRUE, condition_id = condition_id)
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Create Field Dependency
#' @param parent_field_code Parent field
#' @param child_field_code Child field
#' @param dependency_type Type
#' @param created_by User creating
#' @param form_id Optional form ID
#' @param dependency_rule Optional rule
#' @param is_required_dependency Whether required
#' @return List with success status
#' @export
create_field_dependency <- function(parent_field_code, child_field_code,
                                     dependency_type, created_by,
                                     form_id = NULL, dependency_rule = NULL,
                                     is_required_dependency = FALSE) {
  tryCatch({
    valid_types <- names(get_dependency_types())
    if (!dependency_type %in% valid_types) {
      return(list(success = FALSE,
                  error = paste("Invalid dependency_type:", dependency_type)))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      INSERT INTO field_dependencies (
        parent_field_code, child_field_code, form_id, dependency_type,
        dependency_rule, is_required_dependency, created_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      parent_field_code, child_field_code,
      if (is.null(form_id)) NA_integer_ else as.integer(form_id),
      dependency_type, safe_scalar_cl(dependency_rule),
      as.integer(is_required_dependency), created_by
    ))

    dependency_id <- DBI::dbGetQuery(con,
      "SELECT last_insert_rowid() as id")$id[1]

    list(success = TRUE, dependency_id = dependency_id)
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Create Conditional Group
#' @param group_name Name
#' @param created_by User creating
#' @param form_id Optional form ID
#' @param logic_operator AND or OR
#' @param description Optional description
#' @return List with success status
#' @export
create_conditional_group <- function(group_name, created_by, form_id = NULL,
                                      logic_operator = "AND",
                                      description = NULL) {
  tryCatch({
    if (!logic_operator %in% c("AND", "OR")) {
      return(list(success = FALSE,
                  error = "logic_operator must be AND or OR"))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      INSERT INTO conditional_groups (
        group_name, form_id, logic_operator, description, created_by
      ) VALUES (?, ?, ?, ?, ?)
    ", params = list(
      group_name,
      if (is.null(form_id)) NA_integer_ else as.integer(form_id),
      logic_operator, safe_scalar_cl(description), created_by
    ))

    group_id <- DBI::dbGetQuery(con,
      "SELECT last_insert_rowid() as id")$id[1]

    list(success = TRUE, group_id = group_id)
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Add Condition to Group
#' @param group_id Group ID
#' @param condition_id Condition ID
#' @return List with success status
#' @export
add_condition_to_group <- function(group_id, condition_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      INSERT INTO group_conditions (group_id, condition_id)
      VALUES (?, ?)
    ", params = list(group_id, condition_id))

    list(success = TRUE, message = "Condition added to group")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Field Conditions
#' @param form_id Optional form filter
#' @param target_field_code Optional target field filter
#' @param include_inactive Include inactive conditions
#' @return List with conditions
#' @export
get_field_conditions <- function(form_id = NULL, target_field_code = NULL,
                                  include_inactive = FALSE) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    query <- "SELECT * FROM field_conditions WHERE 1=1"
    params <- list()

    if (!include_inactive) {
      query <- paste(query, "AND is_active = 1")
    }
    if (!is.null(form_id)) {
      query <- paste(query, "AND form_id = ?")
      params <- append(params, list(form_id))
    }
    if (!is.null(target_field_code)) {
      query <- paste(query, "AND target_field_code = ?")
      params <- append(params, list(target_field_code))
    }

    query <- paste(query, "ORDER BY execution_order, condition_name")

    if (length(params) > 0) {
      conditions <- DBI::dbGetQuery(con, query, params = params)
    } else {
      conditions <- DBI::dbGetQuery(con, query)
    }

    list(success = TRUE, conditions = conditions, count = nrow(conditions))
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Field Dependencies
#' @param form_id Optional form filter
#' @param field_code Optional field filter
#' @return List with dependencies
#' @export
get_field_dependencies <- function(form_id = NULL, field_code = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    query <- "SELECT * FROM field_dependencies WHERE 1=1"
    params <- list()

    if (!is.null(form_id)) {
      query <- paste(query, "AND form_id = ?")
      params <- append(params, list(form_id))
    }
    if (!is.null(field_code)) {
      query <- paste(query,
        "AND (parent_field_code = ? OR child_field_code = ?)")
      params <- append(params, list(field_code, field_code))
    }

    if (length(params) > 0) {
      dependencies <- DBI::dbGetQuery(con, query, params = params)
    } else {
      dependencies <- DBI::dbGetQuery(con, query)
    }

    list(success = TRUE, dependencies = dependencies,
         count = nrow(dependencies))
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Dependent Fields
#' @param parent_field_code Parent field code
#' @return List with child fields
#' @export
get_dependent_fields <- function(parent_field_code) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    children <- DBI::dbGetQuery(con, "
      SELECT * FROM field_dependencies
      WHERE parent_field_code = ?
    ", params = list(parent_field_code))

    list(success = TRUE, children = children, count = nrow(children))
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Conditional Groups
#' @param form_id Optional form filter
#' @return List with groups
#' @export
get_conditional_groups <- function(form_id = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    if (is.null(form_id)) {
      groups <- DBI::dbGetQuery(con, "SELECT * FROM conditional_groups")
    } else {
      groups <- DBI::dbGetQuery(con, "
        SELECT * FROM conditional_groups WHERE form_id = ?
      ", params = list(form_id))
    }

    list(success = TRUE, groups = groups, count = nrow(groups))
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Group Conditions
#' @param group_id Group ID
#' @return List with conditions
#' @export
get_group_conditions <- function(group_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    conditions <- DBI::dbGetQuery(con, "
      SELECT gc.*, fc.*
      FROM group_conditions gc
      JOIN field_conditions fc ON gc.condition_id = fc.condition_id
      WHERE gc.group_id = ?
      ORDER BY fc.execution_order
    ", params = list(group_id))

    list(success = TRUE, conditions = conditions, count = nrow(conditions))
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Evaluate Condition
#' @param source_value Value to evaluate
#' @param operator Operator
#' @param comparison_value Value to compare
#' @return Boolean result
#' @export
evaluate_condition <- function(source_value, operator, comparison_value) {
  tryCatch({
    result <- switch(operator,
      EQUALS = source_value == comparison_value,
      NOT_EQUALS = source_value != comparison_value,
      GREATER_THAN = as.numeric(source_value) > as.numeric(comparison_value),
      LESS_THAN = as.numeric(source_value) < as.numeric(comparison_value),
      GREATER_EQUAL = as.numeric(source_value) >= as.numeric(comparison_value),
      LESS_EQUAL = as.numeric(source_value) <= as.numeric(comparison_value),
      CONTAINS = grepl(comparison_value, source_value, fixed = TRUE),
      NOT_CONTAINS = !grepl(comparison_value, source_value, fixed = TRUE),
      IS_EMPTY = is.null(source_value) || source_value == "" ||
                 is.na(source_value),
      IS_NOT_EMPTY = !is.null(source_value) && source_value != "" &&
                     !is.na(source_value),
      IN_LIST = source_value %in% strsplit(comparison_value, ",")[[1]],
      NOT_IN_LIST = !(source_value %in% strsplit(comparison_value, ",")[[1]]),
      FALSE
    )

    list(success = TRUE, result = result)
  }, error = function(e) {
    list(success = FALSE, error = e$message, result = FALSE)
  })
}

#' Deactivate Condition
#' @param condition_id Condition ID
#' @return List with success status
#' @export
deactivate_condition <- function(condition_id) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      UPDATE field_conditions SET is_active = 0
      WHERE condition_id = ?
    ", params = list(condition_id))

    list(success = TRUE, message = "Condition deactivated")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Conditional Logic Statistics
#' @return List with statistics
#' @export
get_conditional_logic_statistics <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    stats <- DBI::dbGetQuery(con, "
      SELECT
        (SELECT COUNT(*) FROM field_conditions WHERE is_active = 1)
          as active_conditions,
        (SELECT COUNT(*) FROM field_dependencies) as dependencies,
        (SELECT COUNT(*) FROM conditional_groups) as groups
    ")

    by_type <- DBI::dbGetQuery(con, "
      SELECT condition_type, COUNT(*) as count
      FROM field_conditions WHERE is_active = 1
      GROUP BY condition_type
    ")

    by_action <- DBI::dbGetQuery(con, "
      SELECT action_type, COUNT(*) as count
      FROM field_conditions WHERE is_active = 1
      GROUP BY action_type
    ")

    list(success = TRUE, statistics = as.list(stats),
         by_type = by_type, by_action = by_action)
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}
