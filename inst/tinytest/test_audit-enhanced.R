library(tinytest)

# Helpers (auto-loaded by testthat under the previous layout).
# tinytest auto-sources files prefixed with `_` (so `_setup.R`)
# when invoked via `tinytest::test_package()`. The explicit
# source() below keeps the test runnable when invoked directly
# (e.g., `tinytest::run_test_file("test_foo.R")`).
if (file.exists("_setup.R")) source("_setup.R")
# Feature #3: Enhanced Audit Trail System - Test Suite
#
# Tests for enhanced audit logging functionality including:
# - System event logging
# - Security event logging
# - Anomaly detection
# - Advanced search capabilities

# Skip all tests if audit functions are not available
if (!(exists("get_audit_event_types"))) exit_file("Audit functions not available")

# =============================================================================
# Test Section 1: Event Types
# =============================================================================

# Test: get_audit_event_types returns all categories
local({
    types <- get_audit_event_types()

    expect_equal(typeof(types), "list")
    expect_true("data" %in% names(types))
    expect_true("security" %in% names(types))
    expect_true("system" %in% names(types))
    expect_true("config" %in% names(types))
    expect_true("signature" %in% names(types))

})
# Test: get_all_event_types returns flat vector
local({
    all_types <- zzedc:::get_all_event_types()

    expect_equal(typeof(all_types), "character")
    expect_true(length(all_types) > 20)
    expect_true("INSERT" %in% all_types)
    expect_true("LOGIN_FAILED" %in% all_types)
    expect_true("BACKUP" %in% all_types)

})
# =============================================================================
# Test Section 2: System Event Logging
# =============================================================================

# Test: log_system_event validates event types
local({
    expect_error(
      log_system_event(
        event_type = "INVALID",
        description = "Test"
      ),
      "Invalid system event_type"
    )

})
# Test: log_system_event accepts valid types
local({
    test_db <- tempfile(fileext = ".db")
    old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

    init_result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
    Sys.setenv(DB_ENCRYPTION_KEY = init_result$key)
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
# Test: log_backup_event records backup operations
local({
    test_db <- tempfile(fileext = ".db")
    old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

    init_result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
    Sys.setenv(DB_ENCRYPTION_KEY = init_result$key)
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

    expect_true(nrow(records) > 0)
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

# Test: log_security_event validates event types
local({
    expect_error(
      log_security_event(
        event_type = "INVALID",
        user_id = "test",
        description = "Test"
      ),
      "Invalid security event_type"
    )

})
# Test: log_failed_login records authentication failures
local({
    test_db <- tempfile(fileext = ".db")
    old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

    init_result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
    Sys.setenv(DB_ENCRYPTION_KEY = init_result$key)
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

    expect_true(nrow(records) > 0)
    expect_equal(records$user_id[1], "hacker")

    unlink(test_db)
    if (old_key != "") {
      Sys.setenv(DB_ENCRYPTION_KEY = old_key)
    } else {
      Sys.unsetenv("DB_ENCRYPTION_KEY")
    }

})
# Test: log_account_lockout records lockout events
local({
    test_db <- tempfile(fileext = ".db")
    old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

    init_result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
    Sys.setenv(DB_ENCRYPTION_KEY = init_result$key)
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

    expect_true(nrow(records) > 0)
    expect_match(records$operation[1], "Account locked")

    unlink(test_db)
    if (old_key != "") {
      Sys.setenv(DB_ENCRYPTION_KEY = old_key)
    } else {
      Sys.unsetenv("DB_ENCRYPTION_KEY")
    }

})
# Test: log_password_change records password updates
local({
    test_db <- tempfile(fileext = ".db")
    old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

    init_result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
    Sys.setenv(DB_ENCRYPTION_KEY = init_result$key)
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
# Test: log_role_change records permission modifications
local({
    test_db <- tempfile(fileext = ".db")
    old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

    init_result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
    Sys.setenv(DB_ENCRYPTION_KEY = init_result$key)
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

    expect_true(nrow(records) > 0)
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

# Test: log_config_change records setting modifications
local({
    test_db <- tempfile(fileext = ".db")
    old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

    init_result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
    Sys.setenv(DB_ENCRYPTION_KEY = init_result$key)
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

    expect_true(nrow(records) > 0)
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

# Test: detect_audit_anomalies returns valid structure
local({
    test_db <- tempfile(fileext = ".db")
    old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

    init_result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
    Sys.setenv(DB_ENCRYPTION_KEY = init_result$key)
    audit_result <- init_audit_logging(db_path = test_db)

    result <- detect_audit_anomalies(
      lookback_hours = 24,
      db_path = test_db
    )

    expect_equal(typeof(result), "list")
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
# Test: detect_audit_anomalies detects excessive failed logins
local({
    test_db <- tempfile(fileext = ".db")
    old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

    init_result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
    Sys.setenv(DB_ENCRYPTION_KEY = init_result$key)
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

    expect_true(result$risk_score > 0)
    expect_true(length(result$alerts) > 0)

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

# Test: search_audit_trail returns results
local({
    test_db <- tempfile(fileext = ".db")
    old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

    init_result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
    Sys.setenv(DB_ENCRYPTION_KEY = init_result$key)
    audit_result <- init_audit_logging(db_path = test_db)

    log_system_event("BACKUP", "Test backup", db_path = test_db)
    log_failed_login("user1", db_path = test_db)
    log_config_change("setting1", "old", "new", "admin", db_path = test_db)

    results <- search_audit_trail(
      limit = 100,
      db_path = test_db
    )

    expect_true(inherits(results, "data.frame"))
    expect_true(nrow(results) > 0)

    unlink(test_db)
    if (old_key != "") {
      Sys.setenv(DB_ENCRYPTION_KEY = old_key)
    } else {
      Sys.unsetenv("DB_ENCRYPTION_KEY")
    }

})
# Test: search_audit_trail filters by event type
local({
    test_db <- tempfile(fileext = ".db")
    old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

    init_result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
    Sys.setenv(DB_ENCRYPTION_KEY = init_result$key)
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
# Test: search_audit_trail filters by user
local({
    test_db <- tempfile(fileext = ".db")
    old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

    init_result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
    Sys.setenv(DB_ENCRYPTION_KEY = init_result$key)
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

# Test: get_audit_statistics returns summary data
local({
    test_db <- tempfile(fileext = ".db")
    old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

    init_result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
    Sys.setenv(DB_ENCRYPTION_KEY = init_result$key)
    audit_result <- init_audit_logging(db_path = test_db)

    log_system_event("BACKUP", "Test 1", db_path = test_db)
    log_system_event("BACKUP", "Test 2", db_path = test_db)
    log_failed_login("user1", db_path = test_db)

    stats <- get_audit_statistics(period = "week", db_path = test_db)

    expect_equal(typeof(stats), "list")
    expect_true("total_events" %in% names(stats))
    expect_true("events_by_type" %in% names(stats))
    expect_true(stats$total_events >= 3)

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

# Test: complete audit workflow functions correctly
local({
    test_db <- tempfile(fileext = ".db")
    old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

    init_result <- initialize_encrypted_database(db_path = test_db, overwrite = TRUE)
    Sys.setenv(DB_ENCRYPTION_KEY = init_result$key)
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
    expect_equal(typeof(anomalies), "list")

    stats <- get_audit_statistics(period = "day", db_path = test_db)
    expect_true(stats$total_events >= 4)

    all_events <- search_audit_trail(limit = 100, db_path = test_db)
    expect_true(nrow(all_events) >= 4)

    integrity <- verify_audit_integrity(db_path = test_db)
    expect_true(integrity$valid)

    unlink(test_db)
    if (old_key != "") {
      Sys.setenv(DB_ENCRYPTION_KEY = old_key)
    } else {
      Sys.unsetenv("DB_ENCRYPTION_KEY")
    }

})