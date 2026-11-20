library(tinytest)
if (file.exists("_setup.R")) source("_setup.R")

# Double data entry (DDE), added 2026-11-19. Covers: the
# dde_group_id/superseded_by migration on data_entries (idempotent,
# preserves existing rows); the designer_fields.require_double_entry
# migration; the blind-probe/decide-role split that never reads the
# first entry's data_json until the one save-time diff function; the
# item-level diff restricted to flagged fields only; the three
# in-save resolution choices, their audit detail, and that
# "keep_second"/"revert_first" actually resolve the field (not just
# record a choice); a third submission against an already-complete
# pair; the reconciliation queue; and the reviewer-separation guard
# enforced inside approve_correction()/apply_correction() themselves.

if (!exists("list_dde_discrepancies")) exit_file("double_data_entry functions not available")
for (fn in c("ensure_data_entries_table", "db_insert_data_entry", "db_get_dde_first_entry",
             "db_get_dde_first_entry_values", "db_mark_entry_superseded",
             "db_count_dde_group_entries",
             "flagged_dde_fields", "dde_decide_role", "dde_check_discrepancies",
             "apply_dde_resolutions", "update_first_entry_for_dde_resolution",
             "update_second_entry_for_dde_resolution",
             "list_dde_discrepancies",
             "require_dde_reviewer_separation", "close_dde_group_if_resolved",
             "diff_field_lists", "generate_dde_group_id")) {
  assign(fn, get(fn, envir = asNamespace("zzedc")))
}

setup_db <- function() {
  old_key <- Sys.getenv("DB_ENCRYPTION_KEY")
  if (old_key != "") Sys.setenv(ZZEDC_OLD_KEY = old_key)
  db <- tempfile(fileext = ".db")
  init <- initialize_encrypted_database(db_path = db, overwrite = TRUE)
  Sys.setenv(DB_ENCRYPTION_KEY = init$key)
  init_audit_logging(db_path = db)
  init_version_control(db_path = db)
  init_data_correction(db_path = db)
  conn <- connect_encrypted_db(db_path = db)
  ensure_data_entries_table(conn)
  DBI::dbDisconnect(conn)
  db
}

cleanup_db <- function(db) {
  unlink(db)
  old <- Sys.getenv("ZZEDC_OLD_KEY")
  if (old != "") { Sys.setenv(DB_ENCRYPTION_KEY = old); Sys.unsetenv("ZZEDC_OLD_KEY") }
}

query <- function(db, sql, params = list()) {
  conn <- connect_encrypted_db(db_path = db)
  on.exit(DBI::dbDisconnect(conn))
  if (length(params)) DBI::dbGetQuery(conn, sql, params = params) else DBI::dbGetQuery(conn, sql)
}

# --- Migration: data_entries gets dde_group_id/superseded_by, idempotently ---
local({
  db <- setup_db()
  on.exit(cleanup_db(db), add = TRUE)
  conn <- connect_encrypted_db(db_path = db)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  cols <- DBI::dbListFields(conn, "data_entries")
  expect_true("dde_group_id" %in% cols)
  expect_true("superseded_by" %in% cols)

  entry <- db_insert_data_entry(conn, "S001", "visit1", list(sbp = 120),
                                created_by = "coordinator1")
  expect_true(entry$success)

  # Running the migration again on a database that already has the
  # columns, and already has rows, is a no-op: no error, row intact.
  ensure_data_entries_table(conn)
  row <- DBI::dbGetQuery(conn, "SELECT * FROM data_entries WHERE entry_id = ?",
                         list(entry$entry_id))
  expect_equal(nrow(row), 1)
  expect_true(is.na(row$dde_group_id[1]), info = "ordinary entry has no dde_group_id")
  expect_true(is.na(row$superseded_by[1]))
})

# --- dde_group_id is stored and round-trips ---
local({
  db <- setup_db()
  on.exit(cleanup_db(db), add = TRUE)
  conn <- connect_encrypted_db(db_path = db)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  gid <- generate_dde_group_id()
  expect_true(grepl("^DDE-", gid))
  entry <- db_insert_data_entry(conn, "S001", "visit1", list(sbp = 120),
                                created_by = "coordinator1", dde_group_id = gid)
  expect_true(entry$success)
  stored <- query(db, "SELECT dde_group_id FROM data_entries WHERE entry_id = ?",
                  list(entry$entry_id))
  expect_identical(stored$dde_group_id[1], gid)
})

# --- flagged_dde_fields() ---
local({
  metadata <- list(
    sbp = list(require_double_entry = TRUE),
    dbp = list(require_double_entry = FALSE),
    hr  = list()
  )
  expect_identical(flagged_dde_fields(metadata), "sbp")
})

# --- dde_decide_role(): first entry, second entry, blocked same user ---
local({
  db <- setup_db()
  on.exit(cleanup_db(db), add = TRUE)
  conn <- connect_encrypted_db(db_path = db)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  d1 <- dde_decide_role(conn, "S001", "vitals", "coordinator1")
  expect_identical(d1$role, "first")
  expect_true(is.null(d1$first_entry_id))
  expect_false(d1$blocked_same_user)

  db_insert_data_entry(conn, "S001", "vitals", list(sbp = 120), created_by = "coordinator1",
                       dde_group_id = d1$group_id, is_complete = TRUE)

  d2_same <- dde_decide_role(conn, "S001", "vitals", "coordinator1")
  expect_identical(d2_same$role, "second")
  expect_true(d2_same$blocked_same_user,
             info = "same user attempting the second entry is flagged")

  d2_other <- dde_decide_role(conn, "S001", "vitals", "coordinator2")
  expect_identical(d2_other$role, "second")
  expect_false(d2_other$blocked_same_user)
  expect_identical(d2_other$group_id, d1$group_id)
})

# --- Blind probe: db_get_dde_first_entry() never depends on data_json,
# and is the ONLY thing dde_decide_role() calls. Proven by corrupting
# the first entry's data_json to unparseable garbage: the probe/role
# decision still succeeds (it never reads or needs data_json), while
# the values-fetch function (called only later, at the actual diff
# step) would fail on that same garbage. ---
local({
  db <- setup_db()
  on.exit(cleanup_db(db), add = TRUE)
  conn <- connect_encrypted_db(db_path = db)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  entry <- db_insert_data_entry(conn, "S001", "vitals", list(sbp = 120),
                                created_by = "coordinator1",
                                dde_group_id = generate_dde_group_id())
  DBI::dbExecute(conn, "UPDATE data_entries SET data_json = ? WHERE entry_id = ?",
                 list("{not valid json!!", entry$entry_id))

  probe <- db_get_dde_first_entry(conn, "S001", "vitals")
  expect_equal(nrow(probe), 1, info = "the probe succeeds without touching data_json")
  expect_identical(probe$entry_id[1], entry$entry_id)
  expect_identical(colnames(probe), c("entry_id", "created_by", "dde_group_id"),
                   info = "the probe's query never selects data_json at all")

  decision <- dde_decide_role(conn, "S001", "vitals", "coordinator2")
  expect_identical(decision$role, "second",
                   info = "role decision also never needed data_json")

  expect_error(jsonlite::fromJSON(db_get_dde_first_entry_values(conn, entry$entry_id)$x),
              info = "sanity: the corrupted data_json really is unparseable")
  expect_error(db_get_dde_first_entry_values(conn, entry$entry_id),
              info = "the values-fetch, called only at the actual diff step, does fail on it")
})

# --- dde_check_discrepancies(): only flagged fields are compared ---
local({
  db <- setup_db()
  on.exit(cleanup_db(db), add = TRUE)
  conn <- connect_encrypted_db(db_path = db)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  gid <- generate_dde_group_id()
  first <- db_insert_data_entry(
    conn, "S001", "vitals", list(sbp = 120, dbp = 80, note = "ok"),
    created_by = "coordinator1", dde_group_id = gid
  )

  chk <- dde_check_discrepancies(
    conn, first$entry_id,
    list(sbp = 120, dbp = 99, note = "different but unflagged"),
    flagged_fields = "sbp"
  )
  expect_equal(length(chk$discrepancies), 0,
              info = "sbp matches and is the only flagged field; dbp/note differ but are not checked")

  chk2 <- dde_check_discrepancies(
    conn, first$entry_id,
    list(sbp = 130, dbp = 99, note = "different but unflagged"),
    flagged_fields = "sbp"
  )
  expect_equal(length(chk2$discrepancies), 1)
  expect_true("sbp" %in% names(chk2$discrepancies))
  expect_identical(chk2$discrepancies$sbp$version_a_value, "120")
  expect_identical(chk2$discrepancies$sbp$version_b_value, "130")

  # Type normalization: 5 vs "5" must not falsely register as a mismatch.
  chk3 <- dde_check_discrepancies(conn, first$entry_id, list(sbp = "120"), "sbp")
  expect_equal(length(chk3$discrepancies), 0)
})

# --- apply_dde_resolutions(): three choices ---
local({
  discrepancies <- list(sbp = list(field = "sbp", version_a_value = "120",
                                   version_b_value = "130", change_type = "MODIFIED"))
  first_values <- list(sbp = 120)
  field_data <- list(sbp = 130, dbp = 80)

  keep <- apply_dde_resolutions(field_data, first_values, discrepancies,
                                resolutions = list(sbp = "keep_second"))
  expect_equal(keep$field_data$sbp, 130)
  expect_equal(length(keep$pending_fields), 0)
  expect_identical(keep$resolution_detail$sbp$choice, "keep_second")

  revert <- apply_dde_resolutions(field_data, first_values, discrepancies,
                                  resolutions = list(sbp = "revert_first"))
  expect_equal(revert$field_data$sbp, 120)
  expect_equal(length(revert$pending_fields), 0)

  flagged <- apply_dde_resolutions(field_data, first_values, discrepancies,
                                   resolutions = list(sbp = "flag_for_review"))
  expect_equal(flagged$field_data$sbp, 130, info = "left as keyed")
  expect_identical(flagged$pending_fields, "sbp")

  # No resolution supplied defaults to flag_for_review, not a silent keep/revert.
  default <- apply_dde_resolutions(field_data, first_values, discrepancies)
  expect_identical(default$pending_fields, "sbp")

  expect_error(apply_dde_resolutions(field_data, first_values, discrepancies,
                                     resolutions = list(sbp = "not_a_choice")))
})

# --- In-save resolution is recorded on the second entry's own audit record ---
local({
  db <- setup_db()
  on.exit(cleanup_db(db), add = TRUE)
  conn <- connect_encrypted_db(db_path = db)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  gid <- generate_dde_group_id()
  first <- db_insert_data_entry(conn, "S001", "vitals", list(sbp = 120),
                                created_by = "coordinator1", dde_group_id = gid)
  second <- db_insert_data_entry(
    conn, "S001", "vitals", list(sbp = 130), created_by = "coordinator2",
    dde_group_id = gid,
    audit_extra = list(dde_resolution = list(sbp = list(
      choice = "revert_first", first_value = 120, second_value = 130
    )))
  )
  expect_true(second$success)
  audit <- query(db, "SELECT details FROM audit_log WHERE record_id = ? AND event_type = 'INSERT'",
                list(second$entry_id))
  expect_equal(nrow(audit), 1)
  d <- jsonlite::fromJSON(audit$details[1])
  expect_identical(d$dde_resolution$sbp$choice, "revert_first")
  expect_equal(nrow(query(db, "SELECT * FROM correction_requests")), 0,
              info = "an in-save resolution writes no separate correction request")
})

# --- list_dde_discrepancies(), against a real flagged form ---
# Builds an actual designer_fields form (sbp flagged, dbp not) so
# .dde_flagged_fields_for_form() resolves for real, instead of the
# character(0) a form-less unit test would silently pass against.
setup_vitals_form <- function(db) {
  Sys.setenv(ZZEDC_DB_PATH = db)
  zzedc:::init_crf_version()
  init_crf_designer()
  conn <- connect_encrypted_db(db_path = db)
  on.exit(DBI::dbDisconnect(conn))
  crf <- create_crf_definition(crf_code = "VITALS", crf_name = "Vitals", created_by = "admin")
  zzedc:::ensure_designer_form_row(crf$crf_id, "VITALS", "Vitals", "admin")
  add_form_field(design_id = crf$crf_id, field_code = "sbp", field_label = "SBP",
                 field_type = "NUMBER", require_double_entry = TRUE)
  add_form_field(design_id = crf$crf_id, field_code = "dbp", field_label = "DBP",
                 field_type = "NUMBER", require_double_entry = FALSE)
  crf$crf_id
}

local({
  db <- setup_db()
  on.exit(cleanup_db(db), add = TRUE)
  setup_vitals_form(db)
  conn <- connect_encrypted_db(db_path = db)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  # "flag_for_review": sbp (flagged) differs and stays open; dbp
  # (not flagged) differs too but is never checked at all.
  gid <- generate_dde_group_id()
  first <- db_insert_data_entry(conn, "S001", "vitals", list(sbp = 120, dbp = 80),
                                created_by = "alice", dde_group_id = gid)
  second <- db_insert_data_entry(conn, "S001", "vitals", list(sbp = 130, dbp = 99),
                                 created_by = "bob", dde_group_id = gid,
                                 audit_extra = list(dde_pending_review_fields = "sbp"))
  expect_true(first$success && second$success)

  open_items <- list_dde_discrepancies(conn, dde_group_id = gid)
  expect_equal(nrow(open_items), 1, info = "only the flagged, unresolved field shows up")
  expect_identical(open_items$field_code[1], "sbp")
  expect_identical(open_items$first_value[1], "120")
  expect_identical(open_items$second_value[1], "130")

  # Reviewer-separation guard, independent of the queue's own
  # form-resolution: neither alice nor bob may act as reviewer.
  expect_false(is.null(require_dde_reviewer_separation(conn, gid, "alice")))
  expect_false(is.null(require_dde_reviewer_separation(conn, gid, "bob")))
  expect_true(is.null(require_dde_reviewer_separation(conn, gid, "carol")),
             info = "a third user, neither entry's author, may review")

  # Not yet resolved -- close_dde_group_if_resolved() must not
  # supersede a group with a real open discrepancy.
  expect_false(close_dde_group_if_resolved(conn, gid))
  row2 <- query(db, "SELECT superseded_by FROM data_entries WHERE entry_id = ?", list(second$entry_id))
  expect_true(is.na(row2$superseded_by[1]))
})

# --- "keep_second"/"revert_first" actually resolve the field, not just
# record a choice: update_first_entry_for_dde_resolution() brings the
# canonical (first) entry's value into agreement, so the live diff
# list_dde_discrepancies() reads goes to zero and the field never
# shows up in the queue. ---
local({
  db <- setup_db()
  on.exit(cleanup_db(db), add = TRUE)
  setup_vitals_form(db)
  conn <- connect_encrypted_db(db_path = db)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  gid <- generate_dde_group_id()
  first <- db_insert_data_entry(conn, "S001", "vitals", list(sbp = 120),
                                created_by = "alice", dde_group_id = gid)
  chk <- dde_check_discrepancies(conn, first$entry_id, list(sbp = 130), "sbp")
  applied <- apply_dde_resolutions(list(sbp = 130), chk$first_values, chk$discrepancies,
                                   resolutions = list(sbp = "keep_second"))
  updated <- update_first_entry_for_dde_resolution(conn, first$entry_id,
                                                   applied$resolution_detail, "bob")
  expect_true(updated)
  first_row <- query(db, "SELECT data_json FROM data_entries WHERE entry_id = ?", list(first$entry_id))
  expect_equal(jsonlite::fromJSON(first_row$data_json[1])$sbp, 130,
              info = "the canonical entry now reflects the kept (second-entry) value")

  second <- db_insert_data_entry(conn, "S001", "vitals", applied$field_data,
                                 created_by = "bob", dde_group_id = gid,
                                 audit_extra = list(dde_resolution = applied$resolution_detail))
  expect_equal(nrow(list_dde_discrepancies(conn, dde_group_id = gid)), 0,
              info = "a 'keep_second' field is fully resolved, not stuck in the queue forever")

  audit_row <- query(db, "SELECT details FROM audit_log
                          WHERE record_id = ? AND event_type = 'UPDATE'
                            AND operation LIKE 'Double-data-entry%'", list(first$entry_id))
  expect_equal(nrow(audit_row), 1, info = "the in-save resolution to the first entry is itself audited")

  # A pair fully resolved at save time (no "flag_for_review" field
  # left) is superseded right away, not only after a queued
  # DDE_DISCREPANCY correction is applied (which never happens for a
  # pair with nothing left to queue).
  expect_true(close_dde_group_if_resolved(conn, gid))
  superseded_row <- query(db, "SELECT superseded_by FROM data_entries WHERE entry_id = ?",
                          list(second$entry_id))
  expect_identical(superseded_row$superseded_by[1], first$entry_id)

  # "revert_first" on a fresh pair: the canonical value is unchanged
  # (it already held the kept value), but the second entry's own
  # stored value is overwritten to match -- also zero live diff.
  gid2 <- generate_dde_group_id()
  first2 <- db_insert_data_entry(conn, "S002", "vitals", list(sbp = 115),
                                 created_by = "alice", dde_group_id = gid2)
  chk2 <- dde_check_discrepancies(conn, first2$entry_id, list(sbp = 140), "sbp")
  applied2 <- apply_dde_resolutions(list(sbp = 140), chk2$first_values, chk2$discrepancies,
                                    resolutions = list(sbp = "revert_first"))
  expect_equal(applied2$field_data$sbp, 115, info = "revert_first already overwrites the second entry's own value")

  # Explicitly exercises update_first_entry_for_dde_resolution() with a
  # "revert_first" resolution: it must leave entry #1 completely
  # untouched (not overwrite it with the rejected 140, which an
  # earlier, buggy version of this function did by always writing
  # resolution_detail's recorded second_value regardless of choice).
  updated2 <- update_first_entry_for_dde_resolution(conn, first2$entry_id,
                                                     applied2$resolution_detail, "bob")
  expect_false(updated2, info = "revert_first needs no change to the already-correct first entry")
  first2_row <- query(db, "SELECT data_json FROM data_entries WHERE entry_id = ?", list(first2$entry_id))
  expect_equal(jsonlite::fromJSON(first2_row$data_json[1])$sbp, 115,
              info = "entry #1 still holds its own original value, not the rejected 140")

  second2 <- db_insert_data_entry(conn, "S002", "vitals", applied2$field_data,
                                  created_by = "bob", dde_group_id = gid2,
                                  audit_extra = list(dde_resolution = applied2$resolution_detail))
  expect_equal(nrow(list_dde_discrepancies(conn, dde_group_id = gid2)), 0)
})

# --- Regression test, found on review (2026-11-20): the second entry
# used to be held unsaved (in a reactiveVal) until the resolution
# modal was confirmed, so dismissing the modal (e.g. a browser
# reload) lost it entirely with no audit trace of entry #1's value
# having been shown on screen, and -- since nothing had been saved --
# a reload-then-resubmit with a matching value was never caught by
# dde_decide_role()'s already_paired guard, defeating the blind-entry
# design. The fix: save the second entry immediately, every
# discrepant field defaulted to "flag_for_review" via
# apply_dde_resolutions() with no resolutions, *before* the modal is
# shown; update_second_entry_for_dde_resolution() then only upgrades
# that already-saved row if the enterer actually picks a different
# resolution. ---
local({
  db <- setup_db()
  on.exit(cleanup_db(db), add = TRUE)
  setup_vitals_form(db)
  conn <- connect_encrypted_db(db_path = db)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  gid <- generate_dde_group_id()
  first <- db_insert_data_entry(conn, "S001", "vitals", list(sbp = 100),
                                created_by = "alice", dde_group_id = gid)
  chk <- dde_check_discrepancies(conn, first$entry_id, list(sbp = 222), "sbp")
  expect_equal(length(chk$discrepancies), 1,
              info = "the mismatch is detected before anything is saved")

  # Save immediately with the safe default (no resolutions supplied):
  # this is what the submitcrf handler does before ever showing the
  # modal.
  defaulted <- apply_dde_resolutions(list(sbp = 222), chk$first_values, chk$discrepancies,
                                     resolutions = list())
  expect_equal(defaulted$pending_fields, "sbp",
              info = "with no resolution chosen yet, the field defaults to flag_for_review")
  second <- db_insert_data_entry(conn, "S001", "vitals", defaulted$field_data,
                                 created_by = "bob", dde_group_id = gid,
                                 audit_extra = list(dde_resolution = defaulted$resolution_detail,
                                                    dde_pending_review_fields = defaulted$pending_fields))
  expect_true(second$success)

  # "Reload" scenario: the modal is never confirmed. Nothing is lost
  # -- the field is simply open in the reconciliation queue, exactly
  # like any other real, unresolved discrepancy.
  open <- list_dde_discrepancies(conn, dde_group_id = gid)
  expect_equal(nrow(open), 1)
  expect_equal(open$field_code[1], "sbp")
  second_row <- query(db, "SELECT data_json FROM data_entries WHERE entry_id = ?",
                      list(second$entry_id))
  expect_equal(jsonlite::fromJSON(second_row$data_json[1])$sbp, 222,
              info = "the second entry's own keyed value was saved, not discarded")

  # The blinding bypass this closes: a resubmission for this
  # subject/form (by anyone, including the same second enterer) is
  # now refused as a third submission, not silently treated as a
  # fresh "second entry" that could be re-keyed to match entry #1
  # after having already seen its value.
  resubmit <- dde_decide_role(conn, "S001", "vitals", "bob")
  expect_true(resubmit$already_paired,
             info = "a reload-then-resubmit no longer bypasses blinding -- entry #2 already exists")

  # Now the enterer actually opens the modal and resolves it:
  # update_second_entry_for_dde_resolution() upgrades the already-saved
  # row -- it never inserts a second time.
  applied <- apply_dde_resolutions(list(sbp = 222), chk$first_values, chk$discrepancies,
                                   resolutions = list(sbp = "revert_first"))
  changed <- update_second_entry_for_dde_resolution(conn, second$entry_id, applied,
                                                    modified_by = "bob")
  expect_true(changed, info = "revert_first changes the second entry's own saved value")
  second_row2 <- query(db, "SELECT data_json FROM data_entries WHERE entry_id = ?",
                       list(second$entry_id))
  expect_equal(jsonlite::fromJSON(second_row2$data_json[1])$sbp, 100,
              info = "the second entry now agrees with entry #1 after revert_first")
  expect_equal(nrow(list_dde_discrepancies(conn, dde_group_id = gid)), 0,
              info = "resolving the field clears it from the reconciliation queue")

  audit_row <- query(db, "SELECT details FROM audit_log
                          WHERE record_id = ? AND event_type = 'UPDATE'
                            AND operation LIKE 'Double-data-entry%'", list(second$entry_id))
  expect_equal(nrow(audit_row), 1,
              info = "the resolution upgrade on the second entry is itself audited")

  # update_second_entry_for_dde_resolution() is a no-op when the
  # resolved value already matches what was saved (e.g. "keep_second",
  # which never differs from the second entry's own already-saved
  # default).
  gid2 <- generate_dde_group_id()
  first3 <- db_insert_data_entry(conn, "S003", "vitals", list(sbp = 90),
                                 created_by = "alice", dde_group_id = gid2)
  chk3 <- dde_check_discrepancies(conn, first3$entry_id, list(sbp = 95), "sbp")
  defaulted3 <- apply_dde_resolutions(list(sbp = 95), chk3$first_values, chk3$discrepancies,
                                      resolutions = list())
  second3 <- db_insert_data_entry(conn, "S003", "vitals", defaulted3$field_data,
                                  created_by = "bob", dde_group_id = gid2,
                                  audit_extra = list(dde_resolution = defaulted3$resolution_detail))
  applied3 <- apply_dde_resolutions(list(sbp = 95), chk3$first_values, chk3$discrepancies,
                                    resolutions = list(sbp = "keep_second"))
  changed3 <- update_second_entry_for_dde_resolution(conn, second3$entry_id, applied3,
                                                     modified_by = "bob")
  expect_false(changed3,
              info = "keep_second never differs from what was already saved as the default")
})

# --- A third submission for an already-fully-paired subject/form is refused ---
local({
  db <- setup_db()
  on.exit(cleanup_db(db), add = TRUE)
  conn <- connect_encrypted_db(db_path = db)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  gid <- generate_dde_group_id()
  db_insert_data_entry(conn, "S001", "vitals", list(sbp = 120), created_by = "alice", dde_group_id = gid)
  db_insert_data_entry(conn, "S001", "vitals", list(sbp = 130), created_by = "bob", dde_group_id = gid)

  decision3 <- dde_decide_role(conn, "S001", "vitals", "carol")
  expect_true(decision3$already_paired,
             info = "a third submission against a complete pair is refused, not silently accepted")
})

# --- approve_correction()/apply_correction() enforce reviewer separation
# themselves (fail closed), not only through the Corrections module's UI ---
local({
  db <- setup_db()
  on.exit(cleanup_db(db), add = TRUE)
  conn <- connect_encrypted_db(db_path = db)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  gid <- generate_dde_group_id()
  first <- db_insert_data_entry(conn, "S001", "vitals", list(sbp = 120),
                                created_by = "alice", dde_group_id = gid)
  db_insert_data_entry(conn, "S001", "vitals", list(sbp = 130),
                       created_by = "bob", dde_group_id = gid)
  DBI::dbDisconnect(conn)

  req <- create_correction_request(
    "data_entries", first$entry_id, "sbp", "120", "130", "DDE_DISCREPANCY",
    requested_by = "carol", db_path = db
  )
  expect_true(req$success, info = req$error %||% "")

  denied_alice <- approve_correction(req$request_id, reviewed_by = "alice", db_path = db)
  expect_false(denied_alice$success, info = "alice made one of the two entries")
  denied_bob <- approve_correction(req$request_id, reviewed_by = "bob", db_path = db)
  expect_false(denied_bob$success, info = "bob made one of the two entries")

  ok <- approve_correction(req$request_id, reviewed_by = "dave", db_path = db)
  expect_true(ok$success, info = ok$error %||% "")

  denied_apply_alice <- apply_correction(req$request_id, applied_by = "alice", db_path = db)
  expect_false(denied_apply_alice$success)
  denied_apply_bob <- apply_correction(req$request_id, applied_by = "bob", db_path = db)
  expect_false(denied_apply_bob$success)

  applied_ok <- apply_correction(req$request_id, applied_by = "dave", db_path = db)
  expect_true(applied_ok$success, info = applied_ok$error %||% "")

  # An ordinary (non-DDE) correction's existing self-approval rule is
  # unaffected by any of this -- carol (the requester here) still just
  # can't approve her own ordinary request, same as always.
  conn2 <- connect_encrypted_db(db_path = db)
  db_insert_data_entry(conn2, "S999", "vitals", list(sbp = 100), created_by = "carol")
  DBI::dbDisconnect(conn2)
  ordinary <- create_correction_request(
    "data_entries", "S999", "sbp", "100", "105", "TYPO",
    requested_by = "carol", db_path = db
  )
  self_denied <- approve_correction(ordinary$request_id, reviewed_by = "carol", db_path = db)
  expect_false(self_denied$success, info = "the pre-existing self-approval rule still applies")
  other_ok <- approve_correction(ordinary$request_id, reviewed_by = "alice", db_path = db)
  expect_true(other_ok$success,
             info = "an ordinary correction is unaffected by the DDE-specific guard")
})

# --- diff_field_lists() is the one engine compare_versions() also uses ---
local({
  diffs <- diff_field_lists(list(a = 1, b = 2), list(a = 1, b = 3, c = 4))
  expect_identical(names(diffs), c("b", "c"))
  expect_identical(diffs$b$change_type, "MODIFIED")
  expect_identical(diffs$c$change_type, "ADDED")

  restricted <- diff_field_lists(list(a = 1, b = 2), list(a = 9, b = 3), fields = "b")
  expect_identical(names(restricted), "b", info = "fields= restricts the comparison")
})
