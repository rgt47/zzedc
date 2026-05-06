# forms/renderpanels.R
#
# Demonstration render panels for the EDC tab. Sourced inline by
# `inst/app/edc.R` via `source('forms/renderpanels.R', local=TRUE)`.
# The file should populate one or more `output$*` slots that the
# EDC layout references.
#
# Replace with your study's actual panel definitions. The panel
# below is a single visit form using `zzedc::renderPanel()` to
# render text inputs from the field list in `blfieldlist.R`.

output$visvl <- shiny::renderUI({
  shiny::div(
    class = "p-3",
    shiny::h4("Visit form (demonstration)"),
    shiny::p(
      class = "small text-muted",
      "This is a demonstration form scaffolded by ",
      shiny::tags$code("launch_zzedc()"),
      " on first run. Replace ",
      shiny::tags$code("forms/blfieldlist.R"), ", ",
      shiny::tags$code("forms/renderpanels.R"), ", and ",
      shiny::tags$code("forms/save.R"),
      " in your working directory with your study's actual ",
      "case-report-form scaffolding."
    ),
    shiny::tags$div(
      class = "row",
      shiny::tags$div(
        class = "col-md-12",
        shiny::tagList(zzedc::renderPanel(blfieldlist))
      )
    ),
    shiny::actionButton(
      "submitvislog", "Submit visit",
      class = "btn btn-primary mt-3"
    )
  )
})

# Returned value (unused by the caller; required by the
# `source(..., local = TRUE)[[1]]` idiom in inst/app/edc.R).
NULL
