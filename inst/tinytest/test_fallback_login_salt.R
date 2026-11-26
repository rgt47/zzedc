library(tinytest)
if (file.exists("_setup.R")) source("_setup.R")

# Regression test (2026-11-26): the package's fallback login
# (authenticate_user() in R/auth_module.R, served when the main server
# fails to load) read ZZEDC_SALT when the configuration named no salt
# variable. launch_zzedc() writes such a configuration, and every
# password writer hashes with resolve_auth_salt(cfg), which then uses
# default_salt. With ZZEDC_SALT set, the fallback rejected every
# correct password.

if (!exists("authenticate_user", envir = asNamespace("zzedc"))) {
  exit_file("authenticate_user not available")
}
for (fn in c("authenticate_user", "ensure_edc_users_table",
             "db_insert_user")) {
  assign(fn, get(fn, envir = asNamespace("zzedc")))
}

old_env <- Sys.getenv("ZZEDC_SALT", unset = NA_character_)
had_cfg <- exists("cfg", envir = globalenv())
old_cfg <- if (had_cfg) get("cfg", envir = globalenv())
had_pool <- exists("db_pool", envir = globalenv())
old_pool <- if (had_pool) get("db_pool", envir = globalenv())

launcher_cfg <- list(auth = list(default_salt = "launcher-default-salt"))
con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
ensure_edc_users_table(con)
assign("db_pool", con, envir = globalenv())
assign("cfg", launcher_cfg, envir = globalenv())

for (env in c("", "site-salt-from-env")) {
  if (nzchar(env)) Sys.setenv(ZZEDC_SALT = env) else Sys.unsetenv("ZZEDC_SALT")
  uname <- paste0("admin_", if (nzchar(env)) "env" else "noenv")
  db_insert_user(con, username = uname,
                 password_hash = digest::digest(
                   paste0("admin123", resolve_auth_salt(launcher_cfg)),
                   algo = "sha256"),
                 full_name = "Admin", role = "Admin", created_by = "test")
  r <- authenticate_user(uname, "admin123")
  expect_true(isTRUE(r$success),
              info = paste("ZZEDC_SALT =", shQuote(env),
                           ": the stored hash's own password logs in"))
  r <- authenticate_user(uname, "wrong")
  expect_false(isTRUE(r$success),
               info = paste("ZZEDC_SALT =", shQuote(env),
                            ": a wrong password is rejected"))
}

# A configuration that names its salt variable still uses it
Sys.setenv(ZZEDC_SALT = "named-var-salt")
named_cfg <- list(auth = list(salt_env_var = "ZZEDC_SALT",
                              default_salt = "unused"))
assign("cfg", named_cfg, envir = globalenv())
db_insert_user(con, username = "named",
               password_hash = digest::digest("pwnamed-var-salt",
                                              algo = "sha256"),
               full_name = "Named", role = "Admin", created_by = "test")
expect_true(isTRUE(authenticate_user("named", "pw")$success),
            info = "a configured salt variable is honored")

DBI::dbDisconnect(con)
if (had_pool) assign("db_pool", old_pool, envir = globalenv()) else
  rm("db_pool", envir = globalenv())
if (had_cfg) assign("cfg", old_cfg, envir = globalenv()) else
  rm("cfg", envir = globalenv())
if (is.na(old_env)) Sys.unsetenv("ZZEDC_SALT") else
  Sys.setenv(ZZEDC_SALT = old_env)
