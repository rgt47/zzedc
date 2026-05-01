#' SQL Dialect Helper Functions
#'
#' Utility functions for generating database-agnostic SQL using adapter dialects.
#'
#' @description
#' These functions abstract common SQL operations that differ between database
#' backends (SQLite, DuckDB, PostgreSQL), enabling database-agnostic code.
#'
#' @details
#' The dialect system works with the DatabaseAdapter classes to provide:
#' - Type mapping (INTEGER, TEXT, BOOLEAN, etc.)
#' - Timestamp functions (NOW(), datetime('now'), etc.)
#' - JSON extraction syntax
#' - Boolean literals
#' - UPSERT syntax variations
#'
#' @keywords internal
#' @name db_dialect
NULL


#' Build CREATE TABLE Statement
#'
#' Generates a CREATE TABLE statement using the appropriate dialect for the
#' current database backend.
#'
#' @param adapter DatabaseAdapter instance
#' @param table_name Name of the table to create
#' @param columns List of column definitions, each with:
#'   - name: Column name
#'   - type: Logical type ("text", "integer", "boolean", "timestamp", "json")
#'   - primary_key: TRUE if this is the primary key (optional)
#'   - auto_increment: TRUE for auto-increment primary key (optional)
#'   - nullable: FALSE if NOT NULL constraint (default TRUE)
#'   - default: Default value expression (optional)
#' @param if_not_exists Add IF NOT EXISTS clause (default TRUE)
#'
#' @return Character string with CREATE TABLE SQL
#'
#' @examples
#' \dontrun{
#'   adapter <- create_db_adapter(config)
#'   sql <- build_create_table(adapter, "users", list(
#'     list(name = "id", type = "integer", primary_key = TRUE,
#'          auto_increment = TRUE),
#'     list(name = "email", type = "text", nullable = FALSE),
#'     list(name = "active", type = "boolean", default = TRUE),
#'     list(name = "created_at", type = "timestamp",
#'          default = "CURRENT_TIMESTAMP")
#'   ))
#' }
#'
#' @keywords internal
#' @export
build_create_table <- function(adapter, table_name, columns,
                               if_not_exists = TRUE) {
  dialect <- adapter$dialect()

  col_defs <- vapply(columns, function(col) {
    # Get type from dialect
    col_type <- switch(
      col$type,
      text = dialect$text_type,
      varchar = dialect$varchar_type(col$length %||% 255),
      integer = dialect$integer_type,
      bigint = dialect$bigint_type %||% dialect$integer_type,
      real = dialect$real_type,
      boolean = dialect$boolean_type,
      timestamp = dialect$timestamp_type,
      json = dialect$json_type,
      blob = dialect$blob_type,
      col$type
    )

    # Handle primary key with auto-increment
    if (isTRUE(col$primary_key) && isTRUE(col$auto_increment)) {
      col_def <- sprintf("%s %s", col$name, dialect$auto_increment)
    } else {
      col_def <- sprintf("%s %s", col$name, col_type)

      if (isTRUE(col$primary_key)) {
        col_def <- paste(col_def, "PRIMARY KEY")
      }
    }

    # NOT NULL constraint
    if (isFALSE(col$nullable)) {
      col_def <- paste(col_def, "NOT NULL")
    }

    # Default value
    if (!is.null(col$default)) {
      default_val <- col$default
      # Handle boolean defaults
      if (is.logical(default_val)) {
        default_val <- if (default_val) {
          dialect$boolean_true
        } else {
          dialect$boolean_false
        }
      }
      col_def <- paste(col_def, "DEFAULT", default_val)
    }

    col_def
  }, character(1))

  if_exists_clause <- if (if_not_exists) "IF NOT EXISTS " else ""

  sprintf("CREATE TABLE %s%s (\n  %s\n)",
          if_exists_clause, table_name,
          paste(col_defs, collapse = ",\n  "))
}


#' Build INSERT Statement
#'
#' Generates an INSERT statement with proper placeholder syntax for the
#' current database backend.
#'
#' @param adapter DatabaseAdapter instance
#' @param table_name Name of the table
#' @param columns Character vector of column names
#' @param returning Column name(s) to return (optional, requires backend support)
#'
#' @return Character string with INSERT SQL
#'
#' @examples
#' \dontrun{
#'   adapter <- create_db_adapter(config)
#'   sql <- build_insert(adapter, "users", c("email", "name"), returning = "id")
#'   # SQLite: INSERT INTO users (email, name) VALUES (?, ?) RETURNING id
#'   # PostgreSQL: INSERT INTO users (email, name) VALUES ($1, $2) RETURNING id
#' }
#'
#' @keywords internal
#' @export
build_insert <- function(adapter, table_name, columns, returning = NULL) {
  dialect <- adapter$dialect()

  # Build placeholders
  placeholders <- vapply(seq_along(columns), function(i) {
    dialect$numbered_placeholder(i)
  }, character(1))

  sql <- sprintf("INSERT INTO %s (%s) VALUES (%s)",
                 table_name,
                 paste(columns, collapse = ", "),
                 paste(placeholders, collapse = ", "))

  # Add RETURNING clause if requested and supported
  if (!is.null(returning) && isTRUE(dialect$supports_returning)) {
    returning_cols <- if (is.character(returning)) {
      paste(returning, collapse = ", ")
    } else {
      "*"
    }
    sql <- paste(sql, "RETURNING", returning_cols)
  }

  sql
}


#' Build UPDATE Statement
#'
#' Generates an UPDATE statement with proper placeholder syntax.
#'
#' @param adapter DatabaseAdapter instance
#' @param table_name Name of the table
#' @param set_columns Character vector of columns to update
#' @param where_columns Character vector of columns for WHERE clause
#' @param returning Column name(s) to return (optional)
#'
#' @return Character string with UPDATE SQL
#'
#' @examples
#' \dontrun{
#'   adapter <- create_db_adapter(config)
#'   sql <- build_update(adapter, "users",
#'                       set_columns = c("name", "updated_at"),
#'                       where_columns = c("id"))
#'   # UPDATE users SET name = ?, updated_at = ? WHERE id = ?
#' }
#'
#' @keywords internal
#' @export
build_update <- function(adapter, table_name, set_columns, where_columns,
                         returning = NULL) {
  dialect <- adapter$dialect()

  # Build SET clause
  param_idx <- 1
  set_parts <- vapply(set_columns, function(col) {
    placeholder <- dialect$numbered_placeholder(param_idx)
    param_idx <<- param_idx + 1
    sprintf("%s = %s", col, placeholder)
  }, character(1))

  # Build WHERE clause
  where_parts <- vapply(where_columns, function(col) {
    placeholder <- dialect$numbered_placeholder(param_idx)
    param_idx <<- param_idx + 1
    sprintf("%s = %s", col, placeholder)
  }, character(1))

  sql <- sprintf("UPDATE %s SET %s WHERE %s",
                 table_name,
                 paste(set_parts, collapse = ", "),
                 paste(where_parts, collapse = " AND "))

  # Add RETURNING clause if requested and supported
  if (!is.null(returning) && isTRUE(dialect$supports_returning)) {
    returning_cols <- if (is.character(returning)) {
      paste(returning, collapse = ", ")
    } else {
      "*"
    }
    sql <- paste(sql, "RETURNING", returning_cols)
  }

  sql
}


#' Build UPSERT Statement
#'
#' Generates an INSERT ... ON CONFLICT / INSERT OR REPLACE statement
#' appropriate for the database backend.
#'
#' @param adapter DatabaseAdapter instance
#' @param table_name Name of the table
#' @param columns Character vector of all columns
#' @param conflict_columns Character vector of columns that define uniqueness
#' @param update_columns Character vector of columns to update on conflict
#'
#' @return Character string with UPSERT SQL
#'
#' @examples
#' \dontrun{
#'   adapter <- create_db_adapter(config)
#'   sql <- build_upsert(adapter, "settings",
#'                       columns = c("key", "value", "updated_at"),
#'                       conflict_columns = c("key"),
#'                       update_columns = c("value", "updated_at"))
#' }
#'
#' @keywords internal
#' @export
build_upsert <- function(adapter, table_name, columns, conflict_columns,
                         update_columns) {
  dialect <- adapter$dialect()
  backend <- adapter$backend_name()

  # Build placeholders
  placeholders <- vapply(seq_along(columns), function(i) {
    dialect$numbered_placeholder(i)
  }, character(1))

  if (backend == "postgresql") {
    # PostgreSQL: INSERT ... ON CONFLICT ... DO UPDATE
    conflict_clause <- dialect$upsert_clause(conflict_columns, update_columns)
    sql <- sprintf("INSERT INTO %s (%s) VALUES (%s) %s",
                   table_name,
                   paste(columns, collapse = ", "),
                   paste(placeholders, collapse = ", "),
                   conflict_clause)
  } else {
    # SQLite/DuckDB: INSERT OR REPLACE
    sql <- sprintf("INSERT OR REPLACE INTO %s (%s) VALUES (%s)",
                   table_name,
                   paste(columns, collapse = ", "),
                   paste(placeholders, collapse = ", "))
  }

  sql
}


#' Build Timestamp Expression
#'
#' Returns the appropriate expression for current timestamp based on backend.
#'
#' @param adapter DatabaseAdapter instance
#'
#' @return Character string with timestamp expression
#'
#' @examples
#' \dontrun{
#'   adapter <- create_db_adapter(config)
#'   ts <- timestamp_now(adapter)
#'   # SQLite: datetime('now')
#'   # DuckDB: now()
#'   # PostgreSQL: NOW()
#' }
#'
#' @export
timestamp_now <- function(adapter) {
  adapter$dialect()$timestamp_now
}


#' Build JSON Extract Expression
#'
#' Returns the appropriate JSON extraction syntax for the backend.
#'
#' @param adapter DatabaseAdapter instance
#' @param column Column containing JSON data
#' @param path JSON path to extract
#'
#' @return Character string with JSON extraction expression
#'
#' @examples
#' \dontrun{
#'   adapter <- create_db_adapter(config)
#'   expr <- json_extract(adapter, "metadata", "status")
#'   # SQLite: json_extract(metadata, '$.status')
#'   # DuckDB/PostgreSQL: metadata->>'status'
#' }
#'
#' @keywords internal
#' @export
json_extract <- function(adapter, column, path) {
  adapter$dialect()$json_extract(column, path)
}


#' Build Boolean Literal
#'
#' Returns the appropriate boolean literal for the backend.
#'
#' @param adapter DatabaseAdapter instance
#' @param value Logical TRUE or FALSE
#'
#' @return Character string with boolean literal
#'
#' @examples
#' \dontrun{
#'   adapter <- create_db_adapter(config)
#'   bool_true <- boolean_literal(adapter, TRUE)
#'   # SQLite: "1"
#'   # DuckDB/PostgreSQL: "TRUE"
#' }
#'
#' @keywords internal
#' @export
boolean_literal <- function(adapter, value) {
  dialect <- adapter$dialect()
  if (value) dialect$boolean_true else dialect$boolean_false
}


#' Build String Concatenation
#'
#' Returns the appropriate string concatenation expression for the backend.
#'
#' @param adapter DatabaseAdapter instance
#' @param ... Column names or literals to concatenate
#'
#' @return Character string with concatenation expression
#'
#' @examples
#' \dontrun{
#'   adapter <- create_db_adapter(config)
#'   expr <- concat_strings(adapter, "first_name", "' '", "last_name")
#'   # SQLite: first_name || ' ' || last_name
#'   # DuckDB/PostgreSQL: CONCAT(first_name, ' ', last_name)
#' }
#'
#' @keywords internal
#' @export
concat_strings <- function(adapter, ...) {
  adapter$dialect()$concat(...)
}


#' Get Type Mapping
#'
#' Returns the database-specific type for a logical type name.
#'
#' @param adapter DatabaseAdapter instance
#' @param logical_type One of: "text", "varchar", "integer", "bigint",
#'   "real", "boolean", "timestamp", "json", "blob"
#' @param length For varchar type, the maximum length
#'
#' @return Character string with database-specific type
#'
#' @examples
#' \dontrun{
#'   adapter <- create_db_adapter(config)
#'   get_db_type(adapter, "boolean")
#'   # SQLite: "INTEGER"
#'   # DuckDB/PostgreSQL: "BOOLEAN"
#' }
#'
#' @keywords internal
#' @export
get_db_type <- function(adapter, logical_type, length = NULL) {
  dialect <- adapter$dialect()

  switch(
    logical_type,
    text = dialect$text_type,
    varchar = dialect$varchar_type(length %||% 255),
    integer = dialect$integer_type,
    bigint = dialect$bigint_type %||% dialect$integer_type,
    real = dialect$real_type,
    boolean = dialect$boolean_type,
    timestamp = dialect$timestamp_type,
    json = dialect$json_type,
    blob = dialect$blob_type,
    stop("Unknown logical type: ", logical_type)
  )
}


# Null coalescing operator
`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}
