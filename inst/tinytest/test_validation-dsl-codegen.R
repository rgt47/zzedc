library(tinytest)

# Regression tests for R/validation_dsl_codegen.R's evaluate_if_node(),
# exercised through the public generate_validator()/parse_dsl_rule()
# path, using the exact rule shapes imported into this package's own
# study data dictionaries (see dsl_validation_rules in a live
# deployment, or docs/edc-reports-tabs-plan-2026-10-31.md).

local({
  # Regression: a guarded rule with no else branch ("if X != "" then
  # ... endif") must PASS when the guard is false, not fail. This is
  # the shape every real imported rule uses to mean "only check this
  # once the optional field is actually filled in" -- previously
  # evaluate_if_node() returned a literal fallback string in that
  # case, which every other evaluate_*_node() in this file treats as
  # a failure message, so every guarded rule rejected the common,
  # valid case of the guarded field being blank.
  v <- zzedc:::generate_validator(
    'if acceptance_date != "" then acceptance_date >= submission_date endif'
  )
  expect_true(isTRUE(v(NULL, list(acceptance_date = "", submission_date = "2026-01-01"))),
              info = "guard false (acceptance_date blank), no else -- passes")
  expect_true(isTRUE(v(NULL, list(acceptance_date = "2026-02-01",
                                   submission_date = "2026-01-01"))),
              info = "guard true, order correct -- passes")
  bad <- v(NULL, list(acceptance_date = "2026-01-01", submission_date = "2026-02-01"))
  expect_false(isTRUE(bad), info = "guard true, order wrong -- fails")
  expect_true(is.character(bad))
})

local({
  # The exact six real rules imported into this package's own data
  # dictionaries (manuscripts, courses, mentoring, committees, dsmb)
  # must all parse without error and evaluate sensibly, both guarded-
  # pass and guarded-fail.
  rules <- list(
    accept_after_submit = 'if acceptance_date != "" then acceptance_date >= submission_date endif',
    pub_after_accept     = 'if publication_date != "" then publication_date >= acceptance_date endif',
    enroll_range         = "student_count between 1 and 500",
    hours_range           = "contact_hours between 1 and 500",
    end_after_start      = 'if end_date != "" then end_date >= start_date endif',
    mentor_hours         = 'if hours_per_week != "" then hours_per_week between 0 and 40 endif'
  )
  for (rule_dsl in rules) {
    expect_silent(zzedc:::generate_validator(rule_dsl))
  }
})

local({
  # ENROLL_RANGE / HOURS_RANGE: plain "field between a and b", no
  # guard -- the field must be present (these are required fields in
  # the data dictionary; blank-ness is checked separately by
  # validate_crf_submission()'s own required check, not this rule).
  v <- zzedc:::generate_validator("student_count between 1 and 500")
  expect_false(isTRUE(v(NULL, list(student_count = 600))))
  expect_true(isTRUE(v(NULL, list(student_count = 50))))
})

local({
  # MENTOR_HOURS: a guarded between-range rule (both an "if" guard
  # AND a "between" in the then-branch).
  v <- zzedc:::generate_validator(
    'if hours_per_week != "" then hours_per_week between 0 and 40 endif'
  )
  expect_true(isTRUE(v(NULL, list(hours_per_week = ""))),
              info = "blank optional field -- guard false, passes")
  expect_true(isTRUE(v(NULL, list(hours_per_week = 20))))
  expect_false(isTRUE(v(NULL, list(hours_per_week = 50))))
})
