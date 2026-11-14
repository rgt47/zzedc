#' Audit Log Viewer UI
#'
#' Provides a user-friendly interface for viewing, filtering, and searching audit logs
#' for system compliance tracking.
#'
#' @param id The namespace id for the module
#' @return A tagList containing the audit log viewer UI
#' @keywords internal
audit_log_viewer_ui <- function(id) {
  ns <- NS(id)

  div(class = "audit-log-container",
    # Header
    h3("Audit Trail & System Activity", class = "mb-4 text-primary"),

    # Filter controls
    bslib::card(
      class = "mb-3",
      bslib::card_header("Filter & Search"),
      bslib::card_body(
        div(class = "row",
          # Username filter
          div(class = "col-md-3",
            tags$label("User"),
            selectInput(ns("filter_user"), NULL,
                       choices = c("All Users" = ""),
                       multiple = FALSE)
          ),

          # Action type filter
          div(class = "col-md-3",
            tags$label("Action Type"),
            selectInput(ns("filter_action"), NULL,
                       choices = list(
                         "All Actions" = "",
                         "Sign-in" = c("LOGIN", "LOGOUT", "SESSION_END",
                                       "LOGIN_FAILED", "LOCKOUT", "UNLOCK"),
                         "Data" = c("INSERT", "UPDATE", "DELETE", "EXPORT"),
                         "Signatures" = c("SIGNATURE_APPLIED", "SIGNATURE_REVOKED"),
                         "Accounts" = c("PASSWORD_CHANGE", "ROLE_CHANGE",
                                        "PERMISSION_CHANGE"),
                         "System" = c("BACKUP", "RESTORE", "CONFIG_CHANGE",
                                      "COMPLIANCE_CHECK", "ACCESS"),
                         "Randomization" = c("RANDOMIZATION")
                       ))
          ),

          # Date range filter
          div(class = "col-md-3",
            tags$label("Date From"),
            dateInput(ns("filter_date_from"), NULL,
                     value = Sys.Date() - 30,
                     format = "yyyy-mm-dd")
          ),

          div(class = "col-md-3",
            tags$label("Date To"),
            dateInput(ns("filter_date_to"), NULL,
                     value = Sys.Date(),
                     format = "yyyy-mm-dd")
          )
        ),

        div(class = "row mt-2",
          # Search box
          div(class = "col-md-6",
            tags$label("Search"),
            textInput(ns("search_text"), NULL,
                     placeholder = "Search in all fields...")
          ),

          # Entity type filter
          div(class = "col-md-3",
            tags$label("Entity Type"),
            selectInput(ns("filter_entity_type"), NULL,
                       choices = c("All" = "", "Users" = "user", "Data" = "data",
                                  "Forms" = "form", "System" = "system"))
          ),

          # Buttons
          div(class = "col-md-3 mt-4",
            div(class = "btn-group w-100",
              actionButton(ns("apply_filters"), "Search", class = "btn btn-primary"),
              actionButton(ns("reset_filters"), "Reset", class = "btn btn-secondary")
            )
          )
        )
      )
    ),

    # Summary statistics
    bslib::layout_columns(
      class = "mb-3",
      col_widths = c(3, 3, 3, 3),
      bslib::value_box(
        title    = "Total Actions",
        value    = shiny::textOutput(ns("stat_total")),
        showcase = bsicons::bs_icon("activity"),
        theme    = "info"
      ),
      bslib::value_box(
        title    = "Data Entries",
        value    = shiny::textOutput(ns("stat_entries")),
        showcase = bsicons::bs_icon("file-earmark-text"),
        theme    = "success"
      ),
      bslib::value_box(
        title    = "User Actions",
        value    = shiny::textOutput(ns("stat_users")),
        showcase = bsicons::bs_icon("person-fill"),
        theme    = "warning"
      ),
      bslib::value_box(
        title    = "System Events",
        value    = shiny::textOutput(ns("stat_system")),
        showcase = bsicons::bs_icon("gear-fill"),
        theme    = "danger"
      )
    ),

    # Audit log table
    bslib::card(
      bslib::card_header(
        div(class = "d-flex justify-content-between align-items-center",
          span("Activity Log"),
          div(
            actionButton(ns("export_csv"), "Export CSV", class = "btn btn-sm btn-info",
                        icon = icon("download")),
            actionButton(ns("refresh_logs"), "Refresh", class = "btn btn-sm btn-secondary",
                        icon = icon("sync"), class = "ms-2")
          )
        )
      ),
      bslib::card_body(
        DT::DTOutput(ns("audit_table")),
        div(id = ns("table_info"), class = "mt-2 text-muted small")
      )
    )
  )
}


#' Audit Log Viewer Server
#'
#' @param id The namespace id for the module
#' @param db_pool Reactive expression returning database connection pool
#'
#' @return Invisible NULL
#'
#' @examples
#' \dontrun{
#' # Embed the legacy audit-log viewer (server-only) in a custom app.
#' # Most users will run the full application via
#' # `zzedc::launch_zzedc()`; the example below shows how to
#' # embed the module in a custom Shiny app instead.
#' if (interactive()) {
#'   ui <- shiny::fluidPage(
#'     audit_log_viewer_server("module_id")
#'   )
#'   server <- function(input, output, session) {
#'   }
#'   shiny::shinyApp(ui, server)
#' }
#' }
#' @keywords internal
audit_log_viewer_server <- function(id, db_pool = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Reactive values
    log_state <- reactiveValues(
      all_logs = data.frame(),
      filtered_logs = data.frame(),
      users_list = character(),
      selected_log = NULL,
      load_error = NULL
    )

    # Load the audit trail. This read a table named audit_trail, which
    # nothing in the application writes, and when its query failed it
    # displayed 20 randomly generated "sample" entries as though they
    # were the study's audit trail. It now reads audit_log, the table
    # every audit writer appends to, and an unreadable trail is shown
    # as an error with no rows.
    load_audit_logs <- function() {
      pool_obj <- if (is.function(db_pool) && !inherits(db_pool, "Pool")) db_pool() else db_pool
      if (is.null(pool_obj)) {
        log_state$load_error <- "No database connection."
        return(empty_audit_logs())
      }
      tryCatch({
        logs <- DBI::dbGetQuery(pool_obj, "
          SELECT audit_id, user_id, event_type, table_name, record_id,
                 timestamp, ip_address, session_id, operation, details
          FROM audit_log
          ORDER BY audit_id DESC
          LIMIT 10000
        ")
        log_state$load_error <- NULL
        audit_log_display_frame(logs)
      }, error = function(e) {
        log_state$load_error <- paste("The audit trail could not be read:", conditionMessage(e))
        empty_audit_logs()
      })
    }

    empty_audit_logs <- function() audit_log_display_frame(NULL)

    # Get unique users for filter dropdown
    update_user_list <- function() {
      logs <- log_state$all_logs
      if (nrow(logs) == 0) return()

      unique_users <- unique(logs$user_id)
      choices <- c("All Users" = "")
      names(choices)[1] <- "All Users"

      # Create list with all user IDs
      for (user in unique_users) {
        choices <- c(choices, user)
        names(choices)[length(choices)] <- user
      }

      shiny::freezeReactiveValue(input, "filter_user")
      updateSelectInput(session, "filter_user", choices = choices)
    }

    # Initial load. This runs at moduleServer top level, which is not
    # a reactive consumer: update_user_list()'s read of
    # log_state$all_logs needs isolate(), or it throws "Can't access
    # reactive value 'all_logs' outside of reactive consumer" and
    # aborts the entire enclosing server() call (this module is
    # mounted eagerly by admin_dashboard_server(), so the failure
    # propagated all the way up to create_enhanced_server()).
    shiny::isolate({
      log_state$all_logs <- load_audit_logs()
      update_user_list()
    })

    # Apply filters
    apply_filters <- function() {
      logs <- log_state$all_logs
      if (nrow(logs) == 0) return(logs)

      # User filter
      if (input$filter_user != "") {
        logs <- logs[logs$user_id == input$filter_user, ]
      }

      # Action type filter
      if (!is.null(input$filter_action) && input$filter_action != "") {
        logs <- logs[logs$action %in% input$filter_action, ]
      }

      # Date range filter
      if (!is.null(input$filter_date_from) && !is.null(input$filter_date_to)) {
        date_from <- paste(input$filter_date_from, "00:00:00")
        date_to <- paste(input$filter_date_to, "23:59:59")
        logs <- logs[logs$action_date >= date_from & logs$action_date <= date_to, ]
      }

      # Entity type filter
      if (input$filter_entity_type != "") {
        logs <- logs[logs$entity_type == input$filter_entity_type, ]
      }

      # Text search
      if (input$search_text != "") {
        search_pattern <- tolower(input$search_text)
        matching <- apply(logs, 1, function(row) {
          any(grepl(search_pattern, tolower(as.character(row))))
        })
        logs <- logs[matching, ]
      }

      log_state$filtered_logs <- logs
      return(logs)
    }

    # Watch for filter changes and apply
    observeEvent(input$apply_filters, {
      apply_filters()
    })

    # Reset filters
    observeEvent(input$reset_filters, {
      updateSelectInput(session, "filter_user", selected = "")
      updateSelectInput(session, "filter_action", selected = "")
      updateDateInput(session, "filter_date_from", value = Sys.Date() - 30)
      updateDateInput(session, "filter_date_to", value = Sys.Date())
      updateSelectInput(session, "filter_entity_type", selected = "")
      updateTextInput(session, "search_text", value = "")

      # Reset to all logs
      log_state$filtered_logs <- log_state$all_logs
    })

    # Display audit table
    output$audit_table <- DT::renderDT({
      logs <- apply_filters()

      if (nrow(logs) == 0) {
        msg <- log_state$load_error %||% "No audit logs match your filters"
        return(DT::datatable(
          data.frame(Message = msg),
          options = list(dom = 't', searching = FALSE, paging = FALSE)
        ))
      }

      display_data <- audit_log_table_data(logs, ns("view_details"))

      DT::datatable(
        display_data,
        escape = FALSE,
        options = list(
          pageLength = 20,
          order = list(list(5, "desc")),
          columnDefs = list(
            list(targets = 0, width = "100px"),
            list(targets = 1, width = "120px"),
            list(targets = 2, width = "80px"),
            list(targets = 4, width = "100px"),
            list(targets = 5, width = "160px")
          )
        )
      )
    })

    # Summary statistics. Reactive expression provides a single
    # source of truth for the four value_box outputs and avoids
    # running apply_filters() four times.
    stat_counts <- reactive({
      logs <- apply_filters()
      if (nrow(logs) == 0) {
        return(list(total = 0, entries = 0, users = 0, system = 0))
      }
      list(
        total   = nrow(logs),
        entries = sum(logs$entity_type == "data",   na.rm = TRUE),
        users   = sum(logs$entity_type == "user",   na.rm = TRUE),
        system  = sum(logs$entity_type == "system", na.rm = TRUE)
      )
    })

    output$stat_total   <- renderText(as.character(stat_counts()$total))
    output$stat_entries <- renderText(as.character(stat_counts()$entries))
    output$stat_users   <- renderText(as.character(stat_counts()$users))
    output$stat_system  <- renderText(as.character(stat_counts()$system))

    # View details
    observeEvent(input$view_details, {
      audit_id <- input$view_details
      log_entry <- log_state$all_logs[log_state$all_logs$audit_id == audit_id, ]

      if (nrow(log_entry) == 0) {
        shinyalert("Error", "Log entry not found", type = "error")
        return()
      }

      # Built from tags, which escape their text, rather than raw HTML:
      # audit content can contain text chosen by whoever caused the
      # event (see the table above).
      e1 <- log_entry[1, ]
      row <- function(label, value, code = FALSE) {
        value <- if (is.na(value)) "" else value
        shiny::tags$tr(shiny::tags$td(shiny::tags$strong(label)),
                       shiny::tags$td(if (code) shiny::tags$code(value) else value))
      }
      details_ui <- shiny::tags$table(class = "table",
        row("Audit ID:", e1$audit_id),
        row("User:", e1$user_id),
        row("Action:", e1$action),
        row("Description:", e1$operation),
        row("Table:", e1$table_name, code = TRUE),
        row("Record ID:", e1$entity_id, code = TRUE),
        row("Timestamp (UTC):", e1$action_date),
        row("IP Address:", e1$ip_address, code = TRUE),
        row("Session:", e1$session_id, code = TRUE),
        row("Details:", e1$details, code = TRUE)
      )

      shiny::showModal(shiny::modalDialog(
        title = "Action Details",
        size = "l",
        easyClose = TRUE,
        details_ui,
        footer = shiny::modalButton("Close")
      ))
    })

    # Export CSV
    observeEvent(input$export_csv, {
      logs <- apply_filters()

      if (nrow(logs) == 0) {
        shinyalert("No Data", "No logs to export", type = "warning")
        return()
      }

      # Create filename
      export_filename <- paste0("audit_log_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".csv")

      # This would normally trigger a download
      shinyalert("Export Ready",
                paste("Preparing to download:", export_filename, "\n",
                      "Records:", nrow(logs)),
                type = "info")

      # In production, would use downloadHandler
      # For now, just show message
    })

    # Refresh logs
    observeEvent(input$refresh_logs, {
      log_state$all_logs <- load_audit_logs()
      update_user_list()
      apply_filters()

      shinyalert("Refreshed", "Audit logs updated", type = "success", timer = 1500)
    })

    return(invisible(NULL))
  })
}


#' Log Audit Action
#'
#' Internal function for recording audit trail entries
#' Called by other modules when actions occur
#'
#' @param db_pool Database connection pool
#' @param user_id User ID performing action
#' @param action Action performed (e.g., "login", "create_entry", "update_user")
#' @param entity_type Type of entity (e.g., "data", "user", "system")
#' @param entity_id ID of entity affected
#' @param ip_address User's IP address
#' @param old_values JSON string of previous values (optional)
#' @param new_values JSON string of new values (optional)
#'
#' @return Invisibly returns the audit_id
#' @keywords internal
#' @export
log_audit_action <- function(db_pool, user_id, action, entity_type, entity_id,
                            ip_address = NULL, old_values = NULL, new_values = NULL) {
  # This wrote to a separate audit_trail table, outside the hash chain,
  # that the audit viewer no longer reads. It now appends to the
  # hash-chained audit_log through the same path as every other writer.
  if (is.null(db_pool)) {
    return(invisible(NULL))
  }
  event_type <- toupper(action)
  if (!event_type %in% .audit_event_types) event_type <- "ACCESS"
  details <- if (!is.null(old_values) || !is.null(new_values)) {
    as.character(jsonlite::toJSON(list(action = action, old_values = old_values,
                                       new_values = new_values),
                                  auto_unbox = TRUE, null = "null"))
  } else {
    NULL
  }
  tryCatch({
    audit_id <- .with_db_transaction(db_pool, function(c) {
      .append_audit_record(c, event_type, table_name = entity_type,
                           record_id = entity_id, operation = action,
                           details = details, user_id = user_id,
                           ip_address = ip_address)
    })
    invisible(audit_id)
  }, error = function(e) {
    if (get_security_profile() == "regulated") {
      stop("Audit record could not be written: ", conditionMessage(e), call. = FALSE)
    }
    warning(paste("Failed to log audit action:", e$message))
    invisible(NULL)
  })
}


#' Shape Audit-Log Rows for the Audit Viewer (internal)
#'
#' @param logs Rows of `audit_log`, or `NULL`.
#' @return A data frame with the viewer's columns (`action` is the event
#'   type, `entity_type` one of `user`, `data`, `form`, `system`,
#'   `entity_id` the record acted on, `action_date` the UTC timestamp)
#'   plus `table_name`, `operation`, `details`, and `session_id`.
#' @keywords internal
audit_log_display_frame <- function(logs) {
  cols <- c("audit_id", "user_id", "action", "entity_type", "entity_id",
            "action_date", "ip_address", "table_name", "operation",
            "details", "session_id")
  if (is.null(logs) || nrow(logs) == 0) {
    out <- as.data.frame(stats::setNames(replicate(length(cols), character(0), simplify = FALSE), cols),
                         stringsAsFactors = FALSE)
    return(out)
  }
  user_events <- c("LOGIN", "LOGOUT", "SESSION_START", "SESSION_END", "LOGIN_FAILED",
                   "PASSWORD_CHANGE", "ROLE_CHANGE", "PERMISSION_CHANGE", "LOCKOUT", "UNLOCK")
  data_events <- c("INSERT", "UPDATE", "DELETE", "SELECT", "EXPORT", "SIGNATURE_REQUEST",
                   "SIGNATURE_APPLIED", "SIGNATURE_REJECTED", "SIGNATURE_REVOKED")
  form_tables <- c("designer_forms", "designer_fields", "crf_definitions", "crf_fields")
  tbl <- as.character(logs$table_name)
  ev <- as.character(logs$event_type)
  entity <- ifelse(ev %in% user_events | tbl %in% "edc_users", "user",
            ifelse(tbl %in% form_tables, "form",
            ifelse(ev %in% data_events, "data", "system")))
  data.frame(
    audit_id = as.character(logs$audit_id),
    user_id = as.character(logs$user_id),
    action = ev,
    entity_type = entity,
    entity_id = as.character(logs$record_id),
    action_date = as.character(logs$timestamp),
    ip_address = as.character(logs$ip_address),
    table_name = tbl,
    operation = as.character(logs$operation),
    details = as.character(logs$details),
    session_id = as.character(logs$session_id),
    stringsAsFactors = FALSE
  )
}


#' Rows of the Audit Viewer's Table, HTML-Escaped (internal)
#'
#' Audit content includes text chosen by whoever caused the event (a
#' username typed at a failed login, a record identifier), and the table
#' is rendered with `escape = FALSE` so the action column can carry
#' links. Every value is HTML-escaped here so that such text cannot run
#' as script in an administrator's browser.
#'
#' @param logs From `audit_log_display_frame()`.
#' @param details_input Namespaced input id the action links set.
#' @return A data frame for `DT::datatable(escape = FALSE)`.
#' @keywords internal
audit_log_table_data <- function(logs, details_input) {
  esc <- function(v) htmltools::htmlEscape(ifelse(is.na(v), "", as.character(v)))
  action_links <- vapply(seq_len(nrow(logs)), function(i) {
    paste0(
      '<a href="javascript:void(0)" onclick="Shiny.setInputValue(\'', details_input,
      '\', \'', esc(as.integer(logs$audit_id[i])), '\', {priority: \'event\'})">',
      esc(logs$action[i]),
      '</a>'
    )
  }, character(1))
  data.frame(
    User = esc(logs$user_id),
    Action = action_links,
    Type = esc(logs$entity_type),
    Description = esc(logs$operation),
    `Entity ID` = esc(logs$entity_id),
    Timestamp = esc(logs$action_date),
    check.names = FALSE, stringsAsFactors = FALSE
  )
}
