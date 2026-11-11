#' Database Backends Compared
#'
#' One description of each database backend, used by the launcher's
#' prompt, the setup wizard's tooltips, and the documentation, so the
#' three do not drift apart.
#'
#' @return A data frame with one row per backend and columns `backend`
#'   (the value for `database.backend` in `config.yml`), `label`,
#'   `summary`, `use_when`, `encryption_at_rest`, and `regulated`
#'   (whether the `regulated` security profile accepts it).
#'
#' @examples
#' describe_backends()[, c("backend", "regulated")]
#'
#' @export
describe_backends <- function() {
  data.frame(
    backend = names(.backend_catalog),
    label = vapply(.backend_catalog, `[[`, "", "label"),
    summary = vapply(.backend_catalog, `[[`, "", "summary"),
    use_when = vapply(.backend_catalog, `[[`, "", "use_when"),
    encryption_at_rest = vapply(.backend_catalog, `[[`, "", "encryption"),
    regulated = vapply(.backend_catalog, `[[`, "", "regulated"),
    row.names = NULL,
    stringsAsFactors = FALSE
  )
}

.backend_catalog <- list(
  sqlite = list(
    label = "SQLite",
    summary = paste(
      "One file on this computer, with no database server to run.",
      "The simplest choice for one site and a small team."
    ),
    use_when = paste(
      "Pilot studies, synthetic or de-identified data, and single-site",
      "work with no requirement to encrypt the stored data."
    ),
    encryption = paste(
      "Not encrypted with the standard CRAN build of RSQLite; only an",
      "RSQLite built with SQLCipher can encrypt it."
    ),
    regulated = "Refused, unless RSQLite can encrypt."
  ),
  duckdb = list(
    label = "DuckDB",
    summary = paste(
      "One encrypted file on this computer, with no database server to",
      "run. Recommended when stored data must be encrypted."
    ),
    use_when = paste(
      "Identifiable or regulated data on a single server: 21 CFR Part 11,",
      "HIPAA, or an IRB that requires encryption."
    ),
    encryption = paste(
      "Encrypted with a 256-bit key that you keep outside the project.",
      "Losing the key makes the data unrecoverable."
    ),
    regulated = "Supported."
  ),
  postgresql = list(
    label = "PostgreSQL",
    summary = paste(
      "A database server run by you or your IT department. Suits",
      "multi-site studies and many simultaneous users."
    ),
    use_when = "Institutional deployments with an existing PostgreSQL service.",
    encryption = paste(
      "Configured on the server (disk or volume encryption);",
      "zzedc cannot check it."
    ),
    regulated = paste(
      "Not yet: refused until zzedc can record the server's",
      "encryption setting."
    )
  ),
  mysql = list(
    label = "MySQL / MariaDB",
    summary = paste(
      "A database server run by you or your IT department, common where",
      "REDCap is already in use. Suits multi-site studies."
    ),
    use_when = paste(
      "Institutional deployments with an existing MySQL or MariaDB",
      "service, or migrations from REDCap."
    ),
    encryption = paste(
      "Configured on the server (InnoDB tablespace encryption);",
      "zzedc cannot check it."
    ),
    regulated = paste(
      "Not yet: refused until zzedc can record the server's",
      "encryption setting."
    )
  )
)


#' Write the `database:` Section of an Application config.yml (internal)
#'
#' Produces commented YAML lines for one backend, indented to sit under
#' `default:`. Secrets are never written: the encryption key and server
#' password are `${VAR}` references resolved from the environment by
#' `app_database_config()`.
#'
#' @param backend One of `names(.backend_catalog)`.
#' @param values Optional named list overriding `path`, `host`, `port`,
#'   `name`, `user`, `ssl` (sslmode or ssl_mode), `extension_directory`,
#'   and `pool_size`.
#' @return Character vector of YAML lines.
#' @keywords internal
.database_config_yaml <- function(backend, values = list()) {
  backend <- match.arg(backend, names(.backend_catalog))
  v <- function(name, default) values[[name]] %||% default
  header <- c(
    "  database:",
    "    # Backend: sqlite, duckdb, postgresql, or mysql. Compare them with",
    "    # zzedc::describe_backends().",
    paste0("    backend: ", backend)
  )
  body <- switch(
    backend,
    sqlite = c(
      paste0("    path: ", v("path", "data/zzedc.db")),
      "    # SQLite is encrypted only by an RSQLite build with SQLCipher or",
      "    # SQLite3MultipleCiphers. The standard CRAN build stores it as plain",
      "    # text, which the 'regulated' security profile refuses; to encrypt",
      "    # with CRAN software only, use backend: duckdb.",
      "    # encryption_key: ${DB_ENCRYPTION_KEY}"
    ),
    duckdb = c(
      paste0("    path: ", v("path", "data/zzedc.duckdb")),
      "    # 64 hexadecimal characters (zzedc::generate_db_key()). Keep the key",
      "    # out of this file: set DB_ENCRYPTION_KEY in the environment (for",
      "    # example in ~/.Renviron) or a secrets manager. Losing it makes the",
      "    # data unrecoverable.",
      "    encryption_key: ${DB_ENCRYPTION_KEY}",
      "    # Pre-installed DuckDB extensions (httpfs, icu); populate with",
      "    # zzedc::install_duckdb_extensions(). Required under 'regulated',",
      "    # which does not allow downloads while the application runs.",
      paste0("    extension_directory: ", v("extension_directory", "duckdb_extensions"))
    ),
    postgresql = c(
      paste0("    host: ", v("host", "${ZZEDC_DB_HOST}")),
      paste0("    port: ", v("port", 5432)),
      paste0("    name: ", v("name", "zzedc")),
      paste0("    user: ", v("user", "${ZZEDC_DB_USER}")),
      "    password: ${ZZEDC_DB_PASSWORD}",
      "    # verify-full requires TLS and checks the server's certificate.",
      paste0("    sslmode: ", v("ssl", "verify-full")),
      "    # Encryption at rest is configured on the server; zzedc cannot check",
      "    # it, so the 'regulated' profile refuses server backends for now."
    ),
    mysql = c(
      paste0("    host: ", v("host", "${ZZEDC_DB_HOST}")),
      paste0("    port: ", v("port", 3306)),
      paste0("    name: ", v("name", "zzedc")),
      paste0("    user: ", v("user", "${ZZEDC_DB_USER}")),
      "    password: ${ZZEDC_DB_PASSWORD}",
      "    # VERIFY_IDENTITY requires TLS and checks the server's certificate.",
      paste0("    ssl_mode: ", v("ssl", "VERIFY_IDENTITY")),
      "    # Encryption at rest is InnoDB tablespace encryption on the server;",
      "    # zzedc cannot check it, so the 'regulated' profile refuses server",
      "    # backends for now."
    )
  )
  c(header, body, paste0("    pool_size: ", v("pool_size", 5)))
}


#' Write the `security:` Section of an Application config.yml (internal)
#' @param profile Security profile.
#' @param enforce_https Logical, recorded for when HTTPS enforcement exists.
#' @return Character vector of YAML lines.
#' @keywords internal
.security_config_yaml <- function(profile = "regulated", enforce_https = FALSE) {
  profile <- match.arg(profile, .security_profile_levels)
  c(
    "  security:",
    "    # development, standard, or regulated. 'regulated' refuses a database",
    "    # that cannot be shown to be encrypted at rest. See",
    "    # ?zzedc::resolve_security_profile.",
    paste0("    profile: ", profile),
    "    # true refuses sessions that did not arrive over HTTPS ('regulated'",
    "    # always does). Shiny does not provide HTTPS: use a reverse proxy,",
    "    # e.g. system.file(\"templates\", \"nginx-zzedc.conf\", package = \"zzedc\").",
    paste0("    https_only: ", tolower(as.character(isTRUE(enforce_https))))
  )
}


#' Print the Backend Comparison to the Console (internal)
#' @keywords internal
.print_backend_comparison <- function() {
  d <- describe_backends()
  wrap <- function(label, text) {
    paste0("    ", label, ": ",
           paste(strwrap(text, width = 70, exdent = 6 + nchar(label)), collapse = "\n"))
  }
  for (i in seq_len(nrow(d))) {
    cat("\n", d$label[i], " (backend: ", d$backend[i], ")\n", sep = "")
    cat(wrap("What", d$summary[i]), "\n")
    cat(wrap("Use for", d$use_when[i]), "\n")
    cat(wrap("Encryption", d$encryption_at_rest[i]), "\n")
    cat(wrap("'regulated' profile", d$regulated[i]), "\n")
  }
  cat("\n")
  invisible(d)
}


#' Ask Which Backend a New Study Should Use (internal)
#'
#' @return A backend name, or `"wizard"` to use the setup wizard instead.
#' @keywords internal
.choose_backend_interactive <- function() {
  .print_backend_comparison()
  d <- describe_backends()
  choices <- c(
    paste0(d$label, " (", d$backend, ")"),
    "Use the setup wizard in a web browser instead"
  )
  sel <- utils::menu(choices, title = "Which database should this study use?")
  if (sel == 0) {
    stop("No database chosen; config.yml was not created.", call. = FALSE)
  }
  if (sel == length(choices)) "wizard" else d$backend[sel]
}


#' One-time Preparation After Choosing a Backend (internal)
#'
#' DuckDB: pre-installs its extensions into `duckdb_extensions/` and makes
#' sure an encryption key is available. In an interactive session without
#' `DB_ENCRYPTION_KEY`, a key is generated, shown once, set for this
#' session, and optionally appended to `~/.Renviron` (outside the project,
#' so not beside the data); it is never written to the project directory.
#' Without a key and without an interactive session, it stops with
#' instructions. Server backends: prints what to fill in.
#'
#' @param backend Backend name.
#' @param project_dir Directory holding `config.yml`.
#' @return `invisible(NULL)`.
#' @keywords internal
.prepare_new_backend <- function(backend, project_dir = getwd()) {
  if (backend == "duckdb") {
    # The key first: without one there is nothing to set up, and a
    # non-interactive run should fail before any download.
    if (!nzchar(Sys.getenv("DB_ENCRYPTION_KEY"))) {
      if (!interactive()) {
        stop(
          "DuckDB needs an encryption key. Set DB_ENCRYPTION_KEY (64 hex ",
          "characters; generate one with zzedc::generate_db_key()) before ",
          "launching, for example in ~/.Renviron or a secrets manager.",
          call. = FALSE
        )
      }
      key <- generate_db_key()
      Sys.setenv(DB_ENCRYPTION_KEY = key)
      message(
        "\nA new database encryption key was generated:\n\n    ", key, "\n\n",
        "Save it now in a password manager or secrets manager. It is the only ",
        "way to open the study database: losing it makes the data ",
        "unrecoverable. It has been set for this R session only."
      )
      answer <- readline(
        "Also add DB_ENCRYPTION_KEY to ~/.Renviron so future R sessions set it? (y/n): "
      )
      if (tolower(substr(answer, 1, 1)) == "y") {
        renviron <- path.expand("~/.Renviron")
        existed <- file.exists(renviron)
        cat(sprintf("DB_ENCRYPTION_KEY=%s\n", key), file = renviron, append = TRUE)
        if (!existed) Sys.chmod(renviron, mode = "0600")
        message("Added to ", renviron, ". Anyone who can read that file can ",
                "decrypt the study database; for regulated data prefer a ",
                "secrets manager.")
      }
    }

    ext_dir <- file.path(project_dir, "duckdb_extensions")
    if (length(list.files(ext_dir, recursive = TRUE, pattern = "duckdb_extension$")) == 0) {
      message("Installing DuckDB extensions (httpfs, icu) into ", ext_dir,
              ". This one-time download is needed because the 'regulated' ",
              "profile does not allow downloads while the application runs.")
      installed <- tryCatch(install_duckdb_extensions(ext_dir), error = function(e) e)
      if (inherits(installed, "error") || !all(installed$loads_offline)) {
        message("Could not install the DuckDB extensions",
                if (inherits(installed, "error")) paste0(": ", conditionMessage(installed)),
                ". On a machine with internet access and the same platform, run ",
                "zzedc::install_duckdb_extensions() and copy the directory here.")
      }
    }
  } else if (backend %in% c("postgresql", "mysql")) {
    message(
      "\nEdit the database section of config.yml (server, database name), and ",
      "set ZZEDC_DB_HOST, ZZEDC_DB_USER, and ZZEDC_DB_PASSWORD in the ",
      "environment. Note: the 'regulated' profile refuses server backends ",
      "until zzedc can record the server's encryption setting; use DuckDB, ",
      "or set security.profile to 'standard', in the meantime."
    )
  }
  invisible(NULL)
}
