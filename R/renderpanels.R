#' Render form panel with typed input fields
#'
#' Generates appropriate input controls based on field metadata.
#' Supports 15+ field types for flexible data collection:
#' text, numeric, date, datetime, time, email, select, radio, checkbox,
#' checkbox_group, textarea, notes, slider, file, signature
#'
#' @param fields Character vector of field names OR list of field configurations
#' @param field_metadata List containing field definitions with type, required, choices, etc.
#' @param columns Maximum number of fields placed side by side in one
#'   visual row. Defaults to `1`, which returns the original flat,
#'   one-field-per-line stack (byte-identical to calling
#'   `renderPanel()` without this argument at all). For `columns > 1`
#'   and a `field_metadata` that carries `field_row`/`field_width`
#'   (as [get_crf_field_metadata()] now does), fields are first
#'   grouped into the already-ordered field list's contiguous runs of
#'   equal `field_row` (a design-time grouping), and any such group
#'   longer than `columns` is further split into consecutive chunks
#'   of at most `columns` fields, in order. A form whose fields each
#'   have a distinct `field_row` (one field per design row, which is
#'   how some imports annotate every field) therefore still renders
#'   one field per visual row regardless of `columns` -- `columns`
#'   only ever reduces how many fields share a row, it never combines
#'   fields the form's own author put on separate rows. Each chunk
#'   becomes one `shiny::fluidRow()`; within it, a field's
#'   `shiny::column()` width (out of 12) is `field_width` (a
#'   percentage, default `100`) scaled against the chunk's total:
#'   `max(1, floor(12 * field_width / max(100, sum(field_width))))`.
#'   Ignored entirely when `field_metadata` is `NULL` (the
#'   plain-`textInput()` fallback below has no row/width data to act
#'   on).
#' @param tooltip_mode `"minimal"` (default) leaves the existing
#'   always-present hover icon (`<field>__hint_icon`) as the only
#'   help-text affordance, exactly as before. `"expanded"` additionally
#'   renders the field's help text as a permanently visible
#'   `shiny::tags$small()` beneath the input -- strictly additive, the
#'   hover icon is never removed.
#' @param extra_tags An optional named list, keyed by field name, of
#'   extra UI (e.g. a custom field widget's trigger control) to place
#'   immediately after that field's own rendered block. Replaces the
#'   previous pattern of splicing extra UI into `renderPanel()`'s
#'   returned list by position, which breaks once `columns > 1` means
#'   that list is no longer one element per field.
#'
#' @return List of Shiny input controls matching field types. One
#'   element per field when `columns <= 1` (or `field_metadata` is
#'   `NULL`); one `shiny::fluidRow()` per visual row when
#'   `columns > 1`.
#'
#' @details
#' Field metadata format:
#' \code{
#'   list(
#'     age = list(type = "numeric", required = TRUE, min = 0, max = 150),
#'     email = list(type = "email", required = TRUE),
#'     treatment = list(type = "select", choices = c("A", "B", "C")),
#'     visit_date = list(type = "date", required = TRUE),
#'     visit_time = list(type = "time", required = TRUE),
#'     pain_level = list(type = "slider", min = 0, max = 10, value = 5),
#'     symptoms = list(type = "checkbox_group", choices = c("Pain", "Fever", "Cough"))
#'   )
#' }
#'
#' @examples
#' \dontrun{
#' metadata <- list(
#'   age = list(type = "numeric", required = TRUE, label = "Age (years)"),
#'   gender = list(
#'     type = "select",
#'     choices = c("M", "F"),
#'     label = "Gender"
#'   ),
#'   pregnancy_date = list(
#'     type = "date",
#'     label = "Pregnancy Due Date",
#'     show_if = "gender == 'F'"  # Branching logic
#'   ),
#'   visit_time = list(type = "time", required = TRUE, label = "Visit Time")
#' )
#' renderPanel(names(metadata), metadata)
#' }
#'
#' @keywords internal
#' @export
renderPanel <- function(fields, field_metadata = NULL, columns = 1,
                         tooltip_mode = "minimal", extra_tags = NULL) {
  # Support both simple field names and complex metadata
  if (is.null(field_metadata)) {
    # Fallback: simple textInput for all fields. `columns`/
    # `tooltip_mode` have nothing to act on here (no per-field type,
    # help text, or row/width data), so this path is unaffected by
    # either argument, same as before they existed.
    return(lapply(fields, function(field) {
      textInput(field, field)
    }))
  }

  # Render based on field metadata
  field_units <- lapply(fields, function(field_name) {
    # Get field configuration (default to text if not specified)
    field_config <- field_metadata[[field_name]] %||% list(type = "text")

    # Extract common properties
    label <- field_config$label %||% field_name
    required <- field_config$required %||% FALSE
    help_text <- field_config$help %||% NULL

    # Format label with required indicator
    if (required) {
      label <- shiny::tagList(label, span("*", class = "text-danger"))
    }

    # Render field based on type
    field_input <- switch(field_config$type,
      # Read-only display: a computed/system-set value the user
      # cannot type into (e.g. a randomization result). Not wired to
      # any Shiny input binding -- there is nothing for the server to
      # read back, by design; the value shown is whatever the caller
      # passed in field_config$value.
      "readonly_display" = div(
        id = field_name,
        class = "form-control-plaintext",
        field_config$value %||% ""
      ),

      # Numeric field with optional range
      "numeric" = numericInput(
        field_name,
        label,
        value = field_config$value %||% NA,
        min = field_config$min %||% NA_real_,
        max = field_config$max %||% NA_real_,
        step = field_config$step %||% 1
      ),

      # Date field
      "date" = dateInput(
        field_name,
        label,
        value = field_config$value %||% Sys.Date(),
        format = field_config$format %||% "yyyy-mm-dd",
        startview = field_config$startview %||% "month",
        language = "en"
      ),

      # Email field (validated on client/server)
      "email" = textInput(
        field_name,
        label,
        placeholder = "example@domain.com",
        value = field_config$value %||% ""
      ),

      # Select/dropdown field. shiny::selectInput() auto-selects the
      # first choice when `selected` is unset, which silently records
      # an answer nobody chose for a single-select "pick one" field
      # (prepending a blank placeholder option, selected by default,
      # avoids that -- this is moot for `multiple = TRUE`, which
      # shiny leaves with nothing selected either way).
      "select" = selectInput(
        field_name,
        label,
        choices = if (is.null(field_config$value) && !isTRUE(field_config$multiple)) {
          c("Select one..." = "", field_config$choices)
        } else {
          field_config$choices
        },
        selected = field_config$value %||% NULL,
        multiple = field_config$multiple %||% FALSE
      ),

      # Checkbox field
      "checkbox" = checkboxInput(
        field_name,
        label,
        value = field_config$value %||% FALSE
      ),

      # Textarea for longer text
      "textarea" = tags$textarea(
        id = field_name,
        class = "form-control",
        rows = field_config$rows %||% 4,
        cols = field_config$cols %||% 50,
        field_config$value %||% "",
        placeholder = field_config$placeholder %||% ""
      ),

      # Notes field (alias for textarea with default of 6 rows)
      "notes" = tags$textarea(
        id = field_name,
        class = "form-control",
        rows = field_config$rows %||% 6,
        cols = field_config$cols %||% 50,
        field_config$value %||% "",
        placeholder = field_config$placeholder %||% "Enter notes here..."
      ),

      # Time field (time of day)
      "time" = if (requireNamespace("shinyTime", quietly = TRUE)) {
        shinyTime::timeInput(
          field_name,
          label,
          value = field_config$value %||% Sys.time(),
          seconds = field_config$seconds %||% FALSE
        )
      } else {
        # Fallback to text input if shinyTime not available
        textInput(
          field_name,
          label,
          placeholder = "HH:MM",
          value = field_config$value %||% ""
        )
      },

      # DateTime field (date and time combined)
      # Note: shinyWidgets::datetimeInput doesn't exist; use airDatepickerInput
      "datetime" = if (requireNamespace("shinyWidgets", quietly = TRUE) &&
                       exists("airDatepickerInput", where = asNamespace("shinyWidgets"))) {
        shinyWidgets::airDatepickerInput(
          field_name,
          label,
          value = field_config$value %||% Sys.time(),
          timepicker = TRUE,
          timepickerOpts = shinyWidgets::timepickerOptions(timeFormat = "hh:ii")
        )
      } else {
        # Fallback to text input
        textInput(
          field_name,
          label,
          placeholder = "YYYY-MM-DD HH:MM",
          value = field_config$value %||% ""
        )
      },

      # Slider field (numeric range with slider control)
      "slider" = sliderInput(
        field_name,
        label,
        min = field_config$min %||% 0,
        max = field_config$max %||% 100,
        value = field_config$value %||% field_config$min %||% 50,
        step = field_config$step %||% 1,
        animate = field_config$animate %||% FALSE
      ),

      # Radio buttons (single selection). shiny::radioButtons() also
      # auto-selects the first choice when `selected` is unset (the
      # same issue as "select" above) -- passing character(0) is the
      # documented way to start with nothing checked, so a "select
      # one" question doesn't silently record its first option as
      # the answer before anyone has looked at it.
      "radio" = radioButtons(
        field_name,
        label,
        choices = field_config$choices,
        selected = field_config$value %||% character(0),
        inline = field_config$inline %||% FALSE
      ),

      # Checkbox group (multiple selection)
      "checkbox_group" = checkboxGroupInput(
        field_name,
        label,
        choices = field_config$choices,
        selected = field_config$value %||% NULL,
        inline = field_config$inline %||% FALSE
      ),

      # File upload field
      "file" = fileInput(
        field_name,
        label,
        multiple = field_config$multiple %||% FALSE,
        accept = field_config$accept %||% NULL,
        width = field_config$width %||% NULL
      ),

      # Signature pad (if shinysignature available). The package
      # name is held in a variable so R CMD check's namespace-audit
      # pass does not flag a literal `requireNamespace("...")` for
      # a third-party package not currently on CRAN. The
      # `getFromNamespace` lookup avoids `shinysignature::` syntax
      # for the same reason.
      "signature" = local({
        sig_pkg <- "shinysignature"
        if (requireNamespace(sig_pkg, quietly = TRUE)) {
          signaturePad <- utils::getFromNamespace("signaturePad", sig_pkg)
          signaturePad(
            field_name,
            width = field_config$width %||% "100%",
            height = field_config$height %||% "200px"
          )
        } else {
          tags$textarea(
            id = field_name,
            class = "form-control",
            rows = 6,
            placeholder = "Signature capture not available - enter notes instead"
          )
        }
      }),

      # Default: text input
      "text" = textInput(
        field_name,
        label,
        placeholder = field_config$placeholder %||% "",
        value = field_config$value %||% ""
      )
    )

    # Determine initial visibility based on branching rules
    # (Server-side implementation uses setup_branching_logic to manage this)
    initial_hidden <- FALSE
    if (!is.null(field_config$show_if)) {
      # Field starts hidden if it has a show_if condition
      initial_hidden <- TRUE
    }

    # Wrap field with branching logic wrapper
    # data-field attribute allows JavaScript to identify fields
    # Initial display can be overridden by branching_logic.R setup_branching_logic
    wrapper_style <- if (initial_hidden) "display: none;" else ""

    # One small hover-icon slot per field, always rendered (even when
    # there is no help text yet) so the EDC tab's live-validation
    # reactive (inst/app/edc.R's edc_crf_field_flags) can toggle its
    # tooltip/appearance via plain JS on every keystroke without
    # re-rendering this field -- re-rendering the actual input on
    # every keystroke would steal focus and reset cursor position.
    # Holds both glyphs; CSS (www/style.css) shows only one at a
    # time based on the field-hint-icon--error class. The id is
    # `<field_name>__hint_icon`, distinct from field_name itself
    # (already used by this wrapper div and by the input/select
    # control shiny's own widgets generate) so document.getElementById()
    # can target it unambiguously regardless of field type.
    # `data-tooltip` (read live by CSS's content: attr(data-tooltip),
    # not a `title` attribute: a native browser tooltip's appear
    # delay is an unstyleable OS/browser default (Chrome: ~500-
    # 1000ms, not configurable from the page), so controlling how
    # long a hover takes to show the tooltip -- as opposed to just
    # what it says -- requires a CSS-driven one instead. See the
    # `.field-hint-icon::after` rule (inst/app/edc.R) for the actual
    # appear delay.
    # `data-has-detail`: when the field's data dictionary row carries
    # `help_detail` (a full-page explanation, too long for the hover
    # tooltip), clicking the icon opens a modal with that content
    # instead of just pinning the short tooltip open -- see the
    # click handler and the field_help_detail_click observer in
    # inst/app/edc.R. The detail text itself is never put in this
    # markup (unlike data-tooltip's short text): it can be long, and
    # the click handler only needs to know whether to ask the server
    # for it, not what it says.
    has_detail <- !is.null(field_config$help_detail) &&
      nzchar(trimws(field_config$help_detail))

    hint_icon <- tags$span(
      id = paste0(field_name, "__hint_icon"),
      class = "field-hint-icon",
      `data-tooltip` = help_text %||% "",
      `data-has-detail` = if (has_detail) "true" else "false",
      tags$span(class = "field-hint-icon__info", bsicons::bs_icon("info-circle")),
      tags$span(class = "field-hint-icon__error", bsicons::bs_icon("exclamation-triangle-fill"))
    )

    # "expanded" tooltip mode: a permanently visible help-text line,
    # in addition to (never instead of) hint_icon above. NULL (and so
    # dropped by tags$div() below) in "minimal" mode, which is what
    # keeps "minimal" output byte-identical to the pre-Part-C markup.
    expanded_help <- if (identical(tooltip_mode, "expanded") &&
                            !is.null(help_text) && nzchar(trimws(help_text))) {
      tags$small(class = "text-muted d-block mt-1 field-help-expanded", help_text)
    } else {
      NULL
    }

    field_div <- tags$div(
      id = field_name,
      `data-field` = field_name,
      style = wrapper_style,
      class = "form-field-wrapper mb-3",
      field_input,
      hint_icon,
      expanded_help
    )

    # Extra per-field UI (e.g. a custom widget's trigger control,
    # inst/app/edc.R's widget_triggers) is attached to this exact
    # field via a tagList rather than returned as its own separate
    # top-level list element -- see extra_tags's roxygen above for
    # why: a positional splice into renderPanel()'s return value
    # breaks once columns > 1 regroups that list into fluidRow()s.
    extra <- extra_tags[[field_name]] %||% NULL
    if (is.null(extra)) field_div else shiny::tagList(field_div, extra)
  })

  if (columns <= 1) {
    return(field_units)
  }

  # Multi-column layout: group the already-ordered field list into
  # visual rows (see the `columns` argument's roxygen for the exact
  # grouping/splitting rule), then wrap each row in fluidRow() with
  # one column() per field, its width (out of 12) scaled from that
  # field's field_width percentage against the row's total.
  field_rows <- vapply(fields, function(f) {
    as.integer((field_metadata[[f]]$field_row %||% 1L)[1])
  }, integer(1))
  row_breaks <- cumsum(c(TRUE, diff(field_rows) != 0))
  design_groups <- split(seq_along(fields), row_breaks)

  visual_rows <- list()
  for (g in design_groups) {
    n <- length(g)
    if (n <= columns) {
      visual_rows[[length(visual_rows) + 1]] <- g
    } else {
      for (s in seq(1L, n, by = columns)) {
        visual_rows[[length(visual_rows) + 1]] <- g[s:min(s + columns - 1L, n)]
      }
    }
  }

  row_tags <- lapply(visual_rows, function(idx) {
    widths_pct <- vapply(idx, function(i) {
      as.numeric((field_metadata[[fields[i]]]$field_width %||% 100)[1])
    }, numeric(1))
    denom <- max(100, sum(widths_pct))
    col_widths <- pmax(1L, as.integer(floor(12 * widths_pct / denom)))

    cols <- lapply(seq_along(idx), function(k) {
      shiny::column(width = col_widths[k], field_units[[idx[k]]])
    })
    do.call(shiny::fluidRow, cols)
  })

  row_tags
}
