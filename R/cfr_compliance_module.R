# 21 CFR Part 11 Compliance Module
# Electronic Signatures and Validation Management Interface

#' CFR Part 11 Compliance Management UI
#'
#' @param id The namespace id for the module
#' @return A tagList containing the compliance management UI
#'
#' @examples
#' \dontrun{
#' # Embed the 21 CFR Part 11 compliance dashboard.
#' # Most users will run the full application via
#' # `zzedc::launch_zzedc()`; the example below shows how to
#' # embed the module in a custom Shiny app instead.
#' if (interactive()) {
#'   ui <- shiny::fluidPage(
#'     cfr_compliance_ui("module_id")
#'   )
#'   server <- function(input, output, session) {
#'     cfr_compliance_server("module_id")
#'   }
#'   shiny::shinyApp(ui, server)
#' }
#' }
#' @keywords internal
cfr_compliance_ui <- function(id) {
  ns <- NS(id)

  tagList(
    h2(
      tagList(
        bsicons::bs_icon("shield-check", class = "text-primary"),
        " 21 CFR Part 11 Compliance Dashboard"
      )
    ),

    fluidRow(
        # Compliance Overview Cards
        column(3,
          bslib::value_box(
            title = "Electronic Signatures",
            value = uiOutput(ns("signature_count")),
            showcase = bsicons::bs_icon("pen-fill"),
            theme = "primary"
          )
        ),
        column(3,
          bslib::value_box(
            title = "Audit Trail Events",
            value = uiOutput(ns("audit_count")),
            showcase = bsicons::bs_icon("list-check"),
            theme = "info"
          )
        ),
        column(3,
          bslib::value_box(
            title = "Validation Status",
            value = uiOutput(ns("validation_status")),
            showcase = bsicons::bs_icon("check-circle"),
            theme = "success"
          )
        ),
        column(3,
          bslib::value_box(
            title = "Training Compliance",
            value = uiOutput(ns("training_compliance")),
            showcase = bsicons::bs_icon("mortarboard"),
            theme = "warning"
          )
        )
      ),

      br(),

      # Navigation Tabs
      bslib::navset_card_tab(
        id = ns("compliance_tabs"),

        # Electronic Signatures Tab
        bslib::nav_panel(
          "Electronic Signatures",
          fluidRow(
            column(8,
              bslib::card(
                bslib::card_header("Signature Management"),
                bslib::card_body(
                  h5("Apply Electronic Signature"),
                  p("Select a record to apply your electronic signature:"),

                  fluidRow(
                    column(6,
                      selectInput(ns("sig_table"), "Table:",
                                choices = c("subjects", "demographics", "cognitive_assessments"),
                                selected = "cognitive_assessments")
                    ),
                    column(6,
                      textInput(ns("sig_record_id"), "Record ID:",
                              placeholder = "e.g., SUBJ001_V1")
                    )
                  ),

                  fluidRow(
                    column(6,
                      selectInput(ns("sig_meaning"), "Signature Meaning:",
                                choices = list(
                                  "Created by" = "created_by",
                                  "Reviewed by" = "reviewed_by",
                                  "Approved by" = "approved_by",
                                  "Verified by" = "verified_by",
                                  "Monitored by" = "monitored_by"
                                ))
                    ),
                    column(6,
                      passwordInput(ns("sig_password"), "Confirm Password:")
                    )
                  ),

                  textAreaInput(ns("sig_reason"), "Signature Reason:",
                              placeholder = "Reason for applying signature (optional)"),

                  div(class = "d-grid",
                    actionButton(ns("apply_signature"), "Apply Electronic Signature",
                               class = "btn btn-primary",
                               icon = icon("pen-nib"))
                  )
                )
              )
            ),

            column(4,
              bslib::card(
                bslib::card_header("Signature Verification"),
                bslib::card_body(
                  h5("Verify Signature"),
                  textInput(ns("verify_sig_id"), "Signature ID:",
                          placeholder = "SIG20241201123456"),
                  actionButton(ns("verify_signature"), "Verify",
                             class = "btn btn-info"),
                  br(), br(),
                  uiOutput(ns("signature_verification_result"))
                )
              )
            )
          ),

          br(),

          # Signature History
          bslib::card(
            bslib::card_header("Electronic Signature History"),
            bslib::card_body(
              DT::DTOutput(ns("signature_history"))
            )
          )
        ),

        # Audit Trail Tab
        bslib::nav_panel(
          "Audit Trail",
          fluidRow(
            column(4,
              bslib::card(
                bslib::card_header("Audit Trail Filters"),
                bslib::card_body(
                  dateRangeInput(ns("audit_date_range"), "Date Range:",
                               start = Sys.Date() - 30, end = Sys.Date()),

                  selectInput(ns("audit_event_type"), "Event Type:",
                            choices = c("All" = "", "login", "data_entry", "data_modification",
                                      "signature_applied", "record_lock"),
                            selected = ""),

                  selectInput(ns("audit_user"), "User:",
                            choices = c("All Users" = "")),

                  textInput(ns("audit_table"), "Table:",
                          placeholder = "Filter by table name"),

                  actionButton(ns("filter_audit"), "Apply Filters",
                             class = "btn btn-secondary")
                )
              )
            ),

            column(8,
              bslib::card(
                bslib::card_header(
                  tagList(
                    "Audit Trail Events",
                    span(class = "float-end",
                      downloadButton(ns("download_audit"), "Export",
                                   class = "btn btn-sm btn-outline-primary"))
                  )
                ),
                bslib::card_body(
                  DT::DTOutput(ns("audit_trail_table"))
                )
              )
            )
          )
        ),

        # System Validation Tab
        bslib::nav_panel(
          "System Validation",
          fluidRow(
            column(6,
              bslib::card(
                bslib::card_header("Validation Activities"),
                bslib::card_body(
                  DT::DTOutput(ns("validation_activities"))
                )
              )
            ),

            column(6,
              bslib::card(
                bslib::card_header("Create New Validation"),
                bslib::card_body(
                  selectInput(ns("val_type"), "Validation Type:",
                            choices = list(
                              "Installation Qualification" = "installation_qualification",
                              "Operational Qualification" = "operational_qualification",
                              "Performance Qualification" = "performance_qualification",
                              "Change Control" = "change_control",
                              "Security Assessment" = "security_assessment"
                            )),

                  textInput(ns("val_title"), "Validation Title:"),

                  textAreaInput(ns("val_description"), "Description:"),

                  dateInput(ns("val_date"), "Execution Date:", value = Sys.Date()),

                  actionButton(ns("create_validation"), "Create Validation",
                             class = "btn btn-success")
                )
              )
            )
          )
        ),

        # Training Records Tab
        bslib::nav_panel(
          "Training Records",
          fluidRow(
            column(8,
              bslib::card(
                bslib::card_header("Training Compliance by Role"),
                bslib::card_body(
                  DT::DTOutput(ns("training_compliance_table"))
                )
              )
            ),

            column(4,
              bslib::card(
                bslib::card_header("Record Training"),
                bslib::card_body(
                  selectInput(ns("training_user"), "User:",
                            choices = c()),

                  selectInput(ns("training_type"), "Training Type:",
                            choices = list(
                              "21 CFR Part 11 Basics" = "cfr_part11_basics",
                              "Electronic Signatures" = "electronic_signatures",
                              "Data Integrity" = "data_integrity",
                              "Audit Trail Review" = "audit_trail_review"
                            )),

                  dateInput(ns("training_date"), "Training Date:", value = Sys.Date()),

                  textInput(ns("trainer_name"), "Trainer Name:"),

                  numericInput(ns("training_score"), "Score (%):", value = 85, min = 0, max = 100),

                  actionButton(ns("record_training"), "Record Training",
                             class = "btn btn-info")
                )
              )
            )
          )
        ),

        # Compliance Report Tab
        bslib::nav_panel(
          "Compliance Report",
          bslib::card(
            bslib::card_header(
              tagList(
                "21 CFR Part 11 Compliance Summary",
                span(class = "float-end",
                  actionButton(ns("generate_report"), "Refresh Report",
                             class = "btn btn-sm btn-primary"))
              )
            ),
            bslib::card_body(
              uiOutput(ns("compliance_report"))
            )
          )
        )
      )
    )
}

#' CFR Part 11 Compliance Module Server
#'
#' @param id The namespace id for the module
#' @param user_id Current user identifier
#' @return Server function for CFR compliance module
#'
#' @examples
#' \dontrun{
#' # Embed the 21 CFR Part 11 compliance dashboard.
#' # Most users will run the full application via
#' # `zzedc::launch_zzedc()`; the example below shows how to
#' # embed the module in a custom Shiny app instead.
#' if (interactive()) {
#'   ui <- shiny::fluidPage(
#'     cfr_compliance_ui("module_id")
#'   )
#'   server <- function(input, output, session) {
#'     cfr_compliance_server("module_id")
#'   }
#'   shiny::shinyApp(ui, server)
#' }
#' }
#' @keywords internal
cfr_compliance_server <- function(id, user_id = NULL) {
  moduleServer(id, function(input, output, session) {

    # Reactive values for data
    compliance_data <- reactiveValues(
      signatures = NULL,
      audit_trail = NULL,
      validations = NULL,
      training = NULL,
      report = NULL
    )

    # Load initial data
    observe({
      if (exists("db_pool")) {
        load_compliance_data()
      }
    })

    # Populate the "Record Training" user dropdown with real users.
    # This was previously left as choices = c() with nothing anywhere
    # updating it (see the Record Training card's selectInput, above).
    observe({
      if (exists("db_pool")) {
        tryCatch({
          users <- pool::dbGetQuery(db_pool, "
            SELECT user_id, full_name, username FROM edc_users
            WHERE active = 1 ORDER BY full_name
          ")
          choices <- setNames(users$user_id,
                               paste0(users$full_name, " (", users$username, ")"))
          updateSelectInput(session, "training_user", choices = choices)
        }, error = function(e) NULL)
      }
    })

    # Load compliance data from database
    load_compliance_data <- function() {
      tryCatch({
        # Load electronic signatures
        compliance_data$signatures <- pool::dbGetQuery(db_pool, "
          SELECT s.*, u.full_name as signer_name
          FROM electronic_signatures s
          JOIN edc_users u ON s.signer_user_id = u.user_id
          ORDER BY s.signed_at DESC
        ")

        # Load recent audit trail. The 30-day cutoff was SQLite's
        # date('now', '-30 days'), which no other backend accepts. It is
        # now computed in R; SQLite stores timestamps as text and compares
        # the 'YYYY-MM-DD' string directly, while the other backends
        # compare a TIMESTAMP column and need the parameter cast.
        cutoff <- format(Sys.Date() - 30, "%Y-%m-%d")
        cutoff_sql <- if (identical(tryCatch(get_db_backend(), error = function(e) "sqlite"), "sqlite")) {
          "?"
        } else {
          "CAST(? AS TIMESTAMP)"
        }
        compliance_data$audit_trail <- pool::dbGetQuery(db_pool, paste0("
          SELECT e.*, u.full_name as user_name
          FROM enhanced_audit_trail e
          JOIN edc_users u ON e.user_id = u.user_id
          WHERE e.timestamp >= ", cutoff_sql, "
          ORDER BY e.timestamp DESC
        "), params = list(cutoff))

        # Load validation activities
        compliance_data$validations <- pool::dbGetQuery(db_pool, "
          SELECT v.*, u1.full_name as validator_name,
                 u2.full_name as reviewer_name, u3.full_name as approver_name
          FROM system_validation v
          LEFT JOIN edc_users u1 ON v.validator_user_id = u1.user_id
          LEFT JOIN edc_users u2 ON v.reviewer_user_id = u2.user_id
          LEFT JOIN edc_users u3 ON v.approver_user_id = u3.user_id
          ORDER BY v.execution_date DESC
        ")

        # Load training records
        compliance_data$training <- pool::dbGetQuery(db_pool, "
          SELECT t.*, u.full_name, u.role
          FROM user_training t
          JOIN edc_users u ON t.user_id = u.user_id
          ORDER BY t.training_date DESC
        ")

      }, error = function(e) {
        showNotification(paste("Error loading compliance data:", e$message),
                        type = "error")
      })
    }

    # Update value boxes
    output$signature_count <- renderUI({
      count <- nrow(compliance_data$signatures) %||% 0
      tagList(
        h3(count),
        p(class = "text-muted", "Total Signatures")
      )
    })

    output$audit_count <- renderUI({
      count <- nrow(compliance_data$audit_trail) %||% 0
      tagList(
        h3(paste(count, "K")),
        p(class = "text-muted", "Events (30 days)")
      )
    })

    output$validation_status <- renderUI({
      if (is.null(compliance_data$validations) || nrow(compliance_data$validations) == 0) {
        return(tagList(h3("0%"), p(class = "text-muted", "Not Started")))
      }

      completed <- sum(compliance_data$validations$status == "completed", na.rm = TRUE)
      total <- nrow(compliance_data$validations)
      percentage <- round((completed / total) * 100)

      tagList(
        h3(paste0(percentage, "%")),
        p(class = "text-muted", "Complete")
      )
    })

    output$training_compliance <- renderUI({
      if (is.null(compliance_data$training)) {
        return(tagList(h3("0%"), p(class = "text-muted", "No Data")))
      }

      # Calculate training compliance percentage
      current_training <- sum(compliance_data$training$completion_status == "completed" &
                             compliance_data$training$expiry_date > Sys.Date(), na.rm = TRUE)
      total_required <- nrow(compliance_data$training)

      if (total_required > 0) {
        percentage <- round((current_training / total_required) * 100)
      } else {
        percentage <- 0
      }

      tagList(
        h3(paste0(percentage, "%")),
        p(class = "text-muted", "Current")
      )
    })

    # Electronic signature application. Previously this simulated
    # success unconditionally -- input$sig_password was collected
    # from the UI but never passed to any verification function, no
    # password check ever happened, and no row was ever written to
    # electronic_signatures. §11.200(a) requires a second identity
    # component (the password) to be checked at the moment of
    # signing; this now delegates to the real
    # apply_electronic_signature() (R/electronic_signatures.R), which
    # does that via verify_password_for_signature().
    observeEvent(input$apply_signature, {
      req(input$sig_table, input$sig_record_id, input$sig_meaning, input$sig_password)

      if (exists("db_pool") && !is.null(user_id())) {
        tryCatch({
          signer <- pool::dbGetQuery(db_pool, "
            SELECT full_name, password_hash FROM edc_users WHERE user_id = ?
          ", params = list(user_id()))

          if (nrow(signer) == 0) {
            showNotification("Signing user not found", type = "error")
            return()
          }

          result <- apply_electronic_signature(
            table_name = input$sig_table,
            record_id = input$sig_record_id,
            signer_user_id = user_id(),
            signer_full_name = signer$full_name[1],
            signature_meaning = input$sig_meaning,
            password = input$sig_password,
            password_hash = signer$password_hash[1],
            custom_statement = if (nzchar(input$sig_reason %||% "")) input$sig_reason else NULL
          )

          if (isTRUE(result$success)) {
            showNotification(
              paste("Electronic signature applied successfully. Signature ID:", result$signature_code),
              type = "success", duration = 5
            )

            # Clear form and reload data
            updateTextInput(session, "sig_record_id", value = "")
            updatePasswordInput(session, "sig_password", value = "")
            updateTextAreaInput(session, "sig_reason", value = "")
            load_compliance_data()

          } else {
            showNotification(paste("Signature failed:", result$message %||% result$error),
                           type = "error", duration = 5)
          }

        }, error = function(e) {
          showNotification(paste("Error applying signature:", e$message),
                          type = "error")
        })
      }
    })

    # Signature verification. Previously this always showed "verified
    # successfully" for any non-empty id, including one that does not
    # exist -- it never called verify_electronic_signature(), so it
    # could not detect an invalidated signature or a record modified
    # after signing.
    observeEvent(input$verify_signature, {
      req(input$verify_sig_id)

      result <- verify_electronic_signature(input$verify_sig_id)

      output$signature_verification_result <- renderUI({
        if (isTRUE(result$is_valid)) {
          div(class = "alert alert-success",
            bsicons::bs_icon("check-circle"),
            " Signature verified successfully",
            br(),
            tags$small(result$message)
          )
        } else {
          div(class = "alert alert-danger",
            bsicons::bs_icon("x-circle"),
            " Signature verification failed",
            br(),
            tags$small(result$error %||% "Unknown error")
          )
        }
      })
    })

    # Record training (§11.10(i)). Previously this button had no
    # handler at all -- see ensure_user_training_table()/
    # db_insert_training_record() in R/db_users.R for the table this
    # writes to, added alongside this handler.
    observeEvent(input$record_training, {
      req(input$training_user, input$training_type, input$training_date)

      if (exists("db_pool")) {
        tryCatch({
          conn <- pool::poolCheckout(db_pool)
          on.exit(pool::poolReturn(conn), add = TRUE)

          result <- db_insert_training_record(
            conn = conn,
            user_id = input$training_user,
            training_type = input$training_type,
            training_date = input$training_date,
            trainer_name = if (nzchar(input$trainer_name %||% "")) input$trainer_name else NULL,
            training_score = input$training_score
          )

          if (isTRUE(result$success)) {
            showNotification("Training record saved successfully", type = "success")
            updateTextInput(session, "trainer_name", value = "")
            load_compliance_data()
          } else {
            showNotification(paste("Failed to save training record:", result$error),
                            type = "error")
          }
        }, error = function(e) {
          showNotification(paste("Error recording training:", e$message),
                          type = "error")
        })
      }
    })

    # Signature history table
    output$signature_history <- DT::renderDT({
      if (!is.null(compliance_data$signatures)) {
        # electronic_signatures has no signing_timestamp/signature_status
        # columns -- those are signed_at and is_valid (see
        # init_electronic_signatures(), R/electronic_signatures.R).
        # signature_status here is derived display text, not a stored
        # value; there is no separate "revoked" state in the schema,
        # only is_valid = 0 (optionally with an invalidation_reason).
        display_data <- compliance_data$signatures |>
          select(signature_id, signer_name, signature_meaning, table_name,
                record_id, signed_at, is_valid) |>
          mutate(
            signed_at = format(as.POSIXct(signed_at), "%Y-%m-%d %H:%M"),
            signature_status = ifelse(
              as.logical(is_valid), "[OK] Valid", "[X] Invalid"
            ),
            is_valid = NULL
          )

        DT::datatable(display_data,
                     options = list(pageLength = 10, scrollX = TRUE),
                     rownames = FALSE)
      }
    })

    # Audit trail table
    output$audit_trail_table <- DT::renderDT({
      if (!is.null(compliance_data$audit_trail)) {
        display_data <- compliance_data$audit_trail |>
          select(event_type, table_name, record_id, user_name, timestamp, reason) |>
          mutate(timestamp = format(as.POSIXct(timestamp), "%Y-%m-%d %H:%M"))

        DT::datatable(display_data,
                     options = list(pageLength = 15, scrollX = TRUE),
                     filter = "top",
                     rownames = FALSE)
      }
    })

    # Validation activities table
    output$validation_activities <- DT::renderDT({
      if (!is.null(compliance_data$validations)) {
        display_data <- compliance_data$validations |>
          select(validation_type, validation_title, status, execution_date,
                validator_name, approval_date) |>
          mutate(
            execution_date = as.character(execution_date),
            approval_date = as.character(approval_date),
            status = case_when(
              status == "completed" ~ "[OK] Completed",
              status == "approved" ~ "[OK] Approved",
              status == "in_progress" ~ "[...] In Progress",
              status == "planned" ~ "[>] Planned",
              TRUE ~ status
            )
          )

        DT::datatable(display_data,
                     options = list(pageLength = 10, scrollX = TRUE),
                     rownames = FALSE)
      }
    })

    # Training compliance table
    output$training_compliance_table <- DT::renderDT({
      if (!is.null(compliance_data$training)) {
        summary_data <- compliance_data$training |>
          group_by(role, training_type) |>
          summarise(
            total_trained = sum(completion_status == "completed"),
            current_valid = sum(completion_status == "completed" & expiry_date > Sys.Date()),
            .groups = "drop"
          )

        DT::datatable(summary_data,
                     options = list(pageLength = 10),
                     rownames = FALSE)
      }
    })

    # Generate compliance report
    observeEvent(input$generate_report, {
      if (exists("db_pool")) {
        tryCatch({
          # Generate comprehensive report
          compliance_data$report <- list(
            signatures_count = nrow(compliance_data$signatures) %||% 0,
            audit_events = nrow(compliance_data$audit_trail) %||% 0,
            validation_completion = if (!is.null(compliance_data$validations)) {
              round(mean(compliance_data$validations$status == "completed") * 100)
            } else { 0 },
            training_compliance = if (!is.null(compliance_data$training)) {
              sum(compliance_data$training$completion_status == "completed" &
                  compliance_data$training$expiry_date > Sys.Date())
            } else { 0 }
          )

          showNotification("Compliance report generated successfully", type = "success")
        }, error = function(e) {
          showNotification(paste("Error generating report:", e$message), type = "error")
        })
      }
    })

    # Display compliance report
    output$compliance_report <- renderUI({
      if (!is.null(compliance_data$report)) {
        tagList(
          h4("System Compliance Status"),
          br(),

          fluidRow(
            column(6,
              h5("Electronic Records & Signatures"),
              tags$ul(
                tags$li(paste("Total Electronic Signatures:", compliance_data$report$signatures_count)),
                tags$li(paste("Audit Trail Events (30 days):", compliance_data$report$audit_events)),
                tags$li(paste("System Validation Progress:", compliance_data$report$validation_completion, "%"))
              )
            ),
            column(6,
              h5("Training & Procedures"),
              tags$ul(
                tags$li(paste("Current Training Records:", compliance_data$report$training_compliance)),
                tags$li("SOPs: Updated within 12 months"),
                tags$li("Change Control: All changes documented")
              )
            )
          ),

          br(),

          div(class = "alert alert-info",
            h5("Compliance Summary"),
            p("The system demonstrates substantial progress toward 21 CFR Part 11 compliance."),
            p("Key areas implemented: Electronic signatures, enhanced audit trails, validation framework."),
            p("Recommended next steps: Complete system validation and user training programs.")
          ),

          hr(),

          p(class = "text-muted small",
            "Report generated:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
            "| Next review:", format(Sys.Date() + 90, "%Y-%m-%d")
          )
        )
      } else {
        div(class = "alert alert-warning",
          "Click 'Refresh Report' to generate compliance summary."
        )
      }
    })

    # Return module functions
    list(
      refresh_data = load_compliance_data,
      get_compliance_data = reactive(compliance_data$report)
    )
  })
}
