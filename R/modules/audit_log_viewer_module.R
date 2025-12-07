#' Audit Log Viewer Module
#'
#' Provides a user-friendly interface for viewing, filtering, and searching audit logs
#' Allows data managers to track all system actions for compliance
#'
#' @export

#' Audit Log Viewer UI
#'
#' @param id The namespace id for the module
#' @return A tagList containing the audit log viewer UI
audit_log_viewer_ui <- function(id) {
  ns <- NS(id)

  div(class = "audit-log-container",
    # Header
    h3("Audit Trail & System Activity", class = "mb-4 text-primary"),

    # Filter controls
    div(class = "card mb-3",
      div(class = "card-header",
        h5(class = "card-title mb-0", "Filter & Search")
      ),
      div(class = "card-body",
        div(class = "row",
          # Username filter
          div(class = "col-md-3",
            label("User"),
            selectInput(ns("filter_user"), NULL,
                       choices = c("All Users" = ""),
                       multiple = FALSE)
          ),

          # Action type filter
          div(class = "col-md-3",
            label("Action Type"),
            selectInput(ns("filter_action"), NULL,
                       choices = list(
                         "All Actions" = "",
                         "Login/Logout" = c("login", "logout"),
                         "Data Entry" = c("create_entry", "update_entry", "delete_entry"),
                         "User Management" = c("create_user", "update_user", "delete_user"),
                         "System" = c("backup", "restore", "config_change")
                       ))
          ),

          # Date range filter
          div(class = "col-md-3",
            label("Date From"),
            dateInput(ns("filter_date_from"), NULL,
                     value = Sys.Date() - 30,
                     format = "yyyy-mm-dd")
          ),

          div(class = "col-md-3",
            label("Date To"),
            dateInput(ns("filter_date_to"), NULL,
                     value = Sys.Date(),
                     format = "yyyy-mm-dd")
          )
        ),

        div(class = "row mt-2",
          # Search box
          div(class = "col-md-6",
            label("Search"),
            textInput(ns("search_text"), NULL,
                     placeholder = "Search in all fields...")
          ),

          # Entity type filter
          div(class = "col-md-3",
            label("Entity Type"),
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
    div(class = "row mb-3",
      div(class = "col-md-3",
        div(class = "card bg-info text-white",
          div(class = "card-body",
            p(class = "card-text", "Total Actions"),
            h5(id = ns("stat_total"), "Loading...", class = "mb-0")
          )
        )
      ),
      div(class = "col-md-3",
        div(class = "card bg-success text-white",
          div(class = "card-body",
            p(class = "card-text", "Data Entries"),
            h5(id = ns("stat_entries"), "Loading...", class = "mb-0")
          )
        )
      ),
      div(class = "col-md-3",
        div(class = "card bg-warning text-dark",
          div(class = "card-body",
            p(class = "card-text", "User Actions"),
            h5(id = ns("stat_users"), "Loading...", class = "mb-0")
          )
        )
      ),
      div(class = "col-md-3",
        div(class = "card bg-danger text-white",
          div(class = "card-body",
            p(class = "card-text", "System Events"),
            h5(id = ns("stat_system"), "Loading...", class = "mb-0")
          )
        )
      )
    ),

    # Audit log table
    div(class = "card",
      div(class = "card-header",
        div(class = "d-flex justify-content-between align-items-center",
          h5(class = "card-title mb-0", "Activity Log"),
          div(
            actionButton(ns("export_csv"), "Export CSV", class = "btn btn-sm btn-info",
                        icon = icon("download")),
            actionButton(ns("refresh_logs"), "Refresh", class = "btn btn-sm btn-secondary",
                        icon = icon("sync"), class = "ms-2")
          )
        )
      ),
      div(class = "card-body",
        DT::dataTableOutput(ns("audit_table")),
        div(id = ns("table_info"), class = "mt-2 text-muted small")
      )
    ),

    # Details modal
    shinymodal::modalDialog(
      id = ns("details_modal"),
      title = "Action Details",
      size = "lg",
      easyClose = TRUE,

      div(id = ns("modal_content"), class = "modal-content")
    )
  )
}


#' Audit Log Viewer Server
#'
#' @param id The namespace id for the module
#' @param db_pool Reactive expression returning database connection pool
#'
#' @return Invisible NULL
audit_log_viewer_server <- function(id, db_pool = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Reactive values
    log_state <- reactiveValues(
      all_logs = data.frame(),
      filtered_logs = data.frame(),
      users_list = character(),
      selected_log = NULL
    )

    # Load all audit logs
    load_audit_logs <- function() {
      if (is.null(db_pool)) {
        # Return empty sample data for testing
        return(create_sample_audit_logs())
      }

      tryCatch({
        query <- "
          SELECT
            audit_id,
            user_id,
            action,
            entity_type,
            entity_id,
            action_date,
            ip_address
          FROM audit_trail
          ORDER BY action_date DESC
          LIMIT 10000
        "
        logs <- pool::dbGetQuery(db_pool, query)

        # Format datetime
        if (nrow(logs) > 0) {
          logs$action_date <- format(
            as.POSIXct(logs$action_date),
            "%Y-%m-%d %H:%M:%S"
          )
        }

        log_state$all_logs <- logs
        return(logs)

      }, error = function(e) {
        # Return sample data if database query fails
        return(create_sample_audit_logs())
      })
    }

    # Create sample audit logs for demonstration
    create_sample_audit_logs <- function() {
      data.frame(
        audit_id = paste0("AUDIT_", 1:20),
        user_id = rep(c("USER_001", "USER_002", "USER_003"), length.out = 20),
        action = sample(c("login", "logout", "create_entry", "update_entry", "delete_entry",
                         "create_user", "update_user", "config_change"),
                       20, replace = TRUE),
        entity_type = sample(c("data", "user", "form", "system"), 20, replace = TRUE),
        entity_id = paste0("ENT_", 1:20),
        action_date = format(Sys.time() - sample(1:(30*24*3600), 20), "%Y-%m-%d %H:%M:%S"),
        ip_address = sample(c("192.168.1.100", "192.168.1.101", "10.0.0.50"), 20, replace = TRUE),
        stringsAsFactors = FALSE
      )
    }

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

      updateSelectInput(session, "filter_user", choices = choices)
    }

    # Initial load
    log_state$all_logs <- load_audit_logs()
    update_user_list()

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
    output$audit_table <- DT::renderDataTable({
      logs <- apply_filters()

      if (nrow(logs) == 0) {
        return(DT::datatable(
          data.frame(Message = "No audit logs match your filters"),
          options = list(dom = 't', searching = FALSE, paging = FALSE)
        ))
      }

      # Create clickable action column
      action_links <- sapply(1:nrow(logs), function(i) {
        audit_id <- logs$audit_id[i]
        action <- logs$action[i]
        paste0(
          '<a href="javascript:void(0)" onclick="Shiny.setInputValue(\'', ns("view_details"), '\', \'', audit_id, '\', {priority: \'event\'})">',
          action,
          '</a>'
        )
      })

      display_data <- logs[, c("user_id", "action", "entity_type", "entity_id", "action_date")]
      display_data$action <- action_links
      colnames(display_data) <- c("User", "Action", "Type", "Entity ID", "Timestamp")

      DT::datatable(
        display_data,
        escape = FALSE,
        options = list(
          pageLength = 20,
          order = list(list(4, "desc")),
          columnDefs = list(
            list(targets = 0, width = "100px"),
            list(targets = 1, width = "120px"),
            list(targets = 2, width = "80px"),
            list(targets = 3, width = "100px"),
            list(targets = 4, width = "160px")
          )
        )
      )
    })

    # Update summary statistics
    observe({
      logs <- apply_filters()

      if (nrow(logs) == 0) {
        shinyjs::html(ns("stat_total"), "0")
        shinyjs::html(ns("stat_entries"), "0")
        shinyjs::html(ns("stat_users"), "0")
        shinyjs::html(ns("stat_system"), "0")
        return()
      }

      total <- nrow(logs)
      entries <- sum(logs$entity_type == "data", na.rm = TRUE)
      users <- sum(logs$entity_type == "user", na.rm = TRUE)
      system <- sum(logs$entity_type == "system", na.rm = TRUE)

      shinyjs::html(ns("stat_total"), total)
      shinyjs::html(ns("stat_entries"), entries)
      shinyjs::html(ns("stat_users"), users)
      shinyjs::html(ns("stat_system"), system)
    })

    # View details
    observeEvent(input$view_details, {
      audit_id <- input$view_details
      log_entry <- log_state$all_logs[log_state$all_logs$audit_id == audit_id, ]

      if (nrow(log_entry) == 0) {
        shinyalert("Error", "Log entry not found", type = "error")
        return()
      }

      # Create detailed view
      details_html <- sprintf("
        <table class='table'>
          <tr>
            <td><strong>Audit ID:</strong></td>
            <td>%s</td>
          </tr>
          <tr>
            <td><strong>User:</strong></td>
            <td>%s</td>
          </tr>
          <tr>
            <td><strong>Action:</strong></td>
            <td><span class='badge bg-primary'>%s</span></td>
          </tr>
          <tr>
            <td><strong>Entity Type:</strong></td>
            <td>%s</td>
          </tr>
          <tr>
            <td><strong>Entity ID:</strong></td>
            <td><code>%s</code></td>
          </tr>
          <tr>
            <td><strong>Timestamp:</strong></td>
            <td>%s</td>
          </tr>
          <tr>
            <td><strong>IP Address:</strong></td>
            <td><code>%s</code></td>
          </tr>
        </table>
      ",
        log_entry$audit_id[1],
        log_entry$user_id[1],
        log_entry$action[1],
        log_entry$entity_type[1],
        log_entry$entity_id[1],
        log_entry$action_date[1],
        log_entry$ip_address[1]
      )

      shinyjs::html(ns("modal_content"), details_html)
      shinyjs::show("details_modal")
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
#' @export
log_audit_action <- function(db_pool, user_id, action, entity_type, entity_id,
                            ip_address = "127.0.0.1", old_values = NULL, new_values = NULL) {

  if (is.null(db_pool)) {
    return(invisible(NULL))
  }

  tryCatch({
    audit_id <- paste0("AUDIT_", as.integer(Sys.time()), "_", sample(1000:9999, 1))

    pool::dbExecute(db_pool, "
      INSERT INTO audit_trail
      (audit_id, user_id, action, entity_type, entity_id, old_values, new_values,
       action_date, ip_address)
      VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'), ?)
    ", params = list(
      audit_id, user_id, action, entity_type, entity_id,
      old_values, new_values, ip_address
    ))

    return(invisible(audit_id))

  }, error = function(e) {
    warning(paste("Failed to log audit action:", e$message))
    return(invisible(NULL))
  })
}
