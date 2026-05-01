# scripts/enroll_subjects.R - Subject enrollment for MEMORY-001

library(RSQLite)
library(DBI)

enroll_subject <- function(subject_id, randomization_group = NULL, enrollment_date = Sys.Date()) {
  
  # Connect to database
  con <- dbConnect(SQLite(), "data/memory001_study.db")
  
  # Check if subject already exists
  existing <- dbGetQuery(con, "SELECT subject_id FROM subjects WHERE subject_id = ?", 
                        params = list(subject_id))
  
  if (nrow(existing) > 0) {
    dbDisconnect(con)
    stop("Subject ", subject_id, " already enrolled!")
  }
  
  # Random assignment if not specified
  if (is.null(randomization_group)) {
    randomization_group <- sample(c("Active", "Placebo"), 1)
  }
  
  # Insert new subject
  dbExecute(con, "
    INSERT INTO subjects (subject_id, study_id, enrollment_date, randomization_group, status, created_by)
    VALUES (?, 'MEMORY-001', ?, ?, 'Enrolled', 'system')",
    params = list(subject_id, enrollment_date, randomization_group))
  
  # Create visit schedule
  visit_dates <- seq(from = as.Date(enrollment_date), by = "month", length.out = 7)
  visit_names <- c("Baseline", "Month 1", "Month 2", "Month 3", "Month 4", "Month 5", "Month 6")
  
  for (i in 1:length(visit_names)) {
    # Calculate visit window (±7 days)
    window_start <- visit_dates[i] - 7
    window_end <- visit_dates[i] + 7
    
    dbExecute(con, "
      INSERT INTO visit_schedule (subject_id, visit_name, scheduled_date, visit_window_start, visit_window_end)
      VALUES (?, ?, ?, ?, ?)",
      params = list(subject_id, visit_names[i], visit_dates[i], window_start, window_end))
  }
  
  dbDisconnect(con)
  
  cat("✅ Subject", subject_id, "enrolled successfully\n")
  cat("🎯 Randomized to:", randomization_group, "\n")
  cat("📅 Enrollment date:", enrollment_date, "\n")
  
  return(list(
    subject_id = subject_id,
    randomization_group = randomization_group,
    enrollment_date = enrollment_date,
    visit_schedule = data.frame(
      visit = visit_names,
      scheduled_date = visit_dates,
      window_start = visit_dates - 7,
      window_end = visit_dates + 7
    )
  ))
}

# Batch enrollment function
enroll_batch_subjects <- function(n_subjects = 10, start_date = Sys.Date()) {
  
  enrolled_subjects <- list()
  
  for (i in 1:n_subjects) {
    subject_id <- sprintf("MEM-%03d", i)
    enrollment_date <- start_date + sample(0:30, 1)  # Spread enrollment over 30 days
    
    tryCatch({
      result <- enroll_subject(subject_id, enrollment_date = enrollment_date)
      enrolled_subjects[[i]] <- result
    }, error = function(e) {
      cat("❌ Error enrolling", subject_id, ":", e$message, "\n")
    })
  }
  
  cat("\n📊 Enrollment Summary:\n")
  cat("Total subjects enrolled:", length(enrolled_subjects), "\n")
  
  # Randomization balance
  groups <- sapply(enrolled_subjects, function(x) x$randomization_group)
  table_groups <- table(groups)
  cat("Randomization balance:\n")
  print(table_groups)
  
  return(enrolled_subjects)
}

# Example usage:
# enroll_subject("MEM-001")
# enroll_batch_subjects(n_subjects = 20)