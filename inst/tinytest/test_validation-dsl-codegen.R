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

local({
  # Character inputs (as Shiny delivers them) compare numerically.
  # Previously '72' failed 'between 30 and 200' ('72' > '200' as
  # strings) and '1000' passed 'between 1 and 500'.
  v <- zzedc:::generate_validator("baseline_wt between 30 and 200")
  expect_true(isTRUE(v(NULL, list(baseline_wt = "72"))), info = "'72' in range")
  expect_false(isTRUE(v(NULL, list(baseline_wt = "1000"))),
               info = "'1000' out of range")
  expect_false(isTRUE(v(NULL, list(baseline_wt = "9"))), info = "'9' below range")
  expect_true(isTRUE(v(NULL, list(baseline_wt = "30"))), info = "inclusive lower")
  expect_true(isTRUE(v(NULL, list(baseline_wt = "200.0"))),
              info = "inclusive upper, decimal")
  expect_true(is.character(v(NULL, list(baseline_wt = "heavy"))),
              info = "non-numeric text against numeric bounds fails")

  cmp <- zzedc:::generate_validator("count >= 10")
  expect_true(isTRUE(cmp(NULL, list(count = "60"))), info = "'60' >= 10")
  expect_false(isTRUE(cmp(NULL, list(count = "9"))), info = "'9' < 10")
})

local({
  # Field-less rules apply to the field_name target.
  v <- zzedc:::generate_validator("between 18 and 65", "age")
  expect_true(isTRUE(v(NULL, list(age = "30"))), info = "age 30 passes")
  expect_false(isTRUE(v(NULL, list(age = "70"))), info = "age 70 fails")
  expect_true(isTRUE(v(30, list())), info = "explicit value still works")

  len <- zzedc:::generate_validator("length == 7", "subject_id")
  expect_true(isTRUE(len(NULL, list(subject_id = "ADHD001"))))
  expect_false(isTRUE(len(NULL, list(subject_id = "ADHD01"))))

  req <- zzedc:::generate_validator(
    "if gender == 'Female' then required endif", "pregnancy"
  )
  expect_true(isTRUE(req(NULL, list(gender = "Female", pregnancy = "No"))),
              info = "conditional required passes when filled")
  expect_false(isTRUE(req(NULL, list(gender = "Female", pregnancy = ""))),
               info = "conditional required fails when blank")
  expect_true(isTRUE(req(NULL, list(gender = "Male", pregnancy = ""))),
              info = "guard false: not required")
})

local({
  # Missing operands: unknown, which passes (SQL CHECK semantics);
  # never a comparison of a field with itself.
  v <- zzedc:::generate_validator("dob < consent_date", "dob")
  expect_true(isTRUE(v(NULL, list(dob = "1950-01-01",
                                  consent_date = "2026-01-01"))))
  expect_false(isTRUE(v(NULL, list(dob = "2027-01-01",
                                   consent_date = "2026-01-01"))))
  expect_true(isTRUE(v(NULL, list(dob = "1950-01-01"))),
              info = "missing consent_date is unknown, not a failure")

  gt <- zzedc:::generate_validator("x > other", "x")
  expect_true(isTRUE(gt(NULL, list(x = "5"))),
              info = "missing field does not fall back to the target value")

  # Dates compare as dates, including against today.
  fut <- zzedc:::generate_validator("visit_date <= today", "visit_date")
  expect_true(isTRUE(fut(NULL, list(visit_date = "2020-01-01"))))
  expect_false(isTRUE(fut(NULL, list(
    visit_date = format(Sys.Date() + 30, "%Y-%m-%d")))))
})

local({
  # Three-valued AND/OR, and bare fields as conditions.
  and_v <- zzedc:::generate_validator("a > 1 and b > 1")
  expect_true(isTRUE(and_v(NULL, list(a = "2"))), info = "TRUE and unknown")
  expect_false(isTRUE(and_v(NULL, list(a = "0"))), info = "FALSE and unknown")

  or_v <- zzedc:::generate_validator("a > 1 or b > 1")
  expect_true(isTRUE(or_v(NULL, list(a = "0", b = "2"))))
  expect_false(isTRUE(or_v(NULL, list(a = "0", b = "0"))))

  cond <- zzedc:::generate_validator("if consent then required endif", "sig")
  expect_true(isTRUE(cond(NULL, list(consent = "No", sig = ""))),
              info = "bare field condition reads the named field")
  expect_false(isTRUE(cond(NULL, list(consent = "Yes", sig = ""))))

  inv <- zzedc:::generate_validator("arm in (1, 2)", "arm")
  expect_true(isTRUE(inv(NULL, list(arm = "2"))), info = "'2' in (1, 2)")
  expect_false(isTRUE(inv(NULL, list(arm = "3"))))

  expect_error(zzedc:::generate_validator("bogus(x) > 1")(NULL, list(x = 1)),
               pattern = "Unknown function",
               info = "unknown functions raise instead of returning data")
})
