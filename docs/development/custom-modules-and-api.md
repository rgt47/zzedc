# Custom Modules and REST API
*2026-04-30 16:21 PDT*

This document captures developer-facing patterns for extending
ZZedc with custom Shiny modules and for exposing REST API
endpoints to external systems. Both patterns were previously
covered in `vignettes/advanced-features.Rmd`; that vignette has
been retired in favour of the canonical role-based runbooks
plus this developer reference.

The examples here are illustrative rather than load-bearing.
They are not run as part of `R CMD check` and are not unit-tested.
A package extending ZZedc should use them as starting points,
not as drop-in copy targets.

## Custom Shiny modules

ZZedc is organised as Shiny modules in `R/`. A custom module
follows the same `*_ui` / `*_server` convention.

### Example: a pharmacokinetics data-entry module

```{r pk-module-ui}
pk_module_ui <- function(id) {
  ns <- NS(id)

  tagList(
    fluidRow(
      column(12,
        h3('Pharmacokinetics Data Entry'),

        wellPanel(
          h4('Sample Collection'),
          fluidRow(
            column(4,
              dateInput(ns('collection_date'), 'Collection Date')
            ),
            column(4,
              timeInput(ns('collection_time'), 'Collection Time')
            ),
            column(4,
              selectInput(
                ns('sample_type'), 'Sample Type',
                choices = c('Plasma', 'Serum', 'Urine', 'Saliva')
              )
            )
          )
        ),

        wellPanel(
          h4('Concentration Results'),
          fluidRow(
            column(6,
              numericInput(
                ns('concentration'), 'Concentration (ng/mL)',
                value = NULL, min = 0
              )
            ),
            column(6,
              selectInput(
                ns('assay_method'), 'Assay Method',
                choices = c('LC-MS/MS', 'ELISA', 'RIA')
              )
            )
          ),
          fluidRow(
            column(6,
              numericInput(
                ns('lloq'), 'LLOQ (ng/mL)',
                value = NULL, min = 0
              )
            ),
            column(6,
              checkboxInput(ns('below_lloq'), 'Below LLOQ')
            )
          )
        ),

        wellPanel(
          h4('Quality Control'),
          fluidRow(
            column(6,
              selectInput(
                ns('analyst'), 'Analyst',
                choices = c('Analyst 1', 'Analyst 2', 'Analyst 3')
              )
            ),
            column(6,
              dateInput(ns('analysis_date'), 'Analysis Date')
            )
          ),
          textAreaInput(ns('comments'), 'Comments', rows = 3)
        ),

        fluidRow(
          column(12,
            actionButton(ns('save_data'), 'Save PK Data',
                         class = 'btn-primary'),
            actionButton(ns('validate_data'), 'Validate',
                         class = 'btn-warning'),
            actionButton(ns('clear_form'), 'Clear Form',
                         class = 'btn-secondary')
          )
        )
      )
    ),
    fluidRow(
      column(12,
        h4('Existing PK Data'),
        DT::dataTableOutput(ns('pk_data_table'))
      )
    )
  )
}
```

```{r pk-module-server}
pk_module_server <- function(id) {
  moduleServer(id, function(input, output, session) {

    pk_data <- reactiveVal(data.frame(
      subject_id = character(),
      collection_date = as.Date(character()),
      collection_time = character(),
      sample_type = character(),
      concentration = numeric(),
      assay_method = character(),
      lloq = numeric(),
      below_lloq = logical(),
      analyst = character(),
      analysis_date = as.Date(character()),
      comments = character(),
      stringsAsFactors = FALSE
    ))

    validate_pk_data <- function() {
      errors <- c()

      if (is.null(input$collection_date) ||
          is.na(input$collection_date)) {
        errors <- c(errors, 'Collection date is required')
      }

      if (is.null(input$concentration) ||
          is.na(input$concentration)) {
        if (!input$below_lloq) {
          errors <- c(errors,
                      'Concentration required if not below LLOQ')
        }
      }

      if (input$below_lloq &&
          !is.null(input$concentration) &&
          !is.na(input$concentration)) {
        if (input$concentration >= input$lloq) {
          errors <- c(
            errors,
            "Concentration should be below LLOQ if 'Below LLOQ' is checked"
          )
        }
      }

      errors
    }

    observeEvent(input$save_data, {
      validation_errors <- validate_pk_data()

      if (length(validation_errors) > 0) {
        showModal(modalDialog(
          title = 'Validation Errors',
          HTML(paste(validation_errors, collapse = '<br>')),
          easyClose = TRUE,
          footer = modalButton('OK')
        ))
        return()
      }

      new_record <- data.frame(
        subject_id = 'CURRENT_SUBJECT',
        collection_date = input$collection_date,
        collection_time = format(input$collection_time, '%H:%M'),
        sample_type = input$sample_type,
        concentration = ifelse(input$below_lloq, NA,
                                input$concentration),
        assay_method = input$assay_method,
        lloq = input$lloq,
        below_lloq = input$below_lloq,
        analyst = input$analyst,
        analysis_date = input$analysis_date,
        comments = input$comments,
        stringsAsFactors = FALSE
      )

      pk_data(rbind(pk_data(), new_record))
      showNotification('PK data saved successfully',
                       type = 'success')
    })

    observeEvent(input$clear_form, {
      updateDateInput(session, 'collection_date', value = NA)
      updateNumericInput(session, 'concentration', value = NA)
      updateTextAreaInput(session, 'comments', value = '')
    })

    output$pk_data_table <- DT::renderDataTable({
      DT::datatable(
        pk_data(),
        options = list(scrollX = TRUE, pageLength = 10),
        class = 'cell-border stripe hover'
      )
    })
  })
}
```

### Wiring a custom module into the application

```{r integrate-module}
custom_ui_integration <- function() {
  nav_panel('Pharmacokinetics',
    pk_module_ui('pk_module')
  )
}

custom_server_integration <- function(input, output, session) {
  pk_module_server('pk_module')
}
```

A production custom module should also:

- write to a dedicated table created at study-init time, not a
  reactive value;
- log mutations through `log_audit_event()` from
  `R/audit_logging.R` so the hash chain remains complete;
- use `db_users` helpers from `R/db_users.R` rather than
  open-coding user inserts;
- declare its DB columns in the same migration file used by
  `create_study_database()` so a fresh deploy initialises
  consistently.

## REST API endpoints

ZZedc does not ship with a built-in REST surface. Sites that
need machine-to-machine integration can attach an API layer
above the database adapter. The recipes below are illustrative.

### Endpoint helpers

```{r api-endpoints}
create_api_endpoints <- function() {

  get_subject_data <- function(subject_id) {
    query <- 'SELECT * FROM subjects WHERE subject_id = ?'
    result <- pool::dbGetQuery(db_pool, query,
                               params = list(subject_id))

    if (nrow(result) == 0) {
      return(list(
        status = 'error',
        message = 'Subject not found',
        data = NULL
      ))
    }

    list(status = 'success', data = result)
  }

  submit_external_data <- function(data_payload) {
    validation_result <- validate_external_data(data_payload)

    if (!validation_result$valid) {
      return(list(
        status = 'error',
        message = 'Validation failed',
        errors = validation_result$errors
      ))
    }

    tryCatch({
      pool::dbExecute(
        db_pool,
        paste(
          'INSERT INTO external_data',
          '(subject_id, data_type, data_value, timestamp)',
          'VALUES (?, ?, ?, ?)'
        ),
        params = list(
          data_payload$subject_id,
          data_payload$data_type,
          data_payload$data_value,
          Sys.time()
        )
      )
      list(status = 'success',
           message = 'Data submitted successfully')
    }, error = function(e) {
      list(status = 'error',
           message = paste('Database error:', e$message))
    })
  }

  get_study_statistics <- function() {
    stats_query <- "
      SELECT
        COUNT(*) AS total_subjects,
        COUNT(CASE WHEN status = 'Active'    THEN 1 END) AS active_subjects,
        COUNT(CASE WHEN status = 'Completed' THEN 1 END) AS completed_subjects,
        AVG(age) AS mean_age
      FROM subjects
    "
    result <- pool::dbGetQuery(db_pool, stats_query)
    list(status = 'success', data = result)
  }

  list(
    get_subject = get_subject_data,
    submit_data = submit_external_data,
    get_stats = get_study_statistics
  )
}
```

### Example client

```{r api-client}
call_zzedc_api <- function(endpoint, method = 'GET', data = NULL) {
  base_url <- 'http://localhost:3838/api'
  url <- paste0(base_url, '/', endpoint)

  if (method == 'GET') {
    response <- httr::GET(url)
  } else if (method == 'POST') {
    response <- httr::POST(
      url,
      body = jsonlite::toJSON(data),
      encode = 'json',
      httr::add_headers('Content-Type' = 'application/json')
    )
  }

  content <- httr::content(response, 'text')
  jsonlite::fromJSON(content)
}

subject_data <- call_zzedc_api('subject/STUDY001')
study_stats <- call_zzedc_api('statistics')

external_data <- list(
  subject_id = 'STUDY001',
  data_type = 'laboratory',
  data_value = 'hemoglobin:12.5'
)

submission_result <- call_zzedc_api('submit', 'POST',
                                    external_data)
```

### Operational notes

A REST surface attached to ZZedc should:

- run behind the same TLS termination as the Shiny application;
- authenticate callers against the same `edc_users` table; pair
  with API keys or signed JWTs rather than cookie-based session
  auth;
- log every mutation through `log_audit_event()` so the hash
  chain remains a single source of truth across UI and API;
- treat all writes as audited: a pure-API write should produce
  the same audit row as a UI write of the same record.

## Where this content used to live

Both sections were originally part of `vignettes/advanced-features.Rmd`.
That vignette also covered multi-factor authentication, RBAC,
audit logging, 21 CFR Part 11 features, and multi-backend
configuration. Those topics now live in their canonical homes:

- Multi-backend configuration: `vignette('backend-quickstart')`.
- Authentication and RBAC architecture: `vignette('technical-lead-guide')`
  Chapter 7 and Appendix C.
- Audit logging and Part 11 features: `docs/compliance/gdpr-and-cfr-part11.md`.
- Encryption: `vignette('technical-lead-guide')` Chapter 5.

---
*Source: ~/Dropbox/prj/sfw/05-zzedc/zzedc/docs/development/custom-modules-and-api.md*
