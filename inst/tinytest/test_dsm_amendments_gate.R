library(tinytest)
if (file.exists("_setup.R")) source("_setup.R")

# Monitoring-plan amendments and the optional activity gate (Phase 1,
# slice 3; design Sections 6.5 and 6.6).

if (!exists("dsm_register_amendment")) exit_file("amendment functions not available")

for (fn in c("db_insert_user", "ensure_edc_users_table", "dsm_plan_status",
             ".dsm_activity_gate", "ensure_data_entries_table",
             "db_insert_data_entry")) {
  assign(fn, get(fn, envir = asNamespace("zzedc")))
}

old_key <- Sys.getenv("DB_ENCRYPTION_KEY")
old_opts <- options(zzedc.auth_salt = "dsm-test-salt",
                    zzedc.dsm_require_plan_in_effect = NULL)

.spec <- function() {
  list(dsm_spec_version = 1L, study_id = "S1", risk_tier = "minimal",
       review = list(report_frequency_months = 12L),
       risks = list(list(id = "r1", category = "data_quality",
                         description = "Missing outcome", likelihood = "low",
                         impact = "medium", critical = FALSE,
                         monitored_by = "narrative")))
}

.db <- function() {
  db <- tempfile(fileext = ".db")
  init <- initialize_encrypted_database(db_path = db, overwrite = TRUE)
  if (!is.null(init$error)) stop(init$error)
  Sys.setenv(DB_ENCRYPTION_KEY = init$key)
  stopifnot(isTRUE(init_audit_logging(db_path = db)$success))
  stopifnot(isTRUE(init_electronic_signatures(db_path = db)$success))
  conn <- connect_encrypted_db(db_path = db)
  ensure_edc_users_table(conn)
  for (u in list(c("pi1", "PI"), c("coord1", "Coordinator"))) {
    db_insert_user(conn, username = u[1],
                   password_hash = digest::digest(
                     paste0("pw-", u[1], resolve_auth_salt()), algo = "sha256"),
                   full_name = u[1], email = "x@example.org", role = u[2],
                   active = TRUE, created_by = "setup")
  }
  ids <- DBI::dbGetQuery(conn, "SELECT user_id, username FROM edc_users")
  list(db = db, conn = conn, uid = stats::setNames(ids$user_id, ids$username))
}

.sign <- function(s, plan_id, who, meaning) {
  r <- apply_electronic_signature(
    table_name = "dsm_plan_versions", record_id = as.character(plan_id),
    signer_user_id = s$uid[[who]], signer_full_name = who,
    signature_meaning = meaning, password = paste0("pw-", who),
    password_hash = digest::digest(paste0("pw-", who, resolve_auth_salt()),
                                   algo = "sha256"),
    db_path = s$db)
  if (!isTRUE(r$success)) stop("signing failed: ", r$error)
  r$signature_code
}

# Import, review, and sign a version; returns its plan_id.
.signed_version <- function(s) {
  p <- dsm_import_spec(s$conn, .spec(), user_id = s$uid[["coord1"]])$plan_id
  dsm_transition(s$conn, p, "internal_review", s$uid[["coord1"]])
  code <- .sign(s, p, "pi1", "APPROVED_BY")
  r <- dsm_transition(s$conn, p, "signed", s$uid[["pi1"]],
                      signature_code = code)
  if (!isTRUE(r$success)) stop(r$error)
  p
}

# Take a signed version through ICO approval into effect.
.approve_into_effect <- function(s, p, date) {
  coord <- s$uid[["coord1"]]
  dsm_transition(s$conn, p, "submitted", coord, effective_date = date,
                 as_of = date)
  dsm_record_ico_decision(s$conn, p, "approved", date, coord, as_of = date)
  r <- dsm_transition(s$conn, p, "in_effect", coord, effective_date = date,
                      as_of = date)
  if (!isTRUE(r$success)) stop(r$error)
  p
}

.close <- function(s) {
  DBI::dbDisconnect(s$conn)
  unlink(s$db)
}

# ---------------------------------------------------------------------------
# Amendments
# ---------------------------------------------------------------------------

local({
  s <- .db()
  on.exit(.close(s))
  coord <- s$uid[["coord1"]]

  p0 <- .signed_version(s)
  r <- dsm_transition(s$conn, p0, "in_effect", coord)
  expect_false(r$success,
               info = "an initial plan cannot skip the institute's review")

  draft <- dsm_import_spec(s$conn, .spec(), user_id = coord)$plan_id
  r <- dsm_register_amendment(s$conn, draft, "report_at_interval",
                              "Change", "Minor", coord)
  expect_false(r$success, info = "no plan in effect: nothing to amend")

  .approve_into_effect(s, p0, "2027-01-10")

  r <- dsm_register_amendment(s$conn, draft, "sometimes", "x", "y", coord)
  expect_false(r$success, info = "unknown amendment class refused")
  r <- dsm_register_amendment(s$conn, draft, "report_at_interval", "", "y",
                              coord)
  expect_false(r$success, info = "summary is required")

  r <- dsm_register_amendment(s$conn, draft, "report_at_interval",
                              "Add a reviewer role", "Administrative change",
                              coord)
  expect_true(r$success, info = paste("amendment registered:",
                                      r$error %||% ""))
  expect_equal(r$from_plan_id, p0, info = "amends the version in effect")
  r2 <- dsm_register_amendment(s$conn, draft, "report_at_interval", "x",
                               "y", coord)
  expect_false(r2$success, info = "a version is registered only once")

  dsm_transition(s$conn, draft, "internal_review", coord)
  code <- .sign(s, draft, "pi1", "APPROVED_BY")
  dsm_transition(s$conn, draft, "signed", s$uid[["pi1"]],
                 signature_code = code)
  r <- dsm_register_amendment(s$conn, draft, "prior_approval", "x", "y",
                              coord)
  expect_false(r$success, info = "only a draft can be registered")
  r <- dsm_transition(s$conn, draft, "in_effect", coord,
                      effective_date = "2027-05-01", as_of = "2027-05-01")
  expect_true(r$success,
              info = "a report-at-interval amendment takes effect once signed")
  expect_equal(dsm_plan_status(s$conn, p0)$status, "superseded",
               info = "the amended version is superseded")

  # A prior-approval amendment
  pa <- dsm_import_spec(s$conn, .spec(), user_id = coord)$plan_id
  dsm_register_amendment(s$conn, pa, "prior_approval", "Change stopping rules",
                         "Needs NIH prior approval under the award", coord)
  dsm_transition(s$conn, pa, "internal_review", coord)
  code <- .sign(s, pa, "pi1", "APPROVED_BY")
  dsm_transition(s$conn, pa, "signed", s$uid[["pi1"]], signature_code = code)
  r <- dsm_transition(s$conn, pa, "in_effect", coord, as_of = "2027-06-01")
  expect_false(r$success, info = "a prior-approval amendment needs review")
  dsm_transition(s$conn, pa, "submitted", coord, effective_date = "2027-06-01",
                 as_of = "2027-06-01")
  att <- .sign(s, pa, "coord1", "CERTIFIED_BY")
  r <- dsm_transition(s$conn, pa, "in_effect", coord, as_of = "2027-08-01",
                      signature_code = att)
  expect_false(r$success,
               info = "no deemed approval for a prior-approval amendment")
  dsm_record_ico_decision(s$conn, pa, "approved", "2027-08-02", coord,
                          as_of = "2027-08-02")
  r <- dsm_transition(s$conn, pa, "in_effect", coord,
                      effective_date = "2027-08-05", as_of = "2027-08-05")
  expect_true(r$success, info = "approved prior-approval amendment takes effect")

  a <- dsm_amendments(s$conn, "S1")
  expect_equal(nrow(a), 2L, info = "both amendments listed")
  expect_equal(a$in_effect_from, c("2027-05-01", "2027-08-05"),
               info = "dates each amendment took effect")
  a2 <- dsm_amendments(s$conn, "S1", from = "2027-07-01", to = "2027-12-31")
  expect_equal(a2$amendment_class, "prior_approval",
               info = "amendments filtered by reporting period")
  expect_true(isTRUE(verify_audit_integrity(db_path = s$db)$valid),
              info = "audit chain verifies after amendments")
})

# ---------------------------------------------------------------------------
# Activity gate
# ---------------------------------------------------------------------------

# Off by default, and then it never touches the database
local({
  options(zzedc.dsm_require_plan_in_effect = NULL)
  expect_null(.dsm_activity_gate(NULL, "anything"),
              info = "gate off: returns without using the connection")
})

local({
  s <- .db()
  on.exit({
    options(zzedc.dsm_require_plan_in_effect = NULL)
    .close(s)
  })
  ensure_data_entries_table(s$conn)

  options(zzedc.dsm_require_plan_in_effect = NULL)
  r <- db_insert_data_entry(s$conn, "SUBJ-1", "baseline", list(age = 50),
                            created_by = "coord1")
  expect_true(r$success, info = "gate off: data entry unaffected")

  options(zzedc.dsm_require_plan_in_effect = TRUE)
  n0 <- DBI::dbGetQuery(s$conn, "SELECT COUNT(*) AS n FROM data_entries")$n
  r <- db_insert_data_entry(s$conn, "SUBJ-2", "baseline", list(age = 60),
                            created_by = "coord1")
  expect_false(r$success, info = "gate on, no plan: first entry refused")
  expect_true(grepl("monitoring plan", r$error),
              info = "the refusal names the monitoring plan")
  expect_equal(DBI::dbGetQuery(s$conn,
                               "SELECT COUNT(*) AS n FROM data_entries")$n,
               n0, info = "refused entry writes nothing")
  r <- db_insert_data_entry(s$conn, "SUBJ-1", "visit2", list(age = 50),
                            created_by = "coord1")
  expect_true(r$success,
              info = "gate on: later entries for an existing subject proceed")

  r <- randomize_next_subject(s$conn, "SUBJ-2", randomized_by = "coord1")
  expect_false(r$success, info = "gate on, no plan: randomization refused")
  expect_true(grepl("monitoring plan", r$error),
              info = "randomization refusal names the monitoring plan")

  p <- .signed_version(s)
  .approve_into_effect(s, p, "2027-01-10")
  r <- db_insert_data_entry(s$conn, "SUBJ-2", "baseline", list(age = 60),
                            created_by = "coord1")
  expect_true(r$success, info = "gate on, plan in effect: first entry proceeds")
  r <- randomize_next_subject(s$conn, "SUBJ-2", randomized_by = "coord1")
  expect_false(isTRUE(grepl("monitoring plan", r$error)),
               info = "gate on, plan in effect: randomization passes the gate")
})

options(old_opts)
if (nzchar(old_key)) {
  Sys.setenv(DB_ENCRYPTION_KEY = old_key)
} else {
  Sys.unsetenv("DB_ENCRYPTION_KEY")
}
