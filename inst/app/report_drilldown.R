# Report drill-through: a summary count anywhere in Activity Summary
# (report1.R), Domain Breakdown (report3.R), or the Personal
# Statement draft (R/edc_reports.R's generate_personal_statement_draft())
# is a link/button that opens a modal listing the matching
# data_entries rows for that form (optionally narrowed to one
# field=value pair). Each row in that modal has a "Review" button
# that hands off to the Corrections tab's Create Request view --
# reusing the same pending_entry_id hand-off inst/app/edc.R's
# "Request Correction" button already uses (rv_pending_correction_entry,
# created above in initialize_traditional_server() before this file
# is sourced). There is no direct in-place editor for a submitted
# entry: R/data_correction.R is written to FDA 21 CFR Part 11
# (§11.10(g)), and every change to a submitted value goes through
# create_correction_request()/approve_correction()/apply_correction(),
# never a raw edit. "Review" therefore always starts a correction
# request on that entry, which is the closest thing this application
# has to an "edit" action on already-submitted data.

# Rows matching a form (and optionally one field's stored value),
# for the modal below. Reuses get_data_entries() rather than a new
# query -- the same helper every other report in this file already
# reads from.
.report_drill_entries <- function(form_name, filter_field = NULL, filter_value = NULL) {
  rows <- zzedc:::get_data_entries(db_pool, crf_code = form_name)
  if (!is.null(filter_field) && nzchar(filter_field %||% "") && nrow(rows) > 0) {
    keep <- vapply(rows$fields, function(f) {
      v <- f[[filter_field]]
      if (is.null(v) || length(v) == 0) return(FALSE)
      identical(as.character(v), as.character(filter_value))
    }, logical(1))
    rows <- rows[keep, , drop = FALSE]
  }
  rows
}

# Holds the modal's current rows, read reactively by
# report_drill_table below -- a DT::datatable() object only
# initializes its JS correctly when rendered through the normal
# renderDT()/DTOutput() output-binding path (the same pattern every
# other table in this app uses); a DT widget built once and placed
# directly as a showModal()/modalDialog() body never gets DataTables
# initialized (confirmed live: the modal's title and row count render,
# the table body does not).
.report_drill_rows <- shiny::reactiveVal(NULL)

output$report_drill_table <- DT::renderDT({
  rows <- .report_drill_rows()
  shiny::req(!is.null(rows))
  if (nrow(rows) == 0) {
    return(DT::datatable(data.frame(Message = "No entries match."),
                          rownames = FALSE, options = list(dom = "t")))
  }
  display <- data.frame(
    Subject = rows$subject_id,
    Visit = rows$visit_label,
    Created = rows$created_date,
    By = rows$created_by,
    stringsAsFactors = FALSE
  )
  display$Review <- vapply(rows$entry_id, function(eid) {
    paste0(
      '<button class="btn btn-outline-secondary btn-sm" ',
      'onclick="Shiny.setInputValue(\'report_drill_edit\', \'', eid,
      '\', {priority: \'event\'})">Review</button>'
    )
  }, character(1))
  DT::datatable(
    display, escape = FALSE, rownames = FALSE,
    options = list(pageLength = 10, dom = "t",
                   columnDefs = list(
                     list(targets = 4, searchable = FALSE, orderable = FALSE)
                   ))
  )
})

show_entries_modal <- function(form_name, filter_field = NULL, filter_value = NULL) {
  rows <- .report_drill_entries(form_name, filter_field, filter_value)
  .report_drill_rows(rows)

  title <- if (!is.null(filter_field) && nzchar(filter_field %||% "")) {
    sprintf("%s — %s: %s (%d)", form_name, filter_field, filter_value, nrow(rows))
  } else {
    sprintf("%s (%d)", form_name, nrow(rows))
  }

  shiny::showModal(shiny::modalDialog(
    title = title,
    DT::DTOutput("report_drill_table"),
    size = "l",
    easyClose = TRUE,
    footer = shiny::modalButton("Close")
  ))
}

# Fired by every drill-through link/button: {form: "<crf_code>"}, or
# {form: ..., field: ..., value: ...} for a field=value breakdown
# (Domain Breakdown's per-option counts).
shiny::observeEvent(input$report_drill, {
  info <- input$report_drill
  shiny::req(info$form)
  show_entries_modal(info$form, info$field, info$value)
})

# Fired by a modal row's "Review" button: close the modal and start
# a correction request on that entry, same as EDC's own
# "Request Correction" button.
shiny::observeEvent(input$report_drill_edit, {
  shiny::removeModal()
  rv_pending_correction_entry(input$report_drill_edit)
  bslib::nav_select("main_nav", selected = "corrections", session = session)
})
