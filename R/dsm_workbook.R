#' Monitoring-Plan Workbook
#'
#' The spreadsheet through which plan authors, who write no code and
#' edit no YAML, create and amend a monitoring plan (design document,
#' Section 6.8). `dsm_generate_workbook()` writes it, the author fills
#' it in with any spreadsheet program, and `dsm_import_workbook()`
#' reads it into a new draft plan version, reporting every problem by
#' sheet, row, and column.
#'
#' Sheets: `Plan` (one value per setting), `Risks` (one row per risk),
#' `Indicators` (one row per indicator, linked to a risk by `risk_id`),
#' and `Stopping rules`. A hidden `Lists` sheet holds the drop-down
#' choices. A directory of CSV files with the same names
#' (`plan.csv`, `risks.csv`, `indicators.csv`, `stopping_rules.csv`)
#' is read the same way.
#'
#' @name dsm_workbook
#' @keywords internal
NULL


.dsm_wb_plan_keys <- c(
  "study_id", "funding_ico", "risk_tier", "interim_efficacy",
  "interim_futility", "independent_monitor", "independent_monitor_reason",
  "report_frequency_months", "reviewer_roles"
)

.dsm_wb_plan_help <- c(
  "Study identifier",
  "Funding institute, for example NIA (optional)",
  "minimal, moderate, or trial",
  "yes if interim efficacy analyses are planned",
  "yes if interim futility analyses are planned",
  "none, individual, or committee",
  "The institute's written reason, if it requires independent monitoring",
  "Months between routine monitoring reports (1 to 12)",
  "Roles that review reports, separated by commas (for example pi, monitor)"
)

.dsm_wb_columns <- list(
  Risks = c("risk_id", "category", "description", "likelihood", "impact",
            "critical", "rationale", "mitigation", "monitored_by"),
  Indicators = c("risk_id", "indicator", "form", "field", "grain",
                 "window_days", "threshold_unit", "warning", "alert",
                 "min_denominator", "review_role"),
  `Stopping rules` = c("description", "indicator")
)


#' Drop-Down Choices for the Workbook (internal)
#' @return Named list of character vectors.
#' @keywords internal
.dsm_wb_lists <- function() {
  list(
    category = .dsm_risk_categories(),
    level = c("low", "medium", "high"),
    yes_no = c("yes", "no"),
    monitored_by = c("indicator", "narrative", "both"),
    risk_tier = c("minimal", "moderate", "trial"),
    independent_monitor = c("none", "individual", "committee"),
    grain = c("study", "site", "arm"),
    threshold_unit = c("percent", "number"),
    role = c("pi", "studymanager", "data_manager", "coordinator", "monitor")
  )
}


#' Write a Monitoring-Plan Workbook for Authors
#'
#' Writes an Excel workbook that a plan author fills in. Drop-down
#' lists restrict categories, levels, yes/no answers, grains, threshold
#' units, and roles, so these are chosen rather than typed. To amend a
#' plan, pass an existing version: the workbook is filled from it, and
#' the author edits a fresh copy rather than an old file.
#'
#' @param path File to write (`.xlsx`).
#' @param study_id Study identifier, written into the `Plan` sheet.
#' @param conn,plan_id Optional: a connection and a plan version whose
#'   content fills the workbook.
#' @return `list(success = TRUE, path)` or `list(success = FALSE, error)`.
#' @export
dsm_generate_workbook <- function(path, study_id = "", conn = NULL,
                                  plan_id = NULL) {
  tryCatch({
    spec <- NULL
    if (!is.null(conn) && !is.null(plan_id)) {
      e <- dsm_export_spec(conn, plan_id)
      if (!isTRUE(e$success)) stop(e$error)
      spec <- e$spec
      study_id <- spec$study_id
    }
    tables <- .dsm_spec_to_tables(spec, study_id)
    lists <- .dsm_wb_lists()

    wb <- openxlsx::createWorkbook()
    head_style <- openxlsx::createStyle(textDecoration = "bold",
                                        fgFill = "#E7E6E6")

    openxlsx::addWorksheet(wb, "Plan")
    openxlsx::writeData(wb, "Plan", tables$plan, headerStyle = head_style)
    openxlsx::setColWidths(wb, "Plan", cols = 1:3, widths = c(28, 40, 70))

    for (sheet in names(.dsm_wb_columns)) {
      openxlsx::addWorksheet(wb, sheet)
      openxlsx::writeData(wb, sheet, tables[[sheet]],
                          headerStyle = head_style)
      openxlsx::setColWidths(wb, sheet,
                             cols = seq_along(.dsm_wb_columns[[sheet]]),
                             widths = "auto")
      openxlsx::freezePane(wb, sheet, firstRow = TRUE)
    }

    openxlsx::addWorksheet(wb, "Lists", visible = FALSE)
    for (k in seq_along(lists)) {
      openxlsx::writeData(wb, "Lists", data.frame(lists[[k]]),
                          startCol = k, colNames = FALSE)
    }
    list_ref <- function(name) {
      k <- match(name, names(lists))
      col <- openxlsx::int2col(k)
      sprintf("'Lists'!$%s$1:$%s$%d", col, col, length(lists[[name]]))
    }
    drop <- function(sheet, column, list_name, rows = 2:500) {
      col <- match(column, .dsm_wb_columns[[sheet]])
      openxlsx::dataValidation(wb, sheet, cols = col, rows = rows,
                               type = "list", value = list_ref(list_name))
    }
    drop("Risks", "category", "category")
    drop("Risks", "likelihood", "level")
    drop("Risks", "impact", "level")
    drop("Risks", "critical", "yes_no")
    drop("Risks", "monitored_by", "monitored_by")
    drop("Indicators", "grain", "grain")
    drop("Indicators", "threshold_unit", "threshold_unit")
    drop("Indicators", "review_role", "role")

    plan_row <- function(key) match(key, .dsm_wb_plan_keys) + 1L
    plan_drop <- function(key, list_name) {
      openxlsx::dataValidation(wb, "Plan", cols = 2, rows = plan_row(key),
                               type = "list", value = list_ref(list_name))
    }
    plan_drop("risk_tier", "risk_tier")
    plan_drop("interim_efficacy", "yes_no")
    plan_drop("interim_futility", "yes_no")
    plan_drop("independent_monitor", "independent_monitor")

    openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
    list(success = TRUE, path = path)
  }, error = function(e) {
    list(success = FALSE, error = conditionMessage(e))
  })
}


#' Spec to Workbook Tables (internal)
#' @param spec A spec list, or `NULL` for a blank workbook.
#' @param study_id Study identifier for a blank workbook.
#' @return Named list of data frames.
#' @keywords internal
.dsm_spec_to_tables <- function(spec, study_id = "") {
  yn <- function(x) if (isTRUE(x)) "yes" else "no"
  chr <- function(x) if (is.null(x)) "" else as.character(x)
  empty <- function(cols) {
    stats::setNames(as.data.frame(matrix(character(0), 0, length(cols))),
                    cols)
  }

  values <- if (is.null(spec)) {
    c(study_id, "", "moderate", "no", "no", "none", "", "12", "pi")
  } else {
    c(spec$study_id, chr(spec$funding_ico), spec$risk_tier,
      yn(spec$interim_analyses$efficacy), yn(spec$interim_analyses$futility),
      chr(spec$independent_monitor$type %||% "none"),
      chr(spec$independent_monitor$ico_reason),
      chr(spec$review$report_frequency_months),
      paste(unlist(spec$review$reviewer_roles), collapse = ", "))
  }
  plan <- data.frame(setting = .dsm_wb_plan_keys, value = values,
                     help = .dsm_wb_plan_help)

  risks <- empty(.dsm_wb_columns$Risks)
  inds <- empty(.dsm_wb_columns$Indicators)
  rules <- empty(.dsm_wb_columns$`Stopping rules`)
  if (!is.null(spec)) {
    for (r in spec$risks) {
      risks[nrow(risks) + 1, ] <- c(
        r$id, r$category, r$description, r$likelihood, r$impact,
        yn(r$critical), chr(r$rationale), chr(r$mitigation),
        chr(r$monitored_by))
      for (d in r$indicators %||% list()) {
        unit <- d$threshold_unit %||% "percent"
        thr <- function(v) {
          if (is.null(v)) return("")
          if (identical(unit, "percent")) format(v * 100, digits = 15)
          else format(v, digits = 15)
        }
        inds[nrow(inds) + 1, ] <- c(
          r$id, d$indicator, chr(d$params$crf_code), chr(d$params$field),
          chr(d$grain), chr(d$window_days), unit, thr(d$warning),
          thr(d$alert), chr(d$min_denominator), chr(d$review_role))
      }
    }
    for (s in spec$stopping_rules %||% list()) {
      rules[nrow(rules) + 1, ] <- c(s$description, chr(s$indicator))
    }
  }
  list(plan = plan, Risks = risks, Indicators = inds,
       `Stopping rules` = rules)
}


#' Read the Workbook's Sheets (internal)
#'
#' @param path An `.xlsx` file, or a directory of CSV files.
#' @return Named list of data frames with character columns.
#' @keywords internal
.dsm_read_workbook <- function(path) {
  files <- c(Plan = "plan.csv", Risks = "risks.csv",
             Indicators = "indicators.csv",
             `Stopping rules` = "stopping_rules.csv")
  read_one <- function(sheet) {
    df <- if (dir.exists(path)) {
      f <- file.path(path, files[[sheet]])
      if (!file.exists(f)) return(NULL)
      utils::read.csv(f, colClasses = "character", check.names = FALSE,
                      na.strings = character(0))
    } else {
      if (!sheet %in% openxlsx::getSheetNames(path)) return(NULL)
      openxlsx::read.xlsx(path, sheet = sheet, colNames = TRUE,
                          skipEmptyRows = FALSE, check.names = FALSE,
                          sep.names = "_")
    }
    if (is.null(df)) return(NULL)
    df[] <- lapply(df, function(x) {
      x <- as.character(x)
      x[is.na(x)] <- ""
      trimws(x)
    })
    keep <- apply(df, 1, function(r) any(nzchar(r)))
    df$.row <- seq_len(nrow(df)) + 1L
    df[keep, , drop = FALSE]
  }
  stats::setNames(lapply(names(files), read_one), names(files))
}


#' Workbook Tables to a Spec, With Cell Locations (internal)
#'
#' @param tabs Output of `.dsm_read_workbook()`.
#' @return `list(spec, where, problems)`: `where` maps validation
#'   paths to sheet, row, and column; `problems` holds reading errors
#'   that validation cannot see (unknown values, ambiguous numbers).
#' @keywords internal
.dsm_tables_to_spec <- function(tabs) {
  where <- list()
  probs <- list()
  loc <- function(path, sheet, row, column) {
    where[[path]] <<- list(sheet = sheet, row = row, column = column)
  }
  bad <- function(sheet, row, column, message) {
    probs[[length(probs) + 1]] <<- data.frame(
      sheet = sheet, row = row, column = column, message = message)
  }
  yes_no <- function(x, sheet, row, column) {
    v <- tolower(x)
    if (v %in% c("yes", "y", "true")) return(TRUE)
    if (v %in% c("no", "n", "false", "")) return(FALSE)
    bad(sheet, row, column, "must be yes or no")
    NA
  }
  num <- function(x, sheet, row, column) {
    if (!nzchar(x)) return(NULL)
    v <- suppressWarnings(as.numeric(sub("%$", "", x)))
    if (is.na(v)) {
      bad(sheet, row, column, "must be a number")
      return(NULL)
    }
    v
  }
  opt <- function(x) if (nzchar(x)) x else NULL

  for (sheet in c("Plan", "Risks")) {
    if (is.null(tabs[[sheet]])) bad(sheet, NA, NA, "sheet is missing")
  }
  plan_tab <- tabs$Plan
  pv <- function(key) {
    if (is.null(plan_tab)) return("")
    i <- match(key, plan_tab$setting)
    if (is.na(i)) "" else plan_tab$value[i]
  }
  prow <- function(key) {
    if (is.null(plan_tab)) return(NA_integer_)
    i <- match(key, plan_tab$setting)
    if (is.na(i)) NA_integer_ else plan_tab$.row[i]
  }
  for (k in c("study_id", "risk_tier", "independent_monitor",
              "report_frequency_months", "funding_ico")) {
    loc(switch(k, independent_monitor = "independent_monitor.type",
               report_frequency_months = "review.report_frequency_months",
               k), "Plan", prow(k), "value")
  }
  loc("interim_analyses.efficacy", "Plan", prow("interim_efficacy"), "value")
  loc("interim_analyses.futility", "Plan", prow("interim_futility"), "value")

  freq <- num(pv("report_frequency_months"), "Plan",
              prow("report_frequency_months"), "value")
  monitor <- list(type = if (nzchar(pv("independent_monitor")))
    pv("independent_monitor") else "none")
  if (nzchar(pv("independent_monitor_reason"))) {
    monitor$ico_reason <- pv("independent_monitor_reason")
  }
  roles <- trimws(strsplit(pv("reviewer_roles"), ",")[[1]])
  spec <- list(
    dsm_spec_version = .dsm_spec_version,
    study_id = pv("study_id"),
    funding_ico = opt(pv("funding_ico")),
    risk_tier = pv("risk_tier"),
    interim_analyses = list(
      efficacy = yes_no(pv("interim_efficacy"), "Plan",
                        prow("interim_efficacy"), "value"),
      futility = yes_no(pv("interim_futility"), "Plan",
                        prow("interim_futility"), "value")),
    independent_monitor = monitor,
    review = list(report_frequency_months =
                    if (is.null(freq)) NULL else as.integer(freq),
                  reviewer_roles = as.list(roles[nzchar(roles)])),
    risks = list(),
    stopping_rules = list()
  )
  spec$funding_ico <- spec$funding_ico

  risks <- tabs$Risks %||% data.frame()
  inds <- tabs$Indicators %||% data.frame()
  for (i in seq_len(nrow(risks))) {
    r <- risks[i, ]
    for (f in .dsm_wb_columns$Risks) {
      path_f <- switch(f, risk_id = "id", f)
      loc(sprintf("risks[%d].%s", i, path_f), "Risks", r$.row, f)
    }
    risk <- list(
      id = r$risk_id, category = r$category, description = r$description,
      likelihood = r$likelihood, impact = r$impact,
      critical = yes_no(r$critical, "Risks", r$.row, "critical"),
      rationale = opt(r$rationale), mitigation = opt(r$mitigation),
      monitored_by = opt(r$monitored_by)
    )
    mine <- if (nrow(inds) > 0) inds[inds$risk_id == r$risk_id, , drop = FALSE]
            else inds
    loc(sprintf("risks[%d].indicators", i), "Risks", r$.row, "risk_id")
    risk$indicators <- list()
    for (j in seq_len(nrow(mine))) {
      d <- mine[j, ]
      for (f in .dsm_wb_columns$Indicators) {
        loc(sprintf("risks[%d].indicators[%d].%s", i, j, f), "Indicators",
            d$.row, f)
      }
      unit <- if (nzchar(d$threshold_unit)) d$threshold_unit else "percent"
      if (!unit %in% c("percent", "number")) {
        bad("Indicators", d$.row, "threshold_unit",
            "must be percent or number")
      }
      thr <- function(col) {
        v <- num(d[[col]], "Indicators", d$.row, col)
        if (is.null(v) || unit != "percent") return(v)
        if (v > 0 && v < 1) {
          bad("Indicators", d$.row, col, paste(
            "looks like a proportion; thresholds in percent are entered",
            "as, for example, 15 for 15%"))
          return(NULL)
        }
        v / 100
      }
      whole <- function(col) {
        v <- num(d[[col]], "Indicators", d$.row, col)
        if (is.null(v)) NULL else v
      }
      params <- list()
      if (nzchar(d$form)) params$crf_code <- d$form
      if (nzchar(d$field)) params$field <- d$field
      ind <- list(indicator = d$indicator, grain = opt(d$grain),
                  window_days = whole("window_days"),
                  threshold_unit = unit,
                  warning = thr("warning"), alert = thr("alert"),
                  min_denominator = whole("min_denominator"),
                  review_role = opt(d$review_role))
      if (length(params) > 0) ind$params <- params
      risk$indicators[[j]] <- Filter(Negate(is.null), ind)
    }
    if (length(risk$indicators) == 0) risk$indicators <- NULL
    spec$risks[[i]] <- Filter(Negate(is.null), risk)
  }
  if (nrow(inds) > 0) {
    orphans <- inds[!inds$risk_id %in% risks$risk_id, , drop = FALSE]
    for (k in seq_len(nrow(orphans))) {
      bad("Indicators", orphans$.row[k], "risk_id",
          "does not match a risk_id on the Risks sheet")
    }
  }
  rules <- tabs$`Stopping rules` %||% data.frame()
  for (k in seq_len(nrow(rules))) {
    loc(sprintf("stopping_rules[%d].description", k), "Stopping rules",
        rules$.row[k], "description")
    loc(sprintf("stopping_rules[%d].indicator", k), "Stopping rules",
        rules$.row[k], "indicator")
    spec$stopping_rules[[k]] <- Filter(Negate(is.null), list(
      description = rules$description[k], indicator = opt(rules$indicator[k])))
  }
  if (length(spec$stopping_rules) == 0) spec$stopping_rules <- NULL
  spec <- Filter(Negate(is.null), spec)

  problems <- if (length(probs) == 0) {
    data.frame(sheet = character(0), row = integer(0), column = character(0),
               message = character(0))
  } else {
    do.call(rbind, probs)
  }
  list(spec = spec, where = where, problems = problems)
}


#' Import a Monitoring-Plan Workbook as a New Draft Version
#'
#' Reads the author's workbook (or directory of CSV files), checks it,
#' and stores it as a new draft plan version with the file's SHA-256
#' recorded as its source. Problems are reported in plain language by
#' sheet, row, and column, all at once; nothing is stored unless there
#' are none.
#'
#' Thresholds on a row whose `threshold_unit` is `percent` are entered
#' in percent (15 means 15%) and stored as proportions; a value
#' strictly between 0 and 1 is refused as ambiguous, so thresholds
#' below 1% cannot be entered as percent.
#'
#' @param conn A DBI connection or pool.
#' @param path An `.xlsx` file, or a directory of CSV files.
#' @param user_id The user importing the plan.
#' @return As [dsm_import_spec()], with `problems` as a data frame of
#'   `sheet`, `row`, `column`, and `message` on failure.
#' @export
dsm_import_workbook <- function(conn, path, user_id) {
  if (!file.exists(path)) {
    return(list(success = FALSE, error = paste("File not found:", path)))
  }
  read <- tryCatch({
    tabs <- .dsm_read_workbook(path)
    .dsm_tables_to_spec(tabs)
  }, error = function(e) e)
  if (inherits(read, "error")) {
    return(list(success = FALSE,
                error = paste("Could not read the workbook:",
                              conditionMessage(read))))
  }

  v <- dsm_validate_spec(read$spec)
  located <- if (isTRUE(v$success)) {
    data.frame(sheet = character(0), row = integer(0),
               column = character(0), message = character(0))
  } else {
    do.call(rbind, lapply(seq_len(nrow(v$problems)), function(k) {
      w <- read$where[[v$problems$path[k]]]
      if (is.null(w)) {
        w <- list(sheet = "Plan", row = NA_integer_,
                  column = v$problems$path[k])
      }
      data.frame(sheet = w$sheet, row = w$row, column = w$column,
                 message = v$problems$message[k])
    }))
  }
  problems <- rbind(read$problems, located)
  if (nrow(problems) > 0) {
    problems <- problems[!duplicated(problems), , drop = FALSE]
    lines <- sprintf("%s, row %s, %s: %s", problems$sheet,
                     ifelse(is.na(problems$row), "-", problems$row),
                     problems$column, problems$message)
    return(list(success = FALSE,
                error = paste(c(sprintf("%d problem(s) in the workbook:",
                                        nrow(problems)), lines),
                              collapse = "\n"),
                problems = problems))
  }

  source_hash <- if (dir.exists(path)) {
    files <- sort(list.files(path, pattern = "\\.csv$", full.names = TRUE))
    digest::digest(paste(vapply(files, digest::digest, character(1),
                                algo = "sha256", file = TRUE),
                         collapse = "|"), algo = "sha256", serialize = FALSE)
  } else {
    digest::digest(path, algo = "sha256", file = TRUE)
  }
  dsm_import_spec(conn, read$spec, user_id = user_id,
                  source_hash = source_hash)
}
