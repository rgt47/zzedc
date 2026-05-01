# setup_database.R - MEMORY-001 Study Database Setup

library(RSQLite)
library(DBI)
library(digest)
library(config)

# Load configuration
cfg <- config::get()

# Create database connection
db_path <- "data/memory001_study.db"

# Ensure data directory exists
if (!dir.exists("data")) {
  dir.create("data", recursive = TRUE)
}

con <- dbConnect(SQLite(), db_path)

cat("🚀 Setting up MEMORY-001 Study Database...\n")
cat("==========================================\n")

# Create study metadata table
dbExecute(con, "
CREATE TABLE IF NOT EXISTS study_info (
    study_id TEXT PRIMARY KEY,
    study_name TEXT NOT NULL,
    pi_name TEXT,
    start_date DATE,
    end_date DATE,
    target_enrollment INTEGER,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)")

# Insert study information
dbExecute(con, "
INSERT OR REPLACE INTO study_info 
(study_id, study_name, pi_name, start_date, end_date, target_enrollment)
VALUES 
('MEMORY-001', 'Cognitive Enhancement Trial', 'Dr. Sarah Johnson', 
 '2024-01-15', '2024-12-31', 50)")

cat("✅ Study metadata table created\n")

# Create subjects table
dbExecute(con, "
CREATE TABLE IF NOT EXISTS subjects (
    subject_id TEXT PRIMARY KEY,
    study_id TEXT NOT NULL,
    site_id TEXT DEFAULT '001',
    enrollment_date DATE,
    randomization_group TEXT CHECK(randomization_group IN ('Active', 'Placebo')),
    status TEXT DEFAULT 'Enrolled' CHECK(status IN ('Screened', 'Enrolled', 'Completed', 'Withdrawn')),
    withdrawal_reason TEXT,
    created_by TEXT,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    modified_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (study_id) REFERENCES study_info(study_id)
)")

cat("✅ Subjects table created\n")

# Create demographics form
dbExecute(con, "
CREATE TABLE IF NOT EXISTS demographics (
    record_id INTEGER PRIMARY KEY AUTOINCREMENT,
    subject_id TEXT NOT NULL,
    visit_name TEXT DEFAULT 'Baseline',
    age INTEGER CHECK(age >= 18 AND age <= 85),
    gender TEXT CHECK(gender IN ('Male', 'Female', 'Other', 'Prefer not to say')),
    race TEXT,
    ethnicity TEXT CHECK(ethnicity IN ('Hispanic or Latino', 'Not Hispanic or Latino', 'Unknown')),
    education_years INTEGER CHECK(education_years >= 0 AND education_years <= 25),
    handedness TEXT CHECK(handedness IN ('Right', 'Left', 'Ambidextrous')),
    height_cm REAL CHECK(height_cm >= 100 AND height_cm <= 250),
    weight_kg REAL CHECK(weight_kg >= 30 AND weight_kg <= 200),
    data_entry_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    data_entry_user TEXT,
    form_status TEXT DEFAULT 'Incomplete' CHECK(form_status IN ('Incomplete', 'Complete', 'Verified')),
    FOREIGN KEY (subject_id) REFERENCES subjects(subject_id)
)")

cat("✅ Demographics table created\n")

# Create cognitive assessments table
dbExecute(con, "
CREATE TABLE IF NOT EXISTS cognitive_assessments (
    record_id INTEGER PRIMARY KEY AUTOINCREMENT,
    subject_id TEXT NOT NULL,
    visit_name TEXT NOT NULL,
    visit_date DATE,
    mmse_total INTEGER CHECK(mmse_total >= 0 AND mmse_total <= 30),
    moca_total INTEGER CHECK(moca_total >= 0 AND moca_total <= 30),
    digit_span_forward INTEGER CHECK(digit_span_forward >= 0 AND digit_span_forward <= 9),
    digit_span_backward INTEGER CHECK(digit_span_backward >= 0 AND digit_span_backward <= 8),
    trail_making_a_time REAL CHECK(trail_making_a_time > 0),
    trail_making_b_time REAL CHECK(trail_making_b_time > 0),
    verbal_fluency_animals INTEGER CHECK(verbal_fluency_animals >= 0),
    assessment_notes TEXT,
    assessor_initials TEXT,
    data_entry_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    data_entry_user TEXT,
    form_status TEXT DEFAULT 'Incomplete' CHECK(form_status IN ('Incomplete', 'Complete', 'Verified')),
    FOREIGN KEY (subject_id) REFERENCES subjects(subject_id)
)")

cat("✅ Cognitive assessments table created\n")

# Create visit schedule table
dbExecute(con, "
CREATE TABLE IF NOT EXISTS visit_schedule (
    record_id INTEGER PRIMARY KEY AUTOINCREMENT,
    subject_id TEXT NOT NULL,
    visit_name TEXT NOT NULL,
    scheduled_date DATE,
    actual_date DATE,
    visit_window_start DATE,
    visit_window_end DATE,
    visit_status TEXT DEFAULT 'Scheduled' CHECK(visit_status IN ('Scheduled', 'Completed', 'Missed', 'Cancelled')),
    missed_reason TEXT,
    protocol_deviation BOOLEAN DEFAULT 0,
    deviation_description TEXT,
    data_entry_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    data_entry_user TEXT,
    FOREIGN KEY (subject_id) REFERENCES subjects(subject_id)
)")

cat("✅ Visit schedule table created\n")

# Create adverse events table
dbExecute(con, "
CREATE TABLE IF NOT EXISTS adverse_events (
    ae_id INTEGER PRIMARY KEY AUTOINCREMENT,
    subject_id TEXT NOT NULL,
    ae_term TEXT NOT NULL,
    ae_start_date DATE,
    ae_end_date DATE,
    ongoing BOOLEAN DEFAULT 0,
    severity TEXT CHECK(severity IN ('Mild', 'Moderate', 'Severe')),
    seriousness TEXT CHECK(seriousness IN ('Non-serious', 'Serious')),
    relationship TEXT CHECK(relationship IN ('Unrelated', 'Unlikely', 'Possible', 'Probable', 'Definite')),
    action_taken TEXT CHECK(action_taken IN ('None', 'Dose reduction', 'Dose interruption', 'Drug discontinued', 'Other')),
    outcome TEXT CHECK(outcome IN ('Resolved', 'Ongoing', 'Resolved with sequelae', 'Fatal')),
    reported_by TEXT,
    report_date DATE,
    data_entry_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    data_entry_user TEXT,
    form_status TEXT DEFAULT 'Incomplete' CHECK(form_status IN ('Incomplete', 'Complete', 'Verified')),
    FOREIGN KEY (subject_id) REFERENCES subjects(subject_id)
)")

cat("✅ Adverse events table created\n")

# Create data audit trail
dbExecute(con, "
CREATE TABLE IF NOT EXISTS audit_trail (
    audit_id INTEGER PRIMARY KEY AUTOINCREMENT,
    table_name TEXT NOT NULL,
    record_id TEXT NOT NULL,
    field_name TEXT,
    old_value TEXT,
    new_value TEXT,
    change_type TEXT CHECK(change_type IN ('INSERT', 'UPDATE', 'DELETE')),
    user_id TEXT,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    reason TEXT
)")

cat("✅ Audit trail table created\n")

# Create data validation rules
dbExecute(con, "
CREATE TABLE IF NOT EXISTS validation_rules (
    rule_id INTEGER PRIMARY KEY AUTOINCREMENT,
    table_name TEXT NOT NULL,
    field_name TEXT NOT NULL,
    rule_type TEXT CHECK(rule_type IN ('range', 'required', 'format', 'logic')),
    rule_expression TEXT NOT NULL,
    error_message TEXT NOT NULL,
    severity TEXT DEFAULT 'Error' CHECK(severity IN ('Warning', 'Error')),
    active BOOLEAN DEFAULT 1
)")

# Insert sample validation rules
validation_rules <- data.frame(
  table_name = c("demographics", "demographics", "cognitive_assessments", "cognitive_assessments"),
  field_name = c("age", "weight_kg", "mmse_total", "visit_date"),
  rule_type = c("range", "range", "range", "required"),
  rule_expression = c("18 <= age <= 85", "30 <= weight_kg <= 200", "0 <= mmse_total <= 30", "NOT NULL"),
  error_message = c("Age must be between 18 and 85", "Weight must be between 30 and 200 kg", 
                   "MMSE score must be between 0 and 30", "Visit date is required"),
  severity = c("Error", "Error", "Error", "Error"),
  active = c(1, 1, 1, 1)
)

dbWriteTable(con, "validation_rules", validation_rules, append = TRUE, row.names = FALSE)

cat("✅ Validation rules table created\n")

# Create users table for the EDC system
dbExecute(con, "
CREATE TABLE IF NOT EXISTS edc_users (
    user_id TEXT PRIMARY KEY,
    username TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    full_name TEXT,
    email TEXT,
    role TEXT CHECK(role IN ('Admin', 'PI', 'Coordinator', 'Data Manager', 'Monitor')),
    site_id TEXT,
    active BOOLEAN DEFAULT 1,
    last_login TIMESTAMP,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by TEXT
)")

# Create secure password hashes (using digest with salt)
create_password_hash <- function(password) {
  salt <- Sys.getenv(cfg$auth$salt_env_var)
  if (salt == "") {
    salt <- cfg$auth$default_salt
  }
  digest(paste0(password, salt), algo = "sha256")
}

# Insert sample users with secure password hashing
sample_users <- data.frame(
  user_id = c("admin", "pi_johnson", "coord_smith", "dm_brown"),
  username = c("admin", "sjohnson", "asmith", "mbrown"),
  password_hash = c(
    create_password_hash("admin123"),
    create_password_hash("password123"), 
    create_password_hash("coord123"),
    create_password_hash("data123")
  ),
  full_name = c("System Administrator", "Dr. Sarah Johnson", "Alice Smith", "Mike Brown"),
  email = c("admin@memory001.org", "sjohnson@university.edu", "asmith@university.edu", "mbrown@university.edu"),
  role = c("Admin", "PI", "Coordinator", "Data Manager"),
  site_id = c("ALL", "001", "001", "001"),
  active = c(1, 1, 1, 1),
  created_by = c("SYSTEM", "admin", "admin", "admin")
)

dbWriteTable(con, "edc_users", sample_users, append = TRUE, row.names = FALSE)

cat("✅ EDC users table created\n")

# Create database indexes for performance
dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_subjects_study_id ON subjects(study_id)")
dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_demographics_subject_id ON demographics(subject_id)")
dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_cognitive_subject_visit ON cognitive_assessments(subject_id, visit_name)")
dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_audit_trail_timestamp ON audit_trail(timestamp)")
dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_edc_users_username ON edc_users(username)")

cat("✅ Database indexes created\n")

# Insert sample data for demonstration
sample_subjects <- data.frame(
  subject_id = c("MEM-001", "MEM-002", "MEM-003"),
  study_id = c("MEMORY-001", "MEMORY-001", "MEMORY-001"),
  enrollment_date = c("2024-01-20", "2024-01-22", "2024-01-25"),
  randomization_group = c("Active", "Placebo", "Active"),
  status = c("Enrolled", "Enrolled", "Enrolled"),
  created_by = c("asmith", "asmith", "asmith")
)

dbWriteTable(con, "subjects", sample_subjects, append = TRUE, row.names = FALSE)

# Sample demographics data
sample_demographics <- data.frame(
  subject_id = c("MEM-001", "MEM-002", "MEM-003"),
  age = c(67, 72, 59),
  gender = c("Female", "Male", "Female"), 
  race = c("White", "White", "Asian"),
  ethnicity = c("Not Hispanic or Latino", "Not Hispanic or Latino", "Not Hispanic or Latino"),
  education_years = c(16, 12, 18),
  height_cm = c(165, 178, 160),
  weight_kg = c(68, 82, 62),
  data_entry_user = c("asmith", "asmith", "asmith"),
  form_status = c("Complete", "Complete", "Incomplete")
)

dbWriteTable(con, "demographics", sample_demographics, append = TRUE, row.names = FALSE)

# Sample cognitive assessment data
sample_cognitive <- data.frame(
  subject_id = c("MEM-001", "MEM-002", "MEM-003"),
  visit_name = c("Baseline", "Baseline", "Baseline"),
  visit_date = c("2024-01-20", "2024-01-22", "2024-01-25"),
  mmse_total = c(28, 26, 29),
  moca_total = c(26, 24, 28),
  digit_span_forward = c(6, 5, 7),
  digit_span_backward = c(4, 3, 5),
  trail_making_a_time = c(32.5, 45.2, 28.1),
  trail_making_b_time = c(78.2, 95.6, 65.4),
  verbal_fluency_animals = c(18, 15, 21),
  assessor_initials = c("AS", "AS", "AS"),
  data_entry_user = c("asmith", "asmith", "asmith"),
  form_status = c("Complete", "Complete", "Incomplete")
)

dbWriteTable(con, "cognitive_assessments", sample_cognitive, append = TRUE, row.names = FALSE)

cat("✅ Sample data inserted\n")

# Close connection
dbDisconnect(con)

cat("\n🎉 MEMORY-001 Database Setup Complete!\n")
cat("======================================\n")
cat("📁 Database file: data/memory001_study.db\n")
cat("📊 Tables created: 8 core tables + indexes\n")
cat("👥 Sample users created:\n")
cat("   • admin/admin123 (Administrator)\n")
cat("   • sjohnson/password123 (Principal Investigator)\n")
cat("   • asmith/coord123 (Research Coordinator)\n") 
cat("   • mbrown/data123 (Data Manager)\n")
cat("\n📋 Sample data:\n")
cat("   • 3 enrolled subjects (MEM-001, MEM-002, MEM-003)\n")
cat("   • Demographics and baseline assessments\n")
cat("   • Validation rules configured\n")

cat("\n🚀 Ready to launch ZZedc!\n")
cat("   Run: launch_zzedc() or source('run_app.R')\n")
cat("\n⚠️  Remember to change default passwords in production!\n")