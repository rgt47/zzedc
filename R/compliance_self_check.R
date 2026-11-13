#' Startup Compliance Self-Check
#'
#' Summarizes, at application start, the security configuration actually
#' in force, and records it in the audit log as a `COMPLIANCE_CHECK`
#' event. The record is evidence for the deployer's validation report,
#' HIPAA risk analysis, and GDPR Article 32 statement: it states what
#' was observed on the running instance, not what the documentation
#' says should be the case.
#'
#' @param cfg Application configuration (`config::get()`), before
#'   `${VAR}` substitution.
#' @param storage The value returned by `check_storage_encryption()`.
#' @param db_config Adapter configuration (`app_database_config(cfg)`).
#' @param audit_protection From `audit_protection_status()`, when known.
#'
#' @return `compliance_self_check()` returns a named list:
#' \describe{
#'   \item{profile, profile_source}{Active security profile and where it
#'     was set.}
#'   \item{backend}{Database backend.}
#'   \item{at_rest}{`"yes"`, `"no"`, or `"unknown"`.}
#'   \item{at_rest_mechanism}{`"package-enforced"` (SQLite cipher or
#'     DuckDB encryption, verified on the file), `"server-verified"`
#'     (InnoDB reports the tablespaces encrypted),
#'     `"server-attested"` (the deployer's `at_rest_attestation`, not
#'     verified by zzedc), or `"none"`.}
#'   \item{tls}{For server backends, whether the live database
#'     connection uses TLS; `"not applicable"` for file backends.}
#'   \item{key_source}{Where the database key came from (never the key).}
#'   \item{extensions}{For DuckDB, the extension directory and whether
#'     downloads are allowed; otherwise `"not applicable"`.}
#'   \item{https_required}{Whether sessions must arrive over HTTPS.}
#'   \item{audit_protection}{How the audit tables are protected against
#'     change (`"database triggers"`, `"partial triggers"`, `"none"`).}
#'   \item{audit_checkpoints}{Where external audit checkpoints are written
#'     (`audit.checkpoint_dir`), and whether they are keyed, or
#'     `"not configured"`.}
#'   \item{zzedc_version, checked_at}{Package version and time.}
#' }
#' `record_compliance_check()` returns `invisible(TRUE)` when the event
#' was written.
#'
#' @details
#' The audit record is protected by the audit log's hash chain
#' (`verify_audit_integrity()`): altering or deleting it breaks the
#' chain. It is not a digital signature by a key the deployer holds.
#'
#' @examples
#' cfg <- list(database = list(backend = "duckdb",
#'                             encryption_key = "${DB_ENCRYPTION_KEY}"))
#' storage <- list(profile = "regulated", source = "config.yml",
#'                 backend = "duckdb", encrypted = TRUE)
#' str(compliance_self_check(cfg, storage, app_database_config(cfg, tempdir())))
#'
#' @name compliance_self_check
#' @export
compliance_self_check <- function(cfg, storage, db_config,
                                  audit_protection = "unknown") {
  backend <- storage$backend %||% db_config$db_backend
  at_rest <- if (isTRUE(storage$encrypted)) "yes" else if (isFALSE(storage$encrypted)) "no" else "unknown"
  mechanism <- if (at_rest != "yes") {
    "none"
  } else if (backend %in% c("sqlite", "duckdb")) {
    "package-enforced"
  } else if (identical(storage$basis, "attested")) {
    "server-attested"
  } else {
    "server-verified"
  }
  section <- db_config[[db_config$db_backend]] %||% list()

  list(
    profile = storage$profile %||% get_security_profile(),
    profile_source = storage$source %||% "unknown",
    backend = backend,
    at_rest = at_rest,
    at_rest_mechanism = mechanism,
    at_rest_detail = storage$reason %||% "",
    tls = if (backend %in% c("postgresql", "mysql")) {
      if (isTRUE(storage$tls)) "yes" else "no"
    } else {
      "not applicable"
    },
    key_source = .key_source_description(cfg) %||% "no key configured",
    extensions = if (backend == "duckdb") {
      paste0("directory: ", section$extension_directory %||% "DuckDB default",
             "; downloads ", if (duckdb_extension_download_allowed(section)) "allowed" else "not allowed")
    } else {
      "not applicable"
    },
    https_required = https_required(cfg),
    audit_protection = audit_protection,
    audit_checkpoints = if (!is.null(cfg$audit$checkpoint_dir) && nzchar(cfg$audit$checkpoint_dir)) {
      paste0(cfg$audit$checkpoint_dir, if (nzchar(Sys.getenv("ZZEDC_AUDIT_CHECKPOINT_KEY"))) " (keyed)" else " (not keyed)")
    } else {
      "not configured"
    },
    zzedc_version = as.character(utils::packageVersion("zzedc")),
    checked_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
  )
}


#' @rdname compliance_self_check
#' @param check The list from `compliance_self_check()`.
#' @export
record_compliance_check <- function(check) {
  summary <- paste0(
    "Startup compliance check: profile ", check$profile,
    ", backend ", check$backend,
    ", encrypted at rest ", check$at_rest, " (", check$at_rest_mechanism, ")"
  )
  ok <- tryCatch(
    log_audit_event(
      event_type = "COMPLIANCE_CHECK", table_name = "system",
      operation = summary,
      details = as.character(jsonlite::toJSON(check, auto_unbox = TRUE)),
      user_id = "system"
    ),
    error = function(e) FALSE
  )
  invisible(isTRUE(ok))
}
