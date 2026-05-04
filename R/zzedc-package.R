#' @keywords internal
#' @import shiny
#' @importFrom bslib page_fluid navset_card_tab nav_panel
#' @importFrom bsicons bs_icon
#' @importFrom DT datatable DTOutput
#' @importFrom plotly plotlyOutput renderPlotly plot_ly
#' @importFrom R.utils withTimeout
#' @importFrom graphics plot.new text
#' @importFrom stats aggregate complete.cases median reorder rnorm runif sd
#' @importFrom utils capture.output head modifyList object.size read.csv tail
#'   timestamp write.csv
#' @importFrom rlang .data
"_PACKAGE"

# Declare global variables to avoid R CMD check NOTEs
# These are used in non-standard evaluation (NSE) contexts
utils::globalVariables(c(

  # ggplot2 aesthetics and functions
  "aes", "coord_flip", "geom_bar", "geom_boxplot", "geom_histogram",
  "geom_point", "ggplot", "labs", "theme_minimal",


# plotly functions
  "ggplotly", "plotlyOutput", "renderPlotly",

# dplyr/tidyverse
  "%>%", "case_when", "group_by", "mutate", "select", "summarise",

# bslib components
  "nav_panel", "navset_tab", "small", "label",

# shinyalert
  "shinyalert",

# shinyauthr
  "updatePasswordInput",

# DBI/RSQLite
  "dbConnect", "dbDisconnect", "dbWriteTable", "SQLite",

# Shiny reactive context
  "input", "cfg", "db_pool",

# Column names used in dplyr pipelines (NSE)
  "Missing_Percent", "Variable", "approval_date", "completion_status",
  "event_type", "execution_date", "expiry_date", "reason", "record_id",
  "role", "signature_meaning", "signature_status", "signer_name",
  "signing_timestamp", "status", "table_name", "training_type",
  "user_name", "validation_title", "validation_type", "validator_name",

# DSL parser internals
  "DSLParser", "generate_r_validator", "generate_sql_check"
))

# Package-local environment for session state (avoids .GlobalEnv assignments)
.zzedc_env <- new.env(parent = emptyenv())
