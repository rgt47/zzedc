# Lab Landing Page
#
# launch_lab() is a standalone Shiny app, architecturally separate from
# any study's own launch_zzedc() app -- the same "build and run a
# shinyApp() directly" pattern launch_setup_wizard() already uses
# (R/setup_wizard_module.R). It must stay separate: a study's own
# inst/app/global.R sets up db_pool/cfg/db_path as process-wide state
# for exactly one already-open study, and nothing in this package
# supports two studies' global state coexisting in one process. So
# this landing page never opens a study itself; it only lists what the
# registry (R/lab_registry.R) knows about and shows the exact command
# to run, in the user's own console/session, to open or create one.
#
# The UI-building pieces below are plain top-level functions (not
# closures nested inside launch_lab()), the same shape
# create_enhanced_ui()/create_setup_ui() already use in
# inst/app/gsheets_ui_integration.R -- so they can be built and
# smoke-tested directly against real list_studies() output without
# starting a Shiny session, the same way create_enhanced_ui() is
# tested elsewhere in this session's test additions.


#' One study's tile on the lab landing page
#'
#' @param row One row of [list_studies()]'s return value.
#' @keywords internal
.study_tile <- function(row) {
  status_badge <- if (!isTRUE(row$exists)) {
    tags$span(class = "badge bg-warning text-dark ms-2", "not found")
  } else {
    NULL
  }
  bslib::card(
    bslib::card_header(
      row$name, status_badge
    ),
    bslib::card_body(
      tags$span(class = "badge bg-secondary mb-2", row$backend),
      tags$p(class = "small text-muted mb-1", row$path),
      tags$p(class = "small text-muted mb-2",
             if (!is.na(row$last_opened) && nzchar(row$last_opened)) {
               paste("Last opened:", row$last_opened)
             } else {
               "Never opened from this landing page"
             }),
      tags$button(
        class = "btn btn-primary btn-sm",
        type = "button",
        onclick = sprintf(
          "Shiny.setInputValue('tile_action', {action: 'open', id: '%s'}, {priority: 'event'})",
          row$id
        ),
        "Open"
      ),
      tags$button(
        class = "btn btn-outline-danger btn-sm ms-2",
        type = "button",
        onclick = sprintf(
          "Shiny.setInputValue('tile_action', {action: 'unregister', id: '%s'}, {priority: 'event'})",
          row$id
        ),
        "Remove from lab"
      )
    )
  )
}


#' The fixed "+ Create New Database" tile
#' @keywords internal
.create_tile <- function() {
  bslib::card(
    bslib::card_body(
      class = "text-center d-flex flex-column justify-content-center",
      style = "min-height: 160px;",
      tags$h4("+"),
      tags$p("Create New Database"),
      actionButton("create_new", "Get started", class = "btn btn-success btn-sm")
    )
  )
}


#' The grid of study tiles plus the create-new tile
#'
#' @param rows [list_studies()]'s return value (zero or more rows).
#' @keywords internal
.studies_grid <- function(rows) {
  tiles <- if (nrow(rows) == 0) {
    list()
  } else {
    lapply(seq_len(nrow(rows)), function(i) .study_tile(rows[i, ]))
  }
  tiles[[length(tiles) + 1]] <- .create_tile()
  bslib::layout_column_wrap(width = "280px", !!!tiles)
}


#' The lab landing page's UI
#' @keywords internal
.lab_ui <- function() {
  bslib::page_fluid(
    theme = bslib::bs_theme(version = 5),
    shinyjs::useShinyjs(),
    tags$head(tags$title("ZZedc Lab")),
    div(class = "container my-4",
      div(class = "d-flex justify-content-between align-items-center mb-3",
        h2("ZZedc Lab"),
        actionButton("refresh_studies", "Refresh", class = "btn btn-outline-secondary btn-sm")
      ),
      p(class = "text-muted",
        "Every study registered with this lab. Register an existing ",
        "deployment, or create a new one, with ", tags$code("register_study()"),
        "."),
      uiOutput("studies_grid")
    )
  )
}


#' The lab landing page's server logic
#' @keywords internal
.lab_server <- function(input, output, session) {

  refresh_trigger <- reactiveVal(0)
  observeEvent(input$refresh_studies, {
    refresh_trigger(refresh_trigger() + 1)
  })

  studies <- reactive({
    refresh_trigger()
    list_studies()
  })

  output$studies_grid <- renderUI({
    .studies_grid(studies())
  })

  observeEvent(input$tile_action, {
    action <- input$tile_action$action
    id <- input$tile_action$id
    rows <- studies()
    row <- rows[rows$id == id, , drop = FALSE]
    if (nrow(row) == 0) {
      return(invisible(NULL))
    }

    if (identical(action, "open")) {
      .touch_study_last_opened(id)
      refresh_trigger(refresh_trigger() + 1)
      command <- sprintf('setwd("%s")\nzzedc::launch_zzedc()', row$path[1])
      showModal(modalDialog(
        title = paste("Open", row$name[1]),
        p("Each study runs in its own R session. Copy and run this ",
          "in a fresh R console:"),
        tags$pre(id = "open_command_text", command),
        tags$button(
          class = "btn btn-outline-primary btn-sm",
          type = "button",
          onclick = "navigator.clipboard.writeText(document.getElementById('open_command_text').innerText)",
          "Copy command"
        ),
        footer = modalButton("Close")
      ))
    } else if (identical(action, "unregister")) {
      showModal(modalDialog(
        title = paste("Remove", row$name[1], "from the lab?"),
        p("This only removes it from this landing page. The study's ",
          "own directory and database are untouched, and you can ",
          "register it again later."),
        footer = tagList(
          modalButton("Cancel"),
          actionButton("confirm_unregister", "Remove", class = "btn btn-danger")
        )
      ))
      session$userData$pending_unregister_id <- id
    }
  })

  observeEvent(input$confirm_unregister, {
    id <- session$userData$pending_unregister_id
    if (!is.null(id)) {
      unregister_study(id)
      refresh_trigger(refresh_trigger() + 1)
    }
    removeModal()
  })

  observeEvent(input$create_new, {
    showModal(modalDialog(
      title = "Create a new study",
      textInput("new_study_name", "Study display name", placeholder = "e.g. My New Trial"),
      textInput("new_study_path", "Target directory (full path)",
                 placeholder = "e.g. /Users/you/prj/srv/my-new-trial"),
      uiOutput("create_modal_body"),
      footer = tagList(
        modalButton("Cancel"),
        actionButton("generate_create_command", "Show setup command", class = "btn btn-primary")
      )
    ))
  })

  observeEvent(input$generate_create_command, {
    req(input$new_study_path)
    path <- normalizePath(input$new_study_path, mustWork = FALSE)
    config_path <- file.path(path, "config.yml")

    output$create_modal_body <- renderUI({
      if (file.exists(config_path)) {
        div(class = "alert alert-warning",
          "This directory already contains a study (config.yml): ", path,
          ". Choose a new, empty directory, or register the existing ",
          "one from its own tile instead."
        )
      } else {
        command <- sprintf('zzedc::launch_setup_wizard(base_path = "%s")', path)
        tagList(
          p("Run this in a fresh R console. When the wizard finishes ",
            "(after \"Launch ZZedc\" or \"Create Study\"), come back here ",
            "and click Register below."),
          tags$pre(id = "create_command_text", command),
          tags$button(
            class = "btn btn-outline-primary btn-sm mb-2",
            type = "button",
            onclick = "navigator.clipboard.writeText(document.getElementById('create_command_text').innerText)",
            "Copy command"
          ),
          br(),
          actionButton("register_new_study", "Register this study", class = "btn btn-success btn-sm")
        )
      }
    })
  })

  observeEvent(input$register_new_study, {
    req(input$new_study_path)
    result <- register_study(
      path = input$new_study_path,
      name = if (nzchar(input$new_study_name %||% "")) input$new_study_name else NULL
    )
    if (isTRUE(result$success)) {
      removeModal()
      refresh_trigger(refresh_trigger() + 1)
    } else {
      output$create_modal_body <- renderUI({
        div(class = "alert alert-danger", result$error)
      })
    }
  })
}


#' Launch the ZZedc Lab landing page
#'
#' Shows every study [register_study()] knows about as a tile (name,
#' backend, path, when it was last opened), plus a tile to set up a new
#' one. Clicking a tile's **Open** button does not launch that study
#' in this process -- it shows the exact command to run yourself in a
#' fresh R console, since each study needs its own process (see this
#' file's top comment for why). The same applies to **+ Create New
#' Database**: it shows the `launch_setup_wizard()` command to run, and
#' a **Register this study** button to add it to the lab once you have
#' actually run that command.
#'
#' @param launch.browser,host,port Passed to [shiny::runApp()].
#' @return Invisibly, whatever [shiny::runApp()] returns.
#'
#' @examples
#' \dontrun{
#' zzedc::launch_lab()
#' }
#' @export
launch_lab <- function(launch.browser = TRUE, host = "127.0.0.1", port = NULL) {
  shiny::runApp(shiny::shinyApp(.lab_ui(), .lab_server),
                launch.browser = launch.browser, host = host, port = port)
}
