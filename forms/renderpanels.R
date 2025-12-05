#' Render form panel with typed input fields
#'
#' Generates appropriate input controls based on field metadata.
#' Supports 15+ field types for flexible data collection:
#' text, numeric, date, datetime, time, email, select, radio, checkbox,
#' checkbox_group, textarea, notes, slider, file, signature
#'
#' @param fields Character vector of field names OR list of field configurations
#' @param field_metadata List containing field definitions with type, required, choices, etc.
#'
#' @return List of Shiny input controls matching field types
#'
#' @details
#' Field metadata format:
#' \code{
#'   list(
#'     age = list(type = "numeric", required = TRUE, min = 0, max = 150),
#'     email = list(type = "email", required = TRUE),
#'     treatment = list(type = "select", choices = c("A", "B", "C")),
#'     visit_date = list(type = "date", required = TRUE),
#'     visit_time = list(type = "time", required = TRUE),
#'     pain_level = list(type = "slider", min = 0, max = 10, value = 5),
#'     symptoms = list(type = "checkbox_group", choices = c("Pain", "Fever", "Cough"))
#'   )
#' }
#'
#' @examples
#' \dontrun{
#' metadata <- list(
#'   age = list(type = "numeric", required = TRUE, label = "Age (years)"),
#'   gender = list(
#'     type = "select",
#'     choices = c("M", "F"),
#'     label = "Gender"
#'   ),
#'   pregnancy_date = list(
#'     type = "date",
#'     label = "Pregnancy Due Date",
#'     show_if = "gender == 'F'"  # Branching logic
#'   ),
#'   visit_time = list(type = "time", required = TRUE, label = "Visit Time")
#' )
#' renderPanel(names(metadata), metadata)
#' }
#'
#' @export
renderPanel <- function(fields, field_metadata = NULL) {
  # Support both simple field names and complex metadata
  if (is.null(field_metadata)) {
    # Fallback: simple textInput for all fields
    return(lapply(fields, function(field) {
      textInput(field, field)
    }))
  }

  # Render based on field metadata
  lapply(fields, function(field_name) {
    # Get field configuration (default to text if not specified)
    field_config <- field_metadata[[field_name]] %||% list(type = "text")

    # Extract common properties
    label <- field_config$label %||% field_name
    required <- field_config$required %||% FALSE
    help_text <- field_config$help %||% NULL

    # Format label with required indicator
    if (required) {
      label <- shiny::tagList(label, span("*", class = "text-danger"))
    }

    # Render field based on type
    field_input <- switch(field_config$type,
      # Numeric field with optional range
      "numeric" = numericInput(
        field_name,
        label,
        value = field_config$value %||% NA,
        min = field_config$min,
        max = field_config$max,
        step = field_config$step %||% 1
      ),

      # Date field
      "date" = dateInput(
        field_name,
        label,
        value = field_config$value %||% Sys.Date(),
        format = field_config$format %||% "yyyy-mm-dd",
        startview = field_config$startview %||% "month",
        language = "en"
      ),

      # Email field (validated on client/server)
      "email" = textInput(
        field_name,
        label,
        placeholder = "example@domain.com",
        value = field_config$value %||% ""
      ),

      # Select/dropdown field
      "select" = selectInput(
        field_name,
        label,
        choices = field_config$choices,
        selected = field_config$value %||% NULL,
        multiple = field_config$multiple %||% FALSE
      ),

      # Checkbox field
      "checkbox" = checkboxInput(
        field_name,
        label,
        value = field_config$value %||% FALSE
      ),

      # Textarea for longer text
      "textarea" = tags$textarea(
        id = field_name,
        class = "form-control",
        rows = field_config$rows %||% 4,
        cols = field_config$cols %||% 50,
        field_config$value %||% "",
        placeholder = field_config$placeholder %||% ""
      ),

      # Notes field (alias for textarea with default of 6 rows)
      "notes" = tags$textarea(
        id = field_name,
        class = "form-control",
        rows = field_config$rows %||% 6,
        cols = field_config$cols %||% 50,
        field_config$value %||% "",
        placeholder = field_config$placeholder %||% "Enter notes here..."
      ),

      # Time field (time of day)
      "time" = if (requireNamespace("shinyTime", quietly = TRUE)) {
        shinyTime::timeInput(
          field_name,
          label,
          value = field_config$value %||% Sys.time(),
          seconds = field_config$seconds %||% FALSE
        )
      } else {
        # Fallback to text input if shinyTime not available
        textInput(
          field_name,
          label,
          placeholder = "HH:MM",
          value = field_config$value %||% ""
        )
      },

      # DateTime field (date and time combined)
      "datetime" = if (requireNamespace("shinyWidgets", quietly = TRUE)) {
        shinyWidgets::datetimeInput(
          field_name,
          label,
          value = field_config$value %||% Sys.time(),
          format = field_config$format %||% "YYYY-MM-DD HH:mm"
        )
      } else {
        # Fallback to text input
        textInput(
          field_name,
          label,
          placeholder = "YYYY-MM-DD HH:MM",
          value = field_config$value %||% ""
        )
      },

      # Slider field (numeric range with slider control)
      "slider" = sliderInput(
        field_name,
        label,
        min = field_config$min %||% 0,
        max = field_config$max %||% 100,
        value = field_config$value %||% field_config$min %||% 50,
        step = field_config$step %||% 1,
        animate = field_config$animate %||% FALSE
      ),

      # Radio buttons (single selection)
      "radio" = radioButtons(
        field_name,
        label,
        choices = field_config$choices,
        selected = field_config$value %||% NULL,
        inline = field_config$inline %||% FALSE
      ),

      # Checkbox group (multiple selection)
      "checkbox_group" = checkboxGroupInput(
        field_name,
        label,
        choices = field_config$choices,
        selected = field_config$value %||% NULL,
        inline = field_config$inline %||% FALSE
      ),

      # File upload field
      "file" = fileInput(
        field_name,
        label,
        multiple = field_config$multiple %||% FALSE,
        accept = field_config$accept %||% NULL,
        width = field_config$width %||% NULL
      ),

      # Signature pad (if shinysignature available)
      "signature" = if (requireNamespace("shinysignature", quietly = TRUE)) {
        shinysignature::signaturePad(
          field_name,
          width = field_config$width %||% "100%",
          height = field_config$height %||% "200px"
        )
      } else {
        # Fallback to textarea for notes
        tags$textarea(
          id = field_name,
          class = "form-control",
          rows = 6,
          placeholder = "Signature capture not available - enter notes instead"
        )
      },

      # Default: text input
      "text" = textInput(
        field_name,
        label,
        placeholder = field_config$placeholder %||% "",
        value = field_config$value %||% ""
      )
    )

    # Wrap with help text if provided
    if (!is.null(help_text)) {
      field_input <- shiny::tagList(
        field_input,
        tags$small(class = "form-text text-muted", help_text)
      )
    }

    # Determine initial visibility based on branching rules
    # (Server-side implementation uses setup_branching_logic to manage this)
    initial_hidden <- FALSE
    if (!is.null(field_config$show_if)) {
      # Field starts hidden if it has a show_if condition
      initial_hidden <- TRUE
    }

    # Wrap field with branching logic wrapper
    # data-field attribute allows JavaScript to identify fields
    # Initial display can be overridden by branching_logic.R setup_branching_logic
    wrapper_style <- if (initial_hidden) "display: none;" else ""

    tags$div(
      id = field_name,
      `data-field` = field_name,
      style = wrapper_style,
      class = "form-field-wrapper mb-3",
      field_input
    )
  })
}
