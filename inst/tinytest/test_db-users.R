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
                 "active", "must_change_password",
                 "failed_login_attempts", "locked_at",
                 "password_changed_date", "last_login",
                 "created_date", "created_by", "modified_date",
                 "modified_by")
  expect_true(setequal(cols, expected))
})


# Test: ensure_edc_users_table() migrates an already-existing table
# that predates must_change_password, and the migrated column
# defaults existing rows to 0 (not forcing a surprise password
# change on anyone already using the app)
local({
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  DBI::dbExecute(conn, "
    CREATE TABLE edc_users (
      user_id TEXT PRIMARY KEY, username TEXT UNIQUE NOT NULL,
      password_hash TEXT NOT NULL, full_name TEXT, email TEXT,
      role TEXT, site_id TEXT, active INTEGER DEFAULT 1,
      last_login TIMESTAMP,
      created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      created_by TEXT, modified_date TIMESTAMP, modified_by TEXT
    )
  ")
  DBI::dbExecute(conn, "
    INSERT INTO edc_users (user_id, username, password_hash, active)
    VALUES ('USER_PRE', 'pre_existing', 'h', 1)
  ")

  expect_false("must_change_password" %in%
                 DBI::dbListFields(conn, "edc_users"))

  zzedc:::ensure_edc_users_table(conn)

  expect_true("must_change_password" %in%
                DBI::dbListFields(conn, "edc_users"))
  rows <- DBI::dbGetQuery(conn,
    "SELECT must_change_password FROM edc_users WHERE username = 'pre_existing'")
  expect_equal(rows$must_change_password[1], 0L)
})


# Test: ensure_edc_users_table() migrates in the §11.300 lockout
# columns (failed_login_attempts, locked_at) on a table that predates
# them, same as the must_change_password migration above, and an
# already-existing row starts unlocked with a zero count rather than
# erroring on the newly-added columns.
local({
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  DBI::dbExecute(conn, "
    CREATE TABLE edc_users (
      user_id TEXT PRIMARY KEY, username TEXT UNIQUE NOT NULL,
      password_hash TEXT NOT NULL, full_name TEXT, email TEXT,
      role TEXT, site_id TEXT, active INTEGER DEFAULT 1,
      must_change_password INTEGER DEFAULT 0, last_login TIMESTAMP,
      created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      created_by TEXT, modified_date TIMESTAMP, modified_by TEXT
    )
  ")
  DBI::dbExecute(conn, "
    INSERT INTO edc_users (user_id, username, password_hash, active)
    VALUES ('USER_PRE2', 'pre_existing2', 'h', 1)
  ")

  expect_false("failed_login_attempts" %in% DBI::dbListFields(conn, "edc_users"))
  expect_false("locked_at" %in% DBI::dbListFields(conn, "edc_users"))

  zzedc:::ensure_edc_users_table(conn)

  expect_true("failed_login_attempts" %in% DBI::dbListFields(conn, "edc_users"))
  expect_true("locked_at" %in% DBI::dbListFields(conn, "edc_users"))

  rows <- DBI::dbGetQuery(conn, "
    SELECT failed_login_attempts, locked_at FROM edc_users
    WHERE username = 'pre_existing2'
  ")
  expect_equal(rows$failed_login_attempts[1], 0L)
  expect_true(is.na(rows$locked_at[1]))

  # idempotent: calling again on an already-migrated table is a no-op
  zzedc:::ensure_edc_users_table(conn)
  expect_true("failed_login_attempts" %in% DBI::dbListFields(conn, "edc_users"))
})


# Test: ensure_edc_users_table() migrates in the §11.300(b)
# password_changed_date column on a table that predates it, and
# backfills existing rows from created_date rather than leaving them
# NULL -- a NULL would read as "password never set", forcing every
# pre-existing user into a change the moment this feature ships.
local({
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  DBI::dbExecute(conn, "
    CREATE TABLE edc_users (
      user_id TEXT PRIMARY KEY, username TEXT UNIQUE NOT NULL,
      password_hash TEXT NOT NULL, full_name TEXT, email TEXT,
      role TEXT, site_id TEXT, active INTEGER DEFAULT 1,
      must_change_password INTEGER DEFAULT 0,
      failed_login_attempts INTEGER DEFAULT 0, locked_at TIMESTAMP,
      last_login TIMESTAMP,
      created_date TIMESTAMP DEFAULT '2026-01-01 00:00:00',
      created_by TEXT, modified_date TIMESTAMP, modified_by TEXT
    )
  ")
  DBI::dbExecute(conn, "
    INSERT INTO edc_users (user_id, username, password_hash, active, created_date)
    VALUES ('USER_PRE3', 'pre_existing3', 'h', 1, '2026-01-01 00:00:00')
  ")

  expect_false("password_changed_date" %in% DBI::dbListFields(conn, "edc_users"))

  zzedc:::ensure_edc_users_table(conn)

  expect_true("password_changed_date" %in% DBI::dbListFields(conn, "edc_users"))
  rows <- DBI::dbGetQuery(conn, "
    SELECT password_changed_date, created_date FROM edc_users
    WHERE username = 'pre_existing3'
  ")
  expect_equal(rows$password_changed_date[1], rows$created_date[1],
               info = "a migrated row's password_changed_date must backfill from created_date, not be left NULL")

  # idempotent, and does not clobber an already-backfilled value
  zzedc:::ensure_edc_users_table(conn)
  rows2 <- DBI::dbGetQuery(conn, "
    SELECT password_changed_date FROM edc_users WHERE username = 'pre_existing3'
  ")
  expect_equal(rows2$password_changed_date[1], rows$password_changed_date[1])
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
# through the result list rather than throwing, with a message that
# names the real cause (§11.100: usernames are never reassigned) --
# previously a bare "Database error: ..." indistinguishable from any
# other DBI failure.
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
  expect_true(grepl("already in use", second$error, ignore.case = TRUE))
  expect_true(grepl("bob", second$error))
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


# Test: db_insert_user() defaults must_change_password to TRUE (1)
# -- every account it creates starts with a password someone else
# chose -- and honors an explicit FALSE
local({
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  zzedc:::ensure_edc_users_table(conn)

  zzedc:::db_insert_user(conn, "erin", "h", created_by = "test")
  zzedc:::db_insert_user(conn, "frank", "h", created_by = "test",
                          must_change_password = FALSE)

  rows <- DBI::dbGetQuery(conn,
    "SELECT username, must_change_password FROM edc_users ORDER BY username")
  expect_equal(rows$must_change_password[rows$username == "erin"], 1L)
  expect_equal(rows$must_change_password[rows$username == "frank"], 0L)
})


# Test: db_insert_user() sets password_changed_date on every insert
# (§11.300(b)), not just created_date -- a freshly created account's
# password must not read as already expired.
local({
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  zzedc:::ensure_edc_users_table(conn)

  zzedc:::db_insert_user(conn, "grace", "h", created_by = "test")

  row <- DBI::dbGetQuery(conn,
    "SELECT password_changed_date FROM edc_users WHERE username = 'grace'")
  expect_false(is.na(row$password_changed_date[1]),
               info = "password_changed_date must not be NULL for a freshly inserted user")
})
