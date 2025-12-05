#' Render form panel with typed input fields
#'
#' Generates appropriate input controls based on field metadata.
#' Supports multiple field types: text, numeric, date, select, checkbox, email
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
#'     visit_date = list(type = "date", required = TRUE)
#'   )
#' }
#'
#' @examples
#' \dontrun{
#' metadata <- list(
#'   age = list(type = "numeric", required = TRUE, label = "Age (years)"),
#'   gender = list(type = "select", choices = c("M", "F"), label = "Gender")
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

    field_input
  })
}
