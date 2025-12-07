#' Form Validation and Processing Utilities
#'
#' Server-side validation functions for form submissions
#' Ensures data quality and regulatory compliance

#' Validate entire form submission
#'
#' Validates all form fields against metadata rules.
#' Returns detailed validation results suitable for user feedback.
#'
#' @param form_data List or data.frame with submitted form values
#' @param field_metadata List defining validation rules for each field
#'
#' @return List with:
#'   - valid: logical, TRUE if all validations passed
#'   - errors: named list of field-specific error messages
#'   - warnings: named list of field-specific warnings
#'   - cleaned_data: validated and cleaned data
#'
#' @export
#' @examples
#' \dontrun{
#' metadata <- list(
#'   age = list(type = "numeric", required = TRUE, min = 18, max = 120),
#'   email = list(type = "email", required = TRUE)
#' )
#'
#' result <- validate_form(
#'   list(age = 25, email = "user@example.com"),
#'   metadata
#' )
#'
#' if (result$valid) {
#'   # Process the cleaned data
#'   save_record(result$cleaned_data)
#' } else {
#'   # Show errors to user
#'   show_validation_errors(result$errors)
#' }
#' }
validate_form <- function(form_data, field_metadata) {
  errors <- list()
  warnings <- list()
  cleaned_data <- list()

  # Validate each field
  for (field_name in names(field_metadata)) {
    field_rules <- field_metadata[[field_name]]
    field_value <- form_data[[field_name]]

    # Required field check
    if ((field_rules$required %||% FALSE) && (is.null(field_value) || field_value == "")) {
      errors[[field_name]] <- "This field is required"
      next
    }

    # Skip validation for empty non-required fields
    if (is.null(field_value) || field_value == "") {
      cleaned_data[[field_name]] <- NA
      next
    }

    # Type-specific validation
    validation_result <- validate_field_value(
      field_name,
      field_value,
      field_rules$type %||% "text",
      field_rules
    )

    if (!validation_result$valid) {
      errors[[field_name]] <- validation_result$message
    } else {
      cleaned_data[[field_name]] <- validation_result$cleaned_value
      if (!is.null(validation_result$warning)) {
        warnings[[field_name]] <- validation_result$warning
      }
    }
  }

  list(
    valid = length(errors) == 0,
    errors = errors,
    warnings = warnings,
    cleaned_data = cleaned_data
  )
}

#' Validate individual field value
#'
#' Type-specific validation for a single form field
#'
#' @param field_name Character name of field
#' @param value Value to validate
#' @param type Field type (text, numeric, date, email, select, checkbox)
#' @param rules List of validation rules
#'
#' @return List with valid, message, cleaned_value, warning
#'
validate_field_value <- function(field_name, value, type, rules) {
  result <- list(valid = TRUE, message = "", cleaned_value = value, warning = NULL)

  switch(type,
    "numeric" = {
      # Attempt conversion
      numeric_value <- suppressWarnings(as.numeric(value))

      if (is.na(numeric_value)) {
        result$valid <- FALSE
        result$message <- "Must be a number"
      } else {
        # Range validation
        if (!is.null(rules$min) && numeric_value < rules$min) {
          result$valid <- FALSE
          result$message <- paste("Minimum value is", rules$min)
        } else if (!is.null(rules$max) && numeric_value > rules$max) {
          result$valid <- FALSE
          result$message <- paste("Maximum value is", rules$max)
        }

        if (result$valid) {
          result$cleaned_value <- numeric_value
        }
      }
    },

    "email" = {
      # Email regex validation (RFC 5322 simplified)
      email_pattern <- "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$"

      if (!grepl(email_pattern, value)) {
        result$valid <- FALSE
        result$message <- "Please enter a valid email address"
      } else {
        result$cleaned_value <- tolower(value)  # Normalize to lowercase
      }
    },

    "date" = {
      tryCatch({
        date_value <- as.Date(value)
        result$cleaned_value <- date_value

        # Optional: validate date ranges
        if (!is.null(rules$min_date) && date_value < as.Date(rules$min_date)) {
          result$valid <- FALSE
          result$message <- paste("Date cannot be before", rules$min_date)
        } else if (!is.null(rules$max_date) && date_value > as.Date(rules$max_date)) {
          result$valid <- FALSE
          result$message <- paste("Date cannot be after", rules$max_date)
        }
      }, error = function(e) {
        result$valid <<- FALSE
        result$message <<- "Please enter a valid date (YYYY-MM-DD)"
      })
    },

    "select" = {
      # Verify value is in allowed choices
      if (!value %in% rules$choices) {
        result$valid <- FALSE
        result$message <- "Please select a valid option"
      }
    },

    "text" = {
      # Text length validation
      if (!is.null(rules$max_length) && nchar(value) > rules$max_length) {
        result$valid <- FALSE
        result$message <- paste("Maximum length is", rules$max_length, "characters")
      }

      if (!is.null(rules$pattern) && !grepl(rules$pattern, value)) {
        result$valid <- FALSE
        result$message <- rules$pattern_message %||% "Invalid format"
      }

      if (result$valid) {
        # Trim whitespace
        result$cleaned_value <- stringr::str_trim(value)
      }
    },

    "checkbox" = {
      # Convert to logical
      result$cleaned_value <- as.logical(value)
    }
  )

  result
}

#' Create server-side form validation observer
#'
#' Sets up reactive validation that updates UI in real-time
#'
#' @param session Shiny session object
#' @param form_fields Character vector of form field names
#' @param field_metadata List with field validation rules
#' @param error_container_id ID of element to display errors
#'
#' @export
setup_form_validation <- function(session, form_fields, field_metadata, error_container_id = "form_errors") {
  observe({
    # Collect form values
    form_data <- sapply(form_fields, function(field) {
      input[[field]]
    }, simplify = FALSE)

    # Validate form
    validation <- validate_form(form_data, field_metadata)

    # Update error display
    if (length(validation$errors) > 0) {
      error_html <- tags$div(
        class = "alert alert-danger",
        h4("Form validation errors:"),
        tags$ul(
          lapply(names(validation$errors), function(field) {
            tags$li(paste0(field, ": ", validation$errors[[field]]))
          })
        )
      )

      # Update UI (implementation depends on your error display pattern)
      # shinyjs::html(error_container_id, error_html)
    }
  })
}

#' Display form validation errors to user
#'
#' Creates user-friendly error messages from validation results
#'
#' @param validation_result Result from validate_form()
#'
#' @return HTML list of error messages
#' @export
create_error_display <- function(validation_result) {
  if (length(validation_result$errors) == 0) {
    return(NULL)
  }

  tags$div(
    class = "alert alert-danger alert-dismissible fade show",
    role = "alert",
    tags$strong("Please fix the following errors:"),
    tags$ul(
      lapply(names(validation_result$errors), function(field) {
        tags$li(
          tags$strong(field, ":"),
          validation_result$errors[[field]]
        )
      })
    ),
    tags$button(
      type = "button",
      class = "btn-close",
      `data-bs-dismiss` = "alert",
      `aria-label` = "Close"
    )
  )
}

#' Save validated form data to database
#'
#' Saves validated and cleaned form data with audit logging
#'
#' @param conn Database connection
#' @param table_name Table to insert into
#' @param cleaned_data Validated data from validate_form()
#' @param user_id User submitting the form
#' @param audit_log Optional audit log to record submission
#'
#' @return List with success status and record ID
#' @export
save_validated_form <- function(conn, table_name, cleaned_data, user_id, audit_log = NULL) {
  tryCatch({
    # Prepare data frame for insertion
    insert_data <- as.data.frame(cleaned_data, stringsAsFactors = FALSE)

    # Add metadata
    insert_data$submitted_by <- user_id
    insert_data$submitted_at <- Sys.time()

    # Insert into database
    DBI::dbAppendTable(conn, table_name, insert_data)

    # Log to audit trail if provided
    if (!is.null(audit_log)) {
      log_audit_event(
        audit_log,
        user_id = user_id,
        action = "FORM_SUBMISSION",
        resource = table_name,
        status = "success"
      )
    }

    list(
      success = TRUE,
      message = "Form submitted successfully",
      record_id = nrow(DBI::dbReadTable(conn, table_name))
    )
  }, error = function(e) {
    list(
      success = FALSE,
      message = paste("Error saving form:", e$message),
      record_id = NULL
    )
  })
}
