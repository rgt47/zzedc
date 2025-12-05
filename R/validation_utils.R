#' Input Validation Utilities for ZZedc
#'
#' Provides secure input validation functions for user-supplied data
#' to prevent security vulnerabilities like SQL injection and path traversal.

#' Validate and sanitize filename
#'
#' Removes path components and special characters to prevent path traversal attacks.
#'
#' @param filename Character string containing the filename
#' @param max_length Maximum length for filename (default 100)
#'
#' @return Sanitized filename safe for file operations
#' @export
#' @examples
#' validate_filename("my-export_2024-01-01.csv")  # Returns: "my-export_2024-01-01.csv"
#' validate_filename("../../../etc/passwd")       # Returns: "passwd"
validate_filename <- function(filename, max_length = 100) {
  if (!is.character(filename) || length(filename) == 0) {
    return("")
  }

  # Remove any path components (basename extracts only filename)
  filename <- basename(filename)

  # Remove special characters except underscore, dash, dot
  filename <- gsub("[^a-zA-Z0-9_.-]", "_", filename)

  # Limit length
  if (nchar(filename) > max_length) {
    filename <- substr(filename, 1, max_length)
  }

  # Ensure not empty
  if (filename == "" || filename == ".") {
    filename <- "export"
  }

  filename
}

#' Validate table name from user input
#'
#' Ensures table name is valid and within allowed tables list.
#' Prevents SQL injection through table name manipulation.
#'
#' @param table_name Character string with table name
#' @param allowed_tables Character vector of permitted table names (optional)
#'
#' @return Validated table name, or error if invalid
#' @export
#' @examples
#' validate_table_name("subjects", allowed_tables = c("subjects", "visits", "labs"))
validate_table_name <- function(table_name, allowed_tables = NULL) {
  if (!is.character(table_name) || length(table_name) == 0) {
    stop("Table name must be a non-empty character string")
  }

  # If whitelist provided, enforce it
  if (!is.null(allowed_tables)) {
    if (!table_name %in% allowed_tables) {
      stop("Table name '", table_name, "' not in allowed tables")
    }
  }

  # Validate table name format (alphanumeric + underscore only)
  if (!grepl("^[a-zA-Z][a-zA-Z0-9_]*$", table_name)) {
    stop("Invalid table name format. Must start with letter, contain only alphanumeric and underscore")
  }

  table_name
}

#' Validate user profile image path
#'
#' Ensures image path is safe and returns default if file doesn't exist.
#'
#' @param username Character string with username
#' @param image_dir Directory containing user images (default: "www/avatars")
#' @param default_image Path to default image if user image not found
#'
#' @return Path to image file (either user's or default)
#' @export
validate_user_image <- function(username, image_dir = "www/avatars", default_image = "www/default_avatar.png") {
  if (!is.character(username) || length(username) == 0) {
    return(default_image)
  }

  # Validate username contains only safe characters (alphanumeric + underscore)
  if (!grepl("^[a-zA-Z0-9_]+$", username)) {
    return(default_image)
  }

  # Construct safe path
  image_path <- file.path(image_dir, paste0(username, ".jpg"))

  # Verify file exists before returning
  if (file.exists(image_path)) {
    image_path
  } else {
    default_image
  }
}

#' Validate numeric range from user input
#'
#' Ensures numeric input is within specified bounds.
#'
#' @param value Numeric value to validate
#' @param min Minimum allowed value
#' @param max Maximum allowed value
#' @param name Variable name for error messages
#'
#' @return The value if valid, or error
#' @export
validate_numeric_range <- function(value, min = NULL, max = NULL, name = "value") {
  if (!is.numeric(value) || is.na(value)) {
    stop(name, " must be numeric")
  }

  if (!is.null(min) && value < min) {
    stop(name, " must be >= ", min)
  }

  if (!is.null(max) && value > max) {
    stop(name, " must be <= ", max)
  }

  value
}

#' Validate form field input
#'
#' Multi-purpose validator for form fields based on type and rules.
#'
#' @param value Value to validate
#' @param type Field type: "text", "email", "numeric", "date", "select"
#' @param required Logical, is field required?
#' @param metadata List containing additional validation rules (min, max, choices, etc.)
#'
#' @return List with valid=logical, message=character
#' @export
validate_form_field <- function(value, type = "text", required = FALSE, metadata = NULL) {
  result <- list(valid = TRUE, message = "")

  # Check required
  if (required && (is.null(value) || value == "")) {
    result$valid <- FALSE
    result$message <- "This field is required"
    return(result)
  }

  # If not required and empty, it's valid
  if (!required && (is.null(value) || value == "")) {
    return(result)
  }

  # Type-specific validation
  switch(type,
    "email" = {
      if (!grepl("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", value)) {
        result$valid <- FALSE
        result$message <- "Please enter a valid email address"
      }
    },
    "numeric" = {
      if (!is.numeric(as.numeric(value))) {
        result$valid <- FALSE
        result$message <- "Must be a number"
      } else {
        num_val <- as.numeric(value)
        if (!is.null(metadata$min) && num_val < metadata$min) {
          result$valid <- FALSE
          result$message <- paste("Must be >= ", metadata$min)
        }
        if (!is.null(metadata$max) && num_val > metadata$max) {
          result$valid <- FALSE
          result$message <- paste("Must be <= ", metadata$max)
        }
      }
    },
    "date" = {
      tryCatch({
        as.Date(value)
      }, error = function(e) {
        result$valid <<- FALSE
        result$message <<- "Please enter a valid date"
      })
    },
    "select" = {
      if (!is.null(metadata$choices) && !value %in% metadata$choices) {
        result$valid <- FALSE
        result$message <- "Please select a valid option"
      }
    }
  )

  result
}
