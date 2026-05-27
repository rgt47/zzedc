#!/usr/bin/env Rscript
# edc-init.R
#
# Generalised zzedc project initialiser using the `gum` TUI toolkit.
# Writes zzedc_config.yml and Study_Users.csv for any zzedc project.
# Optionally copies Data_Dictionary.csv and validation_rules.csv from
# caller-supplied source paths (--dd-csv, --rules-csv).
#
# Install gum:
#   brew install gum          # macOS
#   go install github.com/charmbracelet/gum@latest
#
# Three modes:
#   tui     Interactive gum prompts. Falls back to readline if gum absent.
#   config  Plain-text key = value file.
#   sheets  Google Sheets workbook.
#
# Usage:
#   Rscript edc-init.R
#   Rscript edc-init.R --mode tui
#   Rscript edc-init.R --mode config --file study.conf
#   Rscript edc-init.R --mode sheets --url <SHEET_URL>
#   Rscript edc-init.R --mode config --file study.conf \
#           --dd-csv vignettes/prazosin-small/Data_Dictionary.csv \
#           --rules-csv vignettes/prazosin-small/validation_rules.csv

for (pkg in c("cli", "yaml")) {
  if (!requireNamespace(pkg, quietly = TRUE))
    stop(sprintf("Required package '%s' is not installed.", pkg), call. = FALSE)
}
library(cli)
library(yaml)

# ---------------------------------------------------------------------------
# gum detection and wrappers
# ---------------------------------------------------------------------------

has_gum <- function() nzchar(Sys.which("gum"))

gum_input <- function(placeholder = "", header = "", value = "") {
  tmp <- tempfile()
  on.exit(unlink(tmp), add = TRUE)
  cmd <- paste("gum input --placeholder", shQuote(placeholder))
  if (nzchar(header)) cmd <- paste(cmd, "--header", shQuote(header))
  if (nzchar(value))  cmd <- paste(cmd, "--value",  shQuote(value))
  ret <- system(paste(cmd, ">", shQuote(tmp)))
  if (ret != 0) stop("Cancelled.", call. = FALSE)
  out <- readLines(tmp, warn = FALSE)
  if (length(out) == 0) "" else out[[1]]
}

gum_password <- function(placeholder = "Password", header = "") {
  tmp <- tempfile()
  on.exit(unlink(tmp), add = TRUE)
  cmd <- paste("gum input --password --placeholder", shQuote(placeholder))
  if (nzchar(header)) cmd <- paste(cmd, "--header", shQuote(header))
  ret <- system(paste(cmd, ">", shQuote(tmp)))
  if (ret != 0) stop("Cancelled.", call. = FALSE)
  out <- readLines(tmp, warn = FALSE)
  if (length(out) == 0) "" else out[[1]]
}

gum_choose <- function(items, header = "", limit = 1) {
  tmp <- tempfile()
  on.exit(unlink(tmp), add = TRUE)
  item_args <- paste(vapply(items, shQuote, ""), collapse = " ")
  cmd <- paste("gum choose --limit", limit)
  if (nzchar(header)) cmd <- paste(cmd, "--header", shQuote(header))
  cmd <- paste(cmd, item_args)
  ret <- system(paste(cmd, ">", shQuote(tmp)))
  if (ret != 0) stop("Cancelled.", call. = FALSE)
  out <- readLines(tmp, warn = FALSE)
  if (length(out) == 0) stop("Cancelled.", call. = FALSE)
  out
}

gum_confirm <- function(prompt) {
  system(paste("gum confirm", shQuote(prompt))) == 0
}

gum_header <- function(text) {
  system(paste(
    "gum style --foreground 212 --border rounded --padding '0 1' --margin '0 0'",
    shQuote(text)
  ))
  invisible(NULL)
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

is_valid_email     <- function(x) grepl("^[^@]+@[^@]+\\.[^@]+$", x)
is_strong_password <- function(x) {
  nchar(x) >= 8 && grepl("[A-Z]", x) && grepl("[0-9]", x) &&
    grepl("[^A-Za-z0-9]", x)
}

rl_prompt <- function(label, default = NULL) {
  disp <- if (!is.null(default) && nzchar(default))
    sprintf("%s [%s]: ", label, default) else sprintf("%s: ", label)
  if (interactive()) {
    val <- readline(disp)
  } else {
    cat(disp)
    val <- readLines(con = stdin(), n = 1L, warn = FALSE)
    if (length(val) == 0L) val <- ""
  }
  if (!nzchar(val) && !is.null(default)) val <- default
  val
}

default_db_name <- function(protocol_id) {
  paste0(tolower(gsub("[^a-z0-9]", "-", tolower(protocol_id))), ".db")
}

# ---------------------------------------------------------------------------
# TUI: gum implementation
# ---------------------------------------------------------------------------

collect_tui_gum <- function() {
  cli_h1("zzedc Project Initialisation")
  cli_bullets(c(
    "i" = "Type a value and press {.strong Enter} to accept.",
    "i" = "Fields with a pre-filled value can be accepted as-is or overwritten.",
    "i" = "Press {.strong Ctrl-C} at any time to abort without writing files."
  ))
  cat("\n")

  # ── Study ──────────────────────────────────────────────────────────────
  gum_header("Study Information")
  repeat {
    study_name <- gum_input(
      placeholder = "e.g. Prazosin Sleep Study",
      header      = "Study name"
    )
    if (nzchar(study_name)) break
    cat("Study name is required.\n")
  }
  repeat {
    protocol_id <- gum_input(
      placeholder = paste0("e.g. PRAZ-S-", format(Sys.Date(), "%Y")),
      header      = "Protocol ID"
    )
    if (nzchar(protocol_id)) break
    cat("Protocol ID is required.\n")
  }
  enroll_raw <- gum_input(placeholder = "e.g. 50", header = "Target enrollment")
  target_enrollment <- suppressWarnings(as.integer(enroll_raw))
  if (is.na(target_enrollment) || target_enrollment < 1) {
    cat("Invalid enrollment; using 1.\n")
    target_enrollment <- 1L
  }
  phase <- tryCatch(
    gum_choose(
      items  = c("Phase I", "Phase II", "Phase III", "Observational", "Other"),
      header = "Study phase"
    ),
    error = function(e) "Observational"
  )
  db_name <- gum_input(
    placeholder = default_db_name(protocol_id),
    header      = "Database filename (used in next-steps output)",
    value       = default_db_name(protocol_id)
  )
  if (!nzchar(db_name)) db_name <- default_db_name(protocol_id)

  # ── PI ─────────────────────────────────────────────────────────────────
  gum_header("Principal Investigator")
  repeat {
    pi_name <- gum_input(placeholder = "e.g. Professor Smith", header = "PI full name")
    if (nzchar(pi_name)) break
    cat("PI name is required.\n")
  }
  repeat {
    pi_email <- gum_input(
      placeholder = "e.g. psmith@university.edu", header = "PI email"
    )
    if (is_valid_email(pi_email)) break
    cat("Enter a valid email address.\n")
  }

  # ── Admin ───────────────────────────────────────────────────────────────
  gum_header("Admin Account")
  default_user <- gsub("[^a-z0-9]", "", tolower(strsplit(pi_name, " ")[[1]][[1]]))
  username <- gum_input(
    placeholder = default_user,
    header      = "Admin username (no spaces, lowercase)",
    value       = default_user
  )
  fullname <- gum_input(
    placeholder = pi_name, header = "Admin full name", value = pi_name
  )
  repeat {
    email <- gum_input(
      placeholder = pi_email, header = "Admin email", value = pi_email
    )
    if (is_valid_email(email)) break
    cat("Enter a valid email address.\n")
  }
  repeat {
    password <- gum_password(
      placeholder = "min 8 chars, 1 upper, 1 digit, 1 symbol",
      header      = "Admin password"
    )
    if (is_strong_password(password)) break
    cat("Password must be 8+ chars with uppercase, digit, and symbol.\n")
  }
  repeat {
    confirm <- gum_password(
      placeholder = "Re-enter password", header = "Confirm password"
    )
    if (confirm == password) break
    cat("Passwords do not match. Re-enter the password.\n")
    repeat {
      password <- gum_password(
        placeholder = "min 8 chars, 1 upper, 1 digit, 1 symbol",
        header      = "Admin password"
      )
      if (is_strong_password(password)) break
      cat("Password does not meet complexity requirements.\n")
    }
  }
  admin_site <- gum_input(
    placeholder = "ALL",
    header      = "Admin site ID (ALL for multi-site; site code for single-site)",
    value       = "ALL"
  )

  # ── Coordinators ────────────────────────────────────────────────────────
  gum_header("Coordinator Accounts")
  coordinators <- list()
  repeat {
    prompt_text <- if (length(coordinators) == 0)
      "Add a coordinator account?"
    else
      "Add another coordinator account?"
    if (!gum_confirm(prompt_text)) break
    repeat {
      cu <- gum_input(
        placeholder = "e.g. ucsd_coord", header = "Coordinator username"
      )
      if (nzchar(cu)) break
      cat("Username is required.\n")
    }
    cn <- gum_input(placeholder = "Full name", header = "Coordinator full name")
    repeat {
      ce <- gum_input(
        placeholder = "email@domain.edu", header = "Coordinator email"
      )
      if (is_valid_email(ce)) break
      cat("Enter a valid email address.\n")
    }
    cp <- gum_input(
      placeholder = "TempPass!2026",
      header      = "Initial password",
      value       = "TempPass!2026"
    )
    cs <- gum_input(placeholder = "e.g. UCSD", header = "Coordinator site ID")
    coordinators <- c(coordinators, list(list(
      username = cu, fullname = cn, email = ce,
      password = cp, site_id  = cs
    )))
  }

  # ── Security ────────────────────────────────────────────────────────────
  gum_header("Security Settings")
  timeout_raw <- gum_input(
    placeholder = "60", header = "Session timeout (minutes)", value = "60"
  )
  timeout <- suppressWarnings(as.integer(timeout_raw))
  if (is.na(timeout) || timeout < 5) {
    cat("Invalid timeout; using 60 minutes.\n")
    timeout <- 60L
  }

  # ── Output ──────────────────────────────────────────────────────────────
  gum_header("Output Location")
  out_dir <- gum_input(
    placeholder = ".",
    header      = "Output directory (files will be written here)",
    value       = "."
  )

  list(
    study_name        = study_name,
    protocol_id       = protocol_id,
    target_enrollment = target_enrollment,
    phase             = phase,
    db_name           = db_name,
    pi_name           = pi_name,
    pi_email          = pi_email,
    username          = username,
    fullname          = fullname,
    email             = email,
    password          = password,
    admin_site        = admin_site,
    coordinators      = coordinators,
    timeout           = timeout,
    out_dir           = out_dir
  )
}

# ---------------------------------------------------------------------------
# TUI: readline fallback
# ---------------------------------------------------------------------------

collect_tui_readline <- function() {
  cli_h1("zzedc Project Initialisation")

  cli_h2("Study information")
  study_name <- rl_prompt("Study name")
  while (!nzchar(study_name)) {
    cli_alert_danger("Required.")
    study_name <- rl_prompt("Study name")
  }
  protocol_id <- rl_prompt("Protocol ID")
  while (!nzchar(protocol_id)) {
    cli_alert_danger("Required.")
    protocol_id <- rl_prompt("Protocol ID")
  }
  enroll_raw <- rl_prompt("Target enrollment")
  target_enrollment <- suppressWarnings(as.integer(enroll_raw))
  if (is.na(target_enrollment) || target_enrollment < 1) {
    cli_alert_warning("Invalid enrollment; using 1.")
    target_enrollment <- 1L
  }
  phase   <- rl_prompt("Phase (Phase I/II/III/Observational/Other)", "Observational")
  db_name <- rl_prompt("Database filename", default_db_name(protocol_id))

  cli_h2("Principal investigator")
  pi_name <- rl_prompt("PI full name")
  while (!nzchar(pi_name)) {
    cli_alert_danger("Required.")
    pi_name <- rl_prompt("PI full name")
  }
  pi_email <- rl_prompt("PI email")
  while (!is_valid_email(pi_email)) {
    cli_alert_danger("Invalid email.")
    pi_email <- rl_prompt("PI email")
  }

  cli_h2("Admin account")
  default_user <- gsub("[^a-z0-9]", "", tolower(strsplit(pi_name, " ")[[1]][[1]]))
  username   <- rl_prompt("Admin username", default_user)
  fullname   <- rl_prompt("Admin full name", pi_name)
  email      <- rl_prompt("Admin email", pi_email)
  while (!is_valid_email(email)) {
    cli_alert_danger("Invalid email.")
    email <- rl_prompt("Admin email", pi_email)
  }
  password <- ""
  repeat {
    password <- rl_prompt("Admin password (8+ chars, upper, digit, symbol)")
    if (is_strong_password(password)) break
    cli_alert_danger("Password too weak.")
  }
  admin_site <- rl_prompt("Admin site ID", "ALL")

  cli_h2("Coordinator accounts")
  cli_text("Leave username blank to finish adding coordinators.")
  coordinators <- list()
  repeat {
    label <- sprintf(
      "Coordinator %d username (blank to stop)", length(coordinators) + 1L
    )
    cu <- rl_prompt(label, "")
    if (!nzchar(cu)) break
    cn <- rl_prompt("Coordinator full name")
    ce <- rl_prompt("Coordinator email")
    while (nzchar(ce) && !is_valid_email(ce)) {
      cli_alert_danger("Invalid email.")
      ce <- rl_prompt("Coordinator email")
    }
    cp <- rl_prompt("Coordinator initial password", "TempPass!2026")
    cs <- rl_prompt("Coordinator site ID")
    coordinators <- c(coordinators, list(list(
      username = cu, fullname = cn, email = ce,
      password = cp, site_id  = cs
    )))
  }

  cli_h2("Security")
  timeout_raw <- rl_prompt("Session timeout (minutes)", "60")
  timeout     <- suppressWarnings(as.integer(timeout_raw))
  if (is.na(timeout) || timeout < 5) {
    cli_alert_warning("Using 60.")
    timeout <- 60L
  }

  cli_h2("Output location")
  out_dir <- rl_prompt("Output directory", ".")

  list(
    study_name        = study_name,
    protocol_id       = protocol_id,
    target_enrollment = target_enrollment,
    phase             = phase,
    db_name           = db_name,
    pi_name           = pi_name,
    pi_email          = pi_email,
    username          = username,
    fullname          = fullname,
    email             = email,
    password          = password,
    admin_site        = admin_site,
    coordinators      = coordinators,
    timeout           = timeout,
    out_dir           = out_dir
  )
}

# ---------------------------------------------------------------------------
# TUI dispatcher
# ---------------------------------------------------------------------------

collect_tui <- function() {
  if (has_gum()) {
    cli_alert_info("gum detected -- using styled TUI.")
    collect_tui_gum()
  } else {
    cli_alert_info(
      "gum not found -- falling back to readline prompts. ",
      "Install gum: brew install gum"
    )
    collect_tui_readline()
  }
}

# ---------------------------------------------------------------------------
# Mode selection
# ---------------------------------------------------------------------------

select_mode <- function() {
  if (has_gum()) {
    choice <- tryCatch(
      gum_choose(
        items  = c(
          "tui    - Guided prompts (styled, no files needed)",
          "config - Edit a plain-text template, then re-run",
          "sheets - Populate a Google Sheet, then point this script at it"
        ),
        header = "zzedc Project Initialisation -- choose an interface mode"
      ),
      error = function(e) "tui    - Guided prompts (styled, no files needed)"
    )
    sub("^(\\S+).*", "\\1", trimws(choice))
  } else {
    cli_h1("zzedc Project Initialisation")
    cli_text("  {.strong 1  TUI}    -- guided prompts")
    cli_text("  {.strong 2  Config} -- plain-text file")
    cli_text("  {.strong 3  Sheets} -- Google Sheets")
    if (interactive()) {
      raw <- readline("Enter 1, 2, or 3 [1]: ")
    } else {
      cat("Enter 1, 2, or 3 [1]: ")
      raw <- readLines(con = stdin(), n = 1L, warn = FALSE)
      if (length(raw) == 0L) raw <- ""
    }
    if (!nzchar(raw)) raw <- "1"
    switch(raw, "1" = "tui", "2" = "config", "3" = "sheets", {
      cli_alert_warning("Defaulting to TUI.")
      "tui"
    })
  }
}

# ---------------------------------------------------------------------------
# Config file mode
# ---------------------------------------------------------------------------

config_template <- '# zzedc Project Configuration
# Edit the values below. Lines starting with # are comments.
# Fields marked REQUIRED must be filled in before running.

# ── Study ──────────────────────────────────────────────────
study_name         = My Study Name             # REQUIRED
protocol_id        = STUDY-2026                # REQUIRED
target_enrollment  = 50                        # REQUIRED
phase              = Phase II                  # Phase I/II/III/Observational/Other
db_name            = study-2026.db             # Database filename for import step

# ── Principal Investigator ─────────────────────────────────
pi_name            = Professor Smith           # REQUIRED
pi_email           = psmith@university.edu     # REQUIRED

# ── Admin account ──────────────────────────────────────────
admin_username     = psmith                    # REQUIRED, no spaces
admin_fullname     = Professor Smith           # REQUIRED
admin_email        = psmith@university.edu     # REQUIRED
admin_password     = ChangeMeNow!2026          # REQUIRED
admin_site_id      = ALL                       # ALL for multi-site; site code otherwise

# ── Coordinator accounts ────────────────────────────────────
# Add one numbered block per coordinator. Remove unused blocks.
coord_1_username   = site_coord                # REQUIRED if block present
coord_1_fullname   = Site Coordinator
coord_1_email      = coord@university.edu      # REQUIRED if block present
coord_1_password   = TempPass!2026
coord_1_site_id    = UCSD

# coord_2_username =
# coord_2_fullname =
# coord_2_email    =
# coord_2_password = TempPass!2026
# coord_2_site_id  =

# ── Security ────────────────────────────────────────────────
session_timeout_minutes = 60

# ── Output ──────────────────────────────────────────────────
out_dir = .
'

parse_config_file <- function(path) {
  if (!file.exists(path)) cli_abort("Config file not found: {.file {path}}")
  lines <- readLines(path, warn = FALSE)
  lines <- lines[!grepl("^\\s*#", lines) & nzchar(trimws(lines))]
  lines <- sub("#.*$", "", lines)
  pairs <- strsplit(lines, "\\s*=\\s*", perl = TRUE)
  cfg   <- setNames(
    trimws(sapply(pairs, function(x) if (length(x) >= 2) x[[2]] else "")),
    trimws(sapply(pairs, `[[`, 1))
  )
  get_cfg <- function(key, default = "") {
    v <- cfg[[key]]
    if (is.null(v) || !nzchar(v)) default else v
  }

  coord_keys <- grep("^coord_[0-9]+_username$", names(cfg), value = TRUE)
  ns <- sort(as.integer(sub("^coord_([0-9]+)_username$", "\\1", coord_keys)))
  coordinators <- lapply(ns, function(n) {
    list(
      username = get_cfg(sprintf("coord_%d_username", n)),
      fullname = get_cfg(sprintf("coord_%d_fullname", n)),
      email    = get_cfg(sprintf("coord_%d_email",    n)),
      password = get_cfg(sprintf("coord_%d_password", n), "TempPass!2026"),
      site_id  = get_cfg(sprintf("coord_%d_site_id",  n))
    )
  })
  coordinators <- Filter(function(x) nzchar(x$username), coordinators)

  protocol_id <- get_cfg("protocol_id")
  list(
    study_name        = get_cfg("study_name"),
    protocol_id       = protocol_id,
    target_enrollment = suppressWarnings(
      as.integer(get_cfg("target_enrollment", "1"))
    ),
    phase             = get_cfg("phase", "Observational"),
    db_name           = get_cfg("db_name", default_db_name(protocol_id)),
    pi_name           = get_cfg("pi_name"),
    pi_email          = get_cfg("pi_email"),
    username          = get_cfg("admin_username"),
    fullname          = get_cfg("admin_fullname"),
    email             = get_cfg("admin_email"),
    password          = get_cfg("admin_password"),
    admin_site        = get_cfg("admin_site_id", "ALL"),
    coordinators      = coordinators,
    timeout           = suppressWarnings(
      as.integer(get_cfg("session_timeout_minutes", "60"))
    ),
    out_dir           = get_cfg("out_dir", ".")
  )
}

collect_config <- function(path) {
  if (is.null(path)) {
    default_path <- "study.conf"
    writeLines(config_template, default_path)
    cli_alert_success("Template written to {.file {default_path}}. Edit and re-run:")
    cli_code(sprintf(
      "Rscript edc-init.R --mode config --file %s", default_path
    ))
    quit(save = "no", status = 0)
  }
  parse_config_file(path)
}

# ---------------------------------------------------------------------------
# Google Sheets mode
# ---------------------------------------------------------------------------

collect_sheets <- function(url) {
  if (!requireNamespace("googlesheets4", quietly = TRUE))
    cli_abort("Install googlesheets4: pak::pak('googlesheets4')")
  library(googlesheets4)

  if (is.null(url)) {
    if (interactive()) {
      readline("Press Enter to authenticate with Google... ")
    } else {
      cat("Press Enter to authenticate with Google... ")
      readLines(con = stdin(), n = 1L, warn = FALSE)
    }
    gs4_auth()
    sheet_title <- readline("New sheet name [zzedc Project Config]: ")
    if (!nzchar(sheet_title)) sheet_title <- "zzedc Project Config"
    ss <- gs4_create(
      name   = sheet_title,
      sheets = c("Study_Info", "Study_Users")
    )
    googlesheets4::write_sheet(
      data.frame(
        key   = c("study_name", "protocol_id", "target_enrollment",
                  "phase", "db_name", "pi_name", "pi_email"),
        value = c("My Study Name", "STUDY-2026", "50",
                  "Phase II", "study-2026.db",
                  "Professor Smith", "psmith@university.edu"),
        stringsAsFactors = FALSE
      ),
      ss, sheet = "Study_Info"
    )
    googlesheets4::write_sheet(
      data.frame(
        username         = c("psmith",              "site_coord"),
        full_name        = c("Professor Smith",     "Site Coordinator"),
        email            = c("psmith@university.edu", "coord@university.edu"),
        role             = c("Admin",               "Coordinator"),
        password_initial = c("ChangeMeNow!2026",    "TempPass!2026"),
        site_id          = c("ALL",                 "UCSD"),
        active           = c("TRUE",                "TRUE"),
        stringsAsFactors = FALSE
      ),
      ss, sheet = "Study_Users"
    )
    sheet_url <- as.character(ss)
    cli_alert_success("Workbook created: {.url {sheet_url}}")
    cli_text(
      "Edit {.strong Study_Info} and {.strong Study_Users}, then re-run:"
    )
    cli_code(sprintf(
      "Rscript edc-init.R --mode sheets --url '%s'", sheet_url
    ))
    quit(save = "no", status = 0)
  }

  gs4_auth()
  info_df <- tryCatch(
    googlesheets4::read_sheet(url, sheet = "Study_Info"),
    error = function(e) NULL
  )
  users_df <- googlesheets4::read_sheet(url, sheet = "Study_Users")

  get_info <- function(key, default = "") {
    if (is.null(info_df)) return(default)
    row <- info_df[as.character(info_df$key) == key, , drop = FALSE]
    if (nrow(row) == 0 || !nzchar(as.character(row$value[[1]]))) default
    else as.character(row$value[[1]])
  }

  admin_rows <- users_df[
    tolower(as.character(users_df$role)) == "admin", , drop = FALSE
  ]
  if (nrow(admin_rows) == 0) cli_abort("No Admin row found in Study_Users.")
  admin_row <- admin_rows[1, ]

  coord_rows <- users_df[
    tolower(as.character(users_df$role)) == "coordinator", , drop = FALSE
  ]
  coordinators <- if (nrow(coord_rows) > 0) {
    lapply(seq_len(nrow(coord_rows)), function(i) {
      r <- coord_rows[i, ]
      list(
        username = as.character(r$username),
        fullname = as.character(r$full_name),
        email    = as.character(r$email),
        password = as.character(r$password_initial),
        site_id  = as.character(r$site_id)
      )
    })
  } else list()

  protocol_id <- get_info("protocol_id", "STUDY-2026")
  list(
    study_name        = get_info("study_name",        "My Study"),
    protocol_id       = protocol_id,
    target_enrollment = suppressWarnings(
      as.integer(get_info("target_enrollment", "1"))
    ),
    phase             = get_info("phase",             "Observational"),
    db_name           = get_info("db_name", default_db_name(protocol_id)),
    pi_name           = as.character(admin_row$full_name),
    pi_email          = as.character(admin_row$email),
    username          = as.character(admin_row$username),
    fullname          = as.character(admin_row$full_name),
    email             = as.character(admin_row$email),
    password          = as.character(admin_row$password_initial),
    admin_site        = as.character(admin_row$site_id),
    coordinators      = coordinators,
    timeout           = 60L,
    out_dir           = "."
  )
}

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

validate_inputs <- function(cfg) {
  errors <- character(0)
  if (!nzchar(cfg$study_name))  errors <- c(errors, "study_name is required")
  if (!nzchar(cfg$protocol_id)) errors <- c(errors, "protocol_id is required")
  if (is.na(cfg$target_enrollment) || cfg$target_enrollment < 1)
    errors <- c(errors, "target_enrollment must be a positive integer")
  if (!nzchar(cfg$pi_name))           errors <- c(errors, "pi_name is required")
  if (!is_valid_email(cfg$pi_email))  errors <- c(errors, "pi_email is not valid")
  if (!nzchar(cfg$username))          errors <- c(errors, "admin_username is required")
  if (!nzchar(cfg$fullname))          errors <- c(errors, "admin_fullname is required")
  if (!is_valid_email(cfg$email))     errors <- c(errors, "admin_email is not valid")
  if (!is_strong_password(cfg$password))
    errors <- c(errors, "admin_password too weak (min 8 chars, uppercase, digit, symbol)")
  if (is.na(cfg$timeout) || cfg$timeout < 5)
    errors <- c(errors, "session_timeout_minutes must be >= 5")
  if (length(errors) > 0) {
    cli_alert_danger("Validation failed:")
    for (e in errors) cli_bullets(c("x" = e))
    quit(save = "no", status = 1)
  }
}

# ---------------------------------------------------------------------------
# Output writers
# ---------------------------------------------------------------------------

build_users_df <- function(cfg) {
  rows <- list(data.frame(
    username         = cfg$username,
    full_name        = cfg$fullname,
    email            = cfg$email,
    role             = "Admin",
    password_initial = cfg$password,
    site_id          = cfg$admin_site,
    active           = "TRUE",
    stringsAsFactors = FALSE
  ))
  for (coord in cfg$coordinators) {
    rows <- c(rows, list(data.frame(
      username         = coord$username,
      full_name        = coord$fullname,
      email            = coord$email,
      role             = "Coordinator",
      password_initial = coord$password,
      site_id          = coord$site_id,
      active           = "TRUE",
      stringsAsFactors = FALSE
    )))
  }
  do.call(rbind, rows)
}

write_yaml_config <- function(cfg, path) {
  write_yaml(list(
    study = list(
      name              = cfg$study_name,
      protocol_id       = cfg$protocol_id,
      pi_name           = cfg$pi_name,
      pi_email          = cfg$pi_email,
      target_enrollment = cfg$target_enrollment,
      phase             = cfg$phase
    ),
    admin = list(
      username = cfg$username,
      fullname = cfg$fullname,
      email    = cfg$email,
      password = cfg$password
    ),
    security = list(
      session_timeout_minutes   = cfg$timeout,
      enforce_https             = FALSE,
      max_failed_login_attempts = 10L
    ),
    compliance = list(
      gdpr_enabled          = FALSE,
      cfr_part11_enabled    = FALSE,
      audit_logging_enabled = TRUE
    ),
    database = list(type = "sqlite", pool_size = 2L)
  ), path)
  cli_alert_success("Config written to {.file {path}}")
}

write_csv_files <- function(users_df, out_dir, dd_src = NULL, rules_src = NULL) {
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  users_path <- file.path(out_dir, "Study_Users.csv")
  write.csv(users_df, users_path, row.names = FALSE, quote = TRUE)
  cli_alert_success("Users written to {.file {users_path}}")

  if (!is.null(dd_src)) {
    if (!file.exists(dd_src)) {
      cli_alert_warning(
        "Data dictionary not found: {.file {dd_src}} -- skipping."
      )
    } else {
      dd_dest <- file.path(out_dir, "Data_Dictionary.csv")
      file.copy(dd_src, dd_dest, overwrite = TRUE)
      cli_alert_success("Data dictionary copied to {.file {dd_dest}}")
    }
  } else {
    cli_alert_info(
      "No --dd-csv supplied. ",
      "Place {.file Data_Dictionary.csv} in {.file {out_dir}} before importing."
    )
  }

  if (!is.null(rules_src)) {
    if (!file.exists(rules_src)) {
      cli_alert_warning(
        "Validation rules not found: {.file {rules_src}} -- skipping."
      )
    } else {
      rules_dest <- file.path(out_dir, "validation_rules.csv")
      file.copy(rules_src, rules_dest, overwrite = TRUE)
      cli_alert_success("Validation rules copied to {.file {rules_dest}}")
    }
  } else {
    cli_alert_info(
      "No --rules-csv supplied. ",
      "Place {.file validation_rules.csv} in {.file {out_dir}} before importing."
    )
  }
}

print_next_steps <- function(cfg, yaml_path, out_dir, mode) {
  db_path <- file.path("data", cfg$db_name)
  cli_h2("Next steps")
  cli_text("1. Review {.file {yaml_path}} and verify the settings.")
  cli_text(" ")
  if (mode == "sheets") {
    cli_text("2. Import:")
    cli_code(sprintf(
      "zzedc::setup_zzedc_from_gsheets(\n  sheet_url = '<YOUR_SHEET_URL>',\n  db_path   = '%s'\n)",
      db_path
    ))
  } else {
    cli_text("2. Import:")
    cli_code(sprintf(
      paste0(
        "zzedc::setup_zzedc_from_csv(\n",
        "  users_csv      = '%s',\n",
        "  dictionary_csv = '%s',\n",
        "  rules_csv      = '%s',\n",
        "  db_path        = '%s'\n)"
      ),
      file.path(out_dir, "Study_Users.csv"),
      file.path(out_dir, "Data_Dictionary.csv"),
      file.path(out_dir, "validation_rules.csv"),
      db_path
    ))
  }
  cli_text(" ")
  cli_text("3. Launch: {.code library(zzedc); launch_zzedc()}")
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

parse_args <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  out  <- list(mode = NULL, file = NULL, url = NULL,
               dd_csv = NULL, rules_csv = NULL)
  i <- 1L
  while (i <= length(args)) {
    switch(args[[i]],
      "--mode"      = { i <- i + 1L; out$mode      <- args[[i]] },
      "--file"      = { i <- i + 1L; out$file      <- args[[i]] },
      "--url"       = { i <- i + 1L; out$url       <- args[[i]] },
      "--dd-csv"    = { i <- i + 1L; out$dd_csv    <- args[[i]] },
      "--rules-csv" = { i <- i + 1L; out$rules_csv <- args[[i]] }
    )
    i <- i + 1L
  }
  out
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main <- function() {
  args <- parse_args()
  mode <- args$mode
  if (is.null(mode)) mode <- select_mode()
  cfg <- switch(mode,
    tui    = collect_tui(),
    config = collect_config(args$file),
    sheets = collect_sheets(args$url),
    cli_abort("Unknown mode. Choose: tui, config, or sheets.")
  )
  validate_inputs(cfg)
  out_dir   <- cfg$out_dir
  yaml_path <- file.path(out_dir, "zzedc_config.yml")
  write_yaml_config(cfg, yaml_path)
  write_csv_files(
    build_users_df(cfg), out_dir,
    dd_src    = args$dd_csv,
    rules_src = args$rules_csv
  )
  print_next_steps(cfg, yaml_path, out_dir, mode)
}

main()
