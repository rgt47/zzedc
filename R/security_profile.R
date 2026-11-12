#' Security Profiles
#'
#' A security profile is the single setting that decides how zzedc
#' reacts when a protection it is configured to provide cannot be
#' shown to be active. It exists so that a validation record can cite
#' one value, rather than a scatter of independent flags, and so that
#' no code path silently downgrades protection.
#'
#' @details
#' Three profiles are defined:
#'
#' \describe{
#'   \item{`development`}{Unencrypted storage is allowed without a
#'     warning. Result fields still report the true encryption state.
#'     Intended for tests, demonstrations, and local work with
#'     synthetic data.}
#'   \item{`standard`}{The built-in default. Unencrypted storage is
#'     allowed, but a warning naming the risk is issued once per
#'     database per session, and result fields report the true state.
#'     An AWS KMS failure falls back to `DB_ENCRYPTION_KEY` with a
#'     warning.}
#'   \item{`regulated`}{Fail closed. Storage that cannot be shown to be
#'     encrypted is refused with an error, and an AWS KMS failure is an
#'     error rather than a fallback. Intended for 21 CFR Part 11,
#'     HIPAA, and IRB-governed studies.}
#' }
#'
#' The profile is resolved from the first of these that is set:
#'
#' 1. The R option `zzedc.security_profile`.
#' 2. The environment variable `ZZEDC_SECURITY_PROFILE`.
#' 3. `security: profile:` in `config.yml`, either at the top level
#'    (the `load_db_config()` schema) or under `default:` (the
#'    `config::get()` application schema).
#' 4. The built-in default, `"standard"`.
#'
#' Server-hosted backends (PostgreSQL, MySQL/MariaDB, ClickHouse) are
#' not yet checked for encryption at rest under any profile; that
#' depends on server configuration the package cannot observe. See
#' `encryption_capabilities()` on each adapter, and
#' `docs/encryption-compliance-plan-2026-11-10.md` Phases 1.3 and 1.4.
#'
#' @name security_profile
#' @keywords internal
NULL

.security_profile_levels <- c("development", "standard", "regulated")

#' Resolve the Active Security Profile
#'
#' @param config_path Path to `config.yml` consulted when neither the
#'   option nor the environment variable is set.
#' @param config_profile Optional profile value already read from an
#'   application configuration (for example `cfg$security$profile` from
#'   `config::get()`, which applies environment-specific overrides such
#'   as `production:`). When supplied, it is used in place of reading
#'   `config_path`.
#'
#' @return A list with elements `profile` (one of `"development"`,
#'   `"standard"`, `"regulated"`) and `source` (where it came from:
#'   `"option"`, `"environment"`, `"config.yml"`, or `"default"`).
#'
#' @examples
#' resolve_security_profile()
#'
#' @export
resolve_security_profile <- function(config_path = "./config.yml",
                                     config_profile = NULL) {
  candidates <- list(
    option = getOption("zzedc.security_profile"),
    environment = Sys.getenv("ZZEDC_SECURITY_PROFILE", unset = ""),
    "config.yml" = config_profile %||% .security_profile_from_config(config_path)
  )

  for (src in names(candidates)) {
    value <- candidates[[src]]
    if (!is.null(value) && length(value) == 1 && !is.na(value) &&
        nzchar(value)) {
      value <- tolower(trimws(value))
      if (!value %in% .security_profile_levels) {
        stop(
          "Invalid zzedc security profile '", value, "' (from ", src,
          "). Must be one of: ",
          paste(.security_profile_levels, collapse = ", ")
        )
      }
      # check_storage_encryption() fixes the profile as an option for
      # the session; report where it originally came from, not "option".
      pinned <- .zzedc_env$pinned_profile
      if (src == "option" && !is.null(pinned) && identical(pinned$profile, value)) {
        src <- pinned$source
      }
      return(list(profile = value, source = src))
    }
  }

  list(profile = "standard", source = "default")
}

#' Get the Active Security Profile Name
#'
#' Convenience wrapper around `resolve_security_profile()`.
#'
#' @inheritParams resolve_security_profile
#' @return Character scalar: `"development"`, `"standard"`, or
#'   `"regulated"`.
#'
#' @examples
#' get_security_profile()
#'
#' @export
get_security_profile <- function(config_path = "./config.yml") {
  resolve_security_profile(config_path)$profile
}

#' Read `security: profile:` from a config.yml (internal)
#'
#' Cached by path and modification time, because this is consulted on
#' every encrypted connection.
#'
#' @param config_path Path to `config.yml`.
#' @return Character scalar or `NULL`.
#' @keywords internal
.security_profile_from_config <- function(config_path) {
  if (is.null(config_path) || !file.exists(config_path)) {
    return(NULL)
  }
  if (!requireNamespace("yaml", quietly = TRUE)) {
    return(NULL)
  }

  path <- normalizePath(config_path, winslash = "/", mustWork = FALSE)
  mtime <- as.numeric(file.mtime(path))
  cache <- .zzedc_env$security_profile_config_cache
  if (!is.null(cache) && identical(cache$path, path) &&
      identical(cache$mtime, mtime)) {
    return(cache$value)
  }

  parsed <- tryCatch(yaml::read_yaml(path), error = function(e) NULL)
  value <- parsed$security$profile %||% parsed$default$security$profile

  .zzedc_env$security_profile_config_cache <- list(
    path = path, mtime = mtime, value = value
  )
  value
}

#' Enforce the Encryption-at-Rest Policy (internal)
#'
#' Called wherever zzedc has determined whether a database it is about
#' to use is encrypted. Under `regulated` an unencrypted database is
#' an error; under `standard` it produces one warning per database per
#' session; under `development` it is silent.
#'
#' @param encrypted Logical: whether encryption at rest was shown to be
#'   active. `NA` (could not be determined) is treated as not shown.
#' @param target Character: the database path or description, used in
#'   the message and as the once-per-session warning key.
#' @param reason Character: why encryption is not active, for the
#'   message.
#'
#' @return `invisible(encrypted)`.
#' @keywords internal
enforce_encryption_at_rest <- function(encrypted, target, reason) {
  if (isTRUE(encrypted)) {
    return(invisible(TRUE))
  }

  resolved <- resolve_security_profile()
  msg <- paste0(
    "Database is NOT encrypted at rest: ", target, ". ", reason,
    " (zzedc security profile '", resolved$profile, "', from ",
    resolved$source, ".)"
  )

  if (resolved$profile == "regulated") {
    stop(
      msg,
      " The 'regulated' profile refuses unencrypted storage. Use the ",
      "DuckDB backend with duckdb.encryption_key set, or an RSQLite ",
      "build with SQLCipher/SQLite3MultipleCiphers support.",
      call. = FALSE
    )
  }

  if (resolved$profile == "standard") {
    if (is.null(.zzedc_env$encryption_warned)) {
      .zzedc_env$encryption_warned <- character(0)
    }
    if (!target %in% .zzedc_env$encryption_warned) {
      .zzedc_env$encryption_warned <- c(.zzedc_env$encryption_warned, target)
      # immediate. = TRUE: R otherwise holds a top-level warning until
      # the top-level call returns, and launch_zzedc() does not return
      # while the application runs, so the warning never reached the
      # application's log.
      warning(
        msg,
        " Records in this file are readable by anyone with access to ",
        "it; rely on full-disk encryption and file permissions, or set ",
        "the profile to 'regulated' to refuse this configuration.",
        call. = FALSE, immediate. = TRUE
      )
    }
  }

  invisible(encrypted)
}

#' Check a Deployment's Database Against the Security Profile
#'
#' Startup check for the Shiny application. It resolves the security
#' profile, fixes it for the rest of the R session (so that every later
#' check sees the same profile, whatever the working directory), judges
#' whether the SQLite database is encrypted at rest, and applies the
#' profile: under `regulated` an unencrypted database stops the
#' application from starting.
#'
#' @param db_path Character: path to a SQLite database opened without
#'   a key. Used only when `adapter` is `NULL` (the form used before the
#'   application built its pool from the adapter).
#' @param config_profile Optional profile value from the application's
#'   configuration (`cfg$security$profile`).
#' @param config_path Path to `config.yml`, consulted when
#'   `config_profile` is `NULL`.
#' @param adapter Optional `DatabaseAdapter` the application will open
#'   its pool from. When supplied, the check follows its backend.
#'
#' @return Invisibly, a list with `profile`, `source`, `backend`, and
#'   `encrypted` (`TRUE`, `FALSE`, or `NA` when it cannot be
#'   determined).
#'
#' @details
#' How encryption is judged, by backend:
#'
#' - SQLite: an existing file by its header; a file not yet created by
#'   whether a key is configured and the installed RSQLite can apply it.
#' - DuckDB: an existing file by `verify_database_encryption()`; a file
#'   not yet created by whether `encryption_key` is configured (DuckDB
#'   creates it encrypted or refuses).
#' - In-memory databases hold nothing at rest and pass.
#' - MySQL/MariaDB: by asking InnoDB whether every tablespace of the
#'   study database is encrypted; failing that, by the deployer's
#'   `database.at_rest_attestation`.
#' - PostgreSQL: by the deployer's `database.at_rest_attestation`
#'   (community PostgreSQL exposes no encryption state to query). An
#'   attestation is recorded as such, not as a verification.
#' - PostgreSQL and MySQL/MariaDB, in transit: under `regulated`, the
#'   connection settings must require verified TLS and the live
#'   connection must use it (see `?server_encryption`).
#' - ClickHouse: not checked; the state is `NA`, which `regulated`
#'   refuses.
#'
#' @export
check_storage_encryption <- function(db_path = NULL, config_profile = NULL,
                                     config_path = "./config.yml",
                                     adapter = NULL) {
  resolved <- resolve_security_profile(config_path, config_profile)
  if (is.null(getOption("zzedc.security_profile")) &&
      !nzchar(Sys.getenv("ZZEDC_SECURITY_PROFILE"))) {
    options(zzedc.security_profile = resolved$profile)
    .zzedc_env$pinned_profile <- resolved
  }

  state <- if (is.null(adapter)) {
    .storage_state_sqlite(db_path, key = NULL)
  } else {
    .storage_state_adapter(adapter)
  }
  enforce_encryption_at_rest(state$encrypted, state$target, state$reason)

  message(
    "zzedc security profile: ", resolved$profile, " (from ", resolved$source,
    "); backend: ", state$backend, "; database encrypted at rest: ",
    if (isTRUE(state$encrypted)) "yes" else if (isFALSE(state$encrypted)) "NO" else "not verifiable",
    if (identical(state$basis, "attested")) " (attested by the deployer, not verified)" else ""
  )
  invisible(list(profile = resolved$profile, source = resolved$source,
                 backend = state$backend, encrypted = state$encrypted,
                 basis = state$basis %||% if (is.na(state$encrypted)) "unknown" else "verified",
                 tls = state$tls, reason = state$reason))
}

#' Storage Encryption State for a SQLite File (internal)
#' @keywords internal
.storage_state_sqlite <- function(db_path, key) {
  if (identical(db_path, ":memory:")) {
    return(list(backend = "sqlite", target = db_path, encrypted = TRUE,
                reason = "In-memory database."))
  }
  on_disk <- sqlite_file_is_encrypted(db_path)
  has_key <- !is.null(key) && nzchar(key)
  if (!is.na(on_disk)) {
    return(list(backend = "sqlite", target = db_path, encrypted = on_disk,
                reason = "The file has a plaintext SQLite header."))
  }
  will_encrypt <- has_key && sqlite_cipher_available()
  list(
    backend = "sqlite", target = db_path, encrypted = will_encrypt,
    reason = if (!has_key) {
      "The database does not exist yet and no encryption key is configured."
    } else {
      "The database does not exist yet, and the installed RSQLite cannot apply the configured key."
    }
  )
}

#' Storage Encryption State for an Adapter (internal)
#' @keywords internal
.storage_state_adapter <- function(adapter) {
  backend <- adapter$backend_name()
  if (backend == "sqlite") {
    cfg <- adapter$config$sqlite
    return(.storage_state_sqlite(cfg$path, cfg$encryption_key))
  }
  if (backend == "duckdb") {
    cfg <- adapter$config$duckdb
    if (identical(cfg$path, ":memory:")) {
      return(list(backend = backend, target = cfg$path, encrypted = TRUE,
                  reason = "In-memory database."))
    }
    has_key <- !is.null(cfg$encryption_key) && nzchar(cfg$encryption_key)
    if (!file.exists(cfg$path)) {
      return(list(backend = backend, target = cfg$path, encrypted = has_key,
                  reason = "The database does not exist yet and no duckdb encryption_key is configured."))
    }
    v <- verify_database_encryption(db_path = cfg$path, key = cfg$encryption_key,
                                    adapter = adapter)
    return(list(backend = backend, target = cfg$path, encrypted = isTRUE(v$encrypted),
                reason = v$message))
  }
  if (backend %in% c("postgresql", "mysql")) {
    s <- .check_server_storage(adapter)
    return(list(backend = backend, target = paste(backend, "server"),
                encrypted = s$at_rest, basis = s$at_rest_basis,
                tls = isTRUE(s$tls_live), reason = s$reason))
  }
  list(
    backend = backend, target = paste(backend, "server"), encrypted = NA,
    reason = paste("Encryption at rest on", backend, "is a server setting zzedc cannot verify.")
  )
}

#' Whether the Application Must Be Reached over HTTPS
#'
#' @param cfg Application configuration (`config::get()`).
#' @return `TRUE` when `security.https_only` (or the setup wizard's
#'   `security.enforce_https`) is true, or the security profile is
#'   `regulated`.
#' @export
https_required <- function(cfg) {
  isTRUE(cfg$security$https_only) || isTRUE(cfg$security$enforce_https) ||
    get_security_profile() == "regulated"
}


#' Check That a Shiny Session Arrived over HTTPS
#'
#' Shiny does not provide HTTPS; it must come from a reverse proxy (see
#' `system.file("templates", "nginx-zzedc.conf", package = "zzedc")`).
#' This decides whether a session's connection was protected.
#'
#' @param session The Shiny session.
#' @return A list with `ok` (logical) and `reason`.
#'
#' @details
#' A session is accepted when any of these holds:
#'
#' - the browser connected with `https:`;
#' - the request carries `X-Forwarded-Proto: https` *and* came from the
#'   same machine (`REMOTE_ADDR` is a loopback address), as it does from
#'   a reverse proxy running on the server that terminated TLS. The
#'   header is not trusted from other addresses, since a client reaching
#'   the application directly could set it;
#' - the browser connected to a loopback host name (`localhost`,
#'   `127.0.0.1`, `::1`), whose traffic does not leave the machine.
#'
#' @export
session_https_status <- function(session) {
  loopback <- c("localhost", "127.0.0.1", "::1", "[::1]")
  client <- shiny::isolate(session$clientData)
  protocol <- client$url_protocol %||% ""
  hostname <- client$url_hostname %||% ""
  forwarded <- tolower(session$request$HTTP_X_FORWARDED_PROTO %||% "")
  remote <- session$request$REMOTE_ADDR %||% ""

  if (identical(protocol, "https:")) {
    return(list(ok = TRUE, reason = "https"))
  }
  if (identical(forwarded, "https") && remote %in% c("127.0.0.1", "::1")) {
    return(list(ok = TRUE, reason = "https at a local reverse proxy"))
  }
  if (hostname %in% loopback) {
    return(list(ok = TRUE, reason = "loopback connection"))
  }
  list(ok = FALSE, reason = paste0("connection over ", protocol, " to ", hostname))
}


#' Reset Once-per-Session Encryption Warnings (internal)
#'
#' Used by tests that need to observe the `standard`-profile warning
#' more than once in a session.
#'
#' @return `invisible(NULL)`.
#' @keywords internal
reset_encryption_warnings <- function() {
  .zzedc_env$encryption_warned <- NULL
  invisible(NULL)
}
