#!/usr/bin/env Rscript
#
# Verify toy trial data
#

library(DBI)
library(RSQLite)

# Paths
script_dir <- dirname(rstudioapi::getActiveDocumentContext()$path)
base_dir <- dirname(dirname(script_dir))
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
