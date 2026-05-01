#' Database Configuration
#'
#' Functions for loading and validating database configuration from YAML files.
#'
#' @description
#' This module provides utilities for:
#' - Loading database configuration from config.yml
#' - Validating backend-specific settings
#' - Creating database adapters from configuration
#'
#' @details
#' Supported backends:
#' - sqlite: Single-file, zero configuration, proven stability
#' - duckdb: Fast analytics, columnar storage, Parquet export
#' - postgresql: Multi-server, managed cloud, enterprise deployment
#'
#' @keywords internal
#' @name db_config
NULL


#' Load Database Configuration
#'
#' Loads database configuration from a YAML file with environment variable
#' substitution and validation.
#'
#' @param config_path Path to config.yml file (default: "./config.yml")
#' @param env_prefix Prefix for environment variables (default: "ZZEDC")
#'
#' @return List containing validated database configuration
#'
#' @details
#' Configuration file structure:
#' ```yaml
#' database:
#'   backend: sqlite  # or duckdb, postgresql
#'
#'   sqlite:
#'     path: data/zzedc.db
#'     encryption_key: ${ZZEDC_ENCRYPTION_KEY}
#'
#'   duckdb:
#'     path: data/zzedc.duckdb
#'     threads: 4
#'     memory_limit: 4GB
#'
#'   postgresql:
#'     host: ${ZZEDC_DB_HOST}
#'     port: 5432
#'     name: zzedc
#'     user: ${ZZEDC_DB_USER}
#'     password: ${ZZEDC_DB_PASSWORD}
#'     sslmode: require
#' ```
#'
#' Environment variables in the format \code{$\{VAR_NAME\}} are automatically
#' substituted when loading the configuration.
#'
#' @examples
#' \dontrun{
#'   config <- load_db_config("config.yml")
#'   adapter <- create_db_adapter(config)
#' }
#'
#' @keywords internal
#' @export
load_db_config <- function(config_path = "./config.yml", env_prefix = "ZZEDC") {
  if (!file.exists(config_path)) {
    stop("Configuration file not found: ", config_path)
  }

  if (!requireNamespace("yaml", quietly = TRUE)) {
    stop("yaml package required for configuration loading.\n",
         "Install with: install.packages('yaml')")
  }

  # Read raw config
  config_raw <- yaml::read_yaml(config_path)

  # Extract database section
  db_config <- config_raw$database
  if (is.null(db_config)) {
    stop("Configuration file must have a 'database' section")
  }

  # Substitute environment variables
  db_config <- substitute_env_vars(db_config)

  # Determine backend
  backend <- db_config$backend %||% "sqlite"
  db_config$db_backend <- tolower(backend)

  # Validate backend-specific configuration
  validate_db_config(db_config)

  db_config
}


#' Substitute Environment Variables in Configuration
#'
#' Recursively substitutes \code{$\{VAR_NAME\}} patterns with environment variable values.
#'
#' @param x Configuration list or value
#' @return Configuration with substitutions applied
#' @keywords internal
substitute_env_vars <- function(x) {
  if (is.list(x)) {
    lapply(x, substitute_env_vars)
  } else if (is.character(x)) {
    # Match ${VAR_NAME} pattern
    pattern <- "\\$\\{([A-Za-z_][A-Za-z0-9_]*)\\}"
    matches <- gregexpr(pattern, x, perl = TRUE)

    if (matches[[1]][1] != -1) {
      # Extract variable names
      var_names <- regmatches(x, matches)[[1]]
      var_names <- gsub("^\\$\\{|\\}$", "", var_names)

      # Substitute each variable
      for (var_name in var_names) {
        var_value <- Sys.getenv(var_name, unset = NA_character_)
        if (is.na(var_value)) {
          warning("Environment variable not set: ", var_name)
          var_value <- ""
        }
        x <- gsub(sprintf("\\$\\{%s\\}", var_name), var_value, x, fixed = FALSE)
      }
    }
    x
  } else {
    x
  }
}


#' Validate Database Configuration
#'
#' Validates that required settings are present for the selected backend.
#'
#' @param config Database configuration list
#' @return TRUE if valid (stops with error otherwise)
#' @keywords internal
validate_db_config <- function(config) {
  backend <- config$db_backend

  if (backend == "sqlite") {
    if (is.null(config$sqlite$path)) {
      stop("SQLite configuration requires 'sqlite.path'")
    }
  } else if (backend == "duckdb") {
    if (is.null(config$duckdb$path)) {
      stop("DuckDB configuration requires 'duckdb.path'")
    }
  } else if (backend %in% c("postgresql", "postgres")) {
    pg <- config$postgresql
    if (is.null(pg)) {
      stop("PostgreSQL configuration requires 'postgresql' section")
    }
    if (is.null(pg$host)) {
      stop("PostgreSQL configuration requires 'postgresql.host'")
    }
    if (is.null(pg$name)) {
      stop("PostgreSQL configuration requires 'postgresql.name'")
    }
    if (is.null(pg$user)) {
      stop("PostgreSQL configuration requires 'postgresql.user'")
    }
    if (is.null(pg$password)) {
      stop("PostgreSQL configuration requires 'postgresql.password'")
    }
  } else if (backend == "clickhouse") {
    ch <- config$clickhouse
    if (is.null(ch)) {
      stop("ClickHouse configuration requires 'clickhouse' section")
    }
    if (is.null(ch$host)) {
      stop("ClickHouse configuration requires 'clickhouse.host'")
    }
    if (is.null(ch$database)) {
      stop("ClickHouse configuration requires 'clickhouse.database'")
    }
  } else if (backend %in% c("mysql", "mariadb")) {
    my <- config$mysql
    if (is.null(my)) {
      stop("MySQL configuration requires 'mysql' section")
    }
    if (is.null(my$host)) {
      stop("MySQL configuration requires 'mysql.host'")
    }
    if (is.null(my$name)) {
      stop("MySQL configuration requires 'mysql.name'")
    }
    if (is.null(my$user)) {
      stop("MySQL configuration requires 'mysql.user'")
    }
    if (is.null(my$password)) {
      stop("MySQL configuration requires 'mysql.password'")
    }
  } else {
    stop("Unsupported database backend: ", backend,
         "\nSupported backends: sqlite, duckdb, postgresql, ",
         "clickhouse, mysql")
  }

  TRUE
}


#' Create Database Adapter from Config File
#'
#' Convenience function that loads configuration and creates the appropriate
#' database adapter in one step.
#'
#' @param config_path Path to config.yml file (default: "./config.yml")
#'
#' @return DatabaseAdapter subclass instance
#'
#' @examples
#' \dontrun{
#'   adapter <- adapter_from_config("config.yml")
#'   conn <- adapter$connect()
#'   # ... use connection ...
#'   adapter$disconnect(conn)
#' }
#'
#' @keywords internal
#' @export
adapter_from_config <- function(config_path = "./config.yml") {
  config <- load_db_config(config_path)
  create_db_adapter(config)
}


#' Generate Sample Configuration
#'
#' Generates a sample config.yml with documentation for all supported backends.
#'
#' @param backend Which backend to configure: "sqlite" (default), "duckdb",
#'   or "postgresql"
#' @param output_path Where to write the file (default: "./config.yml")
#' @param overwrite Overwrite existing file (default: FALSE)
#'
#' @return Path to created configuration file
#'
#' @examples
#' \dontrun{
#'   generate_sample_config("sqlite", "config.yml")
#'   generate_sample_config("postgresql", "config-prod.yml")
#' }
#'
#' @keywords internal
#' @export
generate_sample_config <- function(backend = "sqlite",
                                   output_path = "./config.yml",
                                   overwrite = FALSE) {
  if (file.exists(output_path) && !overwrite) {
    stop("Configuration file already exists: ", output_path,
         "\nSet overwrite=TRUE to replace it")
  }

  config_template <- switch(
    tolower(backend),
    sqlite = sqlite_config_template(),
    duckdb = duckdb_config_template(),
    postgresql = postgresql_config_template(),
    postgres = postgresql_config_template(),
    clickhouse = clickhouse_config_template(),
    stop("Unknown backend: ", backend)
  )

  writeLines(config_template, output_path)
  message("Configuration file created: ", output_path)

  output_path
}


#' SQLite Configuration Template
#' @return Character string with YAML template
#' @keywords internal
sqlite_config_template <- function() {
  "# ZZedc Database Configuration
# Backend: SQLite (recommended for desktop/single-server deployments)

database:
  backend: sqlite

  sqlite:
    # Path to database file (relative or absolute)
    path: data/zzedc.db

    # Optional: Encryption key for database encryption (requires RSQLCipher)
    # Use environment variable for security
    # encryption_key: ${ZZEDC_ENCRYPTION_KEY}

# Study configuration
study:
  name: My Research Study
  protocol_id: STUDY-001

# Security settings
security:
  session_timeout_minutes: 30
  enforce_https: true
  salt: ${ZZEDC_SALT}
"
}


#' DuckDB Configuration Template
#' @return Character string with YAML template
#' @keywords internal
duckdb_config_template <- function() {
  "# ZZedc Database Configuration
# Backend: DuckDB (recommended for analytics-heavy workloads)

database:
  backend: duckdb

  duckdb:
    # Path to database file (use :memory: for in-memory database)
    path: data/zzedc.duckdb

    # Optional: Number of threads for query execution
    threads: 4

    # Optional: Maximum memory usage
    memory_limit: 4GB

# Study configuration
study:
  name: My Research Study
  protocol_id: STUDY-001

# Security settings
security:
  session_timeout_minutes: 30
  enforce_https: true
  salt: ${ZZEDC_SALT}
"
}


#' PostgreSQL Configuration Template
#' @return Character string with YAML template
#' @keywords internal
postgresql_config_template <- function() {
  "# ZZedc Database Configuration
# Backend: PostgreSQL (recommended for multi-server/cloud deployments)

database:
  backend: postgresql

  postgresql:
    # Database server hostname
    host: ${ZZEDC_DB_HOST}

    # Database server port (default: 5432)
    port: 5432

    # Database name
    name: zzedc

    # Database credentials (use environment variables)
    user: ${ZZEDC_DB_USER}
    password: ${ZZEDC_DB_PASSWORD}

    # SSL mode: disable, allow, prefer, require, verify-ca, verify-full
    sslmode: require

    # Connection pool settings (optional)
    pool_min: 1
    pool_max: 10

# Study configuration
study:
  name: My Research Study
  protocol_id: STUDY-001

# Security settings
security:
  session_timeout_minutes: 30
  enforce_https: true
  salt: ${ZZEDC_SALT}
"
}


#' ClickHouse Configuration Template
#' @return Character string with YAML template
#' @keywords internal
clickhouse_config_template <- function() {
  "# ZZedc Database Configuration
# Backend: ClickHouse (recommended for large-scale analytics)

database:
  backend: clickhouse

  clickhouse:
    # ClickHouse server hostname
    host: ${ZZEDC_CH_HOST}

    # HTTP port (default 8123) or native port (default 9000)
    port: 8123

    # Database name
    database: zzedc

    # Credentials (use environment variables)
    user: ${ZZEDC_CH_USER}
    password: ${ZZEDC_CH_PASSWORD}

    # Use HTTPS connection
    use_https: false

    # Connection pool settings (optional)
    pool_min: 1
    pool_max: 5

# Study configuration
study:
  name: My Research Study
  protocol_id: STUDY-001

# Security settings
security:
  session_timeout_minutes: 30
  enforce_https: true
  salt: ${ZZEDC_SALT}

# ClickHouse-specific settings
clickhouse_options:
  # Table engine for new tables
  default_engine: MergeTree()
  # Batch insert size for optimal performance
  batch_size: 10000
"
}


#' Get Default Configuration for Backend
#'
#' Returns default configuration values for the specified backend.
#' Useful for programmatic configuration without YAML files.
#'
#' @param backend Backend type: "sqlite", "duckdb", or "postgresql"
#' @param ... Override values (e.g., path = "custom.db")
#'
#' @return Configuration list suitable for create_db_adapter()
#'
#' @examples
#' \dontrun{
#'   # SQLite with custom path
#'   config <- default_db_config("sqlite", path = "mydata.db")
#'   adapter <- create_db_adapter(config)
#'
#'   # PostgreSQL with connection details
#'   config <- default_db_config("postgresql",
#'     host = "db.example.com",
#'     name = "zzedc",
#'     user = "app",
#'     password = Sys.getenv("DB_PASSWORD")
#'   )
#' }
#'
#' @keywords internal
#' @export
default_db_config <- function(backend = "sqlite", ...) {
  overrides <- list(...)

  config <- switch(
    tolower(backend),

    sqlite = list(
      db_backend = "sqlite",
      sqlite = list(
        path = overrides$path %||% "data/zzedc.db",
        encryption_key = overrides$encryption_key
      )
    ),

    duckdb = list(
      db_backend = "duckdb",
      duckdb = list(
        path = overrides$path %||% "data/zzedc.duckdb",
        threads = overrides$threads,
        memory_limit = overrides$memory_limit
      )
    ),

    postgresql = list(
      db_backend = "postgresql",
      postgresql = list(
        host = overrides$host %||% "localhost",
        port = overrides$port %||% 5432L,
        name = overrides$name %||% "zzedc",
        user = overrides$user %||% "zzedc",
        password = overrides$password %||% "",
        sslmode = overrides$sslmode %||% "prefer",
        pool_min = overrides$pool_min %||% 1L,
        pool_max = overrides$pool_max %||% 5L
      )
    ),

    mysql = list(
      db_backend = "mysql",
      mysql = list(
        host = overrides$host %||% "localhost",
        port = overrides$port %||% 3306L,
        name = overrides$name %||% "zzedc",
        user = overrides$user %||% "zzedc",
        password = overrides$password %||% "",
        ssl_mode = overrides$ssl_mode,
        pool_min = overrides$pool_min %||% 1L,
        pool_max = overrides$pool_max %||% 5L
      )
    ),

    mariadb = list(
      db_backend = "mariadb",
      mysql = list(
        host = overrides$host %||% "localhost",
        port = overrides$port %||% 3306L,
        name = overrides$name %||% "zzedc",
        user = overrides$user %||% "zzedc",
        password = overrides$password %||% "",
        ssl_mode = overrides$ssl_mode,
        pool_min = overrides$pool_min %||% 1L,
        pool_max = overrides$pool_max %||% 5L
      )
    ),

    postgres = list(
      db_backend = "postgresql",
      postgresql = list(
        host = overrides$host %||% "localhost",
        port = overrides$port %||% 5432L,
        name = overrides$name %||% "zzedc",
        user = overrides$user %||% "zzedc",
        password = overrides$password %||% "",
        sslmode = overrides$sslmode %||% "prefer",
        pool_min = overrides$pool_min %||% 1L,
        pool_max = overrides$pool_max %||% 5L
      )
    ),

    clickhouse = list(
      db_backend = "clickhouse",
      clickhouse = list(
        host = overrides$host %||% "localhost",
        port = overrides$port %||% 8123L,
        database = overrides$database %||% "zzedc",
        user = overrides$user %||% "default",
        password = overrides$password %||% "",
        use_https = overrides$use_https %||% FALSE,
        pool_min = overrides$pool_min %||% 1L,
        pool_max = overrides$pool_max %||% 5L
      )
    ),

    stop("Unknown backend: ", backend,
         "\nSupported backends: sqlite, duckdb, postgresql, clickhouse")
  )

  config
}


# Null coalescing operator
`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}
