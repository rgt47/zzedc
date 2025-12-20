# Test Breach Notification Workflow
# Feature #29

library(testthat)

setup_bn_test <- function() {
  Sys.setenv(ZZEDC_DB_PATH = tempfile(fileext = ".db"))
  Sys.setenv(ZZEDC_ENCRYPTION_KEY = "test_key_for_breach_notificat32!")
  initialize_encrypted_database(Sys.getenv("ZZEDC_DB_PATH"))
  init_audit_logging()
  init_breach_notification()
}

cleanup_bn_test <- function() {
  db_path <- Sys.getenv("ZZEDC_DB_PATH")
  if (db_path != "" && file.exists(db_path)) {
    try(unlink(db_path), silent = TRUE)
  }
}

test_that("init_breach_notification creates tables", {
  setup_bn_test()
  on.exit(cleanup_bn_test())

  con <- connect_encrypted_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  tables <- DBI::dbListTables(con)
  expect_true("breach_incidents" %in% tables)
  expect_true("breach_timeline" %in% tables)
  expect_true("breach_notifications" %in% tables)
  expect_true("breach_risk_assessment" %in% tables)
})

test_that("reference functions return values", {
  expect_true("CONFIDENTIALITY" %in% names(get_breach_types()))
  expect_true("CRITICAL" %in% names(get_breach_severities()))
  expect_true("DETECTED" %in% names(get_breach_statuses()))
})

test_that("report_breach_incident creates incident", {
  setup_bn_test()
  on.exit(cleanup_bn_test())

  result <- report_breach_incident(
    incident_title = "Unauthorized Database Access",
    breach_type = "CONFIDENTIALITY",
    severity = "HIGH",
    description = "Unauthorized access detected to patient database",
    detected_by = "security_analyst",
    data_categories_affected = "Health data, Contact information",
    subjects_affected = 150,
    records_affected = 1200
  )

  expect_true(result$success)
  expect_true(!is.null(result$incident_id))
  expect_true(grepl("^BRE-", result$incident_code))
})

test_that("report_breach_incident validates inputs", {
  result <- report_breach_incident(
    incident_title = "",
    breach_type = "CONFIDENTIALITY",
    severity = "HIGH",
    description = "Test",
    detected_by = "user"
  )
  expect_false(result$success)

  setup_bn_test()
  on.exit(cleanup_bn_test())

  result2 <- report_breach_incident(
    incident_title = "Test",
    breach_type = "INVALID",
    severity = "HIGH",
    description = "Test",
    detected_by = "user"
  )
  expect_false(result2$success)

  result3 <- report_breach_incident(
    incident_title = "Test",
    breach_type = "CONFIDENTIALITY",
    severity = "EXTREME",
    description = "Test",
    detected_by = "user"
  )
  expect_false(result3$success)
})

test_that("update_breach_status updates status", {
  setup_bn_test()
  on.exit(cleanup_bn_test())

  incident <- report_breach_incident(
    incident_title = "Status Test",
    breach_type = "AVAILABILITY",
    severity = "MEDIUM",
    description = "Test incident",
    detected_by = "analyst"
  )

  result <- update_breach_status(
    incident_id = incident$incident_id,
    new_status = "INVESTIGATING",
    updated_by = "security_team"
  )

  expect_true(result$success)
})

test_that("update_breach_status validates status", {
  result <- update_breach_status(
    incident_id = 1,
    new_status = "INVALID_STATUS",
    updated_by = "user"
  )
  expect_false(result$success)
})

test_that("notify_dpo notifies DPO", {
  setup_bn_test()
  on.exit(cleanup_bn_test())

  incident <- report_breach_incident(
    incident_title = "DPO Test",
    breach_type = "CONFIDENTIALITY",
    severity = "HIGH",
    description = "Test",
    detected_by = "analyst"
  )

  result <- notify_dpo(incident$incident_id, "security_lead")
  expect_true(result$success)

  con <- connect_encrypted_db()
  status <- DBI::dbGetQuery(con, "
    SELECT dpo_notified FROM breach_incidents WHERE incident_id = ?
  ", params = list(incident$incident_id))$dpo_notified[1]
  DBI::dbDisconnect(con)

  expect_equal(status, 1)
})

test_that("assess_authority_notification records assessment", {
  setup_bn_test()
  on.exit(cleanup_bn_test())

  incident <- report_breach_incident(
    incident_title = "Authority Test",
    breach_type = "CONFIDENTIALITY",
    severity = "CRITICAL",
    description = "Major breach",
    detected_by = "analyst"
  )

  result <- assess_authority_notification(
    incident_id = incident$incident_id,
    requires_notification = TRUE,
    assessed_by = "dpo",
    justification = "High risk to data subjects"
  )

  expect_true(result$success)
  expect_true(result$requires_notification)
})

test_that("notify_supervisory_authority records notification", {
  setup_bn_test()
  on.exit(cleanup_bn_test())

  incident <- report_breach_incident(
    incident_title = "Authority Notify Test",
    breach_type = "CONFIDENTIALITY",
    severity = "HIGH",
    description = "Breach requiring notification",
    detected_by = "analyst"
  )

  assess_authority_notification(
    incident_id = incident$incident_id,
    requires_notification = TRUE,
    assessed_by = "dpo"
  )

  result <- notify_supervisory_authority(
    incident_id = incident$incident_id,
    notified_by = "dpo",
    authority_reference = "DPA-2025-001234",
    notification_content = "Formal breach notification..."
  )

  expect_true(result$success)
})

test_that("assess_subject_notification records assessment", {
  setup_bn_test()
  on.exit(cleanup_bn_test())

  incident <- report_breach_incident(
    incident_title = "Subject Assessment Test",
    breach_type = "CONFIDENTIALITY",
    severity = "HIGH",
    description = "Test",
    detected_by = "analyst"
  )

  result <- assess_subject_notification(
    incident_id = incident$incident_id,
    requires_notification = TRUE,
    assessed_by = "dpo",
    justification = "High risk to rights and freedoms"
  )

  expect_true(result$success)
  expect_true(result$requires_notification)
})

test_that("notify_data_subjects records notification", {
  setup_bn_test()
  on.exit(cleanup_bn_test())

  incident <- report_breach_incident(
    incident_title = "Subject Notify Test",
    breach_type = "CONFIDENTIALITY",
    severity = "HIGH",
    description = "Test",
    detected_by = "analyst",
    subjects_affected = 50
  )

  assess_subject_notification(
    incident_id = incident$incident_id,
    requires_notification = TRUE,
    assessed_by = "dpo"
  )

  result <- notify_data_subjects(
    incident_id = incident$incident_id,
    notified_by = "communications",
    subjects_notified = 50,
    notification_method = "Email",
    notification_content = "Dear participant..."
  )

  expect_true(result$success)
})

test_that("add_breach_risk_assessment adds risk", {
  setup_bn_test()
  on.exit(cleanup_bn_test())

  incident <- report_breach_incident(
    incident_title = "Risk Test",
    breach_type = "COMBINED",
    severity = "CRITICAL",
    description = "Test",
    detected_by = "analyst"
  )

  result <- add_breach_risk_assessment(
    incident_id = incident$incident_id,
    risk_factor = "Identity Theft",
    risk_level = "HIGH",
    assessed_by = "risk_analyst",
    risk_description = "Risk of identity theft for affected subjects"
  )

  expect_true(result$success)
})

test_that("add_breach_risk_assessment validates level", {
  result <- add_breach_risk_assessment(
    incident_id = 1,
    risk_factor = "Test",
    risk_level = "EXTREME",
    assessed_by = "user"
  )
  expect_false(result$success)
})

test_that("add_timeline_event adds event", {
  setup_bn_test()
  on.exit(cleanup_bn_test())

  incident <- report_breach_incident(
    incident_title = "Timeline Test",
    breach_type = "INTEGRITY",
    severity = "MEDIUM",
    description = "Test",
    detected_by = "analyst"
  )

  result <- add_timeline_event(
    incident_id = incident$incident_id,
    event_type = "CONTAINMENT",
    event_description = "System isolated from network",
    recorded_by = "it_admin"
  )

  expect_true(result$success)
})

test_that("get_breach_timeline retrieves timeline", {
  setup_bn_test()
  on.exit(cleanup_bn_test())

  incident <- report_breach_incident(
    incident_title = "Get Timeline Test",
    breach_type = "AVAILABILITY",
    severity = "LOW",
    description = "Test",
    detected_by = "analyst"
  )

  add_timeline_event(incident$incident_id, "UPDATE", "Test event", "user")

  result <- get_breach_timeline(incident$incident_id)
  expect_true(result$success)
  expect_true(result$count >= 2)
})

test_that("get_breach_incident returns full details", {
  setup_bn_test()
  on.exit(cleanup_bn_test())

  incident <- report_breach_incident(
    incident_title = "Full Details Test",
    breach_type = "CONFIDENTIALITY",
    severity = "HIGH",
    description = "Test breach",
    detected_by = "analyst"
  )

  notify_dpo(incident$incident_id, "user")
  add_breach_risk_assessment(
    incident$incident_id, "Test Risk", "MEDIUM", "analyst"
  )

  result <- get_breach_incident(incident$incident_id)
  expect_true(result$success)
  expect_true("incident" %in% names(result))
  expect_true("timeline" %in% names(result))
  expect_true("risk_assessments" %in% names(result))
})

test_that("get_breach_incident handles not found", {
  setup_bn_test()
  on.exit(cleanup_bn_test())

  result <- get_breach_incident(99999)
  expect_false(result$success)
})

test_that("get_breach_incidents retrieves list", {
  setup_bn_test()
  on.exit(cleanup_bn_test())

  report_breach_incident(
    incident_title = "List Test",
    breach_type = "CONFIDENTIALITY",
    severity = "LOW",
    description = "Test",
    detected_by = "analyst"
  )

  result <- get_breach_incidents()
  expect_true(result$success)
  expect_true(result$count >= 1)
})

test_that("get_breach_incidents filters by status", {
  setup_bn_test()
  on.exit(cleanup_bn_test())

  incident <- report_breach_incident(
    incident_title = "Filter Test",
    breach_type = "INTEGRITY",
    severity = "MEDIUM",
    description = "Test",
    detected_by = "analyst"
  )

  update_breach_status(incident$incident_id, "INVESTIGATING", "user")

  result <- get_breach_incidents(status = "INVESTIGATING")
  expect_true(result$success)
})

test_that("get_breach_statistics returns stats", {
  setup_bn_test()
  on.exit(cleanup_bn_test())

  result <- get_breach_statistics()
  expect_true(result$success)
  expect_true("statistics" %in% names(result))
  expect_true("by_severity" %in% names(result))
  expect_true("by_type" %in% names(result))
})

test_that("check_72_hour_deadline calculates deadline", {
  setup_bn_test()
  on.exit(cleanup_bn_test())

  incident <- report_breach_incident(
    incident_title = "Deadline Test",
    breach_type = "CONFIDENTIALITY",
    severity = "HIGH",
    description = "Test",
    detected_by = "analyst"
  )

  result <- check_72_hour_deadline(incident$incident_id)
  expect_true(result$success)
  expect_true("deadline" %in% names(result))
  expect_true("hours_remaining" %in% names(result))
  expect_false(result$is_overdue)
})

test_that("check_72_hour_deadline handles not found", {
  setup_bn_test()
  on.exit(cleanup_bn_test())

  result <- check_72_hour_deadline(99999)
  expect_false(result$success)
})
