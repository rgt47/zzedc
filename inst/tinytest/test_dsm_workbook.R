library(tinytest)
if (file.exists("_setup.R")) source("_setup.R")

# The plan authors' workbook (design Section 6.8): generate, fill in,
# import; problems reported by sheet, row, and column.

if (!exists("dsm_import_workbook")) exit_file("workbook functions not available")
if (!requireNamespace("openxlsx", quietly = TRUE)) exit_file("openxlsx missing")

for (fn in c("dsm_plan_status", ".dsm_read_workbook")) {
  assign(fn, get(fn, envir = asNamespace("zzedc")))
}

old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

.wb_db <- function() {
  db <- tempfile(fileext = ".db")
  init <- initialize_encrypted_database(db_path = db, overwrite = TRUE)
  if (!is.null(init$error)) stop(init$error)
  Sys.setenv(DB_ENCRYPTION_KEY = init$key)
  stopifnot(isTRUE(init_audit_logging(db_path = db)$success))
  list(db = db, conn = connect_encrypted_db(db_path = db))
}

# Fill a generated workbook the way an author would, by editing cells.
.fill <- function(path, plan = list(), risks = NULL, indicators = NULL,
                  rules = NULL) {
  wb <- openxlsx::loadWorkbook(path)
  pl <- openxlsx::read.xlsx(path, sheet = "Plan")
  for (k in names(plan)) {
    openxlsx::writeData(wb, "Plan", plan[[k]], startCol = 2,
                        startRow = match(k, pl$setting) + 1L)
  }
  if (!is.null(risks)) {
    openxlsx::writeData(wb, "Risks", risks, startRow = 2, colNames = FALSE)
  }
  if (!is.null(indicators)) {
    openxlsx::writeData(wb, "Indicators", indicators, startRow = 2,
                        colNames = FALSE)
  }
  if (!is.null(rules)) {
    openxlsx::writeData(wb, "Stopping rules", rules, startRow = 2,
                        colNames = FALSE)
  }
  openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
}

.risks <- data.frame(
  risk_id = c("data_actigraphy", "stewardship"),
  category = c("data_quality", "financial_stewardship"),
  description = c("Primary outcome unusable from poor device wear",
                  "Enrollment shortfall"),
  likelihood = c("medium", "low"), impact = c("high", "medium"),
  critical = c("yes", "no"),
  rationale = c("About 15% insufficient wear in the pilot.", ""),
  mitigation = c("Training; reminder call on day 3.", ""),
  monitored_by = c("indicator", "narrative")
)
.inds <- data.frame(
  risk_id = "data_actigraphy", indicator = "rule_failure_rate",
  form = "actigraphy", field = "valid_nights", grain = "site",
  window_days = "60", threshold_unit = "percent", warning = "15",
  alert = "25", min_denominator = "8", review_role = "pi"
)

# Generate, fill, import
local({
  s <- .wb_db()
  on.exit({ DBI::dbDisconnect(s$conn); unlink(s$db) })
  path <- tempfile(fileext = ".xlsx")
  g <- dsm_generate_workbook(path, study_id = "PRAZ-L-2026")
  expect_true(g$success && file.exists(path), info = "workbook generated")
  expect_true(all(c("Plan", "Risks", "Indicators", "Stopping rules",
                    "Lists") %in% openxlsx::getSheetNames(path)),
              info = "workbook has every sheet")
  # Drop-downs referring to another sheet are stored in the sheet's
  # extension list, so check the saved XML of the Risks sheet.
  xml_dir <- tempfile("xlsx_")
  utils::unzip(path, files = "xl/worksheets/sheet2.xml", exdir = xml_dir)
  risks_xml <- paste(readLines(file.path(xml_dir, "xl/worksheets/sheet2.xml"),
                               warn = FALSE), collapse = "")
  expect_true(grepl("dataValidation", risks_xml, fixed = TRUE) &&
                grepl("Lists", risks_xml, fixed = TRUE),
              info = "the Risks sheet has drop-down lists from the Lists sheet")

  .fill(path, plan = list(funding_ico = "NIA"), risks = .risks,
        indicators = .inds,
        rules = data.frame(description = "PI review at alert level",
                           indicator = "rule_failure_rate"))
  r <- dsm_import_workbook(s$conn, path, user_id = "coord1")
  expect_true(r$success, info = paste("filled workbook imports:",
                                      r$error %||% ""))
  spec <- dsm_export_spec(s$conn, r$plan_id)$spec
  ind <- spec$risks[[1]]$indicators[[1]]
  expect_equal(ind$warning, 0.15, info = "15 percent is stored as 0.15")
  expect_equal(ind$alert, 0.25, info = "25 percent is stored as 0.25")
  expect_equal(ind$params$field, "valid_nights", info = "field carried")
  expect_true(isTRUE(spec$risks[[1]]$critical), info = "yes is TRUE")
  expect_equal(spec$funding_ico, "NIA", info = "plan settings carried")
  expect_equal(dsm_plan_status(s$conn, r$plan_id)$status, "draft",
               info = "imported as draft")
  src <- DBI::dbGetQuery(s$conn, "SELECT source_hash FROM dsm_plan_versions
                                  WHERE plan_id = ?",
                         params = list(r$plan_id))$source_hash
  expect_equal(src, digest::digest(path, algo = "sha256", file = TRUE),
               info = "the workbook's hash is stored as the source")

  # Amendment workbook: generated from the stored version
  path2 <- tempfile(fileext = ".xlsx")
  g2 <- dsm_generate_workbook(path2, conn = s$conn, plan_id = r$plan_id)
  expect_true(g2$success, info = "workbook generated from a plan version")
  r2 <- dsm_import_workbook(s$conn, path2, user_id = "coord1")
  expect_true(r2$success, info = "regenerated workbook re-imports")
  expect_identical(r2$spec_hash, r$spec_hash,
                   info = "a regenerated, unedited workbook gives the same spec")
})

# Problems are reported by sheet, row, and column, all at once
local({
  s <- .wb_db()
  on.exit({ DBI::dbDisconnect(s$conn); unlink(s$db) })
  path <- tempfile(fileext = ".xlsx")
  dsm_generate_workbook(path, study_id = "PRAZ-L-2026")
  risks <- .risks
  risks$likelihood[2] <- "often"
  inds <- .inds
  inds$warning <- "0.15"
  inds2 <- inds
  inds2$risk_id <- "no_such_risk"
  inds2$warning <- "10"
  .fill(path, plan = list(risk_tier = "huge"), risks = risks,
        indicators = rbind(inds, inds2))
  r <- dsm_import_workbook(s$conn, path, user_id = "coord1")
  expect_false(r$success, info = "a workbook with problems is not imported")
  p <- r$problems
  has <- function(sheet, row, column) {
    any(p$sheet == sheet & p$row %in% row & p$column == column)
  }
  expect_true(has("Plan", 4L, "value"), info = "risk_tier located")
  expect_true(has("Risks", 3L, "likelihood"),
              info = "bad likelihood located at Risks row 3")
  expect_true(has("Indicators", 2L, "warning"),
              info = "ambiguous percent located")
  expect_true(has("Indicators", 3L, "risk_id"),
              info = "indicator for an unknown risk located")
  expect_true(grepl("Risks, row 3, likelihood", r$error, fixed = TRUE),
              info = "plain-language message names sheet, row, column")
  expect_false(DBI::dbExistsTable(s$conn, "dsm_plan_versions"),
               info = "nothing is stored when there are problems")
})

# A directory of CSV files is read the same way
local({
  s <- .wb_db()
  on.exit({ DBI::dbDisconnect(s$conn); unlink(s$db) })
  dir <- tempfile("dsmcsv_")
  dir.create(dir)
  utils::write.csv(data.frame(
    setting = c("study_id", "risk_tier", "report_frequency_months",
                "reviewer_roles"),
    value = c("CSV-STUDY", "minimal", "6", "pi")),
    file.path(dir, "plan.csv"), row.names = FALSE)
  utils::write.csv(.risks[2, ], file.path(dir, "risks.csv"),
                   row.names = FALSE)
  r <- dsm_import_workbook(s$conn, dir, user_id = "coord1")
  expect_true(r$success, info = paste("CSV directory imports:",
                                      r$error %||% ""))
  expect_equal(dsm_export_spec(s$conn, r$plan_id)$spec$study_id, "CSV-STUDY",
               info = "CSV plan settings carried")
})

if (nzchar(old_key)) {
  Sys.setenv(DB_ENCRYPTION_KEY = old_key)
} else {
  Sys.unsetenv("DB_ENCRYPTION_KEY")
}
