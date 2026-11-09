library(tinytest)

# Helpers (auto-loaded by testthat under the previous layout).
# tinytest auto-sources files prefixed with `_` (so `_setup.R`)
# when invoked via `tinytest::test_package()`. The explicit
# source() below keeps the test runnable when invoked directly
# (e.g., `tinytest::run_test_file("test_foo.R")`).
if (file.exists("_setup.R")) source("_setup.R")

# §11.10(i) training records, added 2026-11-09. Before this,
# user_training had no CREATE TABLE anywhere in the package and no
# writer of any kind -- the only reference was a read-only SELECT in
# cfr_compliance_module.R's compliance dashboard, and the dashboard's
# own "Record Training" button had no observeEvent handler behind it
# at all. ensure_user_training_table()/db_insert_training_record()
# (R/db_users.R) close that gap.

local({
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  ensure_user_training_table(conn)
  cols <- DBI::dbListFields(conn, "user_training")
  expected <- c("training_id", "user_id", "training_type", "training_date",
                "trainer_name", "training_score", "completion_status",
                "expiry_date", "created_date")
  expect_true(setequal(cols, expected))

  # idempotent
  ensure_user_training_table(conn)
  expect_true(setequal(DBI::dbListFields(conn, "user_training"), expected))
})

local({
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  ensure_edc_users_table(conn)
  ensure_user_training_table(conn)

  user <- db_insert_user(conn, username = "jdoe", password_hash = "h",
                          full_name = "Jane Doe", role = "Coordinator",
                          created_by = "test")
  expect_true(user$success)

  result <- db_insert_training_record(
    conn = conn, user_id = user$user_id, training_type = "cfr_part11_basics",
    training_date = "2026-11-09", trainer_name = "Alice Trainer",
    training_score = 92
  )
  expect_true(result$success)
  expect_true(grepl("^TRAIN_", result$training_id))

  rows <- DBI::dbGetQuery(conn, "
    SELECT t.*, u.full_name, u.role FROM user_training t
    JOIN edc_users u ON t.user_id = u.user_id
  ")
  expect_equal(nrow(rows), 1L)
  expect_equal(rows$training_type[1], "cfr_part11_basics")
  expect_equal(rows$trainer_name[1], "Alice Trainer")
  expect_equal(rows$training_score[1], 92)
  expect_equal(rows$completion_status[1], "completed",
               info = "recording a training event implies it already happened")
  expect_equal(as.character(rows$expiry_date[1]), "2027-11-09",
               info = "default expiry is one year after training_date")
  expect_equal(rows$full_name[1], "Jane Doe")
  expect_equal(rows$role[1], "Coordinator")
})

# An explicit expiry_date overrides the one-year default.
local({
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  ensure_edc_users_table(conn)
  ensure_user_training_table(conn)
  user <- db_insert_user(conn, username = "bsmith", password_hash = "h",
                          created_by = "test")

  result <- db_insert_training_record(
    conn = conn, user_id = user$user_id, training_type = "data_integrity",
    training_date = "2026-01-01", expiry_date = "2026-06-01"
  )
  expect_true(result$success)

  row <- DBI::dbGetQuery(conn,
    "SELECT expiry_date, training_score FROM user_training WHERE user_id = ?",
    params = list(user$user_id))
  expect_equal(as.character(row$expiry_date[1]), "2026-06-01")
  expect_true(is.na(row$training_score[1]))
})
