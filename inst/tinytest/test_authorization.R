library(tinytest)

# Helpers (auto-loaded by testthat under the previous layout).
# tinytest auto-sources files prefixed with `_` (so `_setup.R`)
# when invoked via `tinytest::test_package()`. The explicit
# source() below keeps the test runnable when invoked directly
# (e.g., `tinytest::run_test_file("test_foo.R")`).
if (file.exists("_setup.R")) source("_setup.R")

# §11.10(g) authority checks, added 2026-11-09. require_role() is the
# shared gate now wired into approve_correction()/reject_correction()
# (data_correction.R), invalidate_signature() (electronic_signatures.R),
# lock_form_design() (crf_designer.R), and save_user_to_db()
# (user_management_module.R) -- none of which had any server-side role
# check before this.

local({
  denied <- zzedc:::require_role("Coordinator", c("Admin", "PI", "StudyManager"),
                                  "approve a data correction")
  expect_false(is.null(denied))
  expect_false(denied$success)
  expect_true(grepl("Coordinator", denied$error))
  expect_true(grepl("approve a data correction", denied$error))
})

local({
  allowed <- zzedc:::require_role("Admin", c("Admin", "PI", "StudyManager"),
                                   "approve a data correction")
  expect_null(allowed)
})

local({
  # Case- and space/underscore-insensitive matching: "Data Manager"
  # (the display string) must match an allow-list entry written the
  # same way, and the check is case-insensitive.
  expect_null(zzedc:::require_role("data manager", c("Admin", "Data Manager"), "x"))
  expect_null(zzedc:::require_role("ADMIN", c("Admin", "PI"), "x"))
  expect_false(is.null(zzedc:::require_role("Monitor", c("Admin", "PI"), "x")))
})

local({
  # NULL/unknown actor_role is denied, not silently allowed.
  denied <- zzedc:::require_role(NULL, c("Admin"), "x")
  expect_false(is.null(denied))
  expect_true(grepl("\\(none\\)", denied$error))
})

# Regression test: .assignable_roles("Data Manager") previously
# returned only "Monitor" (tier-3 fallback) because .ROLE_TIER's
# names use an underscore ("data_manager") while the display string
# has a space ("Data Manager"), and the old lookup only lowercased
# without replacing spaces. .normalize_role_name() fixes both this
# and require_role() the same way.
local({
  dm <- zzedc:::.assignable_roles("Data Manager")
  sm <- zzedc:::.assignable_roles("StudyManager")
  expect_equal(sort(dm), sort(sm),
               info = "Data Manager and StudyManager are both tier 2 and should assign the same set")
  expect_true("Coordinator" %in% dm)
  expect_true("Monitor" %in% dm)
})

local({
  expect_equal(zzedc:::.normalize_role_name("Data Manager"), "data_manager")
  expect_equal(zzedc:::.normalize_role_name("StudyManager"), "studymanager")
  expect_equal(zzedc:::.normalize_role_name(NULL), "")
  expect_equal(zzedc:::.normalize_role_name("  Admin  "), "admin")
})
