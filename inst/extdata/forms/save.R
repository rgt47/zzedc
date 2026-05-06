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
#   2. Insert / update the corresponding row in the study database
#      via `pool::dbExecute()` against the `db_pool` reactive.
#   3. Append an audit-trail entry via `log_audit_action()` from
#      `R/audit_log_viewer_module.R`.
#   4. Optionally trigger downstream notifications (data review,
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
