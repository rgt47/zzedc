# Google Sheets Data Dictionary Builder for ZZedc
# Specialized module for building data dictionary and forms from Google Sheets

source("gsheets_integration.R")

#' Advanced data dictionary builder with form generation and validation
#' @param dd_sheet_name Name of the Google Sheet containing data dictionary
#' @param db_path Path to SQLite database file
#' @param forms_dir Directory to store generated form files
build_advanced_dd_system <- function(
  dd_sheet_name = "zzedc_data_dictionary",
  db_path = "data/zzedc_gsheets.db",
  forms_dir = "forms_generated"
) {

  message("=== Building Advanced Data Dictionary System ===")

  # Setup Google authentication
  setup_google_auth()

  # Read data dictionary with enhanced validation
  dd_data <- read_enhanced_dd_data(dd_sheet_name)

  # Build comprehensive data dictionary tables
  build_comprehensive_dd_tables(dd_data, db_path)

  # Generate form files for Shiny integration
  generate_form_files(dd_data, forms_dir)

  # Generate validation rules
  generate_validation_rules(dd_data, forms_dir)

  message("=== Data dictionary system build completed ===")
}

#' Read data dictionary data with enhanced validation and structure checking
#' @param sheet_name Name of the Google Sheet
read_enhanced_dd_data <- function(sheet_name) {
  message("Reading enhanced data dictionary from: ", sheet_name)

  # Read forms overview sheet
  forms_overview <- read_sheet(sheet_name, sheet = "forms_overview")

  # Validate forms overview structure
  required_cols <- c("workingname", "fullname", "visits")
  missing_cols <- setdiff(required_cols, names(forms_overview))
  if (length(missing_cols) > 0) {
    stop("Missing required columns in forms overview: ", paste(missing_cols, collapse = ", "))
  }

  # Read visits definition if it exists
  visits_data <- tryCatch({
    read_sheet(sheet_name, sheet = "visits")
  }, error = function(e) {
    message("No visits sheet found, extracting from forms overview")
    # Extract visits from forms overview
    all_visits <- forms_overview$visits %>%
      str_replace_all(" ", "") %>%
      strsplit(",") %>%
      unlist() %>%
      unique() %>%
      sort()

    data.frame(
      visit_code = all_visits,
      visit_name = all_visits,
      visit_order = 1:length(all_visits),
      active = 1,
      stringsAsFactors = FALSE
    )
  })

  # Read field types definition if it exists
  field_types <- tryCatch({
    read_sheet(sheet_name, sheet = "field_types")
  }, error = function(e) {
    message("No field_types sheet found, using defaults")
    data.frame(
      type_code = c("C", "N", "D", "L"),
      type_name = c("Character", "Numeric", "Date", "Logical"),
      description = c("Text field", "Numeric field", "Date field", "Yes/No field"),
      stringsAsFactors = FALSE
    )
  })

  # Read validation rules if it exists
  validation_rules <- tryCatch({
    read_sheet(sheet_name, sheet = "validation")
  }, error = function(e) {
    message("No validation sheet found")
    data.frame(
      field = character(0),
      rule = character(0),
      message = character(0),
      stringsAsFactors = FALSE
    )
  })

  # Read individual form definitions
  form_definitions <- list()
  form_errors <- list()

  for (i in 1:nrow(forms_overview)) {
    form_name <- forms_overview$workingname[i]
    sheet_name_full <- paste0("form_", form_name)

    message("Reading form definition: ", sheet_name_full)

    tryCatch({
      form_def <- read_sheet(sheet_name, sheet = sheet_name_full)

      # Validate form structure
      expected_cols <- c("field", "prompt", "type", "layout")
      missing_cols <- setdiff(expected_cols, names(form_def))
      if (length(missing_cols) > 0) {
        warning("Form '", form_name, "' missing columns: ", paste(missing_cols, collapse = ", "))
      }

      # Clean and standardize the form definition
      form_def <- form_def %>%
        filter(!is.na(field), nchar(trimws(field)) > 0) %>%
        mutate(
          field = make.names(trimws(field)),  # Ensure valid R variable names
          prompt = ifelse(is.na(prompt) | prompt == "", field, trimws(prompt)),
          type = ifelse(is.na(type), "C", toupper(trimws(type))),
          layout = ifelse(is.na(layout), "text", trimws(layout)),
          req = ifelse(is.na(req), 0, as.numeric(req)),
          values = ifelse(is.na(values), "", trimws(values)),
          cond = ifelse(is.na(cond), "", trimws(cond)),
          valid = ifelse(is.na(valid), "", trimws(valid)),
          validmsg = ifelse(is.na(validmsg), "", trimws(validmsg))
        )

      # Validate field types
      valid_types <- field_types$type_code
      invalid_types <- setdiff(form_def$type, valid_types)
      if (length(invalid_types) > 0) {
        warning("Form '", form_name, "' has invalid field types: ", paste(invalid_types, collapse = ", "))
        form_def$type[form_def$type %in% invalid_types] <- "C"
      }

      # Check for duplicate field names
      duplicate_fields <- form_def$field[duplicated(form_def$field)]
      if (length(duplicate_fields) > 0) {
        warning("Form '", form_name, "' has duplicate fields: ", paste(duplicate_fields, collapse = ", "))
        form_def <- form_def[!duplicated(form_def$field), ]
      }

      form_definitions[[form_name]] <- form_def

    }, error = function(e) {
      error_msg <- paste("Could not read form definition '", sheet_name_full, "': ", e$message)
      warning(error_msg)
      form_errors[[form_name]] <- error_msg
    })
  }

  message("Successfully read ", length(form_definitions), " form definitions")
  if (length(form_errors) > 0) {
    message("Errors encountered with ", length(form_errors), " forms")
  }

  return(list(
    forms_overview = forms_overview,
    form_definitions = form_definitions,
    visits = visits_data,
    field_types = field_types,
    validation_rules = validation_rules,
    form_errors = form_errors
  ))
}

#' Build comprehensive data dictionary tables including metadata
#' @param dd_data List containing all data dictionary data
#' @param db_path Path to SQLite database file
build_comprehensive_dd_tables <- function(dd_data, db_path) {
  message("Building comprehensive data dictionary tables in: ", db_path)

  # Ensure directory exists
  if (!dir.exists(dirname(db_path))) {
    dir.create(dirname(db_path), recursive = TRUE)
  }

  # Connect to database
  con <- dbConnect(SQLite(), db_path)
  on.exit(dbDisconnect(con))

  tryCatch({
    # 1. Build forms overview table
    forms_overview <- dd_data$forms_overview
    if (dbExistsTable(con, "edc_forms")) {
      dbExecute(con, "DROP TABLE edc_forms")
    }
    dbWriteTable(con, "edc_forms", forms_overview, overwrite = TRUE)
    message("Created edc_forms table with ", nrow(forms_overview), " forms")

    # 2. Build visits table
    visits_data <- dd_data$visits
    if (dbExistsTable(con, "edc_visits")) {
      dbExecute(con, "DROP TABLE edc_visits")
    }
    dbWriteTable(con, "edc_visits", visits_data, overwrite = TRUE)
    message("Created edc_visits table with ", nrow(visits_data), " visits")

    # 3. Build field types table
    field_types <- dd_data$field_types
    if (dbExistsTable(con, "edc_field_types")) {
      dbExecute(con, "DROP TABLE edc_field_types")
    }
    dbWriteTable(con, "edc_field_types", field_types, overwrite = TRUE)
    message("Created edc_field_types table with ", nrow(field_types), " field types")

    # 4. Build validation rules table
    validation_rules <- dd_data$validation_rules
    if (dbExistsTable(con, "edc_validation")) {
      dbExecute(con, "DROP TABLE edc_validation")
    }
    dbWriteTable(con, "edc_validation", validation_rules, overwrite = TRUE)
    message("Created edc_validation table with ", nrow(validation_rules), " validation rules")

    # 5. Build unified fields table
    form_definitions <- dd_data$form_definitions
    all_fields <- data.frame()

    for (form_name in names(form_definitions)) {
      form_def <- form_definitions[[form_name]]
      form_def$form_name <- form_name
      form_def$field_id <- paste(form_name, form_def$field, sep = "_")
      all_fields <- rbind(all_fields, form_def)
    }

    if (dbExistsTable(con, "edc_fields")) {
      dbExecute(con, "DROP TABLE edc_fields")
    }
    dbWriteTable(con, "edc_fields", all_fields, overwrite = TRUE)
    message("Created edc_fields table with ", nrow(all_fields), " fields")

    # 6. Create data storage tables for each form
    data_tables_created <- 0
    for (form_name in names(form_definitions)) {
      form_def <- form_definitions[[form_name]]
      table_name <- paste0("data_", form_name)

      # Drop existing table
      if (dbExistsTable(con, table_name)) {
        dbExecute(con, paste("DROP TABLE", table_name))
      }

      # Build CREATE TABLE statement with proper column types
      col_definitions <- c(
        "record_id INTEGER PRIMARY KEY AUTOINCREMENT",
        "subject_id TEXT NOT NULL",
        "site_id INTEGER",
        "visit_code TEXT",
        "form_status TEXT DEFAULT 'incomplete'",
        "entry_date DATETIME DEFAULT CURRENT_TIMESTAMP",
        "entry_user INTEGER",
        "modified_date DATETIME",
        "modified_user INTEGER"
      )

      # Add form-specific columns
      for (i in 1:nrow(form_def)) {
        field_name <- form_def$field[i]
        field_type <- form_def$type[i]

        sql_type <- case_when(
          field_type == "N" ~ "REAL",
          field_type == "D" ~ "DATE",
          field_type == "L" ~ "INTEGER CHECK (FIELD IN (0, 1))",
          TRUE ~ "TEXT"
        )

        col_definitions <- c(col_definitions, paste(field_name, sql_type))
      }

      create_sql <- paste("CREATE TABLE", table_name, "(", paste(col_definitions, collapse = ", "), ")")
      dbExecute(con, create_sql)

      # Create indexes for performance
      dbExecute(con, paste("CREATE INDEX idx", table_name, "subject ON", table_name, "(subject_id)"))
      dbExecute(con, paste("CREATE INDEX idx", table_name, "visit ON", table_name, "(visit_code)"))

      data_tables_created <- data_tables_created + 1
    }

    message("Created ", data_tables_created, " data storage tables")

    # 7. Create comprehensive views
    dbExecute(con, "
      CREATE VIEW v_forms_detailed AS
      SELECT
        f.workingname,
        f.fullname,
        f.visits,
        COUNT(fd.field) as field_count
      FROM edc_forms f
      LEFT JOIN edc_fields fd ON f.workingname = fd.form_name
      GROUP BY f.workingname, f.fullname, f.visits
    ")

    dbExecute(con, "
      CREATE VIEW v_fields_detailed AS
      SELECT
        fd.field_id,
        fd.form_name,
        f.fullname as form_fullname,
        fd.field,
        fd.prompt,
        fd.type,
        ft.type_name,
        fd.layout,
        fd.req,
        fd.values,
        fd.cond,
        fd.valid,
        fd.validmsg
      FROM edc_fields fd
      LEFT JOIN edc_forms f ON fd.form_name = f.workingname
      LEFT JOIN edc_field_types ft ON fd.type = ft.type_code
    ")

    # 8. Create indexes for performance
    dbExecute(con, "CREATE INDEX idx_form_name ON edc_fields(form_name)")
    dbExecute(con, "CREATE INDEX idx_field_name ON edc_fields(field)")
    dbExecute(con, "CREATE INDEX idx_field_type ON edc_fields(type)")

    # 9. Verify the tables
    forms_count <- dbGetQuery(con, "SELECT COUNT(*) as count FROM edc_forms")$count
    fields_count <- dbGetQuery(con, "SELECT COUNT(*) as count FROM edc_fields")$count
    visits_count <- dbGetQuery(con, "SELECT COUNT(*) as count FROM edc_visits")$count

    message("Data dictionary verification:")
    message("  - Forms: ", forms_count)
    message("  - Fields: ", fields_count)
    message("  - Visits: ", visits_count)
    message("  - Data tables: ", data_tables_created)

    return(TRUE)

  }, error = function(e) {
    message("Error building data dictionary tables: ", e$message)
    return(FALSE)
  })
}

#' Generate form files for Shiny integration
#' @param dd_data Data dictionary data
#' @param forms_dir Directory to store generated form files
generate_form_files <- function(dd_data, forms_dir) {
  message("Generating form files in: ", forms_dir)

  if (!dir.exists(forms_dir)) {
    dir.create(forms_dir, recursive = TRUE)
  }

  form_definitions <- dd_data$form_definitions

  for (form_name in names(form_definitions)) {
    form_def <- form_definitions[[form_name]]
    form_file <- file.path(forms_dir, paste0(form_name, "_form.R"))

    # Generate Shiny UI code for the form
    ui_elements <- c()

    for (i in 1:nrow(form_def)) {
      field <- form_def[i, ]
      element <- generate_shiny_input(field)
      ui_elements <- c(ui_elements, element)
    }

    # Create the complete form file
    form_code <- c(
      paste("# Generated form for:", form_name),
      paste("# Generated on:", Sys.time()),
      "",
      paste0(form_name, "_form <- function() {"),
      "  tagList(",
      paste("    ", ui_elements, collapse = ",\n"),
      "  )",
      "}"
    )

    writeLines(form_code, form_file)
    message("Generated form file: ", form_file)
  }
}

#' Generate Shiny input element for a field
#' @param field Single row data frame with field definition
generate_shiny_input <- function(field) {
  field_name <- field$field
  prompt <- field$prompt
  layout <- field$layout
  values <- field$values
  required <- as.logical(field$req)

  # Handle required fields
  label <- if (required) paste0("requ('", prompt, "')") else paste0("'", prompt, "'")

  # Generate input based on layout
  input_element <- switch(layout,
    "text" = paste0("textInput('", field_name, "', ", label, ")"),
    "textarea" = paste0("textAreaInput('", field_name, "', ", label, ")"),
    "numeric" = paste0("numericInput('", field_name, "', ", label, ", value = NA)"),
    "date" = paste0("dateInput('", field_name, "', ", label, ")"),
    "radio" = {
      choices <- if (values != "") {
        paste0("c(", paste0("'", strsplit(values, ",")[[1]], "'", collapse = ", "), ")")
      } else {
        "c('Yes', 'No')"
      }
      paste0("radioButtons('", field_name, "', ", label, ", choices = ", choices, ", inline = TRUE)")
    },
    "select" = {
      choices <- if (values != "") {
        paste0("c('', ", paste0("'", strsplit(values, ",")[[1]], "'", collapse = ", "), ")")
      } else {
        "c('', 'Option 1', 'Option 2')"
      }
      paste0("selectInput('", field_name, "', ", label, ", choices = ", choices, ")")
    },
    "checkbox" = paste0("checkboxInput('", field_name, "', ", label, ")"),
    # Default to text input
    paste0("textInput('", field_name, "', ", label, ")")
  )

  # Add conditional logic if specified
  if (!is.na(field$cond) && field$cond != "") {
    condition <- parse_condition(field$cond)
    input_element <- paste0("conditionalPanel('", condition, "', ", input_element, ")")
  }

  return(input_element)
}

#' Parse condition string for conditionalPanel
#' @param cond_str Condition string from Google Sheets
parse_condition <- function(cond_str) {
  # Simple parsing - assumes format like "field=value"
  if (grepl("=", cond_str)) {
    parts <- strsplit(cond_str, "=")[[1]]
    field <- trimws(parts[1])
    value <- trimws(parts[2])
    return(paste0("input.", field, " == '", value, "'"))
  }
  return(cond_str)  # Return as-is if not recognizable format
}

#' Generate validation rules file
#' @param dd_data Data dictionary data
#' @param forms_dir Directory to store validation files
generate_validation_rules <- function(dd_data, forms_dir) {
  message("Generating validation rules in: ", forms_dir)

  validation_file <- file.path(forms_dir, "validation_rules.R")

  form_definitions <- dd_data$form_definitions
  validation_rules <- c()

  for (form_name in names(form_definitions)) {
    form_def <- form_definitions[[form_name]]

    # Generate validation for required fields
    required_fields <- form_def[form_def$req == 1, ]
    if (nrow(required_fields) > 0) {
      for (i in 1:nrow(required_fields)) {
        field_name <- required_fields$field[i]
        rule <- paste0("validate(need(input$", field_name, ", '", required_fields$prompt[i], " is required'))")
        validation_rules <- c(validation_rules, rule)
      }
    }

    # Generate custom validation rules
    custom_validations <- form_def[!is.na(form_def$valid) & form_def$valid != "", ]
    if (nrow(custom_validations) > 0) {
      for (i in 1:nrow(custom_validations)) {
        field_name <- custom_validations$field[i]
        valid_rule <- custom_validations$valid[i]
        error_msg <- custom_validations$validmsg[i]
        if (is.na(error_msg) || error_msg == "") {
          error_msg <- paste("Invalid value for", custom_validations$prompt[i])
        }
        rule <- paste0("validate(need(", valid_rule, ", '", error_msg, "'))")
        validation_rules <- c(validation_rules, rule)
      }
    }
  }

  # Write validation rules file
  validation_code <- c(
    "# Generated validation rules",
    paste("# Generated on:", Sys.time()),
    "",
    "# Validation rules for all forms",
    "validation_rules <- list(",
    paste("  ", validation_rules, collapse = ",\n"),
    ")"
  )

  writeLines(validation_code, validation_file)
  message("Generated validation file: ", validation_file)
}

#' Verify data dictionary system
#' @param db_path Path to SQLite database file
verify_dd_system <- function(db_path) {
  message("=== Verifying Data Dictionary System ===")

  con <- dbConnect(SQLite(), db_path)
  on.exit(dbDisconnect(con))

  tryCatch({
    # Check required tables exist
    tables <- dbListTables(con)
    expected_tables <- c("edc_forms", "edc_fields", "edc_visits", "edc_field_types")
    missing_tables <- setdiff(expected_tables, tables)

    if (length(missing_tables) > 0) {
      stop("Missing tables: ", paste(missing_tables, collapse = ", "))
    }

    # Check data integrity
    forms_count <- dbGetQuery(con, "SELECT COUNT(*) as count FROM edc_forms")$count
    fields_count <- dbGetQuery(con, "SELECT COUNT(*) as count FROM edc_fields")$count

    if (forms_count == 0) {
      stop("No forms found in edc_forms table")
    }

    if (fields_count == 0) {
      stop("No fields found in edc_fields table")
    }

    # Check views work
    view_data <- dbGetQuery(con, "SELECT * FROM v_forms_detailed LIMIT 1")
    if (nrow(view_data) == 0) {
      warning("Forms detailed view is empty")
    }

    message("✓ All required tables present")
    message("✓ Data integrity checks passed")
    message("✓ Forms: ", forms_count, ", Fields: ", fields_count)

    message("=== Data dictionary verification completed successfully ===")
    return(TRUE)

  }, error = function(e) {
    message("✗ Data dictionary verification failed: ", e$message)
    return(FALSE)
  })
}