#' @keywords internal
#' @import shiny
#' @importFrom bslib page_fluid navset_card_tab navset_tab nav_panel
#' @importFrom bsicons bs_icon
#' @importFrom DT datatable DTOutput
#' @importFrom plotly plotlyOutput renderPlotly plot_ly ggplotly
#' @importFrom R.utils withTimeout
#' @importFrom graphics plot.new text
#' @importFrom stats aggregate complete.cases median reorder rnorm runif sd
#' @importFrom utils capture.output head modifyList object.size read.csv tail timestamp write.csv
#' @importFrom rlang .data
#' @importFrom dplyr case_when group_by mutate select summarise "%>%"
#' @importFrom ggplot2 aes coord_flip geom_bar geom_boxplot geom_histogram geom_point ggplot labs theme_minimal
#' @importFrom shinyalert shinyalert
#' @importFrom DBI dbConnect dbDisconnect dbWriteTable
#' @importFrom RSQLite SQLite
"_PACKAGE"

# Declare global variables to avoid R CMD check NOTEs
# These are used in non-standard evaluation (NSE) contexts. Function
# names that resolve to real package exports are declared above via
# @importFrom instead; this list is for genuine NSE symbols plus a few
# names not yet traced to a declared dependency (see below).
utils::globalVariables(c(

# small()/label() are used as bare calls in cfr_compliance_module.R
# and admin_dashboard_module.R but do not resolve to any declared
# Import; likely a missing `tags$` prefix or an undeclared dependency.
# updatePasswordInput() is from shinyauthr, which is used but never
# declared in DESCRIPTION Imports or Suggests. Left as globalVariables
# rather than guess-importing an unverified package.
  "small", "label", "updatePasswordInput",

# Shiny reactive context
  "input", "cfg", "db_pool",

# Column names used in dplyr pipelines (NSE)
  "Missing_Percent", "Variable", "approval_date", "completion_status",
  "event_type", "execution_date", "expiry_date", "reason", "record_id",
  "role", "signature_meaning", "signature_status", "signer_name",
  "signing_timestamp", "status", "table_name", "training_type",
  "user_name", "validation_title", "validation_type", "validator_name",

# DSL parser internals (referenced as objects, not calls)
  "DSLParser", "generate_r_validator", "generate_sql_check"
))

# Package-local environment for session state (avoids .GlobalEnv assignments)
.zzedc_env <- new.env(parent = emptyenv())
