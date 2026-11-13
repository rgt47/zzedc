# Lab Landing Page
#
# launch_lab() is a standalone Shiny app, architecturally separate from
# any study's own launch_zzedc() app -- the same "build and run a
# shinyApp() directly" pattern launch_setup_wizard() already uses
# (R/setup_wizard_module.R). It must stay separate: a study's own
# inst/app/global.R sets up db_pool/cfg/db_path as process-wide state
# for exactly one already-open study, and nothing in this package
# supports two studies' global state coexisting in one process. So
# opening or creating a study from this landing page always spawns a
# second, detached R process for it (.spawn_background_r()) rather
# than running it in-process, and then opens that process's own port
# in a new browser tab -- a non-technical user never sees or copies R
# code themselves.
#
# The UI-building pieces below are plain top-level functions (not
# closures nested inside launch_lab()), the same shape
# create_enhanced_ui()/create_setup_ui() already use in
# inst/app/gsheets_ui_integration.R -- so they can be built and
# smoke-tested directly against real list_studies() output without
# starting a Shiny session, the same way create_enhanced_ui() is
# tested elsewhere in this session's test additions.


#' Find an available TCP port
#' @keywords internal
.find_free_port <- function() {
  if (requireNamespace("httpuv", quietly = TRUE)) {
    httpuv::randomPort()
  } else {
    sample(49152:65535, 1)
  }
}


#' Is something already listening on this host/port?
#' @keywords internal
.port_is_alive <- function(host, port) {
  if (is.null(port) || is.na(port)) {
    return(FALSE)
  }
  con <- tryCatch(
    suppressWarnings(socketConnection(host = host, port = port, timeout = 1, open = "r+")),
    error = function(e) NULL
  )
  if (is.null(con)) {
    return(FALSE)
  }
  close(con)
  TRUE
}


#' Block (briefly) until a port starts accepting connections
#' @keywords internal
.wait_for_port <- function(host, port, timeout_s = 25, poll_s = 0.5) {
  deadline <- Sys.time() + timeout_s
  while (Sys.time() < deadline) {
    if (.port_is_alive(host, port)) {
      return(TRUE)
    }
    Sys.sleep(poll_s)
  }
  FALSE
}


#' Run an R expression in a new, detached background process
#'
#' Used so that opening or creating a study starts its own R session
#' (required -- see this file's top comment) without the person running
#' the lab ever seeing or typing R code themselves.
#'
#' @param code A single string of R code to run in the new process.
#' @keywords internal
.spawn_background_r <- function(code) {
  rscript <- file.path(R.home("bin"), "Rscript")
  system2(rscript, args = c("--vanilla", "-e", shQuote(code)),
          stdout = FALSE, stderr = FALSE, wait = FALSE)
  invisible(NULL)
}


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
  initial <- toupper(substr(trimws(row$name), 1, 1))
  div(class = "rgtlab-tile",
    div(class = "d-flex align-items-start justify-content-between",
      div(class = "rgtlab-ico", initial),
      status_badge
    ),
    tags$h4(row$name),
    tags$p(class = "rgtlab-desc mb-3",
           if (!is.na(row$last_opened) && nzchar(row$last_opened)) {
             paste("Last opened:", row$last_opened)
           } else {
             "Never opened from this landing page"
           }),
    tags$button(
      class = "btn btn-rgt-primary btn-sm",
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
}


#' The fixed "+ Create New Database" tile
#' @keywords internal
.create_tile <- function() {
  div(class = "rgtlab-tile text-center d-flex flex-column align-items-center justify-content-center",
    style = "min-height: 200px;",
    div(class = "rgtlab-ico", "+"),
    tags$h4("Create New Database"),
    actionButton("create_new", "Get started", class = "btn btn-rgt-primary btn-sm")
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
    tags$head(tags$title("ZZedc Lab"), .rgtlab_tile_styles()),
    class = "rgtlab-page-bg",
    style = "min-height: 100vh;",
    div(class = "container py-4",
      div(class = "d-flex justify-content-between align-items-center mb-3",
        h2(class = "rgtlab-heading", "ZZedc Lab"),
        actionButton("refresh_studies", "Refresh", class = "btn btn-rgt-ghost btn-sm")
      ),
      p(class = "rgtlab-intro",
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

      host <- "127.0.0.1"
      port <- row$last_port[1]
      already_running <- .port_is_alive(host, port)

      if (!already_running) {
        showModal(modalDialog(
          title = paste("Opening", row$name[1]),
          p("Starting this study in its own R session..."),
          footer = NULL
        ))

        port <- .find_free_port()
        code <- sprintf(
          'setwd(%s); zzedc::launch_zzedc(launch.browser = FALSE, host = %s, port = %dL)',
          deparse(row$path[1]), deparse(host), port
        )
        .spawn_background_r(code)
        .set_study_last_port(id, port)
        ready <- .wait_for_port(host, port)

        if (!ready) {
          showModal(modalDialog(
            title = "Could not start",
            p(row$name[1], " did not start within 25 seconds. Try Open ",
              "again, or ask whoever manages this lab to check it."),
            footer = modalButton("Close")
          ))
          refresh_trigger(refresh_trigger() + 1)
          return(invisible(NULL))
        }
      }

      refresh_trigger(refresh_trigger() + 1)
      url <- sprintf("http://%s:%d/", host, port)
      shinyjs::runjs(sprintf("window.open(%s, '_blank')", jsonlite::toJSON(url, auto_unbox = TRUE)))
      showModal(modalDialog(
        title = paste(row$name[1], "is open"),
        p("Opened in a new browser tab. If a tab did not open, ",
          tags$a(href = url, target = "_blank", "click here"), "."),
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

    if (file.exists(config_path)) {
      output$create_modal_body <- renderUI({
        div(class = "alert alert-warning",
          "This directory already contains a study (config.yml): ", path,
          ". Choose a new, empty directory, or register the existing ",
          "one from its own tile instead."
        )
      })
      return(invisible(NULL))
    }

    output$create_modal_body <- renderUI({
      p("Starting the setup wizard in its own R session...")
    })

    host <- "127.0.0.1"
    port <- .find_free_port()
    code <- sprintf(
      'zzedc::launch_setup_wizard(base_path = %s, launch.browser = FALSE, host = %s, port = %dL)',
      deparse(path), deparse(host), port
    )
    .spawn_background_r(code)
    ready <- .wait_for_port(host, port)

    if (!ready) {
      output$create_modal_body <- renderUI({
        div(class = "alert alert-danger",
            "The setup wizard did not start within 25 seconds. Try again.")
      })
      return(invisible(NULL))
    }

    url <- sprintf("http://%s:%d/", host, port)
    shinyjs::runjs(sprintf("window.open(%s, '_blank')", jsonlite::toJSON(url, auto_unbox = TRUE)))
    output$create_modal_body <- renderUI({
      tagList(
        p("Opened the setup wizard in a new browser tab. If a tab did ",
          "not open, ", tags$a(href = url, target = "_blank", "click here"), "."),
        p("Fill it in there. Once you reach \"Launch ZZedc\" or ",
          "\"Create Study\" in that tab, come back here and click ",
          "Register below."),
        actionButton("register_new_study", "Register this study", class = "btn btn-success btn-sm")
      )
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
#' one. Clicking a tile's **Open** button never launches that study in
#' this process (each study needs its own process -- see this file's
#' top comment for why); instead it starts a detached background R
#' session running [launch_zzedc()] for that study and opens its page
#' in a new browser tab automatically, with no R code for the person
#' running the lab to see or type. **+ Create New Database** does the
#' same for [launch_setup_wizard()], plus a **Register this study**
#' button to add it to the lab once the wizard has finished.
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
