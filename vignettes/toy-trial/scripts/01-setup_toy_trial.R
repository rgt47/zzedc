#!/usr/bin/env Rscript
#
# Toy Clinical Trial Setup Script
# Creates complete ZZedc database with 20 subjects, randomization, and MMSE data
#

cat("Creating Toy Clinical Trial Database...\n")
cat("=========================================\n\n")

# Load required packages
library(DBI)
library(RSQLite)
library(digest)

# Paths (adjust based on working directory)
script_dir <- dirname(rstudioapi::getActiveDocumentContext()$path)
base_dir <- dirname(dirname(script_dir))
db_path <- file.path(base_dir, "data", "toy_trial.db")
csv_dir <- file.path(base_dir, "csv_templates")

# Create data directory if needed
data_dir <- dirname(db_path)
if (!dir.exists(data_dir)) dir.create(data_dir, recursive = TRUE)

# 1. CREATE DATABASE
cat("Step 1: Creating SQLite database...\n")
conn <- dbConnect(SQLite(), db_path)

# 2. CREATE STUDY_INFO TABLE
cat("Step 2: Creating study information table...\n")
dbExecute(conn, "
  CREATE TABLE IF NOT EXISTS study_info (
    study_id TEXT PRIMARY KEY,
    study_name TEXT NOT NULL,
    protocol_id TEXT UNIQUE NOT NULL,
    principal_investigator TEXT,
    pi_email TEXT,
    study_phase TEXT,
    target_enrollment INTEGER,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  )
")

# Insert study info
study_id <- "TOY-TRIAL-001"
dbExecute(conn, "
  INSERT OR REPLACE INTO study_info
  (study_id, study_name, protocol_id, principal_investigator, pi_email,
   study_phase, target_enrollment)
  VALUES (?, ?, ?, ?, ?, ?, ?)
", list(
  study_id,
  "Active vs. Placebo Memory Enhancement Study",
  "PROTO-2025-001",
  "Dr. John Smith",
  "john.smith@hospital.org",
  "Phase III",
  20
))

cat("  Study: TOY-TRIAL-001 created\n")

# 3. CREATE SUBJECTS TABLE
cat("Step 3: Creating subjects table...\n")
dbExecute(conn, "
  CREATE TABLE IF NOT EXISTS subjects (
    subject_id TEXT PRIMARY KEY,
    study_id TEXT NOT NULL REFERENCES study_info(study_id),
    enrollment_date TIMESTAMP,
    enrollment_age INTEGER,
    gender TEXT CHECK(gender IN ('M', 'F')),
    status TEXT CHECK(status IN ('Active', 'Completed', 'Withdrawn')),
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  )
")

# Read subjects CSV and insert
subjects_csv <- read.csv(file.path(csv_dir, "subjects.csv"))
cat("  Loading", nrow(subjects_csv), "subjects...\n")

for (i in 1:nrow(subjects_csv)) {
  row <- subjects_csv[i, ]
  dbExecute(conn, "
    INSERT INTO subjects
    (subject_id, study_id, enrollment_date, enrollment_age, gender, status)
    VALUES (?, ?, ?, ?, ?, 'Active')
  ", list(
    row$subject_id,
    study_id,
    row$enrollment_date,
    row$age,
    row$gender
  ))
}

# 4. CREATE RANDOMIZATION TABLE
cat("Step 4: Creating randomization table...\n")
dbExecute(conn, "
  CREATE TABLE IF NOT EXISTS randomization (
    randomization_id TEXT PRIMARY KEY,
    subject_id TEXT NOT NULL REFERENCES subjects(subject_id),
    randomization_date TIMESTAMP,
    treatment_assignment TEXT CHECK(treatment_assignment IN ('Active', 'Placebo')),
    study_coordinator TEXT,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  )
")

# Read randomization CSV and insert
rand_csv <- read.csv(file.path(csv_dir, "randomization.csv"))
cat("  Loading randomization data for", nrow(rand_csv), "subjects...\n")

for (i in 1:nrow(rand_csv)) {
  row <- rand_csv[i, ]
  rand_id <- paste0("RAND-", row$subject_id, "-", format(Sys.time(), "%Y%m%d"))
  dbExecute(conn, "
    INSERT INTO randomization
    (randomization_id, subject_id, randomization_date, treatment_assignment, study_coordinator)
    VALUES (?, ?, ?, ?, ?)
  ", list(
    rand_id,
    row$subject_id,
    row$randomization_date,
    row$treatment_assignment,
    row$study_coordinator
  ))
}

# 5. CREATE MMSE ASSESSMENTS TABLE
cat("Step 5: Creating MMSE assessments table...\n")
dbExecute(conn, "
  CREATE TABLE IF NOT EXISTS mmse_assessments (
    assessment_id TEXT PRIMARY KEY,
    subject_id TEXT NOT NULL REFERENCES subjects(subject_id),
    visit_label TEXT CHECK(visit_label IN ('Baseline', 'Week 4', 'Week 8')),
    assessment_date TIMESTAMP,
    orientation_time INTEGER CHECK(orientation_time BETWEEN 0 AND 5),
    orientation_place INTEGER CHECK(orientation_place BETWEEN 0 AND 5),
    registration INTEGER CHECK(registration BETWEEN 0 AND 3),
    attention INTEGER CHECK(attention BETWEEN 0 AND 5),
    recall INTEGER CHECK(recall BETWEEN 0 AND 3),
    language INTEGER CHECK(language BETWEEN 0 AND 8),
    visual_spatial INTEGER CHECK(visual_spatial BETWEEN 0 AND 1),
    mmse_total INTEGER CHECK(mmse_total BETWEEN 0 AND 30),
    adverse_events TEXT CHECK(adverse_events IN ('Yes', 'No')),
    ae_description TEXT,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  )
")

# Read MMSE CSV and insert
mmse_csv <- read.csv(file.path(csv_dir, "mmse_assessments.csv"))
cat("  Loading", nrow(mmse_csv), "MMSE assessments...\n")

for (i in 1:nrow(mmse_csv)) {
  row <- mmse_csv[i, ]
  assessment_id <- paste0("MMSE-", row$subject_id, "-",
                          format(as.Date(row$assessment_date), "%Y%m%d"))
  dbExecute(conn, "
    INSERT INTO mmse_assessments
    (assessment_id, subject_id, visit_label, assessment_date,
     orientation_time, orientation_place, registration, attention,
     recall, language, visual_spatial, mmse_total, adverse_events, ae_description)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ", list(
    assessment_id,
    row$subject_id,
    row$visit_label,
    row$assessment_date,
    row$orientation_time,
    row$orientation_place,
    row$registration,
    row$attention,
    row$recall,
    row$language,
    row$visual_spatial,
    row$mmse_total,
    row$adverse_events,
    ifelse(is.na(row$ae_description), "", row$ae_description)
  ))
}

# 6. CREATE INDEXES FOR PERFORMANCE
cat("Step 6: Creating database indexes...\n")
dbExecute(conn, "CREATE INDEX idx_subjects_study ON subjects(study_id)")
dbExecute(conn, "CREATE INDEX idx_rand_subject ON randomization(subject_id)")
dbExecute(conn, "CREATE INDEX idx_mmse_subject ON mmse_assessments(subject_id)")
dbExecute(conn, "CREATE INDEX idx_mmse_visit ON mmse_assessments(visit_label)")
dbExecute(conn, "CREATE INDEX idx_mmse_date ON mmse_assessments(assessment_date)")

# 7. VERIFY DATA
cat("\nStep 7: Verifying data...\n")

subject_count <- dbGetQuery(conn, "SELECT COUNT(*) as count FROM subjects")[1,1]
rand_count <- dbGetQuery(conn, "SELECT COUNT(*) as count FROM randomization")[1,1]
mmse_count <- dbGetQuery(conn, "SELECT COUNT(*) as count FROM mmse_assessments")[1,1]

cat("  Total subjects enrolled:", subject_count, "\n")
cat("  Total randomizations:", rand_count, "\n")
cat("  Total MMSE assessments:", mmse_count, "\n")

# Show treatment breakdown
treatment_breakdown <- dbGetQuery(conn, "
  SELECT treatment_assignment, COUNT(*) as count
  FROM randomization
  GROUP BY treatment_assignment
")
cat("\n  Treatment breakdown:\n")
for (i in 1:nrow(treatment_breakdown)) {
  cat("    ", treatment_breakdown[i,1], ":", treatment_breakdown[i,2], "\n")
}

# Show visit breakdown
visit_breakdown <- dbGetQuery(conn, "
  SELECT visit_label, COUNT(*) as count
  FROM mmse_assessments
  GROUP BY visit_label
")
cat("\n  Visit breakdown:\n")
for (i in 1:nrow(visit_breakdown)) {
  cat("    ", visit_breakdown[i,1], ":", visit_breakdown[i,2], "\n")
}

# Close connection
dbDisconnect(conn)

cat("\n=========================================\n")
cat("SUCCESS: Toy trial database created!\n")
cat("Database location:", db_path, "\n")
cat("Ready to launch ZZedc with toy trial data\n")
cat("=========================================\n")
