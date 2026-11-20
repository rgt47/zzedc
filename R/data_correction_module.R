#' Data Correction Workflow UI Module
#'
#' Shiny module for FDA-compliant data correction workflow.
#' Provides interfaces for creating, reviewing, and applying corrections.

#' Data Correction UI
#'
#' @param id Module namespace ID
#'
#' @return Shiny UI elements
#'
#'
#' @examples
#' \dontrun{
#' # Embed the data-correction approval workflow.
#' # Most users will run the full application via
#' # `zzedc::launch_zzedc()`; the example below shows how to
#' # embed the module in a custom Shiny app instead.
#' if (interactive()) {
#'   ui <- shiny::fluidPage(
#'     data_correction_ui("module_id")
#'   )
#'   server <- function(input, output, session) {
#'     data_correction_server("module_id")
#'   }
#'   shiny::shinyApp(ui, server)
#' }
#' }
#' @export
data_correction_ui <- function(id) {
  ns <- shiny::NS(id)

  shiny::tagList(
    shiny::fluidRow(
      shiny::column(12,
        shiny::h3("Data Correction Workflow"),
        shiny::p("FDA 21 CFR Part 11 compliant data correction system"),
        shiny::hr()
      )
    ),

    shiny::fluidRow(
      shiny::column(3,
        shiny::wellPanel(
          shiny::h4("Navigation"),
          shiny::radioButtons(
            ns("view_mode"),
            "View:",
            choices = c(
              "Create Request" = "create",
              "Pending Review" = "pending",
              "DDE Reconciliation" = "dde_queue",
              "My Requests" = "my_requests",
              "All Corrections" = "all",
              "Statistics" = "stats"
            ),
            selected = "pending"
          ),
          shiny::hr(),
          shiny::h5("Quick Stats"),
          shiny::uiOutput(ns("quick_stats"))
        )
      ),

      shiny::column(9,
        shiny::conditionalPanel(
          condition = sprintf("input['%s'] == 'create'", ns("view_mode")),
          shiny::wellPanel(
            shiny::h4("Create Correction Request"),
            shiny::helpText(
              "For Table Name \"data_entries\" with a valid Record ID (an",
              "entry_id), Field and Corrected Value become dropdowns/typed",
              "controls drawn from that record's own form, with validation",
              "matching what the original form enforced. Any other table",
              "falls back to plain text entry."
            ),
            shiny::fluidRow(
              shiny::column(6,
                shiny::textInput(ns("table_name"), "Table Name", placeholder = "e.g., data_entries"),
                shiny::textInput(ns("record_id"), "Record ID", placeholder = "e.g., S001 or an entry_id"),
                shiny::uiOutput(ns("field_picker"))
              ),
              shiny::column(6,
                shiny::textInput(ns("original_value"), "Original Value (read-only)"),
                shiny::uiOutput(ns("corrected_value_input")),
                shiny::selectInput(
                  ns("correction_reason"),
                  "Reason for Correction",
                  choices = c(
                    "Select reason..." = "",
                    "Typographical Error" = "TYPO",
                    "Source Document Error" = "SOURCE_DOC_ERROR",
                    "Calculation Error" = "CALCULATION_ERROR",
                    "Transcription Error" = "TRANSCRIPTION_ERROR",
                    "Unit Error" = "UNIT_ERROR",
                    "Date/Time Error" = "DATE_ERROR",
                    "Protocol Clarification" = "PROTOCOL_CLARIFICATION",
                    "Query Response" = "QUERY_RESPONSE",
                    "Double-Data-Entry Discrepancy" = "DDE_DISCREPANCY",
                    "Other" = "OTHER"
                  )
                )
              )
            ),
            shiny::fluidRow(
              shiny::column(12,
                shiny::textAreaInput(
                  ns("reason_details"),
                  "Reason Details (required if Other)",
                  rows = 3,
                  placeholder = "Provide detailed explanation..."
                )
              )
            ),
            shiny::fluidRow(
              shiny::column(6,
                shiny::textInput(ns("original_source_doc"),
                                  "Original Source Document Reference")
              ),
              shiny::column(6,
                shiny::textInput(ns("corrected_source_doc"),
                                  "Corrected Source Document Reference")
              )
            ),
            shiny::fluidRow(
              shiny::column(6,
                shiny::textInput(ns("site_id"), "Site ID (optional)"),
                shiny::textInput(ns("study_id"), "Study ID (optional)")
              ),
              shiny::column(6,
                shiny::textInput(ns("subject_id"), "Subject ID (optional)"),
                shiny::textInput(ns("visit_id"), "Visit ID (optional)")
              )
            ),
            shiny::hr(),
            shiny::actionButton(ns("submit_request"), "Submit Correction Request",
                                class = "btn-primary"),
            shiny::textOutput(ns("submit_message"))
          )
        ),

        shiny::conditionalPanel(
          condition = sprintf("input['%s'] == 'pending'", ns("view_mode")),
          shiny::wellPanel(
            shiny::h4("Pending Corrections for Review"),
            DT::DTOutput(ns("pending_table")),
            shiny::hr(),
            shiny::h5("Review Selected Request"),
            shiny::uiOutput(ns("review_panel"))
          )
        ),

        shiny::conditionalPanel(
          condition = sprintf("input['%s'] == 'dde_queue'", ns("view_mode")),
          shiny::wellPanel(
            shiny::h4("Double-Data-Entry Reconciliation Queue"),
            shiny::helpText(
              "Flagged fields where the two independent entries differ and",
              "the discrepancy was not resolved at second-entry save time",
              "(\"leave both and flag for review\"). Select a row and file a",
              "correction request (reason DDE_DISCREPANCY) to resolve it --",
              "the person who files it can be either entry's user, but",
              "approving and applying requires a third reviewer, neither of",
              "the two."
            ),
            DT::DTOutput(ns("dde_queue_table")),
            shiny::hr(),
            shiny::actionButton(ns("dde_file_request"),
                                "File Correction Request for Selected Row",
                                class = "btn-primary")
          )
        ),

        shiny::conditionalPanel(
          condition = sprintf("input['%s'] == 'my_requests'", ns("view_mode")),
          shiny::wellPanel(
            shiny::h4("My Correction Requests"),
            DT::DTOutput(ns("my_requests_table")),
            shiny::hr(),
            shiny::uiOutput(ns("request_details"))
          )
        ),

        shiny::conditionalPanel(
          condition = sprintf("input['%s'] == 'all'", ns("view_mode")),
          shiny::wellPanel(
            shiny::h4("All Corrections"),
            shiny::fluidRow(
              shiny::column(3,
                shiny::selectInput(ns("filter_status"), "Status",
                  choices = c("All" = "", "PENDING", "APPROVED",
                              "REJECTED", "APPLIED", "CANCELLED"))
              ),
              shiny::column(3,
                shiny::textInput(ns("filter_site"), "Site ID")
              ),
              shiny::column(3,
                shiny::dateInput(ns("filter_start"), "From Date",
                                  value = Sys.Date() - 30)
              ),
              shiny::column(3,
                shiny::dateInput(ns("filter_end"), "To Date",
                                  value = Sys.Date())
              )
            ),
            DT::DTOutput(ns("all_corrections_table")),
            shiny::hr(),
            shiny::h5("Review Selected Request"),
            shiny::uiOutput(ns("review_panel_all"))
          )
        ),

        shiny::conditionalPanel(
          condition = sprintf("input['%s'] == 'stats'", ns("view_mode")),
          shiny::wellPanel(
            shiny::h4("Correction Statistics"),
            bslib::layout_columns(
              col_widths = c(3, 3, 3, 3),
              shiny::uiOutput(ns("stat_total")),
              shiny::uiOutput(ns("stat_pending")),
              shiny::uiOutput(ns("stat_approved")),
              shiny::uiOutput(ns("stat_rejected"))
            ),
            shiny::hr(),
            shiny::fluidRow(
              shiny::column(6,
                shiny::h5("By Reason"),
                DT::DTOutput(ns("stats_by_reason"))
              ),
              shiny::column(6,
                shiny::h5("By Table"),
                DT::DTOutput(ns("stats_by_table"))
              )
            ),
            shiny::hr(),
            shiny::h5("Generate Report"),
            shiny::fluidRow(
              shiny::column(4,
                shiny::textInput(ns("report_org"), "Organization",
                                  value = "Clinical Research Organization")
              ),
              shiny::column(4,
                shiny::selectInput(ns("report_format"), "Format",
                  choices = c("Text" = "txt", "JSON" = "json"))
              ),
              shiny::column(4,
                shiny::br(),
                shiny::downloadButton(ns("download_report"), "Download Report")
              )
            )
          )
        )
      )
    )
  )
}


#' Data Correction Server
#'
#' @param id Module namespace ID
#' @param current_user Reactive: Current user ID
#' @param user_role Reactive: Current user role
#' @param db_path Character: Database path
#' @param user_session Optional: the session's login state
#'   (`reactiveValues` with `authenticated`, `username`, `role`). When
#'   supplied, its `authenticated` flag must be `TRUE` as well.
#' @param pending_entry_id Optional: a `shiny::reactiveVal()` (not a
#'   plain `reactive()` -- this module both reads and clears it)
#'   another part of the application sets to a `data_entries.entry_id`
#'   to hand off into this module's "Create Request" view, pre-filled
#'   with `table_name = "data_entries"` and that `record_id`. Used by
#'   `inst/app/edc.R`'s per-row "Request Correction" action so a user
#'   never has to type an entry_id by hand. `NULL` (the default)
#'   disables the hand-off entirely, for the `\dontrun{}` example
#'   below and any other embedding with nothing to hand off from.
#'
#' @details
#' Every output and handler checks the current user through
#' `.module_access_guard()`: after logout (an empty `current_user`, or
#' `user_session$authenticated` `FALSE`) nothing renders and no action
#' runs. Approving, rejecting and applying a correction also require
#' one of the reviewer roles (`Admin`, `PI`, `StudyManager`,
#' `Data Manager`), checked on the server; a denied attempt is recorded
#' as an `ACCESS`/`DENIED` audit event.
#'
#' @return Module server
#'
#'
#' @examples
#' \dontrun{
#' # Embed the data-correction approval workflow.
#' # Most users will run the full application via
#' # `zzedc::launch_zzedc()`; the example below shows how to
#' # embed the module in a custom Shiny app instead.
#' if (interactive()) {
#'   ui <- shiny::fluidPage(
#'     data_correction_ui("module_id")
#'   )
#'   server <- function(input, output, session) {
#'     data_correction_server("module_id")
#'   }
#'   shiny::shinyApp(ui, server)
#' }
#' }
#' @export
data_correction_server <- function(id, current_user = NULL, user_role = NULL,
                                   db_path = NULL, user_session = NULL,
                                   pending_entry_id = NULL) {
  shiny::moduleServer(id, function(input, output, session) {

    guard <- .module_access_guard(user_session = user_session,
                                  user = current_user, role = user_role,
                                  db_path = db_path, session = session)

    rv <- shiny::reactiveValues(
      refresh_trigger = 0,
      selected_request = NULL,
      selected_dde_row = NULL,
      dde_prefill_field = NULL
    )

    shiny::observe({
      if (!guard$authorized()) {
        rv$selected_request <- NULL
        output$submit_message <- shiny::renderText("")
      }
    })

    if (!is.null(pending_entry_id)) {
      shiny::observeEvent(pending_entry_id(), {
        if (!guard$authorized()) return()
        entry_id <- pending_entry_id()
        if (is.null(entry_id) || !nzchar(entry_id)) return()

        shiny::updateRadioButtons(session, "view_mode", selected = "create")
        shiny::updateTextInput(session, "table_name", value = "data_entries")
        shiny::updateTextInput(session, "record_id", value = entry_id)

        # Consumed: clear it so re-selecting the Corrections tab
        # later (with nothing new pending) doesn't re-trigger this.
        pending_entry_id(NULL)
      }, ignoreInit = TRUE, ignoreNULL = TRUE)
    }

    output$quick_stats <- shiny::renderUI({
      guard$require()
      rv$refresh_trigger
      stats <- tryCatch({
        get_correction_statistics(db_path = db_path)
      }, error = function(e) {
        list(summary = list(total_requests = 0, pending = 0,
                            approval_rate = 0))
      })

      shiny::tagList(
        shiny::p(shiny::strong("Total:"), stats$summary$total_requests),
        shiny::p(shiny::strong("Pending:"), stats$summary$pending),
        shiny::p(shiny::strong("Approval Rate:"),
                  paste0(stats$summary$approval_rate, "%"))
      )
    })

    # CRF context for the record under "Table Name"/"Record ID", when
    # that table is `data_entries` and the record ID resolves to a
    # real entry: its field metadata (type/label/required/choices,
    # the same shape renderPanel() and validate_crf_submission()
    # already consume) and its current field values. NULL for any
    # other table, or a `data_entries` record_id/entry_id that does
    # not exist -- both fall back to the plain free-text inputs this
    # module always had. `list(draft = TRUE, entry_id =)` when the
    # entry_id resolves but is still an open "Save and Finish Later"
    # draft (`is_complete = 0`, see `db_update_incomplete_data_entry()`):
    # there is no settled original value yet to correct, so the field
    # picker below shows a message instead of either the typed picker
    # or the free-text fallback, and submission is refused (belt and
    # suspenders alongside `create_correction_request()`'s own check).
    crf_context <- shiny::reactive({
      guard$require()
      tbl <- trimws(input$table_name %||% "")
      rid <- trimws(input$record_id %||% "")
      if (tolower(tbl) != "data_entries" || !nzchar(rid)) return(NULL)

      tryCatch({
        conn <- connect_encrypted_db(db_path = db_path)
        on.exit(DBI::dbDisconnect(conn), add = TRUE)

        row <- DBI::dbGetQuery(conn,
          "SELECT entry_id, form_name, data_json, is_complete FROM data_entries WHERE entry_id = ?",
          list(rid))
        if (nrow(row) == 0) return(NULL)
        if (!isTRUE(as.logical(as.integer(row$is_complete[1])))) {
          return(list(draft = TRUE, entry_id = rid))
        }

        forms <- get_active_crf_forms(conn)
        match_idx <- which(tolower(forms$crf_code) == row$form_name[1])
        if (length(match_idx) == 0) return(NULL)

        metadata <- get_crf_field_metadata(conn, forms$crf_id[match_idx[1]])
        if (length(metadata) == 0) return(NULL)

        values <- jsonlite::fromJSON(row$data_json[1] %||% "{}", simplifyVector = FALSE)
        list(metadata = metadata, values = values)
      }, error = function(e) NULL)
    })

    output$field_picker <- shiny::renderUI({
      guard$require()
      ctx <- crf_context()
      if (!is.null(ctx) && isTRUE(ctx$draft)) {
        return(shiny::div(
          class = "alert alert-warning py-2 px-3",
          sprintf(
            paste("Entry %s is still an open draft (not yet submitted as",
                  "complete). There is no settled value yet to correct --",
                  "finish and submit it, or resume it, instead."),
            ctx$entry_id
          )
        ))
      }
      if (is.null(ctx)) {
        return(shiny::textInput(session$ns("field_name"), "Field Name",
                                 placeholder = "e.g., age"))
      }
      choices <- stats::setNames(
        names(ctx$metadata),
        vapply(ctx$metadata, function(m) m$label %||% "", character(1))
      )
      shiny::selectInput(session$ns("field_name"), "Field",
                          choices = c("Select field..." = "", choices))
    })

    # Auto-fill "Original Value" from the record's own current value
    # once a CRF-aware field is picked -- remains plain, manually
    # editable text for the free-text (non-`data_entries`) path.
    shiny::observeEvent(list(input$field_name, crf_context()), {
      if (!guard$authorized()) return()
      ctx <- crf_context()
      field <- input$field_name %||% ""
      if (!is.null(ctx) && !isTRUE(ctx$draft) &&
            nzchar(field) && field %in% names(ctx$metadata)) {
        current <- ctx$values[[field]]
        shiny::updateTextInput(session, "original_value",
          value = if (is.null(current)) "" else paste(current, collapse = "; "))
      }
    }, ignoreInit = TRUE)

    output$corrected_value_input <- shiny::renderUI({
      guard$require()
      ctx <- crf_context()
      field <- input$field_name %||% ""
      widget_id <- session$ns("corrected_value_widget")

      if (!is.null(ctx) && isTRUE(ctx$draft)) return(NULL)
      if (is.null(ctx) || !nzchar(field) || !(field %in% names(ctx$metadata))) {
        return(shiny::textInput(widget_id, "Corrected Value"))
      }
      # renderPanel() uses its first argument as both the widget's id
      # and the name it looks up in field_metadata -- passing the
      # already-namespaced `widget_id` for both keeps this a single,
      # module-unique DOM id, since the real field_code
      # (e.g. "manuscript_id") could otherwise collide with an
      # identically-named, non-namespaced field the live EDC tab
      # renders elsewhere on the same page.
      renderPanel(widget_id, stats::setNames(list(ctx$metadata[[field]]), widget_id))[[1]]
    })

    shiny::observeEvent(input$submit_request, {
      user <- guard$require_action("submit a correction request")$user

      ctx <- crf_context()
      field <- input$field_name %||% ""
      corrected_raw <- input$corrected_value_widget

      if (!is.null(ctx) && isTRUE(ctx$draft)) {
        output$submit_message <- shiny::renderText(sprintf(
          "Error: Entry %s is still an open draft; there is no settled value yet to correct.",
          ctx$entry_id
        ))
        return()
      }

      if (input$table_name == "" || input$record_id == "" ||
          !nzchar(field) || input$correction_reason == "") {
        output$submit_message <- shiny::renderText(
          "Error: Please fill in all required fields")
        return()
      }

      if (!is.null(ctx) && !isTRUE(ctx$draft) && field %in% names(ctx$metadata)) {
        val_result <- validate_crf_submission(
          stats::setNames(list(corrected_raw), field),
          ctx$metadata[field]
        )
        if (!val_result$valid) {
          err <- val_result$errors[[field]]
          output$submit_message <- shiny::renderText(paste("Error:", err$message))
          return()
        }
        corrected_value_out <- paste(corrected_raw, collapse = "; ")
      } else {
        if (is.null(corrected_raw) || !nzchar(trimws(as.character(corrected_raw)))) {
          output$submit_message <- shiny::renderText(
            "Error: Please fill in all required fields")
          return()
        }
        corrected_value_out <- as.character(corrected_raw)
      }

      result <- create_correction_request(
        table_name = input$table_name,
        record_id = input$record_id,
        field_name = field,
        original_value = input$original_value,
        corrected_value = corrected_value_out,
        correction_reason = input$correction_reason,
        reason_details = input$reason_details,
        requested_by = user,
        original_source_doc = input$original_source_doc,
        corrected_source_doc = input$corrected_source_doc,
        site_id = input$site_id,
        study_id = input$study_id,
        subject_id = input$subject_id,
        visit_id = input$visit_id,
        db_path = db_path
      )

      if (result$success) {
        output$submit_message <- shiny::renderText(
          paste("Request #", result$request_id, "created successfully"))
        rv$refresh_trigger <- rv$refresh_trigger + 1

        # Clearing table_name/record_id drops crf_context() back to
        # NULL, which re-renders field_picker/corrected_value_input
        # into their blank free-text state -- simpler and safer than
        # resetting each possible widget type (select/numeric/date/
        # radio/...) individually.
        shiny::updateTextInput(session, "table_name", value = "")
        shiny::updateTextInput(session, "record_id", value = "")
        shiny::updateTextInput(session, "original_value", value = "")
        shiny::updateSelectInput(session, "correction_reason", selected = "")
        shiny::updateTextAreaInput(session, "reason_details", value = "")
      } else {
        output$submit_message <- shiny::renderText(
          paste("Error:", result$error))
      }
    })

    pending_data <- shiny::reactive({
      guard$require()
      rv$refresh_trigger
      tryCatch({
        get_pending_corrections(db_path = db_path)
      }, error = function(e) data.frame())
    })

    output$pending_table <- DT::renderDT({
      guard$require()
      data <- pending_data()
      if (nrow(data) == 0) {
        return(DT::datatable(data.frame(Message = "No pending corrections")))
      }

      display_cols <- c("request_id", "table_name", "field_name",
                        "original_value", "corrected_value",
                        "correction_reason", "requested_by", "requested_at")
      display_data <- data[, intersect(display_cols, names(data)), drop = FALSE]

      DT::datatable(
        display_data,
        selection = "single",
        options = list(pageLength = 10, scrollX = TRUE)
      )
    })

    shiny::observeEvent(input$pending_table_rows_selected, {
      guard$require()
      data <- pending_data()
      if (!is.null(input$pending_table_rows_selected) && nrow(data) > 0) {
        rv$selected_request <- data$request_id[input$pending_table_rows_selected]
      }
    })

    # Shared by every view that can select a request into rv$selected_request
    # (Pending Review, My Requests, All Corrections) -- a request can be
    # APPROVED or REJECTED, not just PENDING, so the Approve/Reject/Apply
    # controls must be reachable from whichever view a user finds it in,
    # not only the Pending table that lists PENDING rows exclusively.
    render_review_panel <- function() {
      guard$require()
      if (is.null(rv$selected_request)) {
        return(shiny::p("Select a request to review"))
      }

      ns <- session$ns

      req_data <- tryCatch({
        get_correction_request(rv$selected_request, db_path = db_path)
      }, error = function(e) list(success = FALSE))

      if (!req_data$success) {
        return(shiny::p("Error loading request"))
      }

      r <- req_data$request

      shiny::tagList(
        shiny::h5(paste("Request #", r$request_id)),
        shiny::fluidRow(
          shiny::column(6,
            shiny::p(shiny::strong("Table:"), r$table_name),
            shiny::p(shiny::strong("Record:"), r$record_id),
            shiny::p(shiny::strong("Field:"), r$field_name)
          ),
          shiny::column(6,
            shiny::p(shiny::strong("Original:"), r$original_value),
            shiny::p(shiny::strong("Corrected:"), r$corrected_value),
            shiny::p(shiny::strong("Reason:"), r$correction_reason)
          )
        ),
        shiny::p(shiny::strong("Status:"), r$status),
        shiny::p(shiny::strong("Details:"), r$reason_details),
        shiny::p(shiny::strong("Requested by:"), r$requested_by,
                  "at", r$requested_at),
        shiny::hr(),
        shiny::textAreaInput(ns("review_comments"), "Review Comments", rows = 2),
        shiny::actionButton(ns("approve_btn"), "Approve", class = "btn-success"),
        shiny::actionButton(ns("reject_btn"), "Reject", class = "btn-danger"),
        if (.normalize_role_name(
              if (shiny::is.reactive(user_role)) user_role() else user_role
            ) %in% .normalize_role_name(.correction_reviewer_roles)) {
          shiny::actionButton(ns("apply_btn"), "Apply Correction", class = "btn-primary")
        } else {
          shiny::tagList(
            shiny::br(),
            shiny::span(
              class = "text-muted",
              "Applying an approved correction requires the Admin, PI, ",
              "Study Manager, or Data Manager role."
            )
          )
        }
      )
    }

    output$review_panel <- shiny::renderUI(render_review_panel())
    output$review_panel_all <- shiny::renderUI(render_review_panel())
    output$request_details <- shiny::renderUI(render_review_panel())

    # DDE_DISCREPANCY-specific reviewer-separation guard
    # (require_dde_reviewer_separation(), R/double_data_entry.R):
    # neither of the two users who made the two entries may approve
    # or apply the reconciliation of their own discrepancy. The real
    # enforcement point is inside approve_correction()/
    # apply_correction() themselves
    # (.require_dde_reviewer_separation_for_request(),
    # R/data_correction.R), so a scripted caller is covered too, not
    # just this module; this is a fast, redundant UI-layer check that
    # shows the error without a round trip to those functions when it
    # can, and is harmless if it ever disagrees with them (their
    # answer always wins). Unlike the earlier version of this guard,
    # a lookup failure here is NOT treated as "allow" -- fails closed,
    # the same as the enforcement point does, so this layer can never
    # be the one that waves through a request the core functions would
    # have refused.
    .dde_reviewer_guard <- function(request_id, actor) {
      req <- tryCatch(get_correction_request(request_id, db_path = db_path),
                      error = function(e) list(success = FALSE))
      if (!isTRUE(req$success)) {
        return(list(success = FALSE, error = "Could not load the request to check."))
      }
      if (!identical(req$request$correction_reason[1], "DDE_DISCREPANCY")) {
        return(NULL)
      }
      tryCatch({
        conn <- connect_encrypted_db(db_path = db_path)
        on.exit(DBI::dbDisconnect(conn), add = TRUE)
        gid <- DBI::dbGetQuery(conn,
          "SELECT dde_group_id FROM data_entries WHERE entry_id = ?",
          list(req$request$record_id[1]))$dde_group_id[1]
        if (is.null(gid) || length(gid) == 0 || is.na(gid)) {
          return(list(success = FALSE,
                      error = "Could not resolve the double-data-entry group for this request."))
        }
        require_dde_reviewer_separation(conn, gid, actor)
      }, error = function(e) {
        list(success = FALSE, error = paste("Reviewer-separation check failed:", conditionMessage(e)))
      })
    }

    shiny::observeEvent(input$approve_btn, {
      who <- guard$require_action("approve a data correction",
                                  roles = .correction_reviewer_roles)

      dde_denied <- .dde_reviewer_guard(rv$selected_request, who$user)
      if (!is.null(dde_denied)) {
        shiny::showNotification(paste("Error:", dde_denied$error), type = "error")
        return()
      }

      result <- approve_correction(
        request_id = rv$selected_request,
        reviewed_by = who$user,
        review_comments = input$review_comments,
        db_path = db_path,
        reviewer_role = who$role
      )

      if (result$success) {
        shiny::showNotification("Correction approved", type = "message")
        rv$refresh_trigger <- rv$refresh_trigger + 1
        rv$selected_request <- NULL
      } else {
        shiny::showNotification(paste("Error:", result$error), type = "error")
      }
    })

    shiny::observeEvent(input$reject_btn, {
      who <- guard$require_action("reject a data correction",
                                  roles = .correction_reviewer_roles)

      if (nchar(input$review_comments) < 10) {
        shiny::showNotification(
          "Rejection reason required (min 10 characters)", type = "error")
        return()
      }

      result <- reject_correction(
        request_id = rv$selected_request,
        reviewed_by = who$user,
        review_comments = input$review_comments,
        db_path = db_path,
        reviewer_role = who$role
      )

      if (result$success) {
        shiny::showNotification("Correction rejected", type = "warning")
        rv$refresh_trigger <- rv$refresh_trigger + 1
        rv$selected_request <- NULL
      } else {
        shiny::showNotification(paste("Error:", result$error), type = "error")
      }
    })

    shiny::observeEvent(input$apply_btn, {
      who <- guard$require_action("apply a data correction",
                                  roles = .correction_reviewer_roles)

      dde_denied <- .dde_reviewer_guard(rv$selected_request, who$user)
      if (!is.null(dde_denied)) {
        shiny::showNotification(paste("Error:", dde_denied$error), type = "error")
        return()
      }

      result <- apply_correction(
        request_id = rv$selected_request,
        applied_by = who$user,
        db_path = db_path,
        applier_role = who$role
      )

      if (result$success) {
        shiny::showNotification("Correction applied successfully", type = "message")
        rv$refresh_trigger <- rv$refresh_trigger + 1
        rv$selected_request <- NULL

        # Once applied, this may have been the last open discrepancy
        # for this dde_group_id -- if so, mark the non-canonical entry
        # superseded (close_dde_group_if_resolved(), kept, never
        # deleted, per the insert-only design).
        tryCatch({
          conn <- connect_encrypted_db(db_path = db_path)
          on.exit(DBI::dbDisconnect(conn), add = TRUE)
          gid <- DBI::dbGetQuery(conn,
            "SELECT dde_group_id FROM data_entries WHERE entry_id = ?",
            list(result$record_id))$dde_group_id[1]
          if (!is.null(gid) && !is.na(gid)) {
            close_dde_group_if_resolved(conn, gid)
          }
        }, error = function(e) NULL)
      } else {
        shiny::showNotification(paste("Error:", result$error), type = "error")
      }
    })

    # --- DDE Reconciliation Queue -------------------------------------

    dde_queue_data <- shiny::reactive({
      guard$require()
      rv$refresh_trigger
      tryCatch({
        conn <- connect_encrypted_db(db_path = db_path)
        on.exit(DBI::dbDisconnect(conn), add = TRUE)
        list_dde_discrepancies(conn)
      }, error = function(e) data.frame())
    })

    output$dde_queue_table <- DT::renderDT({
      guard$require()
      data <- dde_queue_data()
      if (nrow(data) == 0) {
        return(DT::datatable(data.frame(Message = "No open DDE discrepancies")))
      }
      DT::datatable(data, selection = "single",
                    options = list(pageLength = 10, scrollX = TRUE))
    })

    shiny::observeEvent(input$dde_queue_table_rows_selected, {
      guard$require()
      data <- dde_queue_data()
      if (!is.null(input$dde_queue_table_rows_selected) && nrow(data) > 0) {
        rv$selected_dde_row <- data[input$dde_queue_table_rows_selected, , drop = FALSE]
      }
    })

    # Pre-fills the Create Request view from the selected queue row:
    # table_name/record_id target the first (canonical) entry, the
    # reason is fixed to DDE_DISCREPANCY, and the field/original value
    # are carried through rv$dde_prefill_field for the field_picker/
    # auto-fill observers (below) to apply once crf_context() has
    # re-resolved for the new record_id.
    shiny::observeEvent(input$dde_file_request, {
      guard$require()
      row <- rv$selected_dde_row
      if (is.null(row) || nrow(row) == 0) {
        shiny::showNotification("Select a row in the queue first", type = "error")
        return()
      }
      shiny::updateRadioButtons(session, "view_mode", selected = "create")
      shiny::updateTextInput(session, "table_name", value = "data_entries")
      shiny::updateTextInput(session, "record_id", value = row$first_entry_id[1])
      shiny::updateSelectInput(session, "correction_reason", selected = "DDE_DISCREPANCY")
      rv$dde_prefill_field <- row$field_code[1]
    })

    shiny::observeEvent(list(crf_context(), rv$dde_prefill_field), {
      if (!guard$authorized()) return()
      field <- rv$dde_prefill_field
      ctx <- crf_context()
      if (is.null(field) || is.null(ctx) || isTRUE(ctx$draft)) return()
      if (!field %in% names(ctx$metadata)) return()
      # output$field_picker's renderUI() depends on this same
      # crf_context() recompute and rebuilds the selectInput's DOM
      # node from scratch -- an updateSelectInput() call made in the
      # same reactive flush can be overwritten by that rebuild
      # depending on flush ordering (confirmed directly: the
      # selection was lost without this). session$onFlushed() defers
      # the update to just after the current flush completes, once
      # the rebuilt <select> actually exists in the DOM.
      session$onFlushed(function() {
        shiny::updateSelectInput(session, "field_name", selected = field)
      }, once = TRUE)
      rv$dde_prefill_field <- NULL
    }, ignoreInit = TRUE)

    my_requests_data <- shiny::reactive({
      user <- guard$require()$user
      rv$refresh_trigger

      tryCatch({
        conn <- connect_encrypted_db(db_path = db_path)
        on.exit(DBI::dbDisconnect(conn), add = TRUE)

        DBI::dbGetQuery(conn, "
          SELECT request_id, table_name, field_name, status,
                 corrected_value, correction_reason, requested_at
          FROM correction_requests
          WHERE requested_by = ?
          ORDER BY requested_at DESC
        ", list(user))
      }, error = function(e) data.frame())
    })

    output$my_requests_table <- DT::renderDT({
      guard$require()
      data <- my_requests_data()
      if (nrow(data) == 0) {
        return(DT::datatable(data.frame(Message = "Error loading requests")))
      }
      DT::datatable(data, selection = "single",
                    options = list(pageLength = 10))
    })

    # A request a user submitted themselves can be APPROVED or REJECTED,
    # not just PENDING, so selecting it here (unlike pending_table, which
    # only ever lists PENDING rows) is the only UI path to the review
    # panel -- and so to the Apply button -- once a request has moved
    # past PENDING.
    shiny::observeEvent(input$my_requests_table_rows_selected, {
      guard$require()
      data <- my_requests_data()
      if (!is.null(input$my_requests_table_rows_selected) && nrow(data) > 0) {
        rv$selected_request <- data$request_id[input$my_requests_table_rows_selected]
      }
    })

    all_corrections_data <- shiny::reactive({
      guard$require()
      rv$refresh_trigger

      tryCatch({
        conn <- connect_encrypted_db(db_path = db_path)
        on.exit(DBI::dbDisconnect(conn), add = TRUE)

        query <- "SELECT * FROM correction_requests WHERE 1=1"
        params <- list()

        if (input$filter_status != "") {
          query <- paste(query, "AND status = ?")
          params <- c(params, list(input$filter_status))
        }

        if (input$filter_site != "") {
          query <- paste(query, "AND site_id = ?")
          params <- c(params, list(input$filter_site))
        }

        query <- paste(query, "AND requested_at >= ? AND requested_at <= ?")
        params <- c(params, list(
          as.character(input$filter_start),
          as.character(input$filter_end + 1)
        ))

        query <- paste(query, "ORDER BY requested_at DESC")

        if (length(params) > 0) {
          DBI::dbGetQuery(conn, query, params)
        } else {
          DBI::dbGetQuery(conn, query)
        }
      }, error = function(e) data.frame())
    })

    output$all_corrections_table <- DT::renderDT({
      guard$require()
      data <- all_corrections_data()
      if (nrow(data) == 0) {
        return(DT::datatable(data.frame(Message = "Error loading corrections")))
      }

      display_cols <- c("request_id", "table_name", "field_name", "status",
                        "correction_reason", "requested_by", "requested_at",
                        "reviewed_by", "reviewed_at")

      DT::datatable(
        data[, intersect(display_cols, names(data)), drop = FALSE],
        selection = "single",
        options = list(pageLength = 15, scrollX = TRUE)
      )
    })

    # All Corrections is the only view that lists every status at once,
    # so (like my_requests_table above) its selection must also feed the
    # review panel -- otherwise an approved request a *different* user
    # requested can never be selected again to be applied.
    shiny::observeEvent(input$all_corrections_table_rows_selected, {
      guard$require()
      data <- all_corrections_data()
      if (!is.null(input$all_corrections_table_rows_selected) && nrow(data) > 0) {
        rv$selected_request <- data$request_id[input$all_corrections_table_rows_selected]
      }
    })

    stats_data <- shiny::reactive({
      guard$require()
      rv$refresh_trigger
      tryCatch({
        get_correction_statistics(db_path = db_path)
      }, error = function(e) {
        list(success = FALSE, summary = list(
          total_requests = 0, pending = 0, approved = 0, rejected = 0
        ), by_reason = data.frame(), by_table = data.frame())
      })
    })

    output$stat_total <- shiny::renderUI({
      stats <- stats_data()
      bslib::value_box(
        title    = "Total Requests",
        value    = stats$summary$total_requests,
        showcase = bsicons::bs_icon("file-earmark-text"),
        theme    = "primary"
      )
    })

    output$stat_pending <- shiny::renderUI({
      stats <- stats_data()
      bslib::value_box(
        title    = "Pending",
        value    = stats$summary$pending,
        showcase = bsicons::bs_icon("clock"),
        theme    = "warning"
      )
    })

    output$stat_approved <- shiny::renderUI({
      stats <- stats_data()
      bslib::value_box(
        title    = "Approved/Applied",
        value    = stats$summary$approved + stats$summary$applied,
        showcase = bsicons::bs_icon("check-circle-fill"),
        theme    = "success"
      )
    })

    output$stat_rejected <- shiny::renderUI({
      stats <- stats_data()
      bslib::value_box(
        title    = "Rejected",
        value    = stats$summary$rejected,
        showcase = bsicons::bs_icon("x-circle-fill"),
        theme    = "danger"
      )
    })

    output$stats_by_reason <- DT::renderDT({
      stats <- stats_data()
      DT::datatable(
        stats$by_reason,
        options = list(pageLength = 10, dom = 't')
      )
    })

    output$stats_by_table <- DT::renderDT({
      stats <- stats_data()
      DT::datatable(
        stats$by_table,
        options = list(pageLength = 10, dom = 't')
      )
    })

    output$download_report <- shiny::downloadHandler(
      filename = function() {
        paste0("correction_report_", Sys.Date(), ".",
               input$report_format)
      },
      content = function(file) {
        who <- guard$require_action("download the correction report")
        generate_correction_report(
          output_file = file,
          format = input$report_format,
          organization = input$report_org,
          prepared_by = who$user,
          db_path = db_path
        )
      }
    )
  })
}
