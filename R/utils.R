#' Validate and Sanitize Filename
#'
#' Sanitizes a filename by removing or replacing problematic characters,
#' preventing path traversal attacks, and limiting length
#'
#' @param filename Character string to sanitize
#' @param max_length Maximum filename length (default 100)
#'
#' @return Sanitized filename safe for use in file operations
#' @keywords internal
validate_filename <- function(filename, max_length = 100) {
  # Handle null input
  if (is.null(filename) || length(filename) == 0) {
    return("")
  }

  # Convert to character if needed
  filename <- as.character(filename)

  # Handle empty string - return "export" as default
  if (filename == "") {
    return("export")
  }

  # Remove path traversal attempts - extract just the filename
  # Replace backslashes with forward slashes for consistent handling
  filename <- gsub("\\\\", "/", filename)

  # Remove leading ../ sequences
  filename <- gsub("^(\\.\\.[\\/])+", "", filename)
  # Remove leading slashes
  filename <- gsub("^[\\/]", "", filename)

  # Keep only the filename part if full path was provided
  filename <- basename(filename)

  # Remove or replace special characters - keep only alphanumeric, dots, hyphens, underscores
  filename <- gsub("[^a-zA-Z0-9._-]", "_", filename)

  # Remove multiple consecutive underscores but preserve single ones
  filename <- gsub("_+", "_", filename)

  # Limit length
  filename <- substr(filename, 1, max_length)

  # Return default if nothing left
  if (filename == "" || filename == "." || filename == "..") {
    return("export")
  }

  filename
}
