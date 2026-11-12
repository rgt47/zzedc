#' Encryption Checks for Server Databases (PostgreSQL, MySQL/MariaDB)
#'
#' zzedc cannot encrypt a server database's storage; the server does.
#' What it can do, and does at startup, is establish what is known:
#'
#' - **MySQL/MariaDB: checked.** InnoDB reports, per tablespace, whether
#'   it is encrypted. zzedc queries that for the study database's tables
#'   (`information_schema.INNODB_TABLESPACES` on MySQL 8,
#'   `information_schema.INNODB_TABLESPACES_ENCRYPTION` on MariaDB) and
#'   treats the storage as encrypted only if every one is.
#' - **PostgreSQL: attested.** Community PostgreSQL has no table-level
#'   encryption to query; storage is protected by volume or filesystem
#'   encryption, a cloud provider's storage encryption, or a TDE
#'   distribution, none visible from a database connection. The
#'   deployer records which in `config.yml` as
#'   `database.at_rest_attestation` (for example
#'   `"AWS RDS storage encryption, KMS key alias/zzedc-prod"`); zzedc
#'   records that statement in the audit log at startup and in the
#'   validation report. An attestation is the deployer's statement, not
#'   a measurement, and is labeled as such everywhere it appears.
#' - **TLS.** Under the `regulated` profile the connection settings
#'   must require a verified TLS connection (`sslmode` `verify-full` or
#'   `verify-ca`; `ssl_mode` `VERIFY_IDENTITY` or `VERIFY_CA`), and the
#'   live connection is checked to be using TLS.
#'
#' @name server_encryption
#' @keywords internal
NULL


#' Decide MySQL/MariaDB At-Rest State from InnoDB Rows (internal)
#'
#' @param rows Data frame with column `encrypted` (logical), one row per
#'   tablespace of the study database; `NULL` if the query failed.
#' @return `TRUE` if there is at least one tablespace and all are
#'   encrypted, `FALSE` if any is not, `NA` if unknown.
#' @keywords internal
.mysql_encryption_from_rows <- function(rows) {
  if (is.null(rows) || nrow(rows) == 0) return(NA)
  all(as.logical(rows$encrypted))
}


#' Query InnoDB Tablespace Encryption for the Study Database (internal)
#'
#' @param conn Connection to the MySQL/MariaDB server.
#' @param dbname The study database's name.
#' @return Data frame with `name` and `encrypted`, or `NULL` when neither
#'   the MySQL 8 nor the MariaDB view is available.
#' @keywords internal
.mysql_tablespace_encryption <- function(conn, dbname) {
  like <- paste0(dbname, "/%")
  mysql8 <- tryCatch(DBI::dbGetQuery(conn, "
    SELECT NAME AS name, ENCRYPTION AS enc
    FROM information_schema.INNODB_TABLESPACES WHERE NAME LIKE ?
  ", params = list(like)), error = function(e) NULL)
  if (!is.null(mysql8) && nrow(mysql8) > 0) {
    return(data.frame(name = mysql8$name, encrypted = toupper(mysql8$enc) == "Y"))
  }
  maria <- tryCatch(DBI::dbGetQuery(conn, "
    SELECT NAME AS name, ENCRYPTION_SCHEME AS scheme
    FROM information_schema.INNODB_TABLESPACES_ENCRYPTION WHERE NAME LIKE ?
  ", params = list(like)), error = function(e) NULL)
  if (!is.null(maria) && nrow(maria) > 0) {
    return(data.frame(name = maria$name, encrypted = as.integer(maria$scheme) > 0))
  }
  NULL
}


#' Whether Connection Settings Require Verified TLS (internal)
#' @param backend `"postgresql"` or `"mysql"`.
#' @param section The backend's configuration section.
#' @return Logical.
#' @keywords internal
.tls_mode_verified <- function(backend, section) {
  if (backend == "postgresql") {
    (section$sslmode %||% "") %in% c("verify-full", "verify-ca")
  } else {
    toupper(section$ssl_mode %||% "") %in% c("VERIFY_IDENTITY", "VERIFY_CA")
  }
}


#' Encryption State of a Server Database (internal)
#'
#' Combines the configuration, the deployer's attestation, and (when a
#' connection is given) the server's own reports.
#'
#' @param backend `"postgresql"` or `"mysql"`.
#' @param section The backend's configuration section.
#' @param tablespaces Result of `.mysql_tablespace_encryption()`, or
#'   `NULL`.
#' @param tls_live Logical or `NA`: whether the live connection uses TLS.
#' @return List with `at_rest` (`TRUE`/`FALSE`/`NA`), `at_rest_basis`
#'   (`"verified"`, `"attested"`, or `"unknown"`), `tls_required_by_config`,
#'   `tls_live`, and `reason`.
#' @keywords internal
.server_storage_state <- function(backend, section, tablespaces = NULL, tls_live = NA) {
  attestation <- section$at_rest_attestation
  has_attestation <- !is.null(attestation) && nzchar(attestation)
  measured <- if (backend == "mysql") .mysql_encryption_from_rows(tablespaces) else NA

  if (isTRUE(measured)) {
    at_rest <- TRUE
    basis <- "verified"
    reason <- "InnoDB reports every study tablespace encrypted."
  } else if (isFALSE(measured)) {
    at_rest <- FALSE
    basis <- "verified"
    unencrypted <- tablespaces$name[!tablespaces$encrypted]
    reason <- paste0("InnoDB reports unencrypted tablespaces: ",
                     paste(utils::head(unencrypted, 5), collapse = ", "),
                     if (length(unencrypted) > 5) ", ..." else "", ".")
  } else if (has_attestation) {
    at_rest <- TRUE
    basis <- "attested"
    reason <- paste0("Attested by the deployer (not verified by zzedc): ", attestation)
  } else {
    at_rest <- NA
    basis <- "unknown"
    reason <- paste0(
      "Encryption at rest on ", backend, " cannot be checked from a connection",
      if (backend == "mysql") " (InnoDB encryption views not available)" else "",
      "; record the mechanism as database.at_rest_attestation in config.yml."
    )
  }

  list(
    at_rest = at_rest, at_rest_basis = basis,
    tls_required_by_config = .tls_mode_verified(backend, section),
    tls_live = tls_live, reason = reason
  )
}


#' Check a Server Database Against the Security Profile (internal)
#'
#' Called at startup by `check_storage_encryption()` for PostgreSQL and
#' MySQL/MariaDB. Encryption at rest is then judged by
#' `enforce_encryption_at_rest()` like every other backend; TLS is
#' checked here.
#'
#' @param adapter The `PostgreSQLAdapter` or `MySQLAdapter`.
#' @param profile The active security profile.
#' @return The state from `.server_storage_state()`. Under `regulated`,
#'   stops when the connection settings do not require verified TLS or
#'   the live connection is not using TLS.
#' @keywords internal
.check_server_storage <- function(adapter, profile = get_security_profile()) {
  backend <- adapter$backend_name()
  section <- adapter$config[[backend]]
  conn <- tryCatch(adapter$connect(), error = function(e) e)
  if (inherits(conn, "error")) {
    stop("Could not connect to the ", backend, " server to check encryption: ",
         conditionMessage(conn), call. = FALSE)
  }
  on.exit(adapter$disconnect(conn), add = TRUE)

  tablespaces <- if (backend == "mysql") .mysql_tablespace_encryption(conn, section$name) else NULL
  tls_live <- tryCatch(isTRUE(adapter$is_ssl_connected(conn)), error = function(e) NA)
  state <- .server_storage_state(backend, section, tablespaces, tls_live)
  .enforce_server_tls(state, backend, profile)
  state
}


#' Apply the TLS Rule to a Server Database State (internal)
#' @param state From `.server_storage_state()`.
#' @param backend `"postgresql"` or `"mysql"`.
#' @param profile The active security profile.
#' @return `invisible(TRUE)`; stops under `regulated` on a TLS problem,
#'   warns under `standard`.
#' @keywords internal
.enforce_server_tls <- function(state, backend, profile) {
  problems <- c(
    if (!state$tls_required_by_config) paste0(
      "The connection settings do not require verified TLS (set ",
      if (backend == "postgresql") "sslmode: verify-full" else "ssl_mode: VERIFY_IDENTITY",
      " under database: in config.yml)."),
    if (!isTRUE(state$tls_live)) "The live connection to the database server is not using TLS."
  )
  if (length(problems) == 0) return(invisible(TRUE))
  msg <- paste(problems, collapse = " ")
  if (profile == "regulated") {
    stop("The 'regulated' security profile refuses this ", backend,
         " connection: ", msg, call. = FALSE)
  }
  if (profile == "standard") warning(msg, call. = FALSE, immediate. = TRUE)
  invisible(TRUE)
}
