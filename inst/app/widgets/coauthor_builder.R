# Co-author builder widget
#
# Attached to a form's co_authors-style field via its
# designer_fields.widget_file value ("coauthor_builder"), resolved
# and sourced by zzedc:::load_widget_module() -- see
# R/edc_widget_loader.R for the contract every widget file must
# follow (widget_ui(id), widget_server(id, db_pool, parent_session,
# target_field)).
#
# Builds the target field's text from individual author names in a
# chosen name format and delimiter, or reformats whatever text is
# already there. Every pure string-manipulation helper this relies
# on (format_author_name(), join_author_names(), split_author_list(),
# parse_author_name()) lives in the zzedc package itself
# (R/edc_coauthor_widget.R), not here -- this file is purely the
# Shiny UI/server wiring around them, sourced into its own isolated
# environment rather than attached to the package namespace, so it
# reaches those functions via zzedc:::.

widget_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tags$div(
    style = "margin-top: -0.75rem; margin-bottom: 0.75rem;",
    shiny::actionButton(ns("open"), "Co-author builder…",
                         class = "btn btn-sm btn-outline-secondary")
  )
}

widget_server <- function(id, db_pool, parent_session, target_field) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    rows <- shiny::reactiveVal(list())
    next_id <- shiny::reactiveVal(1L)

    shiny::observeEvent(input$open, {
      shiny::showModal(shiny::modalDialog(
        title = "Co-author builder", size = "l", easyClose = TRUE,
        footer = shiny::modalButton("Close"),

        shiny::tags$div(
          class = "text-muted mb-2",
          "Builds the Co-authors field above from individual names; ",
          "it only ever writes to that one field."
        ),
        shiny::fluidRow(
          shiny::column(4, shiny::selectInput(ns("format"), "Name format", choices = c(
            "First Middle Last"  = "first_middle_last",
            "Last, First Middle" = "last_first_middle",
            "Last, Initials"     = "last_initials"
          ))),
          shiny::column(4, shiny::selectInput(ns("delim"), "Delimiter", choices = c(
            "Comma"                       = "comma",
            "Semicolon"                   = "semicolon",
            "Comma + \"and\" before last" = "comma_and"
          ))),
          shiny::column(4, style = "padding-top: 1.75rem;",
            shiny::actionButton(ns("reformat"), "Reformat existing text",
                                 class = "btn btn-sm btn-outline-secondary"))
        ),
        shiny::tags$div(
          class = "text-muted mb-2", style = "font-size: 0.8em;",
          shiny::tags$strong("Reformatting existing text: "),
          "pick the delimiter the text above is ALREADY split on. If ",
          "it's in \"Last, First\" or \"Last, Initials\" style, pick ",
          "Semicolon -- each name's own comma otherwise looks just ",
          "like the delimiter between names and splits it apart."
        ),
        shiny::fluidRow(
          shiny::column(4, shiny::textInput(ns("first"), "First name")),
          shiny::column(4, shiny::textInput(ns("middle"), "Middle name/initial")),
          shiny::column(4, shiny::textInput(ns("last"), "Last name"))
        ),
        shiny::actionButton(ns("add"), "Add author", class = "btn btn-sm btn-primary mb-2"),
        shiny::uiOutput(ns("preview"))
      ))
    })

    shiny::observeEvent(input$add, {
      first <- trimws(input$first %||% "")
      middle <- trimws(input$middle %||% "")
      last <- trimws(input$last %||% "")
      if (!nzchar(first) && !nzchar(last)) return(invisible(NULL))

      rid <- as.character(next_id())
      current <- rows()
      current[[rid]] <- list(first = first, middle = middle, last = last)
      rows(current)
      next_id(next_id() + 1L)

      shiny::updateTextInput(session, "first", value = "")
      shiny::updateTextInput(session, "middle", value = "")
      shiny::updateTextInput(session, "last", value = "")
    }, ignoreInit = TRUE)

    # Each row's Edit/Remove button is created dynamically, so a
    # static observeEvent per button isn't possible; each button
    # instead calls Shiny.setInputValue() with its own (module-
    # namespaced) input id via onclick, and these two observers
    # dispatch on whichever row id comes through.
    shiny::observeEvent(input$remove_click, {
      current <- rows()
      current[[input$remove_click]] <- NULL
      rows(current)
    }, ignoreInit = TRUE)

    shiny::observeEvent(input$edit_click, {
      rid <- input$edit_click
      current <- rows()
      row <- current[[rid]]
      if (is.null(row)) return(invisible(NULL))
      current[[rid]] <- NULL
      rows(current)
      shiny::updateTextInput(session, "first", value = row$first)
      shiny::updateTextInput(session, "middle", value = row$middle)
      shiny::updateTextInput(session, "last", value = row$last)
    }, ignoreInit = TRUE)

    shiny::observeEvent(input$apply, {
      current <- rows()
      fmt <- input$format %||% "first_middle_last"
      delim <- input$delim %||% "comma"
      formatted <- vapply(current, function(r) {
        zzedc:::format_author_name(r$first, r$middle, r$last, format = fmt)
      }, character(1))
      shiny::updateTextInput(parent_session, target_field,
                              value = zzedc:::join_author_names(formatted, delimiter = delim))
      shiny::removeModal()
    }, ignoreInit = TRUE)

    # Parses the target field's CURRENT text (using the selected
    # delimiter as the splitting rule) back into rows, loads them
    # for review/editing, and immediately writes the reassembled
    # text back -- a no-op round trip if the parse was clean, and a
    # starting point to fix up via Edit/Remove if it wasn't (see
    # parse_author_name()'s documented limitations).
    shiny::observeEvent(input$reformat, {
      delim <- input$delim %||% "comma"
      current_text <- shiny::isolate(parent_session$input[[target_field]])
      pieces <- zzedc:::split_author_list(current_text, delimiter = delim)
      if (length(pieces) == 0) return(invisible(NULL))

      parsed <- lapply(pieces, zzedc:::parse_author_name)
      start_id <- next_id()
      ids <- as.character(seq(start_id, length.out = length(parsed)))
      rows(stats::setNames(parsed, ids))
      next_id(start_id + length(parsed))

      fmt <- input$format %||% "first_middle_last"
      formatted <- vapply(parsed, function(r) {
        zzedc:::format_author_name(r$first, r$middle, r$last, format = fmt)
      }, character(1))
      shiny::updateTextInput(parent_session, target_field,
                              value = zzedc:::join_author_names(formatted, delimiter = delim))
    }, ignoreInit = TRUE)

    output$preview <- shiny::renderUI({
      current <- rows()
      if (length(current) == 0) {
        return(shiny::div(class = "text-muted", "No authors added yet."))
      }
      fmt <- input$format %||% "first_middle_last"
      delim <- input$delim %||% "comma"

      formatted <- vapply(current, function(r) {
        zzedc:::format_author_name(r$first, r$middle, r$last, format = fmt)
      }, character(1))

      row_items <- Map(function(rid, label) {
        shiny::tags$li(
          class = "d-flex justify-content-between align-items-center mb-1",
          shiny::span(label),
          shiny::tags$span(
            shiny::tags$button(
              type = "button", class = "btn btn-sm btn-outline-secondary py-0 px-2",
              style = "margin-right: 4px;",
              onclick = sprintf(
                "Shiny.setInputValue('%s', '%s', {priority: 'event'})", ns("edit_click"), rid
              ),
              "Edit"
            ),
            shiny::tags$button(
              type = "button", class = "btn btn-sm btn-outline-danger py-0 px-2",
              onclick = sprintf(
                "Shiny.setInputValue('%s', '%s', {priority: 'event'})", ns("remove_click"), rid
              ),
              "Remove"
            )
          )
        )
      }, names(current), formatted)

      combined <- zzedc:::join_author_names(formatted, delimiter = delim)

      shiny::tagList(
        shiny::tags$ul(class = "list-unstyled mb-2", row_items),
        shiny::tags$div(class = "text-muted mb-1", "Preview:"),
        shiny::tags$div(class = "border rounded p-2 mb-2 bg-light", combined),
        shiny::actionButton(ns("apply"), "Apply to Co-authors field", class = "btn btn-sm btn-primary")
      )
    })
  })
}
