# Feature #3: Enhanced Audit Trail System - Test Suite
#
# Tests for enhanced audit logging functionality including:
# - System event logging
# - Security event logging
# - Anomaly detection
# - Advanced search capabilities

library(testthat)
library(DBI)
library(RSQLite)

# Source the modules
find_pkg_root <- function() {
  candidates <- c(
    getwd(),
    file.path(getwd(), "..", ".."),
    Sys.getenv("ZZEDC_PKG_ROOT", unset = NA)
  )
  for (path in candidates) {
    if (!is.na(path) && file.exists(file.path(path, "R", "audit_enhanced.R"))) {
      return(normalizePath(path))
    }
  }
  stop("Could not find package root directory")
}

pkg_root <- find_pkg_root()
source(file.path(pkg_root, "R", "encryption_utils.R"))
source(file.path(pkg_root, "R", "db_connection.R"))
source(file.path(pkg_root, "R", "audit_logging.R"))
source(file.path(pkg_root, "R", "audit_enhanced.R"))

# =============================================================================
# Test Section 1: Event Types
# =============================================================================

test_that("get_audit_event_types returns all categories", {
  types <- get_audit_event_types()

  expect_type(types, "list")
  expect_true("data" %in% names(types))
  expect_true("security" %in% names(types))
  expect_true("system" %in% names(types))
  expect_true("config" %in% names(types))
  expect_true("signature" %in% names(types))
})

test_that("get_all_event_types returns flat vector", {
  all_types <- get_all_event_types()

  expect_type(all_types, "character")
  expect_true(length(all_types) > 20)
  expect_true("INSERT" %in% all_types)
  expect_true("LOGIN_FAILED" %in% all_types)
  expect_true("BACKUP" %in% all_types)
})

# =============================================================================
# Test Section 2: System Event Logging
# =============================================================================

test_that("log_system_event validates event types", {
  expect_error(
    log_system_event(
      event_type = "INVALID",
      description = "Test"
    ),
    "Invalid system event_type"
  )
})

test_that("log_system_event accepts valid types", {
  test_db <- tempfile(fileext = ".db")
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

  init_result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
  expect_true(init_result$success)

  audit_result <- init_audit_logging(db_path = test_db)
  expect_true(audit_result$success)

  result <- log_system_event(
    event_type = "BACKUP",
    description = "Test backup completed",
    details = list(size_mb = 10),
    severity = "info",
    db_path = test_db
  )

  expect_true(result)

  unlink(test_db)
  if (old_key != "") {
    Sys.setenv(DB_ENCRYPTION_KEY = old_key)
  } else {
    Sys.unsetenv("DB_ENCRYPTION_KEY")
  }
})

test_that("log_backup_event records backup operations", {
  test_db <- tempfile(fileext = ".db")
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

  init_result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
  audit_result <- init_audit_logging(db_path = test_db)

  result <- log_backup_event(
    backup_path = "/backups/test.db",
    backup_type = "full",
    size_bytes = 1024000,
    duration_seconds = 5,
    success = TRUE,
    db_path = test_db
  )

  expect_true(result)

  conn <- connect_encrypted_db(db_path = test_db)
  records <- DBI::dbGetQuery(conn,
    "SELECT * FROM audit_log WHERE event_type = 'BACKUP'")
  DBI::dbDisconnect(conn)

  expect_gt(nrow(records), 0)
  expect_match(records$operation[1], "Backup completed")

  unlink(test_db)
  if (old_key != "") {
    Sys.setenv(DB_ENCRYPTION_KEY = old_key)
  } else {
    Sys.unsetenv("DB_ENCRYPTION_KEY")
  }
})

# =============================================================================
# Test Section 3: Security Event Logging
# =============================================================================

test_that("log_security_event validates event types", {
  expect_error(
    log_security_event(
      event_type = "INVALID",
      user_id = "test",
      description = "Test"
    ),
    "Invalid security event_type"
  )
})

test_that("log_failed_login records authentication failures", {
  test_db <- tempfile(fileext = ".db")
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

  init_result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
  audit_result <- init_audit_logging(db_path = test_db)

  result <- log_failed_login(
    username = "hacker",
    reason = "Invalid password",
    ip_address = "192.168.1.100",
    attempt_count = 3,
    db_path = test_db
  )

  expect_true(result)

  conn <- connect_encrypted_db(db_path = test_db)
  records <- DBI::dbGetQuery(conn,
    "SELECT * FROM audit_log WHERE event_type = 'LOGIN_FAILED'")
  DBI::dbDisconnect(conn)

  expect_gt(nrow(records), 0)
  expect_equal(records$user_id[1], "hacker")

  unlink(test_db)
  if (old_key != "") {
    Sys.setenv(DB_ENCRYPTION_KEY = old_key)
  } else {
    Sys.unsetenv("DB_ENCRYPTION_KEY")
  }
})

test_that("log_account_lockout records lockout events", {
  test_db <- tempfile(fileext = ".db")
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

  init_result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
  audit_result <- init_audit_logging(db_path = test_db)

  result <- log_account_lockout(
    username = "suspicious_user",
    reason = "5 failed attempts",
    duration_minutes = 30,
    db_path = test_db
  )

  expect_true(result)

  conn <- connect_encrypted_db(db_path = test_db)
  records <- DBI::dbGetQuery(conn,
    "SELECT * FROM audit_log WHERE event_type = 'LOCKOUT'")
  DBI::dbDisconnect(conn)

  expect_gt(nrow(records), 0)
  expect_match(records$operation[1], "Account locked")

  unlink(test_db)
  if (old_key != "") {
    Sys.setenv(DB_ENCRYPTION_KEY = old_key)
  } else {
    Sys.unsetenv("DB_ENCRYPTION_KEY")
  }
})

test_that("log_password_change records password updates", {
  test_db <- tempfile(fileext = ".db")
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

  init_result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
  audit_result <- init_audit_logging(db_path = test_db)

  result <- log_password_change(
    user_id = "john.doe",
    changed_by = "admin",
    method = "admin",
    db_path = test_db
  )

  expect_true(result)

  unlink(test_db)
  if (old_key != "") {
    Sys.setenv(DB_ENCRYPTION_KEY = old_key)
  } else {
    Sys.unsetenv("DB_ENCRYPTION_KEY")
  }
})

test_that("log_role_change records permission modifications", {
  test_db <- tempfile(fileext = ".db")
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

  init_result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
  audit_result <- init_audit_logging(db_path = test_db)

  result <- log_role_change(
    user_id = "jane.smith",
    old_role = "User",
    new_role = "Admin",
    changed_by = "system_admin",
    reason = "Promotion",
    db_path = test_db
  )

  expect_true(result)

  conn <- connect_encrypted_db(db_path = test_db)
  records <- DBI::dbGetQuery(conn,
    "SELECT * FROM audit_log WHERE event_type = 'ROLE_CHANGE'")
  DBI::dbDisconnect(conn)

  expect_gt(nrow(records), 0)
  expect_match(records$operation[1], "Role changed from User to Admin")

  unlink(test_db)
  if (old_key != "") {
    Sys.setenv(DB_ENCRYPTION_KEY = old_key)
  } else {
    Sys.unsetenv("DB_ENCRYPTION_KEY")
  }
})

# =============================================================================
# Test Section 4: Configuration Change Logging
# =============================================================================

test_that("log_config_change records setting modifications", {
  test_db <- tempfile(fileext = ".db")
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

  init_result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
  audit_result <- init_audit_logging(db_path = test_db)

  result <- log_config_change(
    setting_name = "session_timeout",
    old_value = "30",
    new_value = "60",
    changed_by = "admin",
    reason = "Extended for user convenience",
    db_path = test_db
  )

  expect_true(result)

  conn <- connect_encrypted_db(db_path = test_db)
  records <- DBI::dbGetQuery(conn,
    "SELECT * FROM audit_log WHERE event_type = 'CONFIG_CHANGE'")
  DBI::dbDisconnect(conn)

  expect_gt(nrow(records), 0)
  expect_equal(records$record_id[1], "session_timeout")

  unlink(test_db)
  if (old_key != "") {
    Sys.setenv(DB_ENCRYPTION_KEY = old_key)
  } else {
    Sys.unsetenv("DB_ENCRYPTION_KEY")
  }
})

# =============================================================================
# Test Section 5: Anomaly Detection
# =============================================================================

test_that("detect_audit_anomalies returns valid structure", {
  test_db <- tempfile(fileext = ".db")
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

  init_result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
  audit_result <- init_audit_logging(db_path = test_db)

  result <- detect_audit_anomalies(
    lookback_hours = 24,
    db_path = test_db
  )

  expect_type(result, "list")
  expect_true("alerts" %in% names(result))
  expect_true("risk_score" %in% names(result))
  expect_true("risk_level" %in% names(result))
  expect_true(result$risk_level %in% c("LOW", "MEDIUM", "HIGH", "UNKNOWN"))

  unlink(test_db)
  if (old_key != "") {
    Sys.setenv(DB_ENCRYPTION_KEY = old_key)
  } else {
    Sys.unsetenv("DB_ENCRYPTION_KEY")
  }
})

test_that("detect_audit_anomalies detects excessive failed logins", {
  test_db <- tempfile(fileext = ".db")
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

  init_result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
  audit_result <- init_audit_logging(db_path = test_db)

  for (i in 1:6) {
    log_failed_login(
      username = "target_user",
      reason = "Invalid password",
      attempt_count = i,
      db_path = test_db
    )
  }

  result <- detect_audit_anomalies(
    lookback_hours = 1,
    thresholds = list(failed_logins_per_user = 5),
    db_path = test_db
  )

  expect_gt(result$risk_score, 0)
  expect_gt(length(result$alerts), 0)

  alert_types <- sapply(result$alerts, function(a) a$type)
  expect_true("BRUTE_FORCE_SUSPECTED" %in% alert_types)

  unlink(test_db)
  if (old_key != "") {
    Sys.setenv(DB_ENCRYPTION_KEY = old_key)
  } else {
    Sys.unsetenv("DB_ENCRYPTION_KEY")
  }
})

# =============================================================================
# Test Section 6: Enhanced Search
# =============================================================================

test_that("search_audit_trail returns results", {
  test_db <- tempfile(fileext = ".db")
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

  init_result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
  audit_result <- init_audit_logging(db_path = test_db)

  log_system_event("BACKUP", "Test backup", db_path = test_db)
  log_failed_login("user1", db_path = test_db)
  log_config_change("setting1", "old", "new", "admin", db_path = test_db)

  results <- search_audit_trail(
    limit = 100,
    db_path = test_db
  )

  expect_s3_class(results, "data.frame")
  expect_gt(nrow(results), 0)

  unlink(test_db)
  if (old_key != "") {
    Sys.setenv(DB_ENCRYPTION_KEY = old_key)
  } else {
    Sys.unsetenv("DB_ENCRYPTION_KEY")
  }
})

test_that("search_audit_trail filters by event type", {
  test_db <- tempfile(fileext = ".db")
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

  init_result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
  audit_result <- init_audit_logging(db_path = test_db)

  log_system_event("BACKUP", "Backup 1", db_path = test_db)
  log_system_event("BACKUP", "Backup 2", db_path = test_db)
  log_failed_login("user1", db_path = test_db)

  results <- search_audit_trail(
    event_types = c("BACKUP"),
    db_path = test_db
  )

  expect_equal(nrow(results), 2)
  expect_true(all(results$event_type == "BACKUP"))

  unlink(test_db)
  if (old_key != "") {
    Sys.setenv(DB_ENCRYPTION_KEY = old_key)
  } else {
    Sys.unsetenv("DB_ENCRYPTION_KEY")
  }
})

test_that("search_audit_trail filters by user", {
  test_db <- tempfile(fileext = ".db")
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

  init_result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
  audit_result <- init_audit_logging(db_path = test_db)

  log_failed_login("alice", db_path = test_db)
  log_failed_login("alice", db_path = test_db)
  log_failed_login("bob", db_path = test_db)

  results <- search_audit_trail(
    users = c("alice"),
    db_path = test_db
  )

  expect_equal(nrow(results), 2)
  expect_true(all(results$user_id == "alice"))

  unlink(test_db)
  if (old_key != "") {
    Sys.setenv(DB_ENCRYPTION_KEY = old_key)
  } else {
    Sys.unsetenv("DB_ENCRYPTION_KEY")
  }
})

# =============================================================================
# Test Section 7: Audit Statistics
# =============================================================================

test_that("get_audit_statistics returns summary data", {
  test_db <- tempfile(fileext = ".db")
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

  init_result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
  audit_result <- init_audit_logging(db_path = test_db)

  log_system_event("BACKUP", "Test 1", db_path = test_db)
  log_system_event("BACKUP", "Test 2", db_path = test_db)
  log_failed_login("user1", db_path = test_db)

  stats <- get_audit_statistics(period = "week", db_path = test_db)

  expect_type(stats, "list")
  expect_true("total_events" %in% names(stats))
  expect_true("events_by_type" %in% names(stats))
  expect_gte(stats$total_events, 3)

  unlink(test_db)
  if (old_key != "") {
    Sys.setenv(DB_ENCRYPTION_KEY = old_key)
  } else {
    Sys.unsetenv("DB_ENCRYPTION_KEY")
  }
})

# =============================================================================
# Test Section 8: Integration Tests
# =============================================================================

test_that("complete audit workflow functions correctly", {
  test_db <- tempfile(fileext = ".db")
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

  init_result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
  audit_result <- init_audit_logging(db_path = test_db)

  log_system_event("STARTUP", "Application started", severity = "info",
                   db_path = test_db)

  log_failed_login("attacker", reason = "Invalid username",
                   ip_address = "10.0.0.1", db_path = test_db)

  log_config_change("max_login_attempts", "5", "3", "admin",
                    reason = "Security hardening", db_path = test_db)

  log_backup_event("/backups/daily.db", backup_type = "full",
                   size_bytes = 5000000, success = TRUE, db_path = test_db)

  anomalies <- detect_audit_anomalies(lookback_hours = 1, db_path = test_db)
  expect_type(anomalies, "list")

  stats <- get_audit_statistics(period = "day", db_path = test_db)
  expect_gte(stats$total_events, 4)

  all_events <- search_audit_trail(limit = 100, db_path = test_db)
  expect_gte(nrow(all_events), 4)

  integrity <- verify_audit_integrity(db_path = test_db)
  expect_true(integrity$valid)

  unlink(test_db)
  if (old_key != "") {
    Sys.setenv(DB_ENCRYPTION_KEY = old_key)
  } else {
    Sys.unsetenv("DB_ENCRYPTION_KEY")
  }
})
