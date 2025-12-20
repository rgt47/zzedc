#' Calculated/Derived Fields (Feature #31)
#'
#' Auto-calculated fields with formula definitions for BMI,
#' age calculations, date differences, and custom formulas.
#'
#' @name calculated_fields
#' @docType package
NULL

#' @keywords internal
safe_scalar_cf <- function(x, default = NA_character_) {
  if (is.null(x) || length(x) == 0) default
  else if (length(x) > 1) paste(x, collapse = "; ")
  else as.character(x)
}

#' Initialize Calculated Fields System
#' @return List with success status
#' @export
init_calculated_fields <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS calculated_field_definitions (
        calc_id INTEGER PRIMARY KEY AUTOINCREMENT,
        calc_code TEXT UNIQUE NOT NULL,
        calc_name TEXT NOT NULL,
        target_field_code TEXT NOT NULL,
        calc_type TEXT NOT NULL,
        formula TEXT NOT NULL,
        source_fields TEXT NOT NULL,
        result_type TEXT DEFAULT 'NUMBER',
        decimal_places INTEGER DEFAULT 2,
        form_id INTEGER,
        is_active INTEGER DEFAULT 1,
        calculate_on_save INTEGER DEFAULT 1,
        created_at TEXT DEFAULT (datetime('now')),
        created_by TEXT NOT NULL
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS calculation_history (
        history_id INTEGER PRIMARY KEY AUTOINCREMENT,
        calc_id INTEGER NOT NULL,
        record_id TEXT,
        subject_id TEXT,
        input_values TEXT,
        calculated_value TEXT,
        calculated_at TEXT DEFAULT (datetime('now')),
        calculated_by TEXT,
        FOREIGN KEY (calc_id) REFERENCES calculated_field_definitions(calc_id)
      )
    ")

    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS standard_formulas (
        formula_id INTEGER PRIMARY KEY AUTOINCREMENT,
        formula_code TEXT UNIQUE NOT NULL,
        formula_name TEXT NOT NULL,
        formula_category TEXT NOT NULL,
        formula_template TEXT NOT NULL,
        required_inputs TEXT NOT NULL,
        output_type TEXT NOT NULL,
        description TEXT
      )
    ")

    list(success = TRUE, message = "Calculated fields system initialized")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Calculation Types
#' @return Named character vector
#' @export
get_calculation_types <- function() {
  c(
    ARITHMETIC = "Basic arithmetic operations",
    DATE_DIFF = "Date difference calculations",
    AGE = "Age calculation from date of birth",
    BMI = "Body Mass Index calculation",
    BSA = "Body Surface Area calculation",
    CREATININE_CLEARANCE = "Creatinine clearance (Cockcroft-Gault)",
    PERCENTAGE = "Percentage calculation",
    SCORE_SUM = "Sum of score fields",
    CUSTOM = "Custom formula"
  )
}

#' Get Result Types
#' @return Named character vector
#' @export
get_result_types <- function() {
  c(
    NUMBER = "Numeric result",
    INTEGER = "Integer result",
    DATE = "Date result",
    TEXT = "Text result",
    BOOLEAN = "Boolean (TRUE/FALSE)"
  )
}

#' Load Standard Formulas
#' @return List with success status
#' @export
load_standard_formulas <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    formulas <- list(
      list(code = "BMI", name = "Body Mass Index",
           cat = "ANTHROPOMETRIC",
           template = "WEIGHT / (HEIGHT/100)^2",
           inputs = "WEIGHT,HEIGHT",
           output = "NUMBER",
           desc = "BMI = weight(kg) / height(m)^2"),
      list(code = "AGE_YEARS", name = "Age in Years",
           cat = "DATE",
           template = "FLOOR((REFERENCE_DATE - BIRTH_DATE) / 365.25)",
           inputs = "BIRTH_DATE,REFERENCE_DATE",
           output = "INTEGER",
           desc = "Calculate age in complete years"),
      list(code = "DATE_DIFF_DAYS", name = "Date Difference (Days)",
           cat = "DATE",
           template = "END_DATE - START_DATE",
           inputs = "START_DATE,END_DATE",
           output = "INTEGER",
           desc = "Days between two dates"),
      list(code = "BSA_DUBOIS", name = "Body Surface Area (DuBois)",
           cat = "ANTHROPOMETRIC",
           template = "0.007184 * WEIGHT^0.425 * HEIGHT^0.725",
           inputs = "WEIGHT,HEIGHT",
           output = "NUMBER",
           desc = "BSA using DuBois formula"),
      list(code = "CRCL_CG", name = "Creatinine Clearance (Cockcroft-Gault)",
           cat = "CLINICAL",
           template = "((140 - AGE) * WEIGHT * SEX_FACTOR) / (72 * CREATININE)",
           inputs = "AGE,WEIGHT,CREATININE,SEX",
           output = "NUMBER",
           desc = "CrCl using Cockcroft-Gault, SEX_FACTOR=1 for male, 0.85 for female"),
      list(code = "PERCENTAGE", name = "Percentage",
           cat = "ARITHMETIC",
           template = "(PART / TOTAL) * 100",
           inputs = "PART,TOTAL",
           output = "NUMBER",
           desc = "Calculate percentage")
    )

    count <- 0
    for (f in formulas) {
      existing <- DBI::dbGetQuery(con, "
        SELECT formula_id FROM standard_formulas WHERE formula_code = ?
      ", params = list(f$code))

      if (nrow(existing) == 0) {
        DBI::dbExecute(con, "
          INSERT INTO standard_formulas (
            formula_code, formula_name, formula_category, formula_template,
            required_inputs, output_type, description
          ) VALUES (?, ?, ?, ?, ?, ?, ?)
        ", params = list(
          f$code, f$name, f$cat, f$template, f$inputs, f$output, f$desc
        ))
        count <- count + 1
      }
    }

    list(success = TRUE, formulas_loaded = count)
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Standard Formulas
#' @param category Optional category filter
#' @return List with formulas
#' @export
get_standard_formulas <- function(category = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    if (is.null(category)) {
      formulas <- DBI::dbGetQuery(con, "SELECT * FROM standard_formulas")
    } else {
      formulas <- DBI::dbGetQuery(con, "
        SELECT * FROM standard_formulas WHERE formula_category = ?
      ", params = list(category))
    }

    list(success = TRUE, formulas = formulas, count = nrow(formulas))
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Create Calculated Field
#' @param calc_code Unique code
#' @param calc_name Name
#' @param target_field_code Target field
#' @param calc_type Type
#' @param formula Formula
#' @param source_fields Comma-separated source fields
#' @param created_by User creating
#' @param result_type Result type
#' @param decimal_places Decimal places
#' @param form_id Optional form ID
#' @param calculate_on_save Calculate on save
#' @return List with success status
#' @export
create_calculated_field <- function(calc_code, calc_name, target_field_code,
                                     calc_type, formula, source_fields,
                                     created_by, result_type = "NUMBER",
                                     decimal_places = 2, form_id = NULL,
                                     calculate_on_save = TRUE) {
  tryCatch({
    if (missing(calc_code) || calc_code == "") {
      return(list(success = FALSE, error = "calc_code is required"))
    }

    valid_types <- names(get_calculation_types())
    if (!calc_type %in% valid_types) {
      return(list(success = FALSE,
                  error = paste("Invalid calc_type:", calc_type)))
    }

    valid_results <- names(get_result_types())
    if (!result_type %in% valid_results) {
      return(list(success = FALSE,
                  error = paste("Invalid result_type:", result_type)))
    }

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      INSERT INTO calculated_field_definitions (
        calc_code, calc_name, target_field_code, calc_type, formula,
        source_fields, result_type, decimal_places, form_id,
        calculate_on_save, created_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      calc_code, calc_name, target_field_code, calc_type, formula,
      source_fields, result_type, as.integer(decimal_places),
      if (is.null(form_id)) NA_integer_ else as.integer(form_id),
      as.integer(calculate_on_save), created_by
    ))

    calc_id <- DBI::dbGetQuery(con,
      "SELECT last_insert_rowid() as id")$id[1]

    list(success = TRUE, calc_id = calc_id)
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Calculate BMI
#' @param weight Weight in kg
#' @param height Height in cm
#' @param decimal_places Decimal places
#' @return List with BMI value
#' @export
calculate_bmi <- function(weight, height, decimal_places = 2) {
  tryCatch({
    if (is.null(weight) || is.null(height) ||
        is.na(weight) || is.na(height)) {
      return(list(success = FALSE, error = "Weight and height required"))
    }

    weight <- as.numeric(weight)
    height <- as.numeric(height)

    if (weight <= 0 || height <= 0) {
      return(list(success = FALSE, error = "Values must be positive"))
    }

    height_m <- height / 100
    bmi <- weight / (height_m^2)
    bmi <- round(bmi, decimal_places)

    category <- if (bmi < 18.5) {
      "Underweight"
    } else if (bmi < 25) {
      "Normal weight"
    } else if (bmi < 30) {
      "Overweight"
    } else {
      "Obese"
    }

    list(success = TRUE, bmi = bmi, category = category)
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Calculate Age
#' @param birth_date Date of birth
#' @param reference_date Reference date (default: today)
#' @return List with age
#' @export
calculate_age <- function(birth_date, reference_date = Sys.Date()) {
  tryCatch({
    if (is.null(birth_date) || is.na(birth_date)) {
      return(list(success = FALSE, error = "birth_date required"))
    }

    if (is.character(birth_date)) {
      birth_date <- as.Date(birth_date)
    }
    if (is.character(reference_date)) {
      reference_date <- as.Date(reference_date)
    }

    if (birth_date > reference_date) {
      return(list(success = FALSE,
                  error = "birth_date cannot be after reference_date"))
    }

    age_days <- as.numeric(reference_date - birth_date)
    age_years <- floor(age_days / 365.25)
    age_months <- floor((age_days %% 365.25) / 30.44)

    list(success = TRUE, age_years = age_years, age_months = age_months,
         age_days = age_days)
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Calculate Date Difference
#' @param start_date Start date
#' @param end_date End date
#' @param unit Unit (days, weeks, months, years)
#' @return List with difference
#' @export
calculate_date_diff <- function(start_date, end_date, unit = "days") {
  tryCatch({
    if (is.null(start_date) || is.null(end_date)) {
      return(list(success = FALSE, error = "Both dates required"))
    }

    if (is.character(start_date)) start_date <- as.Date(start_date)
    if (is.character(end_date)) end_date <- as.Date(end_date)

    days <- as.numeric(end_date - start_date)

    result <- switch(unit,
      days = days,
      weeks = days / 7,
      months = days / 30.44,
      years = days / 365.25,
      days
    )

    list(success = TRUE, difference = result, unit = unit, days = days)
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Calculate Body Surface Area
#' @param weight Weight in kg
#' @param height Height in cm
#' @param formula Formula to use (DUBOIS, MOSTELLER)
#' @return List with BSA
#' @export
calculate_bsa <- function(weight, height, formula = "DUBOIS") {
  tryCatch({
    if (is.null(weight) || is.null(height)) {
      return(list(success = FALSE, error = "Weight and height required"))
    }

    weight <- as.numeric(weight)
    height <- as.numeric(height)

    bsa <- switch(formula,
      DUBOIS = 0.007184 * (weight^0.425) * (height^0.725),
      MOSTELLER = sqrt((height * weight) / 3600),
      0.007184 * (weight^0.425) * (height^0.725)
    )

    list(success = TRUE, bsa = round(bsa, 4), formula_used = formula)
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Calculate Score Sum
#' @param values Vector of values to sum
#' @param na_handling How to handle NA (ignore, zero, error)
#' @return List with sum
#' @export
calculate_score_sum <- function(values, na_handling = "ignore") {

  tryCatch({
    if (is.null(values) || length(values) == 0) {
      return(list(success = FALSE, error = "Values required"))
    }

    values <- as.numeric(values)

    if (na_handling == "error" && any(is.na(values))) {
      return(list(success = FALSE, error = "NA values found"))
    }

    if (na_handling == "zero") {
      values[is.na(values)] <- 0
    }

    total <- sum(values, na.rm = (na_handling == "ignore"))
    count <- sum(!is.na(values))

    list(success = TRUE, sum = total, count = count,
         mean = if (count > 0) total / count else NA)
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Record Calculation
#' @param calc_id Calculation ID
#' @param input_values Input values (JSON or comma-separated)
#' @param calculated_value Result
#' @param calculated_by User
#' @param record_id Optional record ID
#' @param subject_id Optional subject ID
#' @return List with success status
#' @export
record_calculation <- function(calc_id, input_values, calculated_value,
                                calculated_by, record_id = NULL,
                                subject_id = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    DBI::dbExecute(con, "
      INSERT INTO calculation_history (
        calc_id, record_id, subject_id, input_values,
        calculated_value, calculated_by
      ) VALUES (?, ?, ?, ?, ?, ?)
    ", params = list(
      calc_id, safe_scalar_cf(record_id), safe_scalar_cf(subject_id),
      input_values, as.character(calculated_value), calculated_by
    ))

    list(success = TRUE, message = "Calculation recorded")
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Calculated Fields
#' @param form_id Optional form filter
#' @param include_inactive Include inactive
#' @return List with calculations
#' @export
get_calculated_fields <- function(form_id = NULL, include_inactive = FALSE) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    query <- "SELECT * FROM calculated_field_definitions WHERE 1=1"
    params <- list()

    if (!include_inactive) {
      query <- paste(query, "AND is_active = 1")
    }
    if (!is.null(form_id)) {
      query <- paste(query, "AND form_id = ?")
      params <- append(params, list(form_id))
    }

    if (length(params) > 0) {
      calcs <- DBI::dbGetQuery(con, query, params = params)
    } else {
      calcs <- DBI::dbGetQuery(con, query)
    }

    list(success = TRUE, calculations = calcs, count = nrow(calcs))
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Calculation History
#' @param calc_id Calculation ID
#' @param subject_id Optional subject filter
#' @return List with history
#' @export
get_calculation_history <- function(calc_id, subject_id = NULL) {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    if (is.null(subject_id)) {
      history <- DBI::dbGetQuery(con, "
        SELECT * FROM calculation_history
        WHERE calc_id = ?
        ORDER BY calculated_at DESC
      ", params = list(calc_id))
    } else {
      history <- DBI::dbGetQuery(con, "
        SELECT * FROM calculation_history
        WHERE calc_id = ? AND subject_id = ?
        ORDER BY calculated_at DESC
      ", params = list(calc_id, subject_id))
    }

    list(success = TRUE, history = history, count = nrow(history))
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}

#' Get Calculated Fields Statistics
#' @return List with statistics
#' @export
get_calculated_fields_statistics <- function() {
  tryCatch({
    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    stats <- DBI::dbGetQuery(con, "
      SELECT
        (SELECT COUNT(*) FROM calculated_field_definitions WHERE is_active = 1)
          as active_calculations,
        (SELECT COUNT(*) FROM calculation_history) as total_executions,
        (SELECT COUNT(*) FROM standard_formulas) as standard_formulas
    ")

    by_type <- DBI::dbGetQuery(con, "
      SELECT calc_type, COUNT(*) as count
      FROM calculated_field_definitions WHERE is_active = 1
      GROUP BY calc_type
    ")

    list(success = TRUE, statistics = as.list(stats), by_type = by_type)
  }, error = function(e) {
    list(success = FALSE, error = e$message)
  })
}
