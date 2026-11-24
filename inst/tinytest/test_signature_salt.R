library(tinytest)
if (file.exists("_setup.R")) source("_setup.R")

# Regression test (2026-11-23): signing rejected every correct
# password. verify_password_for_signature() hashed the password
# without the installation salt, while the login, the setup wizard,
# and user management store SHA-256(password + resolve_auth_salt()).
# The existing signature tests built unsalted hashes, matching the
# defect, so they passed.

if (!exists("apply_electronic_signature")) {
  exit_file("electronic signature functions not available")
}
verify_password_for_signature <- get("verify_password_for_signature",
                                     envir = asNamespace("zzedc"))

old_key <- Sys.getenv("DB_ENCRYPTION_KEY")
old_salt <- getOption("zzedc.auth_salt")

db <- tempfile(fileext = ".db")
init <- initialize_encrypted_database(db_path = db, overwrite = TRUE)
Sys.setenv(DB_ENCRYPTION_KEY = init$key)
stopifnot(isTRUE(init_audit_logging(db_path = db)$success))
stopifnot(isTRUE(init_electronic_signatures(db_path = db)$success))
con <- connect_encrypted_db(db_path = db)
DBI::dbExecute(con, "CREATE TABLE vitals (id INTEGER PRIMARY KEY, sbp INTEGER)")
DBI::dbExecute(con, "INSERT INTO vitals VALUES (1, 120), (2, 130)")
DBI::dbDisconnect(con)

sign <- function(record_id, password, stored) {
  apply_electronic_signature(
    table_name = "vitals", record_id = record_id, signer_user_id = "pi1",
    signer_full_name = "Pat Investigator", signature_meaning = "APPROVED_BY",
    password = password, password_hash = stored, db_path = db)
}

for (salt in c("site-salt-123", "default_salt")) {
  options(zzedc.auth_salt = salt)
  # The application's stored hash (R/user_management_module.R,
  # R/setup_wizard_utils.R, R/auth_module.R).
  stored <- digest::digest(paste0("Correct-Horse-1", resolve_auth_salt()),
                           algo = "sha256")

  expect_true(verify_password_for_signature("Correct-Horse-1", stored),
              info = paste("salt", salt, ": login-rule hash verifies"))
  expect_false(verify_password_for_signature("wrong", stored),
               info = paste("salt", salt, ": wrong password rejected"))

  ok <- sign(if (salt == "default_salt") "1" else "2",
             "Correct-Horse-1", stored)
  expect_true(isTRUE(ok$success),
              info = paste("salt", salt, ": signing with the correct password",
                           ok$error %||% ""))
  bad <- sign("1", "wrong", stored)
  expect_false(isTRUE(bad$success),
               info = paste("salt", salt, ": signing with a wrong password"))
}

# An explicit salt argument overrides the installation salt
expect_true(verify_password_for_signature(
  "pw", digest::digest("pwXYZ", algo = "sha256"), salt = "XYZ"),
  info = "explicit salt is used")

unlink(db)
options(zzedc.auth_salt = old_salt)
if (nzchar(old_key)) {
  Sys.setenv(DB_ENCRYPTION_KEY = old_key)
} else {
  Sys.unsetenv("DB_ENCRYPTION_KEY")
}
