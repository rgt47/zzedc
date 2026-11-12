# forms/save.R
#
# Demonstration save handler for the EDC tab. Sourced inline by
# `inst/app/edc.R` via `source('forms/save.R', local=TRUE)`.
# Defines a `saveData()` function that the EDC tab's
# `submitvislog` observer calls with the submitted form data.
#
# Replace with your study's actual persistence logic. In a real
# study, `saveData()` would:
#   1. Validate the submitted form data against the field metadata.
#   2. Save the entry with `zzedc:::save_crf_entry()` or
#      `zzedc:::db_insert_data_entry()` against `db_pool`. These write
#      the row and its audit-trail record in one transaction, so an
#      entry cannot be saved without its audit record
#      (21 CFR 11.10(e)). Do not write study data with a bare
#      `pool::dbExecute()`: nothing would audit it.
#   3. Optionally trigger downstream notifications (data review,
#      monitoring queries, etc.).

saveData <- function(form_data) {
  shiny::showNotification(
    sprintf(
      paste0("Demonstration form captured (%d field(s)). Replace ",
             "forms/save.R with your study's persistence logic."),
      length(form_data %||% list())
    ),
    type = "message", duration = 5
  )
  message("[zzedc demo] saveData called: ",
          paste(names(form_data %||% list()), collapse = ", "))
  invisible(NULL)
}

# Returned value (unused; the `source(...)[[1]]` idiom requires
# this file to evaluate to something).
saveData
