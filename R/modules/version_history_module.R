# Version History Viewer Module
#
# Shiny module for viewing, comparing, and restoring record versions.
# Supports FDA 21 CFR Part 11 compliance requirements.

#' Version History UI
#'
#' Creates the UI for the version history viewer module.
#'
#' @param id Character: Module namespace ID
#'
#' @return Shiny UI elements
#'
#' @export
version_history_ui <- function(id) {
  ns <- shiny::NS(id)

  shiny::tagList(
    shiny::fluidRow(
      shiny::column(
        width = 12,
        shiny::h3("Version History"),
        shiny::p("View, compare, and restore previous versions of records.")
      )
    ),

    shiny::fluidRow(
      shiny::column(
        width = 4,
        shiny::wellPanel(
          shiny::h4("Select Record"),

          shiny::selectInput(
            ns("table_name"),
            "Table:",
            choices = c("Select table..." = "")
          ),

          shiny::textInput(
            ns("record_id"),
            "Record ID:",
            placeholder = "Enter record ID"
          ),

          shiny::actionButton(
            ns("load_history_btn"),
            "Load History",
            class = "btn-primary",
            width = "100%"
          ),

          shiny::hr(),

          shiny::h4("Version Actions"),

          shiny::selectInput(
            ns("version_a"),
            "Compare Version A:",
            choices = c("Select version..." = "")
          ),

          shiny::selectInput(
            ns("version_b"),
            "Compare Version B:",
            choices = c("Select version..." = "")
          ),

          shiny::actionButton(
            ns("compare_btn"),
            "Compare Versions",
            class = "btn-info",
            width = "100%"
          ),

          shiny::hr(),

          shiny::selectInput(
            ns("restore_version"),
            "Restore to Version:",
            choices = c("Select version..." = "")
          ),

          shiny::textInput(
            ns("restore_reason"),
            "Restore Reason:",
            placeholder = "Required for audit trail"
          ),

          shiny::actionButton(
            ns("restore_btn"),
            "Restore Version",
            class = "btn-warning",
            width = "100%"
          )
        )
      ),

      shiny::column(
        width = 8,
        shiny::tabsetPanel(
          id = ns("version_tabs"),

          shiny::tabPanel(
            "Version History",
            shiny::br(),
            DT::dataTableOutput(ns("history_table"))
          ),

          shiny::tabPanel(
            "Version Details",
            shiny::br(),
            shiny::verbatimTextOutput(ns("version_details"))
          ),

          shiny::tabPanel(
            "Compare",
            shiny::br(),
            shiny::verbatimTextOutput(ns("comparison_output"))
          ),

          shiny::tabPanel(
            "Integrity",
            shiny::br(),
            shiny::actionButton(
              ns("verify_btn"),
              "Verify Chain Integrity",
              class = "btn-info"
            ),
            shiny::br(), shiny::br(),
            shiny::verbatimTextOutput(ns("integrity_output"))
          ),

          shiny::tabPanel(
            "Statistics",
            shiny::br(),
            shiny::fluidRow(
              shiny::column(
                width = 4,
                shiny::wellPanel(
                  shiny::h5("Total Versions"),
                  shiny::textOutput(ns("total_versions"))
                )
              ),
              shiny::column(
                width = 4,
                shiny::wellPanel(
                  shiny::h5("Unique Editors"),
                  shiny::textOutput(ns("unique_editors"))
                )
              ),
              shiny::column(
                width = 4,
                shiny::wellPanel(
                  shiny::h5("First Version"),
                  shiny::textOutput(ns("first_version"))
                )
              )
            ),
            shiny::hr(),
            shiny::h5("Changes by Type"),
            shiny::tableOutput(ns("changes_by_type"))
          )
        )
      )
    )
  )
}


#' Version History Server
#'
#' Server logic for the version history viewer module.
#'
#' @param id Character: Module namespace ID
#' @param db_path Reactive: Database path
#' @param current_user Reactive: Current user ID
#'
#' @return Module server function
#'
#' @export
version_history_server <- function(id, db_path = shiny::reactive(NULL),
                                    current_user = shiny::reactive("system")) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    history_data <- shiny::reactiveVal(data.frame())
    stats_data <- shiny::reactiveVal(list())

    shiny::observe({
      tryCatch({
        conn <- connect_encrypted_db(db_path = db_path())

        tables <- DBI::dbGetQuery(conn, "
          SELECT DISTINCT table_name FROM record_versions
          ORDER BY table_name
        ")

        DBI::dbDisconnect(conn)

        if (nrow(tables) > 0) {
          choices <- c("Select table..." = "", stats::setNames(
            tables$table_name, tables$table_name
          ))
          shiny::updateSelectInput(session, "table_name", choices = choices)
        }
      }, error = function(e) {
        # Silently handle if version control not initialized
      })
    })

    shiny::observeEvent(input$load_history_btn, {
      shiny::req(input$table_name, input$record_id)

      history <- get_version_history(
        table_name = input$table_name,
        record_id = input$record_id,
        include_data = FALSE,
        db_path = db_path()
      )

      history_data(history)

      if (nrow(history) > 0) {
        version_choices <- c("Select version..." = "",
          stats::setNames(history$version_number,
                          paste("v", history$version_number, "-",
                                history$change_type)))

        shiny::updateSelectInput(session, "version_a", choices = version_choices)
        shiny::updateSelectInput(session, "version_b", choices = version_choices)
        shiny::updateSelectInput(session, "restore_version",
                                  choices = version_choices)

        stats <- get_version_statistics(
          table_name = input$table_name,
          record_id = input$record_id,
          db_path = db_path()
        )
        stats_data(stats)
      }
    })

    output$history_table <- DT::renderDataTable({
      data <- history_data()

      if (nrow(data) == 0) {
        return(DT::datatable(
          data.frame(Message = "No version history. Select a record and click Load."),
          options = list(dom = 't')
        ))
      }

      display_cols <- c("version_number", "change_type", "changed_by",
                        "changed_at", "is_current")
      display_cols <- intersect(display_cols, names(data))

      DT::datatable(
        data[, display_cols, drop = FALSE],
        options = list(
          pageLength = 10,
          order = list(list(0, 'desc'))
        ),
        selection = 'single',
        rownames = FALSE
      )
    })

    shiny::observeEvent(input$history_table_rows_selected, {
      data <- history_data()
      shiny::req(nrow(data) > 0)

      selected_row <- input$history_table_rows_selected
      shiny::req(selected_row)

      version_num <- data$version_number[selected_row]

      version_details <- get_record_version(
        table_name = input$table_name,
        record_id = input$record_id,
        version_number = version_num,
        db_path = db_path()
      )

      output$version_details <- shiny::renderPrint({
        if (!version_details$found) {
          cat("Version not found\n")
          return()
        }

        cat("Version Details\n")
        cat("===============\n\n")
        cat("Version Number:", version_details$version_number, "\n")
        cat("Change Type:", version_details$change_type, "\n")
        cat("Changed By:", version_details$changed_by, "\n")
        cat("Changed At:", version_details$changed_at, "\n")
        cat("Reason:", version_details$change_reason, "\n")
        cat("Hash:", substr(version_details$version_hash, 1, 16), "...\n")
        cat("Is Current:", version_details$is_current, "\n")
        cat("\nData Snapshot:\n")
        print(version_details$data)

        if (!is.null(version_details$field_changes) &&
            nrow(version_details$field_changes) > 0) {
          cat("\nField Changes:\n")
          print(version_details$field_changes)
        }
      })
    })

    shiny::observeEvent(input$compare_btn, {
      shiny::req(input$version_a, input$version_b)
      shiny::req(input$version_a != "", input$version_b != "")

      summary <- get_version_diff_summary(
        table_name = input$table_name,
        record_id = input$record_id,
        version_a = as.integer(input$version_a),
        version_b = as.integer(input$version_b),
        db_path = db_path()
      )

      output$comparison_output <- shiny::renderPrint({
        cat("Version Comparison\n")
        cat("==================\n\n")
        cat(paste(summary, collapse = "\n"))
      })

      shiny::updateTabsetPanel(session, "version_tabs", selected = "Compare")
    })

    shiny::observeEvent(input$restore_btn, {
      shiny::req(input$restore_version, input$restore_reason)
      shiny::req(input$restore_version != "")
      shiny::req(nchar(input$restore_reason) > 0)

      result <- restore_record_version(
        table_name = input$table_name,
        record_id = input$record_id,
        version_number = as.integer(input$restore_version),
        restore_reason = input$restore_reason,
        restored_by = current_user(),
        db_path = db_path()
      )

      if (result$success) {
        shiny::showNotification(
          result$message,
          type = "message"
        )

        shinyjs::click("load_history_btn")
      } else {
        shiny::showNotification(
          paste("Restore failed:", result$error),
          type = "error"
        )
      }
    })

    shiny::observeEvent(input$verify_btn, {
      shiny::req(input$table_name, input$record_id)

      result <- verify_version_integrity(
        table_name = input$table_name,
        record_id = input$record_id,
        db_path = db_path()
      )

      output$integrity_output <- shiny::renderPrint({
        cat("Version Chain Integrity Verification\n")
        cat("=====================================\n\n")
        cat("Status:", ifelse(result$valid, "VALID", "FAILED"), "\n")
        cat("Versions Checked:", result$versions_checked, "\n")
        cat("Errors Found:", result$errors_found, "\n\n")
        cat("Message:", result$message, "\n")

        if (length(result$error_details) > 0) {
          cat("\nError Details:\n")
          for (err in result$error_details) {
            cat("  -", err, "\n")
          }
        }
      })
    })

    output$total_versions <- shiny::renderText({
      stats <- stats_data()
      if (length(stats) == 0 || is.null(stats$statistics)) {
        "---"
      } else {
        as.character(stats$statistics$total_versions)
      }
    })

    output$unique_editors <- shiny::renderText({
      stats <- stats_data()
      if (length(stats) == 0 || is.null(stats$statistics)) {
        "---"
      } else {
        as.character(stats$statistics$unique_editors)
      }
    })

    output$first_version <- shiny::renderText({
      stats <- stats_data()
      if (length(stats) == 0 || is.null(stats$statistics)) {
        "---"
      } else {
        as.character(stats$statistics$first_version_at)
      }
    })

    output$changes_by_type <- shiny::renderTable({
      stats <- stats_data()
      if (length(stats) == 0 || is.null(stats$by_change_type)) {
        data.frame(Type = "No data", Count = 0)
      } else {
        stats$by_change_type
      }
    })
  })
}
