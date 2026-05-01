library(tinytest)

if (file.exists("_setup.R")) source("_setup.R")


# Test: ensure_edc_users_table is idempotent and produces the
# canonical column set
local({
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  zzedc:::ensure_edc_users_table(conn)
  zzedc:::ensure_edc_users_table(conn)  # idempotent

  cols <- DBI::dbListFields(conn, "edc_users")
  expected <- c("user_id", "username", "password_hash",
                 "full_name", "email", "role", "site_id",
                 "active", "last_login", "created_date",
                 "created_by", "modified_date", "modified_by")
  expect_true(setequal(cols, expected))
})


# Test: db_insert_user happy path produces a row with the
# expected columns
local({
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  zzedc:::ensure_edc_users_table(conn)

  saved <- zzedc:::db_insert_user(
    conn          = conn,
    username      = "alice",
    password_hash = "deadbeef",
    full_name     = "Alice Apple",
    email         = "alice@example.org",
    role          = "Coordinator",
    site_id       = "100",
    active        = TRUE,
    created_by    = "test"
  )

  expect_true(saved$success)
  expect_true(grepl("^USER_", saved$user_id))

  rows <- DBI::dbGetQuery(conn, "SELECT * FROM edc_users")
  expect_equal(nrow(rows), 1L)
  expect_equal(rows$username[1], "alice")
  expect_equal(rows$role[1], "Coordinator")
  expect_equal(rows$site_id[1], "100")
  expect_equal(rows$active[1], 1L)
  expect_equal(rows$created_by[1], "test")
})


# Test: db_insert_user surfaces unique-username conflicts
# through the result list rather than throwing
local({
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  zzedc:::ensure_edc_users_table(conn)

  first <- zzedc:::db_insert_user(conn, "bob", "h1",
                                    created_by = "test")
  expect_true(first$success)

  second <- zzedc:::db_insert_user(conn, "bob", "h2",
                                     created_by = "test")
  expect_false(second$success)
  expect_true(grepl("UNIQUE|constraint",
                     second$error, ignore.case = TRUE))
})


# Test: db_insert_user honours an explicit user_id
local({
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  zzedc:::ensure_edc_users_table(conn)

  saved <- zzedc:::db_insert_user(
    conn          = conn,
    username      = "carol",
    password_hash = "h",
    user_id       = "USER_FIXED_42",
    created_by    = "test"
  )

  expect_true(saved$success)
  expect_equal(saved$user_id, "USER_FIXED_42")
  rows <- DBI::dbGetQuery(conn,
    "SELECT user_id FROM edc_users WHERE username = 'carol'")
  expect_equal(rows$user_id[1], "USER_FIXED_42")
})


# Test: active = FALSE round-trips as 0L
local({
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  zzedc:::ensure_edc_users_table(conn)

  zzedc:::db_insert_user(conn, "dave", "h",
                          active = FALSE, created_by = "test")
  rows <- DBI::dbGetQuery(conn,
    "SELECT active FROM edc_users WHERE username = 'dave'")
  expect_equal(rows$active[1], 0L)
})
