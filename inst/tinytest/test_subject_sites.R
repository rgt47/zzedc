library(tinytest)
if (file.exists("_setup.R")) source("_setup.R")

# Subjects, sites, and enrollment at first data entry (design
# document Section 13, decision 9).

if (!exists("migrate_add_subject_sites")) exit_file("subject site functions not available")

for (fn in c("db_insert_user", "ensure_edc_users_table",
             "ensure_data_entries_table", "db_insert_data_entry",
             "save_crf_entry")) {
  assign(fn, get(fn, envir = asNamespace("zzedc")))
}

old_key <- Sys.getenv("DB_ENCRYPTION_KEY")

.db <- function() {
  db <- tempfile(fileext = ".db")
  init <- initialize_encrypted_database(db_path = db, overwrite = TRUE)
  if (!is.null(init$error)) stop(init$error)
  Sys.setenv(DB_ENCRYPTION_KEY = init$key)
  stopifnot(isTRUE(init_audit_logging(db_path = db)$success))
  conn <- connect_encrypted_db(db_path = db)
  ensure_edc_users_table(conn)
  ensure_data_entries_table(conn)
  list(db = db, conn = conn)
}
.user <- function(s, name, site = NA_character_) {
  db_insert_user(s$conn, username = name, password_hash = "x",
                 full_name = name, email = "x@example.org", role = "Coordinator",
                 site_id = site, active = TRUE, created_by = "setup")
}
.entry <- function(s, subject, who, ...) {
  db_insert_data_entry(s$conn, subject, "baseline", list(v = 1),
                       created_by = who, ...)
}
.subj <- function(s, id) {
  DBI::dbGetQuery(s$conn, "SELECT * FROM subjects WHERE subject_id = ?",
                  params = list(id))
}
.n <- function(s, sql) DBI::dbGetQuery(s$conn, sql)[[1]]
.close <- function(s) {
  DBI::dbDisconnect(s$conn)
  unlink(s$db)
}

# ---------------------------------------------------------------------------
# Enrollment at first entry, on the initializer's subjects schema
# ---------------------------------------------------------------------------
local({
  s <- .db()
  on.exit(.close(s))
  .user(s, "site_user", "S01")
  .user(s, "central_user")

  r <- .entry(s, "SUBJ-1", "site_user")
  expect_true(r$success, info = paste("first entry saved", r$error %||% ""))
  expect_true(r$enrolled, info = "first entry enrolls the subject")
  expect_equal(.subj(s, "SUBJ-1")$site_id, "S01",
               info = "site defaults to the entering user's site")
  expect_equal(.n(s, "SELECT COUNT(*) FROM sites WHERE site_id = 'S01'"), 1,
               info = "the user's site is registered")
  expect_equal(.n(s, "SELECT COUNT(*) FROM audit_log
                      WHERE table_name = 'subjects'"), 1,
               info = "enrollment is audited")

  r <- .entry(s, "SUBJ-1", "central_user")
  expect_false(r$enrolled, info = "a later entry does not enroll again")
  expect_equal(.n(s, "SELECT COUNT(*) FROM subjects"), 1)

  r <- .entry(s, "SUBJ-2", "central_user")
  expect_equal(.subj(s, "SUBJ-2")$site_id, "S01",
               info = "user without a site: the study's only site")

  expect_true(add_site(s$conn, "S02", "Second", "admin")$success)
  expect_false(add_site(s$conn, "S02", "Again", "admin")$success,
               info = "a site is registered once")
  r <- .entry(s, "SUBJ-3", "central_user")
  expect_true(r$success && r$enrolled)
  expect_true(is.na(.subj(s, "SUBJ-3")$site_id),
              info = "several sites and a user without one: no site recorded")

  r <- .entry(s, "SUBJ-4", "central_user", site_id = "S02")
  expect_equal(.subj(s, "SUBJ-4")$site_id, "S02",
               info = "an explicitly chosen site is recorded")

  n_entries <- .n(s, "SELECT COUNT(*) FROM data_entries")
  r <- .entry(s, "SUBJ-5", "central_user", site_id = "NOPE")
  expect_false(r$success, info = "an unknown site refuses the entry")
  expect_equal(.n(s, "SELECT COUNT(*) FROM data_entries"), n_entries,
               info = "refused entry writes no data")
  expect_equal(nrow(.subj(s, "SUBJ-5")), 0L,
               info = "refused entry enrolls no one")

  r <- save_crf_entry(s$conn, "demog", list(age = 40),
                      created_by = "site_user")
  expect_true(r$success)
  expect_false(r$enrolled,
               info = "a generated subject ID does not enroll anyone")

  # Transfers
  r <- transfer_subject_site(s$conn, "SUBJ-3", "S02", "", "admin")
  expect_false(r$success, info = "a reason is required")
  r <- transfer_subject_site(s$conn, "SUBJ-3", "S99", "x", "admin")
  expect_false(r$success, info = "the new site must be registered")
  r <- transfer_subject_site(s$conn, "SUBJ-3", "S02", "Site review", "admin")
  expect_true(r$success, info = paste("site set", r$error %||% ""))
  expect_true(is.na(r$from_site_id))
  r <- transfer_subject_site(s$conn, "SUBJ-1", "S02", "Moved", "admin")
  expect_equal(c(r$from_site_id, .subj(s, "SUBJ-1")$site_id), c("S01", "S02"),
               info = "transfer changes the recorded site")
  r <- transfer_subject_site(s$conn, "SUBJ-1", "S02", "Again", "admin")
  expect_false(r$success, info = "a transfer to the current site is refused")
  expect_true(isTRUE(verify_audit_integrity(db_path = s$db)$valid),
              info = "audit chain verifies")
})

# ---------------------------------------------------------------------------
# Subjects that predate enrollment recording, and the migration
# ---------------------------------------------------------------------------
local({
  s <- .db()
  on.exit(.close(s))
  .user(s, "u_a", "A")
  .user(s, "u_b", "B")
  for (sid in c("OLD-1", "OLD-2", "DEMOG-20261101093000.123")) {
    DBI::dbExecute(s$conn,
      "INSERT INTO data_entries (entry_id, subject_id, form_name, data_json,
                                 is_complete, created_by)
       VALUES (?, ?, 'baseline', '{}', 1, 'u_a')",
      params = list(paste0("E-", sid), sid))
  }

  r <- .entry(s, "OLD-1", "u_b")
  expect_true(r$success)
  expect_false(r$enrolled,
               info = "a subject with earlier entries is not enrolled now")
  expect_equal(nrow(.subj(s, "OLD-1")), 0L,
               info = "no site is inferred from today's user")

  m <- migrate_add_subject_sites(s$conn, user_id = "admin")
  expect_true(m$success, info = paste("migration", m$error %||% ""))
  expect_equal(sort(.n(s, "SELECT site_id FROM sites")), c("A", "B"),
               info = "sites in use are registered")
  expect_equal(m$subjects_added, 2L, info = "existing subjects recorded")
  expect_equal(m$skipped_generated_ids, "DEMOG-20261101093000.123",
               info = "generated submission IDs are not subjects")
  expect_equal(sort(m$subjects_without_site), c("OLD-1", "OLD-2"),
               info = "migrated subjects await site review")

  m2 <- migrate_add_subject_sites(s$conn, user_id = "admin")
  expect_equal(c(m2$sites_added, m2$subjects_added), c(0L, 0L),
               info = "the migration is idempotent")
  expect_true(isTRUE(verify_audit_integrity(db_path = s$db)$valid))
})

# A study with no sites at all gets a default site
local({
  s <- .db()
  on.exit(.close(s))
  .user(s, "solo")
  r <- .entry(s, "P-1", "solo")
  expect_equal(.subj(s, "P-1")$site_id, "_default_site_",
               info = "single-site study: default site created and used")
})

# ---------------------------------------------------------------------------
# DuckDB: subjects.study_id references an empty study_info
# ---------------------------------------------------------------------------
if (requireNamespace("duckdb", quietly = TRUE)) local({
  cache <- get(".db_adapter_cache", envir = asNamespace("zzedc"))
  old_adapter <- cache$adapter
  on.exit(cache$adapter <- old_adapter, add = TRUE)
  p <- tempfile(fileext = ".duckdb")
  cfg <- list(db_backend = "duckdb", duckdb = list(path = p))
  get_db_adapter(config = cfg, force_new = TRUE)
  init <- initialize_encrypted_database(db_path = p, overwrite = TRUE)
  cfg$duckdb$encryption_key <- init$key
  get_db_adapter(config = cfg, force_new = TRUE)
  Sys.setenv(DB_ENCRYPTION_KEY = init$key)
  stopifnot(isTRUE(init_audit_logging(db_path = p)$success))
  conn <- connect_encrypted_db(db_path = p)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  ensure_edc_users_table(conn)
  ensure_data_entries_table(conn)
  db_insert_user(conn, username = "d_user", password_hash = "x",
                 full_name = "D", email = "d@example.org", role = "Coordinator",
                 site_id = "D1", active = TRUE, created_by = "setup")

  r <- db_insert_data_entry(conn, "DK-1", "baseline", list(v = 1),
                            created_by = "d_user")
  expect_true(r$success && r$enrolled,
              info = paste("DuckDB: first entry enrolls", r$error %||% ""))
  expect_equal(DBI::dbGetQuery(conn,
                 "SELECT study_id FROM subjects WHERE subject_id = 'DK-1'")[[1]],
               "_default_study_",
               info = "DuckDB: placeholder study row satisfies the reference")
  expect_true(add_site(conn, "D2", "Two", "admin")$success)
  r <- transfer_subject_site(conn, "DK-1", "D2", "Moved", "admin")
  expect_true(r$success, info = paste("DuckDB: transfer", r$error %||% ""))
  expect_true(isTRUE(verify_audit_integrity(db_path = p)$valid),
              info = "DuckDB: audit chain verifies")
})

if (nzchar(old_key)) {
  Sys.setenv(DB_ENCRYPTION_KEY = old_key)
} else {
  Sys.unsetenv("DB_ENCRYPTION_KEY")
}
