library(tinytest)

# Helpers (auto-loaded by testthat under the previous layout).
# tinytest auto-sources files prefixed with `_` (so `_setup.R`)
# when invoked via `tinytest::test_package()`. The explicit
# source() below keeps the test runnable when invoked directly
# (e.g., `tinytest::run_test_file("test_foo.R")`).
if (file.exists("_setup.R")) source("_setup.R")
# Test Study Reconciliation & Closeout System
# Feature #26
setup_co_test_env <- function() {
  if (!exists("test_db_initialized", envir = .GlobalEnv) ||
      !get("test_db_initialized", envir = .GlobalEnv)) {
    Sys.setenv(ZZEDC_DB_PATH = tempfile(fileext = ".db"))
    Sys.setenv(ZZEDC_ENCRYPTION_KEY = "test_key_for_study_closeout_32!")
    .init_res <- initialize_encrypted_database(Sys.getenv("ZZEDC_DB_PATH"))
    Sys.setenv(DB_ENCRYPTION_KEY = .init_res$key)
    init_audit_logging()
    assign("test_db_initialized", TRUE, envir = .GlobalEnv)
  }
}

# Test: init_study_closeout creates tables
local({
    setup_co_test_env()
    result <- init_study_closeout()
    expect_true(result$success)

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    tables <- DBI::dbListTables(con)
    expect_true("study_closeout" %in% tables)
    expect_true("closeout_checklist" %in% tables)
    expect_true("data_reconciliation" %in% tables)
    expect_true("database_lock_log" %in% tables)

})
# Test: reference functions return values
local({
    expect_true("PENDING" %in% names(get_closeout_statuses()))
    expect_true("STANDARD" %in% names(get_closeout_types()))
    expect_true("DATA_QUALITY" %in% names(get_checklist_categories()))

})
# Test: initiate_study_closeout creates closeout
local({
    setup_co_test_env()
    init_study_closeout()

    result <- initiate_study_closeout(
      study_id = 1,
      initiated_by = "dm_lead",
      closeout_type = "STANDARD",
      closeout_notes = "End of study closeout"
    )

    expect_true(result$success)
    expect_true(!is.null(result$closeout_id))

})
# Test: initiate_study_closeout validates inputs
local({
    result <- initiate_study_closeout(
      initiated_by = "user"
    )
    expect_false(result$success)

    setup_co_test_env()
    result2 <- initiate_study_closeout(
      study_id = 1,
      initiated_by = "user",
      closeout_type = "INVALID"
    )
    expect_false(result2$success)

})
# Test: add_checklist_item adds item
local({
    setup_co_test_env()
    init_study_closeout()

    closeout <- initiate_study_closeout(
      study_id = 100,
      initiated_by = "dm"
    )

    result <- add_checklist_item(
      closeout_id = closeout$closeout_id,
      item_category = "DATA_QUALITY",
      item_description = "All edit checks resolved",
      item_order = 1,
      is_required = TRUE
    )

    expect_true(result$success)

})
# Test: complete_checklist_item marks complete
local({
    setup_co_test_env()

    closeout <- initiate_study_closeout(
      study_id = 101,
      initiated_by = "dm"
    )

    add_checklist_item(
      closeout_id = closeout$closeout_id,
      item_category = "DATA_QUALITY",
      item_description = "Test item",
      item_order = 1
    )

    con <- connect_encrypted_db()
    item_id <- DBI::dbGetQuery(con, "
      SELECT item_id FROM closeout_checklist ORDER BY item_id DESC LIMIT 1
    ")$item_id[1]
    DBI::dbDisconnect(con)

    result <- complete_checklist_item(
      item_id = item_id,
      completed_by = "reviewer",
      completion_notes = "Verified complete"
    )

    expect_true(result$success)

})
# Test: load_standard_checklist loads items
local({
    setup_co_test_env()
    init_study_closeout()

    closeout <- initiate_study_closeout(
      study_id = 102,
      initiated_by = "dm"
    )

    result <- load_standard_checklist(closeout$closeout_id)

    expect_true(result$success)
    expect_true(result$items_loaded >= 10)

})
# Test: get_checklist_status returns status
local({
    setup_co_test_env()

    closeout <- initiate_study_closeout(
      study_id = 103,
      initiated_by = "dm"
    )
    load_standard_checklist(closeout$closeout_id)

    result <- get_checklist_status(closeout$closeout_id)

    expect_true(result$success)
    expect_true(result$total_items > 0)
    expect_true("completion_pct" %in% names(result))

})
# Test: record_data_reconciliation records reconciliation
local({
    setup_co_test_env()
    init_study_closeout()

    closeout <- initiate_study_closeout(
      study_id = 104,
      initiated_by = "dm"
    )

    result <- record_data_reconciliation(
      closeout_id = closeout$closeout_id,
      reconciliation_type = "SAE_SAFETY_DB",
      performed_by = "safety_mgr",
      source_system = "EDC",
      target_system = "Safety Database",
      records_compared = 150,
      records_matched = 148,
      discrepancies_found = 2
    )

    expect_true(result$success)
    expect_true(!is.null(result$reconciliation_id))

})
# Test: resolve_reconciliation_discrepancy resolves
local({
    setup_co_test_env()

    closeout <- initiate_study_closeout(
      study_id = 105,
      initiated_by = "dm"
    )

    recon <- record_data_reconciliation(
      closeout_id = closeout$closeout_id,
      reconciliation_type = "CODING",
      performed_by = "coder",
      records_compared = 100,
      records_matched = 95,
      discrepancies_found = 5
    )

    result <- resolve_reconciliation_discrepancy(
      reconciliation_id = recon$reconciliation_id,
      resolved_by = "coder",
      discrepancies_resolved = 5,
      resolution_notes = "All coding issues resolved"
    )

    expect_true(result$success)
    expect_true(result$all_resolved)

})
# Test: get_reconciliation_status returns status
local({
    setup_co_test_env()

    closeout <- initiate_study_closeout(
      study_id = 106,
      initiated_by = "dm"
    )

    record_data_reconciliation(
      closeout_id = closeout$closeout_id,
      reconciliation_type = "TEST",
      performed_by = "tester"
    )

    result <- get_reconciliation_status(closeout$closeout_id)

    expect_true(result$success)
    expect_true(result$count >= 1)

})
# Test: lock_database locks study
local({
    setup_co_test_env()
    init_study_closeout()

    initiate_study_closeout(
      study_id = 107,
      initiated_by = "dm"
    )

    result <- lock_database(
      study_id = 107,
      locked_by = "dm_lead",
      authorized_by = "medical_dir",
      reason = "Final database lock",
      lock_scope = "FULL"
    )

    expect_true(result$success)

})
# Test: unlock_database requires reason
local({
    setup_co_test_env()

    result <- unlock_database(
      study_id = 1,
      unlocked_by = "dm",
      authorized_by = "dir",
      reason = ""
    )

    expect_false(result$success)

})
# Test: unlock_database with reason succeeds
local({
    setup_co_test_env()
    init_study_closeout()

    initiate_study_closeout(
      study_id = 108,
      initiated_by = "dm"
    )

    lock_database(
      study_id = 108,
      locked_by = "dm_lead",
      authorized_by = "dir"
    )

    result <- unlock_database(
      study_id = 108,
      unlocked_by = "dm_lead",
      authorized_by = "dir",
      reason = "Additional data corrections needed"
    )

    expect_true(result$success)

})
# Test: get_lock_history returns history
local({
    setup_co_test_env()

    initiate_study_closeout(
      study_id = 109,
      initiated_by = "dm"
    )

    lock_database(study_id = 109, locked_by = "dm", authorized_by = "dir")

    result <- get_lock_history(study_id = 109)

    expect_true(result$success)
    expect_true(result$count >= 1)

})
# Test: complete_study_closeout requires checklist
local({
    setup_co_test_env()
    init_study_closeout()

    closeout <- initiate_study_closeout(
      study_id = 110,
      initiated_by = "dm"
    )

    add_checklist_item(
      closeout_id = closeout$closeout_id,
      item_category = "DATA_QUALITY",
      item_description = "Required item",
      is_required = TRUE
    )

    result <- complete_study_closeout(
      closeout_id = closeout$closeout_id,
      completed_by = "dm_lead"
    )

    expect_false(result$success)
    expect_true(grepl("checklist", result$error, ignore.case = TRUE))

})
# Test: complete_study_closeout succeeds with checklist
local({
    setup_co_test_env()

    closeout <- initiate_study_closeout(
      study_id = 111,
      initiated_by = "dm"
    )

    add_checklist_item(
      closeout_id = closeout$closeout_id,
      item_category = "DATA_QUALITY",
      item_description = "Required item",
      is_required = TRUE
    )

    con <- connect_encrypted_db()
    item_id <- DBI::dbGetQuery(con, "
      SELECT item_id FROM closeout_checklist ORDER BY item_id DESC LIMIT 1
    ")$item_id[1]
    DBI::dbDisconnect(con)

    complete_checklist_item(item_id, "reviewer")

    result <- complete_study_closeout(
      closeout_id = closeout$closeout_id,
      completed_by = "dm_lead",
      final_subject_count = 150,
      final_record_count = 12000
    )

    expect_true(result$success)

})
# Test: get_closeout_status returns status
local({
    setup_co_test_env()

    closeout <- initiate_study_closeout(
      study_id = 112,
      initiated_by = "dm"
    )

    result <- get_closeout_status(closeout$closeout_id)

    expect_true(result$success)
    expect_true("closeout" %in% names(result))

})
# Test: get_closeout_statistics returns stats
local({
    setup_co_test_env()

    result <- get_closeout_statistics()

    expect_true(result$success)
    expect_true("statistics" %in% names(result))
    expect_true("by_type" %in% names(result))

})
# Test: cleanup test environment
local({
    if (exists("test_db_initialized", envir = .GlobalEnv)) {
      rm("test_db_initialized", envir = .GlobalEnv)
    }
    db_path <- Sys.getenv("ZZEDC_DB_PATH")
    if (db_path != "" && file.exists(db_path)) unlink(db_path)
    expect_true(TRUE)

})