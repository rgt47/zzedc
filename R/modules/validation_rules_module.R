#' Validation Rules Management Module
#'
#' Shiny module for managing DSL validation rules with role-based access
#' control and approval workflow.

#' Validation Rules UI
#'
#' @param id Module namespace ID
#'
#' @export
validation_rules_ui <- function(id) {
  ns <- shiny::NS(id)

  bslib::page_fluid(
    shiny::tags$h3("Validation Rules Management"),
    shiny::tags$p(
      class = "text-muted",
      "Define data validation rules using plain English syntax. ",
      "Rules can be imported from Google Sheets or created directly."
    ),

    bslib::navset_card_tab(
      id = ns("rules_tabs"),

      bslib::nav_panel(
        title = "Active Rules",
        icon = bsicons::bs_icon("check-circle"),
        shiny::div(
          class = "mb-3",
          shiny::actionButton(
            ns("refresh_rules"), "Refresh",
            icon = shiny::icon("sync"),
            class = "btn-outline-secondary btn-sm me-2"
          ),
          shiny::downloadButton(
            ns("export_rules"), "Export Rules",
            class = "btn-outline-primary btn-sm"
          )
        ),
        DT::dataTableOutput(ns("active_rules_table"))
      ),

      bslib::nav_panel(
        title = "Pending Approval",
        icon = bsicons::bs_icon("hourglass-split"),
        shiny::uiOutput(ns("pending_approval_ui"))
      ),

      bslib::nav_panel(
        title = "Import from Google Sheets",
        icon = bsicons::bs_icon("cloud-download"),
        shiny::uiOutput(ns("import_ui"))
      ),

      bslib::nav_panel(
        title = "Create Rule",
        icon = bsicons::bs_icon("plus-circle"),
        shiny::uiOutput(ns("create_rule_ui"))
      ),

      bslib::nav_panel(
        title = "Syntax Reference",
        icon = bsicons::bs_icon("book"),
        syntax_reference_ui()
      )
    )
  )
}

#' Syntax Reference UI
#'
#' Displays the DSL syntax reference guide.
#'
#' @keywords internal
syntax_reference_ui <- function() {
  shiny::div(
    class = "p-3",
    shiny::tags$h4("Validation DSL Syntax Reference"),
    shiny::tags$p(
      "Use these patterns to define validation rules in plain English. ",
      "No programming knowledge required."
    ),

    bslib::accordion(
      id = "syntax_accordion",
      open = "range",

      bslib::accordion_panel(
        title = "Range Validation",
        value = "range",
        shiny::tags$table(
          class = "table table-sm",
          shiny::tags$thead(
            shiny::tags$tr(
              shiny::tags$th("Syntax"),
              shiny::tags$th("Meaning"),
              shiny::tags$th("Example")
            )
          ),
          shiny::tags$tbody(
            shiny::tags$tr(
              shiny::tags$td(shiny::tags$code("between X and Y")),
              shiny::tags$td("Value must be between X and Y"),
              shiny::tags$td(shiny::tags$code("between 18 and 65"))
            ),
            shiny::tags$tr(
              shiny::tags$td(shiny::tags$code("X..Y")),
              shiny::tags$td("Shorthand range syntax"),
              shiny::tags$td(shiny::tags$code("1..100"))
            ),
            shiny::tags$tr(
              shiny::tags$td(shiny::tags$code(">= X")),
              shiny::tags$td("Greater than or equal to X"),
              shiny::tags$td(shiny::tags$code(">= 0"))
            ),
            shiny::tags$tr(
              shiny::tags$td(shiny::tags$code("<= X")),
              shiny::tags$td("Less than or equal to X"),
              shiny::tags$td(shiny::tags$code("<= 200"))
            )
          )
        )
      ),

      bslib::accordion_panel(
        title = "Value Matching",
        value = "matching",
        shiny::tags$table(
          class = "table table-sm",
          shiny::tags$thead(
            shiny::tags$tr(
              shiny::tags$th("Syntax"),
              shiny::tags$th("Meaning"),
              shiny::tags$th("Example")
            )
          ),
          shiny::tags$tbody(
            shiny::tags$tr(
              shiny::tags$td(shiny::tags$code("== 'value'")),
              shiny::tags$td("Must equal the value"),
              shiny::tags$td(shiny::tags$code("== 'Female'"))
            ),
            shiny::tags$tr(
              shiny::tags$td(shiny::tags$code("!= 'value'")),
              shiny::tags$td("Must not equal the value"),
              shiny::tags$td(shiny::tags$code("!= 'Unknown'"))
            ),
            shiny::tags$tr(
              shiny::tags$td(shiny::tags$code("in('a', 'b', 'c')")),
              shiny::tags$td("Must be one of listed values"),
              shiny::tags$td(shiny::tags$code("in('Yes', 'No', 'N/A')"))
            ),
            shiny::tags$tr(
              shiny::tags$td(shiny::tags$code("not in('x', 'y')")),
              shiny::tags$td("Must not be any listed value"),
              shiny::tags$td(shiny::tags$code("not in('Missing', 'Unknown')"))
            )
          )
        )
      ),

      bslib::accordion_panel(
        title = "Conditional Logic",
        value = "conditional",
        shiny::tags$table(
          class = "table table-sm",
          shiny::tags$thead(
            shiny::tags$tr(
              shiny::tags$th("Syntax"),
              shiny::tags$th("Meaning"),
              shiny::tags$th("Example")
            )
          ),
          shiny::tags$tbody(
            shiny::tags$tr(
              shiny::tags$td(shiny::tags$code("if COND then RULE endif")),
              shiny::tags$td("Apply rule only when condition is true"),
              shiny::tags$td(shiny::tags$code("if age >= 18 then consent required endif"))
            ),
            shiny::tags$tr(
              shiny::tags$td(shiny::tags$code("if COND then RULE else RULE endif")),
              shiny::tags$td("Different rules for true/false"),
              shiny::tags$td(shiny::tags$code("if sex == 'Female' then pregnant in('Yes','No') else pregnant == 'N/A' endif"))
            ),
            shiny::tags$tr(
              shiny::tags$td(shiny::tags$code("RULE and RULE")),
              shiny::tags$td("Both rules must pass"),
              shiny::tags$td(shiny::tags$code(">= 0 and <= 100"))
            ),
            shiny::tags$tr(
              shiny::tags$td(shiny::tags$code("RULE or RULE")),
              shiny::tags$td("At least one rule must pass"),
              shiny::tags$td(shiny::tags$code("== 'Yes' or == 'No'"))
            )
          )
        )
      ),

      bslib::accordion_panel(
        title = "Date Validation",
        value = "dates",
        shiny::tags$table(
          class = "table table-sm",
          shiny::tags$thead(
            shiny::tags$tr(
              shiny::tags$th("Syntax"),
              shiny::tags$th("Meaning"),
              shiny::tags$th("Example")
            )
          ),
          shiny::tags$tbody(
            shiny::tags$tr(
              shiny::tags$td(shiny::tags$code("within N days of FIELD")),
              shiny::tags$td("Date within N days of another date"),
              shiny::tags$td(shiny::tags$code("visit_date within 7 days of scheduled_date"))
            ),
            shiny::tags$tr(
              shiny::tags$td(shiny::tags$code("<= today")),
              shiny::tags$td("Date must be today or earlier"),
              shiny::tags$td(shiny::tags$code("birth_date <= today"))
            ),
            shiny::tags$tr(
              shiny::tags$td(shiny::tags$code(">= today")),
              shiny::tags$td("Date must be today or later"),
              shiny::tags$td(shiny::tags$code("appointment_date >= today"))
            )
          )
        )
      ),

      bslib::accordion_panel(
        title = "Cross-Visit Validation (Batch QC)",
        value = "crossvisit",
        shiny::tags$table(
          class = "table table-sm",
          shiny::tags$thead(
            shiny::tags$tr(
              shiny::tags$th("Syntax"),
              shiny::tags$th("Meaning"),
              shiny::tags$th("Example")
            )
          ),
          shiny::tags$tbody(
            shiny::tags$tr(
              shiny::tags$td(shiny::tags$code("within N% of FIELD")),
              shiny::tags$td("Value within N% of another value"),
              shiny::tags$td(shiny::tags$code("weight within 10% of baseline_weight"))
            ),
            shiny::tags$tr(
              shiny::tags$td(shiny::tags$code("within N% of previous_FIELD")),
              shiny::tags$td("Compare to previous visit"),
              shiny::tags$td(shiny::tags$code("weight within 10% of previous_weight"))
            )
          )
        )
      )
    )
  )
}

#' Validation Rules Server
#'
#' @param id Module namespace ID
#' @param user_info Reactive containing user information
#'
#' @export
validation_rules_server <- function(id, user_info) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    permissions <- shiny::reactive({
      req(user_info())
      get_user_dsl_permissions(user_info()$role)
    })

    rules_data <- shiny::reactiveVal(NULL)

    load_rules <- function() {
      tryCatch({
        rules <- get_all_dsl_rules(include_inactive = TRUE, include_pending = TRUE)
        rules_data(rules)
      }, error = function(e) {
        shiny::showNotification(
          paste("Error loading rules:", e$message),
          type = "error"
        )
      })
    }

    shiny::observe({
      load_rules()
    })

    shiny::observeEvent(input$refresh_rules, {
      load_rules()
      shiny::showNotification("Rules refreshed", type = "message")
    })

    output$active_rules_table <- DT::renderDataTable({
      rules <- rules_data()
      if (is.null(rules) || nrow(rules) == 0) {
        return(DT::datatable(
          data.frame(Message = "No validation rules defined"),
          options = list(dom = 't')
        ))
      }

      active_rules <- rules[rules$is_active == 1, ]

      display_df <- data.frame(
        ID = active_rules$rule_id,
        Field = active_rules$field_code,
        Form = ifelse(is.na(active_rules$form_code), "All", active_rules$form_code),
        Rule = active_rules$rule_dsl,
        Severity = active_rules$severity,
        Category = active_rules$rule_category,
        stringsAsFactors = FALSE
      )

      DT::datatable(
        display_df,
        selection = "single",
        options = list(
          pageLength = 15,
          order = list(list(2, 'asc'), list(1, 'asc'))
        ),
        class = "table table-striped table-hover"
      ) |>
        DT::formatStyle(
          "Severity",
          backgroundColor = DT::styleEqual(
            c("ERROR", "WARNING", "INFO"),
            c("#f8d7da", "#fff3cd", "#d1ecf1")
          )
        )
    })

    output$pending_approval_ui <- shiny::renderUI({
      perms <- permissions()
      rules <- rules_data()

      if (is.null(rules)) {
        return(shiny::div(class = "text-muted", "Loading..."))
      }

      pending <- rules[rules$approval_status == "PENDING" & rules$requires_approval == 1, ]

      if (nrow(pending) == 0) {
        return(shiny::div(
          class = "alert alert-info",
          "No rules pending approval."
        ))
      }

      cards <- lapply(seq_len(nrow(pending)), function(i) {
        rule <- pending[i, ]
        bslib::card(
          bslib::card_header(
            class = "d-flex justify-content-between align-items-center",
            shiny::tags$strong(rule$rule_id),
            shiny::tags$span(class = "badge bg-warning", "Pending")
          ),
          bslib::card_body(
            shiny::tags$p(
              shiny::tags$strong("Field: "), rule$field_code,
              if (!is.na(rule$form_code)) paste(" (Form:", rule$form_code, ")") else ""
            ),
            shiny::tags$p(
              shiny::tags$strong("Rule: "),
              shiny::tags$code(rule$rule_dsl)
            ),
            shiny::tags$p(
              shiny::tags$strong("Error Message: "),
              rule$error_message
            ),
            shiny::tags$p(
              class = "text-muted small",
              "Imported by ", rule$imported_by, " on ", rule$imported_at
            ),
            if (perms$approve) {
              shiny::div(
                class = "mt-3",
                shiny::textAreaInput(
                  ns(paste0("comments_", rule$rule_id)),
                  "Review Comments",
                  rows = 2
                ),
                shiny::actionButton(
                  ns(paste0("approve_", rule$rule_id)),
                  "Approve",
                  class = "btn-success btn-sm me-2"
                ),
                shiny::actionButton(
                  ns(paste0("reject_", rule$rule_id)),
                  "Reject",
                  class = "btn-danger btn-sm"
                )
              )
            } else {
              shiny::tags$p(
                class = "text-muted",
                shiny::tags$em("You do not have permission to approve rules.")
              )
            }
          )
        )
      })

      shiny::div(class = "row", lapply(cards, function(card) {
        shiny::div(class = "col-md-6 mb-3", card)
      }))
    })

    output$import_ui <- shiny::renderUI({
      perms <- permissions()

      if (!perms$create) {
        return(shiny::div(
          class = "alert alert-warning",
          "You do not have permission to import validation rules."
        ))
      }

      shiny::div(
        bslib::card(
          bslib::card_header("Import from Google Sheets"),
          bslib::card_body(
            shiny::tags$p(
              "Import validation rules defined in a Google Sheet. ",
              "The sheet should have columns: rule_id, field_code, rule_dsl, ",
              "and optionally: form_code, error_message, severity, rule_category."
            ),
            shiny::textInput(
              ns("gsheet_id"),
              "Google Sheet ID or URL",
              placeholder = "Enter the Google Sheet ID or full URL"
            ),
            shiny::textInput(
              ns("sheet_name"),
              "Sheet Name",
              value = "validation_rules"
            ),
            shiny::checkboxInput(
              ns("validate_syntax"),
              "Validate DSL syntax before import",
              value = TRUE
            ),
            shiny::checkboxInput(
              ns("dry_run"),
              "Dry run (validate only, don't import)",
              value = FALSE
            ),
            shiny::actionButton(
              ns("import_rules"),
              "Import Rules",
              class = "btn-primary",
              icon = shiny::icon("cloud-download")
            ),
            shiny::hr(),
            shiny::actionButton(
              ns("create_template"),
              "Create Template Sheet",
              class = "btn-outline-secondary",
              icon = shiny::icon("file-excel")
            )
          )
        ),
        shiny::uiOutput(ns("import_results"))
      )
    })

    shiny::observeEvent(input$import_rules, {
      req(input$gsheet_id)

      user <- user_info()

      shiny::withProgress(message = "Importing rules...", {
        result <- import_validation_rules_from_gsheets(
          sheet_id = input$gsheet_id,
          sheet_name = input$sheet_name,
          imported_by = user$user_id,
          validate_syntax = input$validate_syntax,
          dry_run = input$dry_run
        )
      })

      if (result$success) {
        shiny::showNotification(
          paste("Imported", result$imported, "rules"),
          type = "message"
        )
        load_rules()
      } else {
        shiny::showNotification(
          paste("Import failed:", result$error),
          type = "error"
        )
      }

      output$import_results <- shiny::renderUI({
        if (result$success) {
          shiny::div(
            class = "alert alert-success mt-3",
            shiny::tags$strong("Import Successful"),
            shiny::tags$p(result$message),
            if (length(result$errors) > 0) {
              shiny::tags$div(
                shiny::tags$strong("Errors:"),
                shiny::tags$ul(
                  lapply(names(result$errors), function(id) {
                    shiny::tags$li(paste(id, ":", result$errors[[id]]))
                  })
                )
              )
            }
          )
        } else {
          shiny::div(
            class = "alert alert-danger mt-3",
            shiny::tags$strong("Import Failed"),
            shiny::tags$p(result$error)
          )
        }
      })
    })

    output$create_rule_ui <- shiny::renderUI({
      perms <- permissions()

      if (!perms$create) {
        return(shiny::div(
          class = "alert alert-warning",
          "You do not have permission to create validation rules."
        ))
      }

      bslib::card(
        bslib::card_header("Create New Validation Rule"),
        bslib::card_body(
          shiny::fluidRow(
            shiny::column(
              6,
              shiny::textInput(ns("new_rule_id"), "Rule ID",
                               placeholder = "e.g., AGE_RANGE"),
              shiny::textInput(ns("new_field_code"), "Field Code",
                               placeholder = "e.g., age"),
              shiny::textInput(ns("new_form_code"), "Form Code (optional)",
                               placeholder = "e.g., demographics")
            ),
            shiny::column(
              6,
              shiny::selectInput(ns("new_severity"), "Severity",
                                 choices = c("ERROR", "WARNING", "INFO")),
              shiny::selectInput(ns("new_category"), "Category",
                                 choices = names(get_dsl_rule_categories())),
              shiny::checkboxInput(ns("new_requires_approval"),
                                   "Requires PI Approval", value = FALSE)
            )
          ),
          shiny::textAreaInput(
            ns("new_rule_dsl"),
            "Validation Rule (DSL)",
            placeholder = "e.g., between 18 and 65",
            rows = 3
          ),
          shiny::textInput(
            ns("new_error_message"),
            "Error Message (optional)",
            placeholder = "Custom error message shown to users"
          ),
          shiny::div(
            class = "mt-3",
            shiny::actionButton(
              ns("validate_new_rule"),
              "Validate Syntax",
              class = "btn-outline-secondary me-2"
            ),
            shiny::actionButton(
              ns("save_new_rule"),
              "Save Rule",
              class = "btn-primary"
            )
          ),
          shiny::uiOutput(ns("new_rule_validation"))
        )
      )
    })

    shiny::observeEvent(input$validate_new_rule, {
      req(input$new_rule_dsl)

      result <- validate_dsl_syntax(input$new_rule_dsl)

      output$new_rule_validation <- shiny::renderUI({
        if (result$valid) {
          shiny::div(
            class = "alert alert-success mt-3",
            shiny::icon("check-circle"),
            " Syntax is valid"
          )
        } else {
          shiny::div(
            class = "alert alert-danger mt-3",
            shiny::icon("times-circle"),
            " Syntax error: ", result$error
          )
        }
      })
    })

    shiny::observeEvent(input$save_new_rule, {
      req(input$new_rule_id, input$new_field_code, input$new_rule_dsl)

      user <- user_info()

      syntax_check <- validate_dsl_syntax(input$new_rule_dsl)
      if (!syntax_check$valid) {
        shiny::showNotification(
          paste("Invalid syntax:", syntax_check$error),
          type = "error"
        )
        return()
      }

      rule_record <- list(
        rule_id = input$new_rule_id,
        field_code = input$new_field_code,
        form_code = if (input$new_form_code == "") NA else input$new_form_code,
        rule_name = input$new_rule_id,
        rule_dsl = input$new_rule_dsl,
        error_message = if (input$new_error_message == "") {
          generate_default_error_message(input$new_rule_dsl, input$new_field_code)
        } else {
          input$new_error_message
        },
        severity = input$new_severity,
        rule_category = input$new_category,
        is_active = !input$new_requires_approval,
        requires_approval = input$new_requires_approval,
        imported_by = user$user_id,
        imported_at = Sys.time()
      )

      result <- save_dsl_rule_to_db(rule_record)

      if (result$success) {
        if (input$new_requires_approval) {
          request_dsl_rule_approval(input$new_rule_id, user$user_id)
          shiny::showNotification(
            "Rule saved and submitted for approval",
            type = "message"
          )
        } else {
          shiny::showNotification("Rule saved and activated", type = "message")
        }

        shiny::updateTextInput(session, "new_rule_id", value = "")
        shiny::updateTextInput(session, "new_field_code", value = "")
        shiny::updateTextInput(session, "new_form_code", value = "")
        shiny::updateTextAreaInput(session, "new_rule_dsl", value = "")
        shiny::updateTextInput(session, "new_error_message", value = "")

        load_rules()
      } else {
        shiny::showNotification(
          paste("Error saving rule:", result$error),
          type = "error"
        )
      }
    })

    output$export_rules <- shiny::downloadHandler(
      filename = function() {
        paste0("validation_rules_", Sys.Date(), ".csv")
      },
      content = function(file) {
        rules <- rules_data()
        if (!is.null(rules) && nrow(rules) > 0) {
          utils::write.csv(rules, file, row.names = FALSE)
        }
      }
    )
  })
}
