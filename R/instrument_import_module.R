# Instrument Library Import Module
#
# Allows users to browse, preview, and import pre-built survey instruments
# as new forms in the study database.

#' Instrument Import Module UI
#'
#' @param id Namespace ID for the module
#'
#' @return A tagList containing the instrument import UI
#'
#' @keywords internal
instrument_import_ui <- function(id) {
  ns <- NS(id)

  div(
    class = "card",
    div(
      class = "card-body",
      h4(icon("clipboard-list"), "Import Pre-Built Instrument", class = "mb-3"),

      # Available instruments table
      h5("Available Instruments", class = "mt-4 mb-2"),
      p("Select an instrument to import as a new form in your study.", class = "text-muted small"),

      div(
        id = ns("instruments_container"),
        p("Loading instruments...", class = "text-muted")
      ),

      # Hidden alert for messages
      div(
        id = ns("import_message"),
        style = "display: none;",
        class = "alert"
      ),

      # Import controls (hidden until instrument selected)
      div(
        id = ns("import_controls"),
        style = "display: none;",
        class = "mt-4 p-3 border rounded bg-light",

        h5("Import Configuration", class = "mb-3"),

        # Selected instrument info
        div(
          class = "row mb-3",
          div(
            class = "col-md-6",
            p(strong("Selected Instrument: "), span(id = ns("selected_name"), ""))
          ),
          div(
            class = "col-md-6",
            p(strong("Fields: "), span(id = ns("selected_count"), ""))
          )
        ),

        # Form name input
        textInput(
          ns("form_name"),
          "Form Name",
          placeholder = "e.g., baseline_depression"
        ),

        # Form description
        textAreaInput(
          ns("form_description"),
          "Form Description (optional)",
          placeholder = "Description of this form and when it's administered",
          rows = 3
        ),

        # Field preview
        h5("Field Preview", class = "mb-2"),
        p("First 5 fields of this instrument:", class = "text-muted small"),
        div(
          id = ns("field_preview"),
          class = "table-responsive mb-3",
          tableOutput(ns("preview_table"))
        ),

        # Action buttons
        div(
          class = "d-flex gap-2",
          actionButton(
            ns("import_button"),
            "Import Instrument",
            class = "btn btn-success",
            icon = icon("check")
          ),
          actionButton(
            ns("cancel_button"),
            "Cancel",
            class = "btn btn-secondary",
            icon = icon("times")
          )
        )
      )
    )
  )
}

#' Instrument Import Module Server
#'
#' @param id Namespace ID for the module
#' @param db_conn Reactive database connection
#' @param instruments_dir Directory containing instrument CSV files
#'
#' @keywords internal
instrument_import_server <- function(id, db_conn, instruments_dir = "instruments/") {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Reactive values to store state
    state <- reactiveValues(
      selected_instrument = NULL,
      selected_index = NULL,
      instruments = NULL
    )

    # Load available instruments
    observe({
      tryCatch({
        instr <- list_available_instruments(instruments_dir)
        state$instruments <- instr
      }, error = function(e) {
        show_message(session, ns, "Error loading instruments", "danger")
      })
    })

    # Render instruments table
    output$instruments_table <- renderUI({
      if (is.null(state$instruments) || nrow(state$instruments) == 0) {
        return(p("No instruments available. Check instruments/ directory.", class = "text-muted"))
      }

      # Create clickable instrument rows
      lapply(seq_len(nrow(state$instruments)), function(i) {
        instr <- state$instruments[i, ]
        div(
          class = "list-group-item list-group-item-action cursor-pointer mb-2",
          id = ns(paste0("instr_", i)),
          onclick = paste0("Shiny.onInputChange('", ns("selected_id"), "', ", i, ")"),
          style = "cursor: pointer;",
          div(
            class = "d-flex justify-content-between align-items-start",
            div(
              strong(instr$full_name),
              br(),
              small(
                class = "text-muted",
                paste0(instr$items, " items - ", instr$description)
              )
            ),
            div(
              class = "badge bg-primary",
              paste0(instr$items, " fields")
            )
          )
        )
      })
    })

    # Render instruments container
    output$instruments_container <- renderUI({
      if (is.null(state$instruments) || nrow(state$instruments) == 0) {
        p("No instruments available in ", instruments_dir, class = "text-muted")
      } else {
        div(
          class = "list-group",
          uiOutput(ns("instruments_table"))
        )
      }
    })

    # Handle instrument selection
    observeEvent(input$selected_id, {
      state$selected_index <- input$selected_id

      if (!is.null(state$selected_index)) {
        selected <- state$instruments[state$selected_index, ]
        state$selected_instrument <- selected$name

        # Pre-fill form name
        updateTextInput(session, "form_name", value = selected$name)
        updateTextAreaInput(session, "form_description",
          value = paste("Instrument:", selected$full_name)
        )

        # Load and preview fields
        tryCatch({
          template <- load_instrument_template(selected$name, instruments_dir)

          # Update preview table with first 5 fields
          preview_data <- head(template[, c("field_name", "field_label", "field_type")], 5)
          output$preview_table <- renderTable(
            preview_data,
            striped = TRUE,
            hover = TRUE,
            bordered = TRUE,
            spacing = "xs"
          )

          # Update display info
          output$selected_name <- renderText(selected$full_name)
          output$selected_count <- renderText(nrow(template))

          # Show import controls
          shinyjs::show("import_controls")

        }, error = function(e) {
          show_message(session, ns, paste("Error loading instrument:", e$message), "danger")
        })
      }
    })

    # Handle cancel
    observeEvent(input$cancel_button, {
      shinyjs::hide("import_controls")
      shinyjs::hide("import_message")
      state$selected_instrument <- NULL
      state$selected_index <- NULL
      updateTextInput(session, "form_name", value = "")
      updateTextAreaInput(session, "form_description", value = "")
    })

    # Handle import
    observeEvent(input$import_button, {
      tryCatch({
        # Validate inputs
        if (is.null(state$selected_instrument) || state$selected_instrument == "") {
          show_message(session, ns, "Please select an instrument", "warning")
          return()
        }

        form_name <- trimws(input$form_name)
        if (form_name == "") {
          show_message(session, ns, "Form name is required", "warning")
          return()
        }

        form_desc <- trimws(input$form_description)

        # Import instrument
        result <- import_instrument(
          instrument_name = state$selected_instrument,
          form_name = form_name,
          form_description = form_desc,
          db_conn = db_conn(),
          instruments_dir = instruments_dir
        )

        # Show result
        if (result$success) {
          show_message(
            session, ns,
            paste0(
              "Success! Imported ",
              result$fields_imported,
              " fields as form '",
              result$form_name,
              "'"
            ),
            "success"
          )

          # Reset form
          shinyjs::hide("import_controls")
          state$selected_instrument <- NULL
          state$selected_index <- NULL
          updateTextInput(session, "form_name", value = "")
          updateTextAreaInput(session, "form_description", value = "")

          # Notify parent to refresh forms list
          session$sendCustomMessage("instrument_imported", result)

        } else {
          show_message(
            session, ns,
            paste0(
              "Error: ",
              result$message,
              if (length(result$errors) > 0) {
                paste0(" (", paste(result$errors, collapse = "; "), ")")
              } else {
                ""
              }
            ),
            "danger"
          )
        }

      }, error = function(e) {
        show_message(session, ns, paste("Import failed:", e$message), "danger")
      })
    })

    # Return reactive list for parent module
    list(
      selected_instrument = reactive(state$selected_instrument)
    )
  })
}

# Helper function to show messages
show_message <- function(session, ns, message, type = "info") {
  alert_class <- switch(type,
    "success" = "alert-success",
    "danger" = "alert-danger",
    "warning" = "alert-warning",
    "alert-info"
  )

  shinyjs::addClass(ns("import_message"), alert_class)
  shinyjs::removeClass(ns("import_message"), "alert-success alert-danger alert-warning alert-info")
  shinyjs::addClass(ns("import_message"), alert_class)

  output <- session$output
  output$import_message <- renderText(message)

  shinyjs::show(ns("import_message"))

  # Auto-hide after 5 seconds if success
  if (type == "success") {
    invalidateLater(5000, session)
    shinyjs::hide(ns("import_message"))
  }
}
