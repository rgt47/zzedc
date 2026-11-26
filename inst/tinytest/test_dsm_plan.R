library(tinytest)
if (file.exists("_setup.R")) source("_setup.R")

# Monitoring-plan storage, validation, and lifecycle (Phase 1 of
# docs/nih-dsm-monitoring-plan-design-2026-11-23.md, Section 6).

if (!exists("dsm_import_spec")) exit_file("monitoring-plan functions not available")

for (fn in c("db_insert_user", "ensure_edc_users_table",
             ".dsm_canonical_json", "dsm_plan_status",
             "migrate_add_dsm_tables")) {
  assign(fn, get(fn, envir = asNamespace("zzedc")))
}

old_key <- Sys.getenv("DB_ENCRYPTION_KEY")
old_salt <- getOption("zzedc.auth_salt")
options(zzedc.auth_salt = "dsm-test-salt")

.valid_spec <- function() {
  list(
    dsm_spec_version = 1L,
    study_id = "PRAZ-L-2026",
    funding_ico = "NIA",
    risk_tier = "moderate",
    interim_analyses = list(efficacy = FALSE, futility = FALSE),
    independent_monitor = list(type = "none"),
    review = list(report_frequency_months = 12L,
                  reviewer_roles = list("pi", "monitor")),
    risks = list(
      list(id = "safety_sae", category = "participant_safety",
           description = "Serious adverse events above expected rate",
           likelihood = "medium", impact = "high", critical = TRUE,
           rationale = "Older population.",
           mitigation = "Expedited SAE review.",
           indicators = list(list(indicator = "sae_rate", grain = "site",
                                  window_days = 90L, warning = 0.05,
                                  alert = 0.1, min_denominator = 10L,
                                  review_role = "pi"))),
      list(id = "stewardship", category = "financial_stewardship",
           description = "Enrollment shortfall", likelihood = "low",
           impact = "medium", critical = FALSE, monitored_by = "narrative")
    ),
    stopping_rules = list(list(description = "PI review at alert level",
                               indicator = "sae_rate"))
  )
}

.dsm_db <- function() {
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
                     paste0("pw-", u[1], resolve_auth_salt()),
                     algo = "sha256"),
                   full_name = u[1], email = paste0(u[1], "@example.org"),
                   role = u[2], active = TRUE, created_by = "setup")
  }
  ids <- DBI::dbGetQuery(conn, "SELECT user_id, username FROM edc_users")
  list(db = db, conn = conn,
       uid = stats::setNames(ids$user_id, ids$username))
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

.close <- function(s) {
  DBI::dbDisconnect(s$conn)
  unlink(s$db)
}

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

local({
  v <- dsm_validate_spec(.valid_spec())
  expect_true(v$success, info = "a valid spec validates")
  expect_equal(nrow(v$problems), 0L, info = "no problems for a valid spec")

  bad <- .valid_spec()
  bad$risk_tier <- "huge"
  bad$risks[[1]]$likelihood <- "often"
  bad$risks[[2]]$category <- "budget"
  bad$review$report_frequency_months <- 18L
  v <- dsm_validate_spec(bad)
  expect_false(v$success, info = "an invalid spec fails")
  expect_true(all(c("risk_tier", "risks[1].likelihood", "risks[2].category",
                    "review.report_frequency_months") %in% v$problems$path),
              info = "every problem is reported with its path")

  bad <- .valid_spec()
  bad$interim_analyses$efficacy <- TRUE
  v <- dsm_validate_spec(bad)
  expect_true("independent_monitor.type" %in% v$problems$path,
              info = "interim efficacy without an independent monitor fails")
  bad$independent_monitor$type <- "committee"
  expect_true(dsm_validate_spec(bad)$success,
              info = "interim efficacy with a committee validates")

  bad <- .valid_spec()
  bad$risks[[1]]$indicators <- list()
  bad$risks[[1]]$monitored_by <- "indicator"
  expect_true("risks[1].indicators" %in% dsm_validate_spec(bad)$problems$path,
              info = "a critical indicator-monitored risk needs an indicator")

  bad <- .valid_spec()
  bad$risks[[2]]$id <- "safety_sae"
  expect_true("risks[2].id" %in% dsm_validate_spec(bad)$problems$path,
              info = "duplicate risk ids are reported")

  bad <- .valid_spec()
  bad$stopping_rules[[1]]$indicator <- "no_such_indicator"
  expect_true("stopping_rules[1].indicator" %in%
                dsm_validate_spec(bad)$problems$path,
              info = "a stopping rule must name an indicator in the plan")

  old <- options(zzedc.dsm_risk_categories = c("participant_safety", "budget"))
  bad <- .valid_spec()
  bad$risks[[2]]$category <- "budget"
  expect_true(dsm_validate_spec(bad)$success,
              info = "risk categories are configuration")
  options(old)
})

# ---------------------------------------------------------------------------
# Import, export, canonical hash
# ---------------------------------------------------------------------------

local({
  s <- .dsm_db()
  on.exit(.close(s))

  bad <- .valid_spec()
  bad$risk_tier <- "huge"
  r <- dsm_import_spec(s$conn, bad, user_id = s$uid[["coord1"]])
  expect_false(r$success, info = "an invalid spec is not imported")
  expect_false(DBI::dbExistsTable(s$conn, "dsm_plan_versions") &&
                 DBI::dbGetQuery(s$conn, "SELECT COUNT(*) AS n
                                  FROM dsm_plan_versions")$n > 0,
               info = "nothing is stored for an invalid spec")

  r1 <- dsm_import_spec(s$conn, .valid_spec(), user_id = s$uid[["coord1"]])
  expect_true(r1$success, info = "a valid spec is imported")
  expect_equal(r1$version, 1L, info = "first version is 1")
  expect_equal(dsm_plan_status(s$conn, r1$plan_id)$status, "draft",
               info = "an imported plan starts as draft")

  path <- tempfile(fileext = ".json")
  e <- dsm_export_spec(s$conn, r1$plan_id, path = path)
  expect_true(e$success && file.exists(path), info = "spec exported")
  r2 <- dsm_import_spec(s$conn, path, user_id = s$uid[["coord1"]])
  expect_true(r2$success, info = "exported spec re-imports")
  expect_equal(r2$version, 2L, info = "re-import creates version 2")
  expect_identical(r2$spec_hash, r1$spec_hash,
                   info = "spec hash survives export and re-import")

  reordered <- .valid_spec()
  reordered <- reordered[rev(names(reordered))]
  expect_identical(digest::digest(.dsm_canonical_json(reordered),
                                  algo = "sha256", serialize = FALSE),
                   r1$spec_hash,
                   info = "the hash does not depend on key order")

  a <- DBI::dbGetQuery(s$conn, "SELECT event_type, table_name FROM audit_log")
  expect_true(all(c("dsm_plan_versions", "dsm_plan_events") %in%
                    a$table_name),
              info = "version and event are audited")
  expect_true("DSM_PLAN_STATUS" %in% a$event_type,
              info = "lifecycle events use DSM_PLAN_STATUS")
  expect_true(isTRUE(verify_audit_integrity(db_path = s$db)$valid),
              info = "audit chain verifies after import")
})

# ---------------------------------------------------------------------------
# Lifecycle: ICO approval path
# ---------------------------------------------------------------------------

local({
  s <- .dsm_db()
  on.exit(.close(s))
  coord <- s$uid[["coord1"]]
  pi <- s$uid[["pi1"]]
  p <- dsm_import_spec(s$conn, .valid_spec(), user_id = coord)$plan_id

  r <- dsm_transition(s$conn, p, "submitted", user_id = coord)
  expect_false(r$success, info = "draft cannot jump to submitted")
  expect_true(dsm_transition(s$conn, p, "internal_review", coord)$success,
              info = "draft -> internal_review")

  r <- dsm_transition(s$conn, p, "signed", user_id = pi)
  expect_false(r$success, info = "signing needs a signature code")

  code_coord <- .sign(s, p, "coord1", "APPROVED_BY")
  r <- dsm_transition(s$conn, p, "signed", user_id = coord,
                      signature_code = code_coord)
  expect_false(r$success, info = "the APPROVED_BY signer must be a PI")

  code_wrong <- .sign(s, p, "pi1", "REVIEWED_BY")
  r <- dsm_transition(s$conn, p, "signed", user_id = pi,
                      signature_code = code_wrong)
  expect_false(r$success, info = "a signature with the wrong meaning fails")

  code <- .sign(s, p, "pi1", "APPROVED_BY")
  r <- dsm_transition(s$conn, p, "signed", user_id = coord,
                      signature_code = code)
  expect_false(r$success, info = "the signer must be the user moving it")
  r <- dsm_transition(s$conn, p, "signed", user_id = pi, signature_code = code)
  expect_true(r$success, info = paste("PI signature moves to signed:",
                                      r$error %||% ""))

  sig <- verify_electronic_signature(code, db_path = s$db)
  r <- dsm_transition(s$conn, p, "submitted", user_id = coord,
                      effective_date = "2027-03-01", as_of = "2027-03-02")
  expect_true(r$success, info = "signed -> submitted with a date")
  sig2 <- verify_electronic_signature(code, db_path = s$db)
  expect_true(isTRUE(sig2$record_unchanged),
              info = "the signature stays valid after later transitions")

  r <- dsm_record_ico_decision(s$conn, p, "approved", "2027-02-01",
                               user_id = coord, as_of = "2027-03-10")
  expect_false(r$success, info = "a decision before submission is refused")
  r <- dsm_record_ico_decision(s$conn, p, "approved", "2027-03-15",
                               user_id = coord, document_ref = "letter-1",
                               as_of = "2027-03-20")
  expect_true(r$success, info = "ICO approval recorded")
  st <- dsm_plan_status(s$conn, p, as_of = "2027-03-20")
  expect_equal(st$status, "approved", info = "status approved")
  expect_equal(st$ico_decision, "approved", info = "decision recorded")

  expect_true(is.null(dsm_plan_in_effect(s$conn, "PRAZ-L-2026")),
              info = "nothing in effect before activation")
  r <- dsm_transition(s$conn, p, "in_effect", user_id = coord,
                      effective_date = "2027-04-01", as_of = "2027-04-01")
  expect_true(r$success, info = "approved -> in_effect")
  ie <- dsm_plan_in_effect(s$conn, "PRAZ-L-2026")
  expect_equal(ie$plan_id, p, info = "version in effect")
  expect_equal(ie$in_effect_from, "2027-04-01", info = "effective date kept")

  # A second version supersedes the first
  p2 <- dsm_import_spec(s$conn, .valid_spec(), user_id = coord)$plan_id
  dsm_transition(s$conn, p2, "internal_review", coord)
  dsm_transition(s$conn, p2, "signed", pi,
                 signature_code = .sign(s, p2, "pi1", "APPROVED_BY"))
  dsm_transition(s$conn, p2, "submitted", coord, effective_date = "2027-06-01",
                 as_of = "2027-06-01")
  dsm_record_ico_decision(s$conn, p2, "approved", "2027-06-10", coord,
                          as_of = "2027-06-10")
  r <- dsm_transition(s$conn, p2, "in_effect", coord,
                      effective_date = "2027-06-15", as_of = "2027-06-15")
  expect_true(r$success, info = "second version goes into effect")
  expect_equal(dsm_plan_in_effect(s$conn, "PRAZ-L-2026")$plan_id, p2,
               info = "only the new version is in effect")
  expect_equal(dsm_plan_status(s$conn, p)$status, "superseded",
               info = "the old version is superseded")

  h <- dsm_plan_history(s$conn, "PRAZ-L-2026")
  expect_true(nrow(h) >= 12L, info = "history lists every event")
  expect_true(isTRUE(verify_audit_integrity(db_path = s$db)$valid),
              info = "audit chain verifies after the lifecycle")
})

# ---------------------------------------------------------------------------
# Lifecycle: deemed approval, days 29, 30, 31
# ---------------------------------------------------------------------------

local({
  s <- .dsm_db()
  on.exit(.close(s))
  coord <- s$uid[["coord1"]]
  pi <- s$uid[["pi1"]]
  p <- dsm_import_spec(s$conn, .valid_spec(), user_id = coord)$plan_id
  dsm_transition(s$conn, p, "internal_review", coord)
  dsm_transition(s$conn, p, "signed", pi,
                 signature_code = .sign(s, p, "pi1", "APPROVED_BY"))
  dsm_transition(s$conn, p, "submitted", coord, effective_date = "2027-03-01",
                 as_of = "2027-03-01")

  expect_false(dsm_plan_status(s$conn, p, as_of = "2027-03-30")$deemed_eligible,
               info = "day 29: not eligible")
  expect_true(dsm_plan_status(s$conn, p, as_of = "2027-03-31")$deemed_eligible,
              info = "day 30: eligible")
  expect_true(dsm_plan_status(s$conn, p, as_of = "2027-04-01")$deemed_eligible,
              info = "day 31: eligible")
  expect_equal(dsm_plan_status(s$conn, p)$deemed_eligible_on, "2027-03-31",
               info = "eligibility date is reported")

  r <- dsm_transition(s$conn, p, "in_effect", coord, as_of = "2027-03-30",
                      signature_code = .sign(s, p, "coord1", "CERTIFIED_BY"))
  expect_false(r$success, info = "cannot take effect before eligibility")

  r <- dsm_transition(s$conn, p, "in_effect", coord, as_of = "2027-04-02")
  expect_false(r$success, info = "deemed approval needs an attestation")

  att <- .sign(s, p, "coord1", "CERTIFIED_BY")
  r <- dsm_transition(s$conn, p, "in_effect", coord, as_of = "2027-04-02",
                      effective_date = "2027-04-02", signature_code = att)
  expect_true(r$success, info = paste("attested deemed approval takes effect:",
                                      r$error %||% ""))

  old <- options(zzedc.dsm_deemed_approval_days = 45L)
  expect_false(dsm_plan_status(s$conn, p, as_of = "2027-04-02")$deemed_eligible,
               info = "status is no longer submitted after taking effect")
  options(old)
})

# The day count is configuration
local({
  s <- .dsm_db()
  on.exit(.close(s))
  coord <- s$uid[["coord1"]]
  p <- dsm_import_spec(s$conn, .valid_spec(), user_id = coord)$plan_id
  dsm_transition(s$conn, p, "internal_review", coord)
  dsm_transition(s$conn, p, "signed", s$uid[["pi1"]],
                 signature_code = .sign(s, p, "pi1", "APPROVED_BY"))
  dsm_transition(s$conn, p, "submitted", coord, effective_date = "2027-03-01",
                 as_of = "2027-03-01")
  old <- options(zzedc.dsm_deemed_approval_days = 45L)
  expect_false(dsm_plan_status(s$conn, p, as_of = "2027-03-31")$deemed_eligible,
               info = "configured day count is used")
  options(zzedc.dsm_deemed_approval_days = 30L,
          zzedc.dsm_deemed_approval_day_type = "business")
  expect_false(dsm_plan_status(s$conn, p, as_of = "2027-03-31")$deemed_eligible,
               info = "business days exclude weekends")
  options(old)
  options(zzedc.dsm_deemed_approval_day_type = NULL)
})

# A refused move writes nothing
local({
  s <- .dsm_db()
  on.exit(.close(s))
  p <- dsm_import_spec(s$conn, .valid_spec(), user_id = s$uid[["coord1"]])$plan_id
  n_ev <- DBI::dbGetQuery(s$conn, "SELECT COUNT(*) AS n FROM dsm_plan_events")$n
  n_au <- DBI::dbGetQuery(s$conn, "SELECT COUNT(*) AS n FROM audit_log")$n
  dsm_transition(s$conn, p, "in_effect", s$uid[["coord1"]])
  expect_equal(DBI::dbGetQuery(s$conn, "SELECT COUNT(*) AS n
                                FROM dsm_plan_events")$n, n_ev,
               info = "refused move: no event")
  expect_equal(DBI::dbGetQuery(s$conn, "SELECT COUNT(*) AS n
                                FROM audit_log")$n, n_au,
               info = "refused move: no audit record")
})

# Reads on a database without monitoring plans
local({
  s <- .dsm_db()
  on.exit(.close(s))
  expect_true(is.null(dsm_plan_in_effect(s$conn, "X")),
              info = "no tables: nothing in effect")
  expect_equal(nrow(dsm_plan_history(s$conn, "X")), 0L,
               info = "no tables: empty history")
  expect_true(is.null(dsm_plan_status(s$conn, 1L)),
              info = "no tables: no status")
})

options(zzedc.auth_salt = old_salt)
if (nzchar(old_key)) {
  Sys.setenv(DB_ENCRYPTION_KEY = old_key)
} else {
  Sys.unsetenv("DB_ENCRYPTION_KEY")
}
