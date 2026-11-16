library(tinytest)

if (file.exists("_setup.R")) source("_setup.R")

# Defect 8 (zzedc-modernization-whitepaper-2026-11-13.md, Section
# 2.2): MySQLAdapter$connect()/pool() used to set
# args$ssl.mode <- my$ssl_mode, but ssl.mode is not a parameter
# RMariaDB::dbConnect() recognizes at all -- confirmed directly
# against its own documented connection arguments (ssl.key, ssl.cert,
# ssl.ca, ssl.capath, ssl.cipher, and a separate client.flag =
# CLIENT_SSL to require TLS; no ssl.mode among them).
# do.call(DBI::dbConnect, args) silently drops an unrecognized
# argument name rather than erroring, so mysql$ssl_mode = "REQUIRED"
# (the package's own documented example) connected in plaintext with
# no warning. .mysql_tls_args() is the fix: it maps ssl_mode to real
# RMariaDB arguments and, under the 'regulated' profile, refuses
# anything the defect calls "unverified TLS".
#
# Pure logic, no live server needed.

if (requireNamespace("RMariaDB", quietly = TRUE)) local({
  old_profile <- getOption("zzedc.security_profile")
  on.exit(options(zzedc.security_profile = old_profile), add = TRUE)

  options(zzedc.security_profile = "standard")

  expect_equal(zzedc:::.mysql_tls_args(list()), list(),
               info = "no ssl_mode configured: no extra connection args, no error")

  required <- zzedc:::.mysql_tls_args(list(ssl_mode = "REQUIRED"))
  expect_equal(names(required), "client.flag")
  expect_identical(required$client.flag, RMariaDB::CLIENT_SSL,
                    info = "REQUIRED forces TLS via the real client.flag argument, not a nonexistent ssl.mode")

  expect_error(
    zzedc:::.mysql_tls_args(list(ssl_mode = "VERIFY_CA")),
    "ssl_ca",
    info = "verification is impossible without a CA to verify against -- an explicit error, not a silent downgrade"
  )
  expect_error(
    zzedc:::.mysql_tls_args(list(ssl_mode = "VERIFY_IDENTITY")),
    "ssl_ca"
  )

  verify_ca <- zzedc:::.mysql_tls_args(
    list(ssl_mode = "VERIFY_CA", ssl_ca = "/path/to/ca.pem")
  )
  expect_equal(sort(names(verify_ca)), sort(c("client.flag", "ssl.ca")))
  expect_identical(verify_ca$ssl.ca, "/path/to/ca.pem")

  # ssl_cert/ssl_key/ssl_cipher pass through verbatim when configured.
  full <- zzedc:::.mysql_tls_args(list(
    ssl_mode = "VERIFY_IDENTITY", ssl_ca = "/ca.pem",
    ssl_cert = "/client.pem", ssl_key = "/client-key.pem",
    ssl_cipher = "HIGH"
  ))
  expect_identical(full$ssl.cert, "/client.pem")
  expect_identical(full$ssl.key, "/client-key.pem")
  expect_identical(full$ssl.cipher, "HIGH")

  # The 'regulated' profile must not accept what this defect calls
  # "unverified TLS" -- unset, or REQUIRED alone, are both refused;
  # only VERIFY_CA/VERIFY_IDENTITY (with ssl_ca) are allowed.
  options(zzedc.security_profile = "regulated")
  expect_error(zzedc:::.mysql_tls_args(list()), "regulated")
  expect_error(zzedc:::.mysql_tls_args(list(ssl_mode = "REQUIRED")), "regulated")
  expect_error(zzedc:::.mysql_tls_args(list(ssl_mode = "required")), "regulated",
               info = "ssl_mode matching is case-insensitive")
  regulated_ok <- zzedc:::.mysql_tls_args(
    list(ssl_mode = "VERIFY_CA", ssl_ca = "/ca.pem")
  )
  expect_true("ssl.ca" %in% names(regulated_ok))
})
