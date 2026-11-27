library(tinytest)
if (file.exists("_setup.R")) source("_setup.R")

# Regression test (2026-11-27): the data-entry path read the subject
# only from a field named tracking_id. The shipped demonstration study
# and the authoring guide name it subject_id, so every entry in such a
# study was stored under a generated placeholder and linked to no
# subject (verified by execution).

ns <- asNamespace("zzedc")
save_crf_entry <- get("save_crf_entry", envir = ns)
ensure_data_entries_table <- get("ensure_data_entries_table", envir = ns)
key <- get0("crf_subject_key", envir = ns,
            ifnotfound = function(field_data) NULL)
key_field <- get0("crf_subject_key_field", envir = ns,
                  ifnotfound = function(field_names) NULL)

expect_equal(key(list(subject_id = "S01-001", age = 9)), "S01-001",
             info = "subject_id identifies the subject")
expect_equal(key(list(tracking_id = "PUB-2026-001")), "PUB-2026-001",
             info = "tracking_id still identifies the record")
expect_equal(key(list(tracking_id = "T-1", subject_id = "S-1")), "T-1",
             info = "tracking_id takes precedence when both are filled in")
expect_equal(key(list(tracking_id = "", subject_id = "S-1")), "S-1",
             info = "a blank tracking_id falls back to subject_id")
expect_equal(key(list(subject_id = "  S-2 ")), "S-2",
             info = "surrounding spaces are trimmed")
expect_null(key(list(subject_id = NA)), info = "NA is no subject")
expect_null(key(list(age = 9)), info = "no key field is no subject")
expect_equal(key_field(c("age", "subject_id")), "subject_id")
expect_equal(key_field(c("tracking_id", "subject_id")), "tracking_id")
expect_null(key_field(c("age")))

old_key <- Sys.getenv("DB_ENCRYPTION_KEY")
db <- tempfile(fileext = ".db")
init <- initialize_encrypted_database(db_path = db, overwrite = TRUE)
Sys.setenv(DB_ENCRYPTION_KEY = init$key)
stopifnot(isTRUE(init_audit_logging(db_path = db)$success))
conn <- connect_encrypted_db(db_path = db)
ensure_data_entries_table(conn)

r <- save_crf_entry(conn, "screening", list(subject_id = "S01-001", age = 9),
                    created_by = "coord")
expect_true(r$success)
stored <- DBI::dbGetQuery(conn, "SELECT subject_id FROM data_entries")$subject_id
expect_equal(stored, "S01-001",
             info = "an entry on a subject_id form is stored under that subject")
r <- save_crf_entry(conn, "demographics",
                    list(subject_id = "S01-001", sex = "F"),
                    created_by = "coord")
expect_equal(DBI::dbGetQuery(conn,
               "SELECT COUNT(DISTINCT subject_id) AS n FROM data_entries")$n,
             1L, info = "two forms for one subject share the subject")

DBI::dbDisconnect(conn)
unlink(db)
if (nzchar(old_key)) {
  Sys.setenv(DB_ENCRYPTION_KEY = old_key)
} else {
  Sys.unsetenv("DB_ENCRYPTION_KEY")
}
