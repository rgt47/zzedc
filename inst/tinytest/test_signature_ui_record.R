library(tinytest)
if (file.exists("_setup.R")) source("_setup.R")

# Regression tests (2026-11-25):
# 1. The compliance module offered lowercase signature meanings
#    ('approved_by'), which apply_electronic_signature() rejects, so no
#    signature could be applied through the application. The module
#    test set 'CREATED_BY' directly and never saw the offered choices.
# 2. apply_electronic_signature() signed records that do not exist:
#    compute_record_hash() hashes a placeholder for a missing table or
#    record, and the signature succeeded.

if (!exists("apply_electronic_signature")) {
  exit_file("electronic signature functions not available")
}
for (fn in c("cfr_compliance_ui", "cfr_compliance_server",
             "ensure_edc_users_table", "db_insert_user")) {
  assign(fn, get(fn, envir = asNamespace("zzedc")))
}
.signable_tables <- get0(".signable_tables", envir = asNamespace("zzedc"),
                         ifnotfound = function() NULL)

old_key <- Sys.getenv("DB_ENCRYPTION_KEY")
old_opts <- options(zzedc.auth_salt = "ui-test-salt",
                    zzedc.signable_tables = NULL)

.select_values <- function(html, id) {
  block <- regmatches(html, regexpr(
    paste0('(?s)<select id="', id, '"[^>]*>.*?</select>'), html, perl = TRUE))
  vals <- regmatches(block, gregexpr('value="[^"]*"', block))[[1]]
  gsub('^value="|"$', "", vals)
}

# The meanings the form offers are the ones the function accepts
html <- paste(as.character(cfr_compliance_ui("c")), collapse = "")
offered <- .select_values(html, "c-sig_meaning")
expect_true(length(offered) > 0, info = "the form offers signature meanings")
expect_true(all(offered %in% names(get_signature_meanings())),
            info = paste("offered meanings are valid:",
                         paste(offered, collapse = ", ")))

# The tables the form offers are study tables, never system tables
tables <- .select_values(html, "c-sig_table")
expect_identical(tables, .signable_tables(),
                 info = "the form offers the signable tables")
expect_false(any(c("edc_users", "audit_log", "electronic_signatures") %in%
                   tables),
             info = "system tables are not offered for signing")

# Database with one signable record and one user
db <- tempfile(fileext = ".db")
init <- initialize_encrypted_database(db_path = db, overwrite = TRUE)
Sys.setenv(DB_ENCRYPTION_KEY = init$key)
stopifnot(isTRUE(init_audit_logging(db_path = db)$success))
stopifnot(isTRUE(init_electronic_signatures(db_path = db)$success))
con <- connect_encrypted_db(db_path = db)
DBI::dbExecute(con, "CREATE TABLE vitals (id INTEGER PRIMARY KEY, sbp INTEGER)")
DBI::dbExecute(con, "INSERT INTO vitals VALUES (1, 120)")
ensure_edc_users_table(con)
stored <- digest::digest(paste0("pw-1", resolve_auth_salt()), algo = "sha256")
db_insert_user(con, username = "pi1", password_hash = stored,
               full_name = "Pat Investigator", role = "PI",
               user_id = "U_PI", created_by = "test")
DBI::dbDisconnect(con)

n_sigs <- function() {
  con <- connect_encrypted_db(db_path = db)
  on.exit(DBI::dbDisconnect(con))
  DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM electronic_signatures")$n
}
sign <- function(tbl, id) {
  apply_electronic_signature(tbl, id, "U_PI", "Pat Investigator",
                             "APPROVED_BY", "pw-1", stored, db_path = db)
}

# Missing record or table: refused, nothing written, attempt logged
r <- sign("vitals", "999")
expect_false(isTRUE(r$success), info = "a missing record cannot be signed")
expect_true(grepl("not found", r$error), info = "the refusal names the cause")
r <- sign("no_such_table", "1")
expect_false(isTRUE(r$success), info = "a missing table cannot be signed")
expect_equal(n_sigs(), 0L, info = "refused signatures write no row")
con <- connect_encrypted_db(db_path = db)
att <- DBI::dbGetQuery(con, "SELECT attempt_result FROM signature_attempts")
DBI::dbDisconnect(con)
expect_equal(sum(att$attempt_result == "FAILED_VALIDATION"), 2L,
             info = "both refusals are logged as failed attempts")

r <- sign("vitals", "1")
expect_true(isTRUE(r$success), info = paste("an existing record is signed",
                                            r$error %||% ""))
expect_true(isTRUE(verify_electronic_signature(r$signature_code,
                                               db_path = db)$is_valid),
            info = "the signature verifies")

# Through the module, with a meaning the form actually offers. The
# module signs on the default connection, which is the cached adapter.
cache <- get(".db_adapter_cache", envir = asNamespace("zzedc"))
old_adapter <- cache$adapter
get_db_adapter(config = list(db_backend = "sqlite", sqlite = list(path = db)),
               force_new = TRUE)
db_pool <- connect_encrypted_db(db_path = db)
assign("db_pool", db_pool, envir = globalenv())
Sys.setenv(ZZEDC_DB_PATH = db)
options(zzedc.signable_tables = "vitals")

shiny::testServer(cfr_compliance_server,
                  args = list(user_id = shiny::reactive("U_PI")), {
  session$setInputs(sig_table = "vitals", sig_record_id = "1",
                    sig_meaning = offered[1],
                    sig_password = "pw-1", sig_reason = "",
                    apply_signature = 1)
})
expect_equal(n_sigs(), 2L,
             info = "the module signs with a meaning offered by the form")

shiny::testServer(cfr_compliance_server,
                  args = list(user_id = shiny::reactive("U_PI")), {
  session$setInputs(sig_table = "edc_users", sig_record_id = "U_PI",
                    sig_meaning = "APPROVED_BY", sig_password = "pw-1",
                    sig_reason = "", apply_signature = 1)
})
expect_equal(n_sigs(), 2L,
             info = "the module refuses a table outside the signable list")

DBI::dbDisconnect(db_pool)
rm("db_pool", envir = globalenv())
Sys.unsetenv("ZZEDC_DB_PATH")
cache$adapter <- old_adapter
unlink(db)
options(old_opts)
if (nzchar(old_key)) {
  Sys.setenv(DB_ENCRYPTION_KEY = old_key)
} else {
  Sys.unsetenv("DB_ENCRYPTION_KEY")
}
