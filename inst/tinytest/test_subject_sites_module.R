library(tinytest)
if (file.exists("_setup.R")) source("_setup.R")

# The Admin tab's subject-site review screen
# (R/subject_sites_module.R).

ns <- asNamespace("zzedc")
if (!exists("subject_sites_admin_server", envir = ns)) {
  exit_file("subject sites module not available")
}
server <- get("subject_sites_admin_server", envir = ns)
ui <- get("subject_sites_admin_ui", envir = ns)
for (fn in c("ensure_edc_users_table", "ensure_data_entries_table",
             "db_insert_user")) {
  assign(fn, get(fn, envir = ns))
}

.session <- function(role, username) {
  shiny::reactiveValues(authenticated = TRUE,
                        authentication_timestamp = Sys.time(),
                        user_id = paste0("U_", username), username = username,
                        full_name = username, role = role, site_id = NULL,
                        must_change_password = FALSE)
}

old_key <- Sys.getenv("DB_ENCRYPTION_KEY")
old_db_path <- Sys.getenv("ZZEDC_DB_PATH", unset = NA_character_)
cache <- get(".db_adapter_cache", envir = ns)
old_adapter <- cache$adapter
db <- tempfile(fileext = ".db")
# Denied-action audit records go to the default database, which
# ZZEDC_DB_PATH names ahead of the cached adapter.
Sys.setenv(ZZEDC_DB_PATH = db)
get_db_adapter(config = list(db_backend = "sqlite", sqlite = list(path = db)),
               force_new = TRUE)
init <- initialize_encrypted_database(db_path = db, overwrite = TRUE)
Sys.setenv(DB_ENCRYPTION_KEY = init$key)
stopifnot(isTRUE(init_audit_logging(db_path = db)$success))
conn <- connect_encrypted_db(db_path = db)
ensure_edc_users_table(conn)
ensure_data_entries_table(conn)
for (sid in c("OLD-1", "OLD-2")) {
  DBI::dbExecute(conn,
    "INSERT INTO data_entries (entry_id, subject_id, form_name, data_json,
                               is_complete, created_by)
     VALUES (?, ?, 'baseline', '{}', 1, 'x')",
    params = list(paste0("E-", sid), sid))
}
stopifnot(isTRUE(migrate_add_subject_sites(conn, "setup")$success))
stopifnot(isTRUE(add_site(conn, "S01", "One", "setup")$success))
stopifnot(isTRUE(add_site(conn, "S02", "Two", "setup")$success))

site_of <- function(id) {
  DBI::dbGetQuery(conn, "SELECT site_id FROM subjects WHERE subject_id = ?",
                  params = list(id))$site_id
}
n_audit <- function(where) {
  DBI::dbGetQuery(conn, paste("SELECT COUNT(*) AS n FROM audit_log WHERE",
                              where))$n
}

labels <- get(".site_labels", envir = ns)
expect_equal(labels(c("S01", "1", "S02"), c("One", "1", NA)),
             c("One (S01)", "1", "S02"),
             info = "a site named by its ID is shown once")

html <- paste(as.character(ui("ss")), collapse = "")
expect_true(grepl("ss-subjects_table", html) && grepl("ss-record_btn", html),
            info = "the UI renders the table and the record button")

# An Admin reviews and records a site
reads_before <- n_audit("table_name = 'subjects' AND event_type = 'SELECT'")
shiny::testServer(server, args = list(db_pool = conn,
                                      user_session = .session("Admin", "ann")), {
  session$setInputs(only_unset = TRUE)
  expect_equal(sort(subjects()$subject_id), c("OLD-1", "OLD-2"),
               info = "subjects without a site are listed")
  session$setInputs(subject = "OLD-1", site = "S01", reason = "",
                    record_btn = 1)
  expect_true(is.na(site_of("OLD-1")), info = "a reason is required")
  session$setInputs(reason = "Site log reviewed", record_btn = 2)
  expect_equal(site_of("OLD-1"), "S01", info = "an Admin records a site")
  expect_equal(subjects()$subject_id, "OLD-2",
               info = "the list refreshes after recording")
  session$setInputs(new_site_id = "S03", new_site_name = "Three",
                    add_site_btn = 1)
  expect_equal(DBI::dbGetQuery(conn,
                 "SELECT COUNT(*) AS n FROM sites WHERE site_id = 'S03'")$n, 1L,
               info = "an Admin registers a site")
})
expect_true(n_audit("table_name = 'subjects' AND event_type = 'SELECT'") >
              reads_before,
            info = "viewing the list is recorded as a read")
expect_equal(n_audit("table_name = 'subjects' AND event_type = 'UPDATE'
                      AND record_id = 'OLD-1'"), 1L,
             info = "the site change is audited")

# A PI records a transfer but cannot register sites
shiny::testServer(server, args = list(db_pool = conn,
                                      user_session = .session("PI", "pat")), {
  # The filter change re-populates (and briefly freezes) the subject
  # input, which a browser then acknowledges; choose after that.
  session$setInputs(only_unset = FALSE)
  session$setInputs(subject = "OLD-1", site = "S02", reason = "Moved",
                    record_btn = 1)
  expect_equal(site_of("OLD-1"), "S02", info = "a PI records a transfer")
  session$setInputs(new_site_id = "S04", add_site_btn = 1)
  expect_equal(DBI::dbGetQuery(conn,
                 "SELECT COUNT(*) AS n FROM sites WHERE site_id = 'S04'")$n, 0L,
               info = "a PI cannot register a site")
})

# A Coordinator cannot change sites
shiny::testServer(server, args = list(db_pool = conn,
                                      user_session = .session("Coordinator", "cal")), {
  session$setInputs(only_unset = TRUE, subject = "OLD-2", site = "S01",
                    reason = "x", record_btn = 1)
  expect_true(is.na(site_of("OLD-2")),
              info = "a Coordinator cannot record a site")
})
expect_true(n_audit("event_type = 'ACCESS' AND operation = 'DENIED'
                     AND details LIKE '%record a subject%'") >= 1,
            info = "the refused action is audited")

# Signed out: nothing is shown and nothing changes
us <- .session("Admin", "ann")
shiny::testServer(server, args = list(db_pool = conn, user_session = us), {
  us$authenticated <- FALSE
  us$role <- NULL
  session$flushReact()
  session$setInputs(subject = "OLD-2", site = "S01", reason = "x",
                    record_btn = 1)
  expect_true(is.na(site_of("OLD-2")), info = "no action after sign-out")
})
expect_true(isTRUE(verify_audit_integrity(db_path = db)$valid),
            info = "audit chain verifies")

DBI::dbDisconnect(conn)
unlink(db)
cache$adapter <- old_adapter
if (is.na(old_db_path)) {
  Sys.unsetenv("ZZEDC_DB_PATH")
} else {
  Sys.setenv(ZZEDC_DB_PATH = old_db_path)
}
if (nzchar(old_key)) {
  Sys.setenv(DB_ENCRYPTION_KEY = old_key)
} else {
  Sys.unsetenv("DB_ENCRYPTION_KEY")
}
