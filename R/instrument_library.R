#' Pre-Built Instrument Library Service
#'
#' Manages loading and importing standardized survey instruments.
#' Pure business logic without Shiny dependencies for testability.
#'
#' Supported instruments include:
#' - PHQ-9: Patient Health Questionnaire (depression screening, 9 items)
#' - GAD-7: Generalized Anxiety Disorder scale (anxiety, 7 items)
#' - SF-36: Short Form Health Survey (quality of life, 36 items)
#' - DASS-21: Depression Anxiety Stress Scale (psychological distress, 21 items)
#' - PROMIS: Patient-Reported Outcomes Measurement Information System
#' - AUDIT-C: Alcohol Use Disorders Identification Test (alcohol use, 3 items)
#' - STOP-BANG: Sleep Apnea Screening (8 items)

#' List available instruments
#'
#' Returns names and metadata of all available pre-built instruments.
#'
#' @param instruments_dir Path to instruments directory (default: "instruments/")
#'
#' @return data.frame with columns:
#'   - name: Instrument ID (e.g., "phq9")
#'   - full_name: Full instrument name
#'   - items: Number of items
#'   - description: Brief description
#'
#' @export
#' @examples
#' \dontrun{
#' available <- list_available_instruments()
#' print(available)
#' }
list_available_instruments <- function(instruments_dir = "instruments/") {
  if (!dir.exists(instruments_dir)) {
    return(data.frame(
      name = character(0),
      full_name = character(0),
      items = integer(0),
      description = character(0)
    ))
  }

  csv_files <- list.files(instruments_dir, pattern = "\\.csv$", full.names = FALSE)

  if (length(csv_files) == 0) {
    return(data.frame(
      name = character(0),
      full_name = character(0),
      items = integer(0),
      description = character(0)
    ))
  }

  # Instrument metadata
  metadata_map <- list(
    phq9 = list(full_name = "Patient Health Questionnaire (PHQ-9)", description = "9-item depression screening tool"),
    gad7 = list(full_name = "Generalized Anxiety Disorder (GAD-7)", description = "7-item anxiety screening tool"),
    sf36 = list(full_name = "Short Form Health Survey (SF-36)", description = "36-item quality of life assessment"),
    dass21 = list(full_name = "Depression Anxiety Stress Scale (DASS-21)", description = "21-item psychological distress measure"),
    promis_depression = list(full_name = "PROMIS Depression", description = "Patient-reported depression outcomes"),
    promis_anxiety = list(full_name = "PROMIS Anxiety", description = "Patient-reported anxiety outcomes"),
    audit_c = list(full_name = "AUDIT-C", description = "3-item alcohol use screening"),
    stop_bang = list(full_name = "STOP-BANG", description = "8-item obstructive sleep apnea screening")
  )

  # Build results
  results <- lapply(csv_files, function(filename) {
    instrument_id <- sub("\\.csv$", "", filename)
    filepath <- file.path(instruments_dir, filename)

    # Try to load to count items
    tryCatch({
      df <- read.csv(filepath, stringsAsFactors = FALSE)
      num_items <- nrow(df)
    }, error = function(e) {
      num_items <- 0
    })

    # Get metadata
    meta <- metadata_map[[instrument_id]]
    if (is.null(meta)) {
      meta <- list(
        full_name = tools::toTitleCase(gsub("_", " ", instrument_id)),
        description = "Custom instrument"
      )
    }

    data.frame(
      name = instrument_id,
      full_name = meta$full_name,
      items = num_items,
      description = meta$description,
      stringsAsFactors = FALSE
    )
  })

  do.call(rbind, results)
}

#' Load instrument template from CSV
#'
#' Loads a pre-built instrument template and returns as data.frame
#' with validated structure.
#'
#' @param instrument_name Name of instrument (e.g., "phq9", "gad7")
#' @param instruments_dir Path to instruments directory
#'
#' @return data.frame with columns:
#'   - field_name: Unique field identifier
#'   - field_label: User-facing label
#'   - field_type: Input type (text, numeric, select, etc.)
#'   - validation_rules: JSON string with validation constraints
#'   - description: Item description/instruction text
#'   - required: Logical, is field required?
#'
#' @export
#' @examples
#' \dontrun{
#' phq9_fields <- load_instrument_template("phq9")
#' head(phq9_fields)
#' }
load_instrument_template <- function(instrument_name, instruments_dir = "instruments/") {
  # Validate input
  if (!is.character(instrument_name) || length(instrument_name) == 0) {
    stop("instrument_name must be a non-empty character string")
  }

  # Sanitize filename
  safe_name <- gsub("[^a-zA-Z0-9_-]", "", instrument_name)
  filepath <- file.path(instruments_dir, paste0(safe_name, ".csv"))

  # Check file exists
  if (!file.exists(filepath)) {
    stop("Instrument not found: ", instrument_name)
  }

  # Load CSV
  tryCatch({
    df <- read.csv(filepath, stringsAsFactors = FALSE)
  }, error = function(e) {
    stop("Failed to load instrument: ", e$message)
  })

  # Validate required columns
  required_cols <- c("field_name", "field_label", "field_type")
  missing_cols <- setdiff(required_cols, names(df))

  if (length(missing_cols) > 0) {
    stop("Instrument CSV missing columns: ", paste(missing_cols, collapse = ", "))
  }

  # Ensure all required columns exist with defaults
  if (!"validation_rules" %in% names(df)) df$validation_rules <- NA_character_
  if (!"description" %in% names(df)) df$description <- NA_character_
  if (!"required" %in% names(df)) df$required <- FALSE

  # Validate field names (alphanumeric + underscore only)
  invalid_names <- !grepl("^[a-zA-Z][a-zA-Z0-9_]*$", df$field_name)
  if (any(invalid_names)) {
    stop("Invalid field names: ", paste(df$field_name[invalid_names], collapse = ", "))
  }

  # Validate field types are recognized
  valid_types <- c("text", "numeric", "date", "email", "select", "checkbox", "textarea",
                   "radio", "slider", "time", "datetime", "signature", "file")
  invalid_types <- !df$field_type %in% valid_types
  if (any(invalid_types)) {
    warning("Unrecognized field types: ", paste(unique(df$field_type[invalid_types]), collapse = ", "))
  }

  # Clean NAs
  df$validation_rules[is.na(df$validation_rules)] <- ""
  df$description[is.na(df$description)] <- ""

  df
}

#' Import instrument as new form
#'
#' Imports a pre-built instrument into the project as a new form.
#' Creates form record in database and returns form metadata.
#'
#' @param instrument_name Name of instrument to import (e.g., "phq9")
#' @param form_name New form name (defaults to instrument name if not provided)
#' @param form_description Description of form for display
#' @param db_conn Database connection (RSQLite::SQLiteConnection)
#' @param instruments_dir Path to instruments directory
#'
#' @return List containing:
#'   - success: Logical, operation successful?
#'   - form_id: ID of newly created form
#'   - form_name: Name of created form
#'   - fields_imported: Number of fields added
#'   - message: Status message
#'   - errors: Character vector of any errors encountered
#'
#' @export
#' @examples
#' \dontrun{
#' result <- import_instrument(
#'   instrument_name = "phq9",
#'   form_name = "baseline_depression",
#'   form_description = "PHQ-9 administered at baseline visit",
#'   db_conn = conn
#' )
#' }
import_instrument <- function(instrument_name, form_name = NULL, form_description = NULL,
                              db_conn = NULL, instruments_dir = "instruments/") {

  errors <- c()

  # Validate inputs
  if (is.null(db_conn)) {
    return(list(
      success = FALSE,
      form_id = NA,
      message = "Database connection required",
      errors = "db_conn is NULL"
    ))
  }

  if (is.null(form_name) || form_name == "") {
    form_name <- instrument_name
  }

  if (is.null(form_description) || form_description == "") {
    form_description <- paste("Imported instrument:", instrument_name)
  }

  # Load instrument template
  tryCatch({
    template_fields <- load_instrument_template(instrument_name, instruments_dir)
  }, error = function(e) {
    errors <<- c(errors, paste("Failed to load instrument:", e$message))
    stop(e$message)
  })

  if (length(errors) > 0) {
    return(list(
      success = FALSE,
      form_id = NA,
      message = "Failed to load instrument",
      errors = errors
    ))
  }

  # Validate form doesn't already exist
  tryCatch({
    existing <- DBI::dbGetQuery(db_conn,
      "SELECT form_id FROM forms WHERE form_name = ?",
      list(form_name))

    if (nrow(existing) > 0) {
      errors <- c(errors, paste("Form already exists:", form_name))
      return(list(
        success = FALSE,
        form_id = NA,
        message = paste("Form already exists:", form_name),
        errors = errors
      ))
    }
  }, error = function(e) {
    errors <<- c(errors, paste("Database error checking form:", e$message))
  })

  # Insert form record
  tryCatch({
    DBI::dbExecute(db_conn,
      "INSERT INTO forms (form_name, form_description, form_type) VALUES (?, ?, ?)",
      list(form_name, form_description, "instrument_import")
    )

    form_result <- DBI::dbGetQuery(db_conn,
      "SELECT form_id FROM forms WHERE form_name = ? ORDER BY form_id DESC LIMIT 1",
      list(form_name)
    )

    form_id <- form_result$form_id[1]
  }, error = function(e) {
    errors <<- c(errors, paste("Failed to create form:", e$message))
    stop(e$message)
  })

  if (length(errors) > 0) {
    return(list(
      success = FALSE,
      form_id = NA,
      message = "Failed to create form in database",
      errors = errors
    ))
  }

  # Insert form fields
  fields_imported <- 0
  tryCatch({
    for (i in seq_len(nrow(template_fields))) {
      field <- template_fields[i, ]

      DBI::dbExecute(db_conn,
        "INSERT INTO form_fields (form_id, field_name, field_label, field_type, validation_rules, description, field_order, required)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        list(
          form_id,
          field$field_name,
          field$field_label,
          field$field_type,
          field$validation_rules,
          field$description,
          i,
          as.integer(field$required)
        )
      )
      fields_imported <- fields_imported + 1
    }

    # Log the import event
    log_audit_event(
      db_conn = db_conn,
      user_id = "system",
      action = "INSTRUMENT_IMPORT",
      resource = paste0("form:", form_id),
      details = jsonlite::toJSON(list(
        instrument_name = instrument_name,
        form_name = form_name,
        fields_imported = fields_imported
      )),
      status = "SUCCESS"
    )

  }, error = function(e) {
    errors <<- c(errors, paste("Failed to insert form fields:", e$message))
  })

  if (length(errors) > 0) {
    return(list(
      success = FALSE,
      form_id = form_id,
      message = paste("Partial import: created form but", length(errors), "errors during field insertion"),
      errors = errors,
      fields_imported = fields_imported
    ))
  }

  list(
    success = TRUE,
    form_id = form_id,
    form_name = form_name,
    fields_imported = fields_imported,
    message = paste("Successfully imported", instrument_name, "as", form_name, "with", fields_imported, "fields"),
    errors = character(0)
  )
}

#' Get instrument field by name
#'
#' Retrieves a single field definition from an instrument.
#'
#' @param instrument_name Name of instrument
#' @param field_name Name of field to retrieve
#' @param instruments_dir Path to instruments directory
#'
#' @return List with field properties, or NULL if not found
#'
#' @keywords internal
get_instrument_field <- function(instrument_name, field_name, instruments_dir = "instruments/") {
  template <- load_instrument_template(instrument_name, instruments_dir)
  field_row <- template[template$field_name == field_name, ]

  if (nrow(field_row) == 0) return(NULL)

  as.list(field_row[1, ])
}

#' Validate instrument CSV structure
#'
#' Checks that a CSV file has correct structure for import.
#' Used for validation before accepting user uploads.
#'
#' @param filepath Path to CSV file to validate
#'
#' @return List containing:
#'   - valid: Logical, structure is valid?
#'   - errors: Character vector of validation errors
#'   - warnings: Character vector of warnings
#'   - field_count: Number of fields in file
#'
#' @export
validate_instrument_csv <- function(filepath) {
  errors <- c()
  warnings <- c()
  field_count <- 0

  # Check file exists
  if (!file.exists(filepath)) {
    return(list(
      valid = FALSE,
      errors = "File does not exist",
      warnings = character(0),
      field_count = 0
    ))
  }

  # Check file extension
  if (!grepl("\\.csv$", filepath, ignore.case = TRUE)) {
    warnings <- c(warnings, "File extension should be .csv")
  }

  # Try to load
  tryCatch({
    df <- read.csv(filepath, stringsAsFactors = FALSE)
  }, error = function(e) {
    errors <<- c(errors, paste("Cannot read CSV:", e$message))
    return(NULL)
  })

  if (is.null(df)) {
    return(list(
      valid = FALSE,
      errors = errors,
      warnings = warnings,
      field_count = 0
    ))
  }

  # Check required columns
  required_cols <- c("field_name", "field_label", "field_type")
  missing_cols <- setdiff(required_cols, names(df))
  if (length(missing_cols) > 0) {
    errors <- c(errors, paste("Missing required columns:", paste(missing_cols, collapse = ", ")))
  }

  # Check for empty dataframe
  if (nrow(df) == 0) {
    errors <- c(errors, "CSV contains no field definitions")
  }

  # Check field names are valid
  if ("field_name" %in% names(df)) {
    invalid_names <- !grepl("^[a-zA-Z][a-zA-Z0-9_]*$", df$field_name)
    if (any(invalid_names)) {
      errors <- c(errors, paste("Invalid field names:", paste(df$field_name[invalid_names], collapse = ", ")))
    }
    # Check for duplicates
    if (any(duplicated(df$field_name))) {
      errors <- c(errors, paste("Duplicate field names:", paste(unique(df$field_name[duplicated(df$field_name)]), collapse = ", ")))
    }
  }

  # Check field types
  if ("field_type" %in% names(df)) {
    valid_types <- c("text", "numeric", "date", "email", "select", "checkbox", "textarea",
                     "radio", "slider", "time", "datetime", "signature", "file")
    invalid_types <- !df$field_type %in% valid_types
    if (any(invalid_types)) {
      warnings <- c(warnings, paste("Unrecognized field types:", paste(unique(df$field_type[invalid_types]), collapse = ", ")))
    }
  }

  field_count <- nrow(df)

  list(
    valid = length(errors) == 0,
    errors = errors,
    warnings = warnings,
    field_count = field_count
  )
}
