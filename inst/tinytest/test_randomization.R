library(tinytest)

if (file.exists("_setup.R")) source("_setup.R")
if (!exists("randomize_next_subject")) exit_file("randomization functions not available")

# Permanent regression tests for the randomization/blinding feature
# (~/.claude/plans/soft-orbiting-acorn.md, phases 1-4). These
# properties were all verified by one-off scratch scripts during
# that work; this file captures them permanently so a future change
# cannot silently regress them.

setup_randomization_db <- function() {
  config <- test_backend_config("sqlite")
  adapter <- get_db_adapter(config = config, force_new = TRUE)
  conn <- adapter$connect()
  zzedc:::.create_randomization_tables(conn, adapter$dialect(), "sqlite", adapter)
  DBI::dbExecute(conn, "CREATE TABLE study_info (study_id TEXT PRIMARY KEY, study_name TEXT)")
  DBI::dbExecute(conn, "INSERT INTO study_info VALUES ('TESTSTUDY', 'Test Study')")
  DBI::dbExecute(conn, "CREATE TABLE edc_users (user_id TEXT, username TEXT)")
  zzedc:::.ensure_audit_tables(conn, adapter = adapter)
  list(conn = conn, adapter = adapter)
}

# --- Phase 1: simple scheme, reproducible replay -------------------

db <- setup_randomization_db()
conn <- db$conn

cfg <- set_randomization_config(conn, scheme = "simple", rng_seed = 42L,
                                 created_by = "tester")
expect_true(isTRUE(cfg$success))

r1 <- randomize_next_subject(conn, "SUBJ001", randomized_by = "tester")
expect_true(isTRUE(r1$success))
r2 <- randomize_next_subject(conn, "SUBJ002", randomized_by = "tester")
expect_true(isTRUE(r2$success))

# Re-randomizing the same subject is rejected.
r_dup <- randomize_next_subject(conn, "SUBJ001", randomized_by = "tester")
expect_false(isTRUE(r_dup$success))

# Replay reproducibility: the one-at-a-time sequence must match a
# one-shot batch allocate() call from the same seed.
set.seed(42L)
expected <- zzalloc::alloc_simple(2L)
expect_identical(as.integer(c(r1$arm_code, r2$arm_code)), as.integer(expected))

# The config is locked after the first subject; reconfiguring is
# refused even for the fields that didn't change.
locked <- set_randomization_config(conn, scheme = "simple", rng_seed = 99L,
                                    created_by = "tester")
expect_false(isTRUE(locked$success))

# A NULL randomized_by must not crash (DBI parameter binding requires
# length-1 values; this was a real bug found while building Phase 2).
r3 <- randomize_next_subject(conn, "SUBJ003", randomized_by = NULL)
expect_true(isTRUE(r3$success))

DBI::dbDisconnect(conn)

# --- Phase 3: covariate-adaptive schemes ---------------------------

run_covariate_scheme_test <- function(scheme) {
  db <- setup_randomization_db()
  conn <- db$conn
  cfg <- set_randomization_config(conn, scheme = scheme, rng_seed = 123L,
                                   covariate_fields = c("sex", "stage"),
                                   created_by = "tester")
  expect_true(isTRUE(cfg$success), info = scheme)

  sexes <- rep(c("F", "M"), 10)
  stages <- rep(c("I", "II", "III"), length.out = 20)
  subs <- sprintf("SUBJ%03d", seq_len(20))
  arms <- integer(20)
  for (i in seq_len(20)) {
    res <- randomize_next_subject(conn, subs[i],
                                   covariates_row = list(sex = sexes[i], stage = stages[i]),
                                   randomized_by = "tester")
    expect_true(isTRUE(res$success), info = paste(scheme, i))
    arms[i] <- res$arm_code
  }

  # One-at-a-time replay must match a one-shot batch call over the
  # full history, AND the first-10 prefix of a longer one-shot call
  # -- the actual property the replay strategy depends on, since
  # zzalloc's own RNG draws exactly one value per subject regardless
  # of branch (verified by reading zzalloc's source during Phase 3).
  cov_df <- data.frame(sex = sexes, stage = stages, stringsAsFactors = FALSE)
  set.seed(123L)
  expected_full <- zzalloc::allocate(scheme = scheme, covariates = cov_df)
  expect_identical(as.integer(arms), as.integer(expected_full), info = scheme)

  set.seed(123L)
  expected_10 <- zzalloc::allocate(scheme = scheme, covariates = cov_df[1:10, , drop = FALSE])
  expect_identical(as.integer(arms[1:10]), as.integer(expected_10), info = scheme)

  imb <- get_study_imbalance(conn, "TESTSTUDY")
  direct <- zzalloc::allocation_imbalance(arms, cov_df)
  expect_identical(imb$overall, direct$overall, info = scheme)
  expect_identical(imb$max_marginal, direct$max_marginal, info = scheme)

  DBI::dbDisconnect(conn)
}

for (s in c("stratified_block", "pocock_simon", "hu_hu", "msb")) {
  run_covariate_scheme_test(s)
}

# "cara" is response-adaptive, not covariate-adaptive, and returns a
# different shape (list($trt, $response)) that randomize_next_subject()
# does not handle -- it must be rejected at both the validator and
# the setter, not silently mishandled.
expect_false(isTRUE(zzedc:::validate_randomization_config("cara", covariate_fields = "x")$success))

db2 <- setup_randomization_db()
cara_cfg <- set_randomization_config(db2$conn, scheme = "cara", rng_seed = 1L,
                                      covariate_fields = "x", created_by = "t")
expect_false(isTRUE(cara_cfg$success))
DBI::dbDisconnect(db2$conn)

# --- Phase 2: blinding grant/revoke ---------------------------------

db3 <- setup_randomization_db()
conn3 <- db3$conn
study_id <- "TESTSTUDY"

expect_false(is_unblinded(conn3, study_id, "alice"))

# Non-Admin cannot grant.
bad_grant <- grant_unblinded_access(conn3, study_id, "alice", granted_by = "bob",
                                     actor_role = "Coordinator")
expect_false(isTRUE(bad_grant$success))

ok_grant <- grant_unblinded_access(conn3, study_id, "alice", granted_by = "admin1",
                                    actor_role = "Admin")
expect_true(isTRUE(ok_grant$success))
expect_true(is_unblinded(conn3, study_id, "alice"))

# A duplicate grant is rejected.
dup_grant <- grant_unblinded_access(conn3, study_id, "alice", granted_by = "admin1",
                                     actor_role = "Admin")
expect_false(isTRUE(dup_grant$success))

grants <- list_unblinding_grants(conn3, study_id)
expect_equal(nrow(grants), 1)
expect_identical(grants$user_id[1], "alice")

# NULL granted_by must not crash (the same DBI length-1 issue as
# randomized_by above; found and fixed for this function too).
null_grant <- grant_unblinded_access(conn3, study_id, "carol", granted_by = NULL,
                                      actor_role = "Admin")
expect_false(isTRUE(null_grant$success))

ok_revoke <- revoke_unblinded_access(conn3, study_id, "alice", revoked_by = "admin1",
                                      actor_role = "Admin")
expect_true(isTRUE(ok_revoke$success))
expect_false(is_unblinded(conn3, study_id, "alice"))
expect_equal(nrow(list_unblinding_grants(conn3, study_id)), 0)

# Revoking an already-revoked grant is rejected.
dup_revoke <- revoke_unblinded_access(conn3, study_id, "alice", revoked_by = "admin1",
                                       actor_role = "Admin")
expect_false(isTRUE(dup_revoke$success))

# Both the grant and the revoke are recorded as PERMISSION_CHANGE
# audit events, and neither ever carries a treatment arm (there is
# none to leak -- these events are about access, not assignment).
audit <- DBI::dbGetQuery(conn3, "
  SELECT event_type, details FROM audit_log
  WHERE table_name = 'study_unblinding_grants' AND record_id = 'alice'
  ORDER BY audit_id
")
expect_equal(nrow(audit), 2)
expect_true(all(audit$event_type == "PERMISSION_CHANGE"))
expect_false(any(grepl("arm", audit$details, ignore.case = TRUE)))

DBI::dbDisconnect(conn3)

# --- Phase 4: emergency unblind --------------------------------------

db4 <- setup_randomization_db()
conn4 <- db4$conn
set_randomization_config(conn4, scheme = "simple", rng_seed = 7L,
                          created_by = "admin1", actor_role = "Admin")
set_treatment_arm_labels(conn4, c("0" = "Placebo", "1" = "Active"))

# Unblinding a never-randomized subject is rejected.
not_yet <- emergency_unblind_subject(conn4, "GHOST", requested_by = "doc1",
                                      reason = "checking before randomizing")
expect_false(isTRUE(not_yet$success))

randomize_next_subject(conn4, "S01", randomized_by = "coord1")

# Only Admin or PI may perform it.
bad_role <- emergency_unblind_subject(conn4, "S01", requested_by = "doc1",
                                       reason = "patient had a serious AE",
                                       actor_role = "Coordinator")
expect_false(isTRUE(bad_role$success))

# A reason under 10 characters is rejected.
short_reason <- emergency_unblind_subject(conn4, "S01", requested_by = "doc1",
                                           reason = "SAE", actor_role = "PI")
expect_false(isTRUE(short_reason$success))

ok_unblind <- emergency_unblind_subject(conn4, "S01", requested_by = "doc1",
                                         reason = "patient had a serious adverse event",
                                         actor_role = "PI")
expect_true(isTRUE(ok_unblind$success))
expect_true(ok_unblind$arm_code %in% c(0L, 1L))

# The property this phase exists for: an emergency unblind must NOT
# create a standing grant. doc1 remains blinded for the rest of the
# study even after learning one subject's arm.
expect_false(is_unblinded(conn4, "TESTSTUDY", "doc1"))
expect_equal(nrow(list_unblinding_grants(conn4, "TESTSTUDY")), 0)

# The EMERGENCY_UNBLIND audit event legitimately contains the arm
# (unlike every RANDOMIZATION event, which never does).
emerg_audit <- DBI::dbGetQuery(conn4, "
  SELECT event_type, details, user_id FROM audit_log
  WHERE event_type = 'EMERGENCY_UNBLIND'
")
expect_equal(nrow(emerg_audit), 1)
expect_true(grepl("arm_code", emerg_audit$details[1]))
expect_identical(emerg_audit$user_id[1], "doc1")

DBI::dbDisconnect(conn4)
