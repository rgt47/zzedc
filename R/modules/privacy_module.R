# GDPR Privacy Module
# Implementation of GDPR compliance features for ZZedc

#' Privacy Management Module UI
#'
#' @param id The namespace id for the module
#' @return A tagList containing the privacy management UI
privacy_ui <- function(id) {
  ns <- NS(id)

  tagList(
    # Privacy Notice Banner
    conditionalPanel(
      condition = "true", # Show based on user acceptance status
      div(id = ns("privacy_banner"), class = "alert alert-info privacy-banner",
        div(class = "row align-items-center",
          div(class = "col-md-8",
            h5(bsicons::bs_icon("shield-check"), " Privacy Notice"),
            p("We process your personal data in accordance with GDPR. Please review our privacy policy and consent to continue.")
          ),
          div(class = "col-md-4 text-end",
            actionButton(ns("show_privacy_notice"), "View Privacy Policy", class = "btn btn-outline-primary btn-sm"),
            actionButton(ns("accept_privacy"), "Accept", class = "btn btn-primary btn-sm")
          )
        )
      )
    ),

    # Data Subject Rights Portal
    fluidPage(
      titlePanel("Privacy & Data Management"),

      fluidRow(
        column(4,
          bslib::card(
            bslib::card_header(
              tagList(bsicons::bs_icon("person-check", class = "text-primary"), " Your Rights")
            ),
            bslib::card_body(
              h5("GDPR Data Subject Rights"),
              p("As a data subject, you have the following rights:"),

              div(class = "d-grid gap-2",
                actionButton(ns("request_access"), "Request My Data",
                            class = "btn btn-outline-primary",
                            title = "Article 15 - Right of Access"),
                actionButton(ns("request_correction"), "Correct My Data",
                            class = "btn btn-outline-warning",
                            title = "Article 16 - Right to Rectification"),
                actionButton(ns("request_deletion"), "Delete My Data",
                            class = "btn btn-outline-danger",
                            title = "Article 17 - Right to Erasure"),
                actionButton(ns("export_data"), "Export My Data",
                            class = "btn btn-outline-info",
                            title = "Article 20 - Right to Data Portability")
              )
            )
          )
        ),

        column(4,
          bslib::card(
            bslib::card_header(
              tagList(bsicons::bs_icon("check2-square", class = "text-success"), " Consent Management")
            ),
            bslib::card_body(
              h5("Your Consent Status"),
              uiOutput(ns("consent_status")),
              br(),
              actionButton(ns("manage_consent"), "Manage Consent", class = "btn btn-success"),
              br(), br(),
              actionButton(ns("withdraw_consent"), "Withdraw All Consent", class = "btn btn-outline-danger")
            )
          )
        ),

        column(4,
          bslib::card(
            bslib::card_header(
              tagList(bsicons::bs_icon("file-text", class = "text-info"), " Processing Information")
            ),
            bslib::card_body(
              h5("How We Process Your Data"),
              tags$ul(
                tags$li("Legal Basis: Scientific Research (Article 9(2)(j))"),
                tags$li("Purpose: Clinical trial data collection"),
                tags$li("Retention: 25 years post-study"),
                tags$li("Recipients: Research team only")
              ),
              actionButton(ns("show_full_notice"), "Full Privacy Notice", class = "btn btn-outline-info")
            )
          )
        )
      ),

      # Data Subject Request Forms
      fluidRow(
        column(12,
          uiOutput(ns("request_forms"))
        )
      )
    )
  )
}

#' Privacy Management Module Server
#'
#' @param id The namespace id for the module
#' @param user_id Current user identifier
#' @return Server function for privacy module
privacy_server <- function(id, user_id = NULL) {
  moduleServer(id, function(input, output, session) {

    # Privacy acceptance state
    privacy_accepted <- reactiveVal(FALSE)

    # Load GDPR and dual compliance configuration
    gdpr_config <- reactive({
      if (exists("cfg") && "gdpr" %in% names(cfg)) {
        cfg$gdpr
      } else {
        # Default configuration
        list(
          enabled = TRUE,
          rights = list(
            enable_access = TRUE,
            enable_rectification = TRUE,
            enable_erasure = TRUE,
            enable_portability = TRUE
          ),
          privacy_notice = list(
            show_banner = TRUE,
            require_acknowledgment = TRUE
          )
        )
      }
    })

    # Load dual compliance configuration
    dual_compliance_config <- reactive({
      if (exists("cfg") && "dual_compliance" %in% names(cfg)) {
        cfg$dual_compliance
      } else {
        list(enabled = FALSE)
      }
    })

    # Check if CFR Part 11 is enabled
    cfr_enabled <- reactive({
      exists("cfg") && "cfr_part11" %in% names(cfg) && cfg$cfr_part11$enabled
    })

    # Show privacy notice modal
    observeEvent(input$show_privacy_notice, {
      showModal(
        modalDialog(
          title = tagList(bsicons::bs_icon("shield-check"), " Privacy Notice"),
          size = "l",
          easyClose = FALSE,
          footer = tagList(
            modalButton("Cancel"),
            actionButton("accept_privacy_modal", "Accept & Continue", class = "btn btn-primary")
          ),

          div(
            h4("Data Protection Information"),

            h5("1. Controller Information"),
            p("This clinical trial is conducted by [Your Organization Name]"),
            p("Contact: [Data Protection Officer Email]"),

            h5("2. Legal Basis for Processing"),
            p("We process your personal data based on:"),
            tags$ul(
              tags$li("Article 9(2)(j) GDPR - Scientific research purposes"),
              tags$li("Your explicit consent for special category health data"),
              tags$li("Performance of a task in the public interest")
            ),

            h5("3. Categories of Data Processed"),
            p("We collect and process:"),
            tags$ul(
              tags$li("Demographics: Age, gender, education"),
              tags$li("Health data: Cognitive assessments, medical history"),
              tags$li("Study data: Visit schedules, test scores"),
              tags$li("Technical data: System usage logs (anonymized)")
            ),

            h5("4. Your Rights"),
            p("Under GDPR, you have the right to:"),
            tags$ul(
              tags$li("Access your personal data (Article 15)"),
              tags$li("Rectify inaccurate data (Article 16)"),
              tags$li("Erase your data under certain conditions (Article 17)"),
              tags$li("Data portability (Article 20)"),
              tags$li("Object to processing (Article 21)"),
              tags$li("Withdraw consent at any time")
            ),

            h5("5. Data Retention"),
            p("Your data will be retained for 25 years following study completion to meet regulatory requirements."),

            h5("6. International Transfers"),
            p("Data may be transferred internationally with appropriate safeguards under Chapter V GDPR."),

            h5("7. Contact Information"),
            p("For privacy concerns, contact: [DPO Email Address]"),
            p("Supervisory Authority: [Your National Data Protection Authority]")
          )
        )
      )
    })

    # Accept privacy notice
    observeEvent(input$accept_privacy, {
      privacy_accepted(TRUE)

      # Log consent
      if (exists("db_pool")) {
        record_consent(user_id, "privacy_notice", "accepted")
      }

      # Hide banner
      shinyjs::hide("privacy_banner")

      showNotification("Privacy notice accepted. Thank you for your consent.",
                      type = "success", duration = 3)
    })

    # Consent status display
    output$consent_status <- renderUI({
      if (privacy_accepted()) {
        tagList(
          div(class = "alert alert-success",
            bsicons::bs_icon("check-circle-fill"),
            " Privacy notice accepted"
          ),
          p("Last updated:", format(Sys.time(), "%Y-%m-%d %H:%M"))
        )
      } else {
        div(class = "alert alert-warning",
          bsicons::bs_icon("exclamation-triangle-fill"),
          " Consent pending"
        )
      }
    })

    # Data access request
    observeEvent(input$request_access, {
      showModal(
        modalDialog(
          title = "Data Access Request (Article 15 GDPR)",
          size = "m",

          div(
            h5("Request Your Personal Data"),
            p("We will provide you with a copy of all personal data we process about you."),

            textInput(session$ns("access_email"), "Email address for delivery:",
                     placeholder = "your.email@example.com"),

            checkboxInput(session$ns("access_structured"),
                         "Provide data in structured format (CSV/JSON)", TRUE),

            textAreaInput(session$ns("access_notes"), "Additional requests or specifications:",
                         placeholder = "Optional: Specify particular data categories or time periods")
          ),

          footer = tagList(
            modalButton("Cancel"),
            actionButton(session$ns("submit_access_request"), "Submit Request", class = "btn btn-primary")
          )
        )
      )
    })

    # Submit access request
    observeEvent(input$submit_access_request, {
      # Validate email
      req(input$access_email, input$access_email != "")

      # Log the request
      if (exists("db_pool")) {
        log_data_subject_request(user_id, "access", input$access_email, input$access_notes)
      }

      removeModal()
      showNotification("Data access request submitted. You will receive a response within 30 days.",
                      type = "info", duration = 5)
    })

    # Data correction request
    observeEvent(input$request_correction, {
      showModal(
        modalDialog(
          title = "Data Correction Request (Article 16 GDPR)",
          size = "m",

          div(
            h5("Correct Your Personal Data"),
            p("Please specify which data needs to be corrected and provide the correct information."),

            textAreaInput(session$ns("correction_details"), "Describe the incorrect data:",
                         placeholder = "E.g., My age is recorded as 65 but should be 67"),

            textAreaInput(session$ns("correction_evidence"), "Supporting information:",
                         placeholder = "Optional: Provide evidence or context for the correction")
          ),

          footer = tagList(
            modalButton("Cancel"),
            actionButton(session$ns("submit_correction_request"), "Submit Request", class = "btn btn-warning")
          )
        )
      )
    })

    # Data deletion request with regulatory considerations
    observeEvent(input$request_deletion, {

      # Check for regulatory hold if dual compliance is enabled
      regulatory_warning <- ""
      if (dual_compliance_config()$enabled && cfr_enabled()) {
        regulatory_warning <- div(class = "alert alert-danger",
          h6("🔒 Regulatory Hold Notice"),
          p("This system is subject to FDA 21 CFR Part 11 requirements."),
          p("Some clinical trial data cannot be deleted due to regulatory obligations."),
          p("Affected data may be anonymized instead of deleted.")
        )
      }

      showModal(
        modalDialog(
          title = "Data Deletion Request (Article 17 GDPR)",
          size = "l",

          div(
            h5("⚠️ Request Data Deletion"),
            div(class = "alert alert-warning",
              p("WARNING: Deleting your data from an ongoing clinical trial may:"),
              tags$ul(
                tags$li("Affect the scientific validity of the study"),
                tags$li("Be restricted by regulatory requirements"),
                tags$li("Not be fully possible until study completion")
              )
            ),

            # Show regulatory warning if applicable
            regulatory_warning,

            selectInput(session$ns("deletion_reason"), "Reason for deletion request:",
                       choices = list(
                         "Withdraw from study" = "withdrawal",
                         "No longer necessary for study" = "purpose_fulfilled",
                         "Unlawful processing" = "unlawful",
                         "Legal obligation" = "legal_obligation",
                         "Other" = "other"
                       )),

            conditionalPanel(
              condition = "input.deletion_reason == 'other'",
              textAreaInput(session$ns("deletion_other_reason"), "Please specify:")
            ),

            # Dual compliance options
            if (dual_compliance_config()$enabled) {
              div(
                h6("Regulatory Compliance Options:"),
                checkboxInput(session$ns("accept_anonymization"),
                             "I accept anonymization instead of deletion for regulatory-required data",
                             value = FALSE),
                checkboxInput(session$ns("request_regulatory_review"),
                             "Request regulatory review for potential deletion",
                             value = FALSE)
              )
            }
          ),

          footer = tagList(
            modalButton("Cancel"),
            actionButton(session$ns("submit_deletion_request"), "Submit Request", class = "btn btn-danger")
          )
        )
      )
    })

    # Data export (portability)
    observeEvent(input$export_data, {
      showModal(
        modalDialog(
          title = "Data Export Request (Article 20 GDPR)",
          size = "m",

          div(
            h5("Export Your Personal Data"),
            p("We will provide your data in a structured, machine-readable format."),

            checkboxGroupInput(session$ns("export_categories"), "Data categories to export:",
                              choices = list(
                                "Demographics" = "demographics",
                                "Clinical assessments" = "assessments",
                                "Visit schedule" = "visits",
                                "Consent records" = "consent"
                              ),
                              selected = c("demographics", "assessments")),

            radioButtons(session$ns("export_format"), "Export format:",
                        choices = list(
                          "CSV (Comma-separated values)" = "csv",
                          "JSON (JavaScript Object Notation)" = "json",
                          "PDF Report" = "pdf"
                        ),
                        selected = "csv")
          ),

          footer = tagList(
            modalButton("Cancel"),
            actionButton(session$ns("submit_export_request"), "Export Data", class = "btn btn-info")
          )
        )
      )
    })

    # Consent withdrawal
    observeEvent(input$withdraw_consent, {
      showModal(
        modalDialog(
          title = "⚠️ Withdraw Consent",
          size = "m",

          div(
            div(class = "alert alert-danger",
              h5("Important Notice"),
              p("Withdrawing consent will:"),
              tags$ul(
                tags$li("Stop further data processing"),
                tags$li("May require withdrawal from the study"),
                tags$li("Will not affect data processed before withdrawal")
              )
            ),

            p("Are you sure you want to withdraw all consent for data processing?")
          ),

          footer = tagList(
            modalButton("Cancel"),
            actionButton(session$ns("confirm_withdrawal"), "Withdraw Consent", class = "btn btn-danger")
          )
        )
      )
    })

    # Helper functions for database operations
    record_consent <- function(user_id, consent_type, status) {
      tryCatch({
        pool::dbExecute(db_pool, "
          INSERT INTO consent_log (user_id, consent_type, status, timestamp, ip_address)
          VALUES (?, ?, ?, ?, ?)
        ", params = list(user_id, consent_type, status, Sys.time(), session$clientData$url_hostname))
      }, error = function(e) {
        warning("Failed to record consent: ", e$message)
      })
    }

    log_data_subject_request <- function(user_id, request_type, contact_email, notes) {
      tryCatch({
        # Check for regulatory hold if dual compliance is enabled
        regulatory_notes <- ""
        if (dual_compliance_config()$enabled && cfr_enabled() && request_type == "erasure") {
          regulatory_notes <- paste(notes, "[REGULATORY REVIEW REQUIRED - CFR Part 11]")
        }

        pool::dbExecute(db_pool, "
          INSERT INTO data_subject_requests (user_id, request_type, contact_email, request_description,
                                           status, created_date, priority)
          VALUES (?, ?, ?, ?, ?, ?, ?)
        ", params = list(
          user_id,
          request_type,
          contact_email,
          regulatory_notes,
          if (request_type == "erasure" && dual_compliance_config()$enabled) "in_progress" else "pending",
          Sys.time(),
          if (request_type == "erasure" && dual_compliance_config()$enabled) "high" else "normal"
        ))

        # Log in enhanced audit trail if CFR Part 11 is enabled
        if (cfr_enabled() && exists("log_audit_event")) {
          log_audit_event(
            event_type = "data_subject_request",
            user_id = user_id,
            reason = paste("GDPR", request_type, "request submitted"),
            db_connection = db_pool
          )
        }

      }, error = function(e) {
        warning("Failed to log data subject request: ", e$message)
      })
    }

    # Enhanced consent recording with CFR Part 11 integration
    record_consent_enhanced <- function(user_id, consent_type, status) {
      tryCatch({
        # Standard GDPR consent logging
        pool::dbExecute(db_pool, "
          INSERT INTO consent_log (user_id, consent_type, status, timestamp, ip_address)
          VALUES (?, ?, ?, ?, ?)
        ", params = list(user_id, consent_type, status, Sys.time(), session$clientData$url_hostname))

        # If CFR Part 11 is enabled, also create an audit trail entry
        if (cfr_enabled() && exists("log_audit_event")) {
          log_audit_event(
            event_type = "consent_change",
            user_id = user_id,
            reason = paste("GDPR consent", status, "for", consent_type),
            db_connection = db_pool
          )
        }

        # If this is consent withdrawal and dual compliance is enabled, check for regulatory impact
        if (status == "withdrawn" && dual_compliance_config()$enabled && cfr_enabled()) {
          # Create a regulatory review task
          pool::dbExecute(db_pool, "
            INSERT INTO data_subject_requests (user_id, request_type, request_description,
                                             status, created_date, priority)
            VALUES (?, 'consent_withdrawal_review', ?, 'pending', ?, 'high')
          ", params = list(
            user_id,
            paste("Consent withdrawal with regulatory impact assessment required for CFR Part 11 compliance"),
            Sys.time()
          ))
        }

      }, error = function(e) {
        warning("Failed to record enhanced consent: ", e$message)
      })
    }

    # Return public functions
    list(
      privacy_accepted = privacy_accepted,
      show_privacy_notice = function() {
        shinyjs::show("privacy_banner")
      }
    )
  })
}
