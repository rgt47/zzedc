#!/usr/bin/env Rscript
#
# Verify toy trial data
#
# Usage:
#   From package root: Rscript vignettes/toy-trial/scripts/03-verify_toy_trial.R
#   From scripts dir:  Rscript 03-verify_toy_trial.R
#

library(DBI)
library(RSQLite)

# Determine script location (works from command line or RStudio)
get_script_dir <- function() {

  if (requireNamespace("rstudioapi", quietly = TRUE) &&
      rstudioapi::isAvailable()) {
    return(dirname(rstudioapi::getActiveDocumentContext()$path))
  }

  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    return(dirname(normalizePath(sub("^--file=", "", file_arg))))
  }

  for (i in seq_len(sys.nframe())) {
    if (!is.null(sys.frame(i)$ofile)) {
      return(dirname(normalizePath(sys.frame(i)$ofile)))
    }
  }

  candidates <- c(
    "vignettes/toy-trial/scripts",
    ".",
    file.path(getwd(), "vignettes/toy-trial/scripts")
  )
  for (cand in candidates) {
    if (file.exists(file.path(cand, "03-verify_toy_trial.R"))) {
      return(normalizePath(cand))
    }
  }

  stop("Cannot determine script directory. Run from package root or scripts dir.")
}

script_dir <- get_script_dir()
base_dir <- dirname(script_dir)
db_path <- file.path(base_dir, "data", "toy_trial.db")

conn <- dbConnect(SQLite(), db_path)

cat("\n=== TOY TRIAL VERIFICATION ===\n\n")

# Study info
cat("Study Information:\n")
study_info <- dbGetQuery(conn, "SELECT * FROM study_info")
print(study_info[, c("study_id", "study_name", "protocol_id", "target_enrollment")])

cat("\n\nSubject Summary:\n")
subjects <- dbGetQuery(conn, "
  SELECT
    COUNT(*) as total_subjects,
    COUNT(DISTINCT gender) as genders,
    ROUND(AVG(enrollment_age), 1) as mean_age,
    MIN(enrollment_age) as min_age,
    MAX(enrollment_age) as max_age
  FROM subjects
")
print(subjects)

cat("\n\nTreatment Assignment:\n")
treatment <- dbGetQuery(conn, "
  SELECT treatment_assignment, COUNT(*) as count
  FROM randomization
  GROUP BY treatment_assignment
")
print(treatment)

cat("\n\nMMSE Scores by Visit and Treatment:\n")
mmse_summary <- dbGetQuery(conn, "
  SELECT
    r.treatment_assignment as treatment,
    m.visit_label as visit,
    COUNT(*) as n_subjects,
    ROUND(AVG(m.mmse_total), 1) as mean_score,
    ROUND(MIN(m.mmse_total), 0) as min_score,
    ROUND(MAX(m.mmse_total), 0) as max_score
  FROM mmse_assessments m
  JOIN randomization r ON m.subject_id = r.subject_id
  GROUP BY r.treatment_assignment, m.visit_label
  ORDER BY r.treatment_assignment,
           CASE m.visit_label
             WHEN 'Baseline' THEN 1
             WHEN 'Week 4' THEN 2
             WHEN 'Week 8' THEN 3
           END
")
print(mmse_summary)

cat("\n\nAdverse Events:\n")
adverse <- dbGetQuery(conn, "
  SELECT
    m.subject_id,
    r.treatment_assignment,
    m.visit_label,
    m.ae_description
  FROM mmse_assessments m
  JOIN randomization r ON m.subject_id = r.subject_id
  WHERE m.adverse_events = 'Yes' AND m.ae_description != ''
")
if (nrow(adverse) > 0) {
  print(adverse)
} else {
  cat("No adverse events recorded\n")
}

dbDisconnect(conn)

cat("\n=== VERIFICATION COMPLETE ===\n\n")
