library(tinytest)

# Regression tests for inst/scripts/edc-init.R's CSV template
# generation (data_dictionary_template(), validation_rules_template(),
# write_csv_files()), added so a brand-new study run through
# `edc-init.R --mode config` (or the TUI) without --dd-csv/--rules-csv
# gets an importable starting point for Data_Dictionary.csv and
# validation_rules.csv instead of just an instruction to create them
# by hand. edc-init.R is a standalone Rscript, not part of the
# package's R/ functions, so its definitions are sourced directly
# (skipping its trailing main() call) rather than loaded via library().

local({
  script_path <- system.file("scripts", "edc-init.R", package = "zzedc")
  if (!nzchar(script_path)) {
    # Running against the source tree (devtools::load_all()), not an
    # installed copy.
    script_path <- file.path(
      Sys.getenv("ZZEDC_SOURCE_DIR", "../../inst/scripts"), "edc-init.R"
    )
  }
  expect_true(file.exists(script_path),
              info = "inst/scripts/edc-init.R is present to source its definitions from")

  lines <- readLines(script_path, warn = FALSE)
  main_line <- which(lines == "main()")
  lines <- if (length(main_line) == 1) lines[seq_len(main_line - 1)] else lines
  env <- new.env()
  suppressWarnings(suppressMessages(
    eval(parse(text = lines), envir = env)
  ))

  dd <- env$data_dictionary_template()
  expect_true(all(c("form_code", "field_name", "field_label",
                     "field_type", "required") %in% names(dd)),
              info = "template has every documented required Data_Dictionary column")
  expect_equal(nrow(dd), 1, info = "template is a single editable example row")

  vr <- env$validation_rules_template()
  expect_true(all(c("rule_id", "field_code", "rule_dsl") %in% names(vr)),
              info = "template has every documented required validation_rules column")
  expect_equal(nrow(vr), 1, info = "template is a single editable example row")

  # write_csv_files(): generates both templates when neither source is
  # supplied, never overwrites a file already there, and always
  # writes Study_Users.csv regardless.
  out_dir <- tempfile("edc_init_csv_test_")
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

  users_df <- data.frame(
    username = "pi1", full_name = "Test PI", email = "pi1@example.edu",
    role = "Admin", password_initial = "Abc12345!", site_id = "ALL",
    active = "TRUE", stringsAsFactors = FALSE
  )

  env$write_csv_files(users_df, out_dir)

  dd_path <- file.path(out_dir, "Data_Dictionary.csv")
  rules_path <- file.path(out_dir, "validation_rules.csv")
  expect_true(file.exists(dd_path), info = "Data_Dictionary.csv template is written")
  expect_true(file.exists(rules_path), info = "validation_rules.csv template is written")
  expect_true(file.exists(file.path(out_dir, "Study_Users.csv")))

  edited <- c("form_code,field_name,field_label,field_type,required",
              "screening,edited_field,Edited,text,TRUE")
  writeLines(edited, dd_path)
  env$write_csv_files(users_df, out_dir)
  expect_equal(readLines(dd_path), edited,
               info = "an existing Data_Dictionary.csv is never overwritten by a re-run")
})
