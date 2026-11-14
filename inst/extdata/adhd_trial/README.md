# ADHD Trial Example Study
*2026-11-11 12:18 PST*

A complete example study for ZZedc: a fictional, single-site,
placebo-controlled ADHD medication trial. The people, email
addresses, and passwords are invented. Use it to try ZZedc, to see
what a finished study definition looks like, or as a starting point
for your own study.

## Contents

The study is defined by three tables, the same ones a Google Sheets
workbook would hold as tabs:

- **`Study_Users.csv`**: four demonstration accounts (a PI, two
  administrators, one of them inactive, and a coordinator). Every
  account's initial password is `ChangeMe-Demo-2026`, and each must
  be changed at first login.
- **`Data_Dictionary.csv`**: nine forms and 128 fields: screening
  and enrollment, demographics, medical history, the ADHD Rating
  Scale (the example primary endpoint), vital signs, side effects,
  medication compliance, adverse events, and study completion.
  Choice fields list their options as `in(...)`. Treatment arm is
  not a CRF field: it is assigned by `randomize_next_subject()`
  (R/randomization_module.R) once a subject is confirmed eligible,
  not entered by hand.
- **`validation_rules.csv`**: 56 rules, such as ranges
  (`between 18 and 65`), lengths (`length == 7`), dates
  (`screening_date <= today`), and conditional requirements
  (`if gender == "Female" then required endif`).

## Loading it

From local CSV files, into a new encrypted DuckDB study:

```r
library(zzedc)
dir.create("adhd_study/data", recursive = TRUE)
key <- generate_db_key()   # save it: it is needed to open the study
cfg <- list(db_backend = "duckdb",
            duckdb = list(path = "adhd_study/data/study.duckdb",
                          encryption_key = key))
result <- setup_zzedc_from_csv(
  system.file("extdata", "adhd_trial", package = "zzedc"),
  adapter_config = cfg
)
result$forms$imported_forms   # 9
```

For a SQLite study, pass `db_path = "adhd_study/data/study.db"`
instead of `adapter_config`.

From Google Sheets: create a workbook with three tabs named
`Study_Users`, `Data_Dictionary`, and `validation_rules`, paste each
CSV into its tab, and call `setup_zzedc_from_gsheets()` with the
workbook's ID. Inside a running study, the Google Sheets card in the
application imports the same workbook into the existing database.

## Adapting it to your study

Replace the ADHD Rating Scale rows in `Data_Dictionary.csv` with your
study's primary endpoint, edit the other forms as needed, and replace
the demonstration accounts in `Study_Users.csv`. The columns are
documented in `?setup_zzedc_from_gsheets`.

## Differences from the earlier version of this example

Until 2026-11-11 this example used an older format (one CSV per form,
with validation written as R expressions) that only a since-removed
setup script could read. It was converted to the three-table format
above. Two things did not carry over: a form for the Conners Adult
ADHD Rating Scale was listed but never defined, and the condition on
`pregnancy_status` (shown only when `gender` is Female) refers to a
field on another form, which validation rules cannot reference. The
visit schedule (which forms are completed at which visits) is not part
of the three-table format.
