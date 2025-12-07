#' @keywords internal
NULL

#' Create paginated data view
#'
#' Prepares data for paginated display with server-side processing.
#' Handles filtering, sorting, and pagination efficiently.
#'
#' @param data data.frame to paginate
#' @param page_size Number of rows per page (default: 25)
#' @param search_term Optional text to filter rows
#' @param sort_by Column name to sort by
#' @param sort_direction "asc" or "desc"
#' @param page_number Current page (1-indexed)
#'
#' @return List containing:
#'   - data: data.frame with rows for current page
#'   - pagination: list with page info (total_pages, total_rows, current_page)
#'   - summary: summary statistics
#'
#' @export
#' @examples
#' \dontrun{
#' paginated <- paginate_data(
#'   large_dataset,
#'   page_size = 25,
#'   page_number = 1
#' )
#' display_data(paginated$data)
#' show_page_numbers(paginated$pagination$total_pages)
#' }
paginate_data <- function(
  data,
  page_size = 25,
  search_term = NULL,
  sort_by = NULL,
  sort_direction = "asc",
  page_number = 1) {

  # Input validation
  if (!is.data.frame(data)) {
    stop("data must be a data.frame")
  }

  if (nrow(data) == 0) {
    return(list(
      data = data,
      pagination = list(
        total_rows = 0,
        total_pages = 0,
        current_page = 1,
        page_size = page_size
      ),
      summary = NULL
    ))
  }

  # Step 1: Apply search filter
  filtered_data <- data
  if (!is.null(search_term) && search_term != "") {
    filtered_data <- filter_data_by_search(data, search_term)
  }

  # Step 2: Apply sorting
  if (!is.null(sort_by) && sort_by %in% names(filtered_data)) {
    filtered_data <- sort_data(filtered_data, sort_by, sort_direction)
  }

  # Step 3: Calculate pagination info
  total_rows <- nrow(filtered_data)
  total_pages <- ceiling(total_rows / page_size)

  # Validate page number
  if (page_number < 1) page_number <- 1
  if (page_number > total_pages && total_pages > 0) page_number <- total_pages

  # Step 4: Extract page data
  start_row <- (page_number - 1) * page_size + 1
  end_row <- min(page_number * page_size, total_rows)

  page_data <- if (total_rows > 0) {
    filtered_data[start_row:end_row, ]
  } else {
    filtered_data
  }

  # Step 5: Calculate summary statistics
  summary <- list(
    total_rows = total_rows,
    returned_rows = nrow(page_data),
    start_row = start_row,
    end_row = end_row
  )

  list(
    data = page_data,
    pagination = list(
      total_rows = total_rows,
      total_pages = total_pages,
      current_page = page_number,
      page_size = page_size,
      has_prev = page_number > 1,
      has_next = page_number < total_pages
    ),
    summary = summary
  )
}

#' Filter data by search term
#'
#' Searches all columns for matching values
#'
#' @param data data.frame to search
#' @param search_term Text to search for (case-insensitive)
#' @param columns Column names to search in (NULL = all columns)
#'
#' @return Filtered data.frame
#'
filter_data_by_search <- function(data, search_term, columns = NULL) {
  if (is.null(search_term) || search_term == "") {
    return(data)
  }

  # Determine which columns to search
  search_cols <- if (is.null(columns)) {
    names(data)
  } else {
    intersect(columns, names(data))
  }

  # Create search pattern (case-insensitive)
  pattern <- tolower(search_term)

  # Search through each column
  matches <- rep(FALSE, nrow(data))

  for (col in search_cols) {
    if (is.character(data[[col]])) {
      # Text search
      col_matches <- grepl(pattern, tolower(data[[col]]), fixed = TRUE)
    } else {
      # Convert to character and search
      col_matches <- grepl(pattern, tolower(as.character(data[[col]])), fixed = TRUE)
    }
    matches <- matches | col_matches
  }

  data[matches, ]
}

#' Sort data frame
#'
#' Sorts data by specified column
#'
#' @param data data.frame to sort
#' @param sort_column Column name
#' @param direction "asc" or "desc"
#'
#' @return Sorted data.frame
#'
sort_data <- function(data, sort_column, direction = "asc") {
  if (!sort_column %in% names(data)) {
    return(data)
  }

  if (direction == "desc") {
    data[order(-xtfrm(data[[sort_column]])), ]
  } else {
    data[order(data[[sort_column]]), ]
  }
}

#' Create pagination UI controls
#'
#' Generates navigation buttons for pagination
#'
#' @param pagination Pagination info from paginate_data()
#' @param input_id Namespace ID for pagination inputs
#'
#' @return HTML div with pagination controls
#'
#' @export
create_pagination_ui <- function(pagination, input_id = "data") {
  ns <- function(x) paste0(input_id, "_", x)

  # Current page info
  page_info <- sprintf(
    "Page %d of %d (showing %d-%d of %d rows)",
    pagination$current_page,
    pagination$total_pages,
    (pagination$current_page - 1) * pagination$page_size + 1,
    min(pagination$current_page * pagination$page_size, pagination$total_rows),
    pagination$total_rows
  )

  # Navigation buttons
  tags$div(
    class = "d-flex justify-content-between align-items-center mt-3",
    tags$div(
      class = "text-muted",
      page_info
    ),
    tags$div(
      class = "btn-group",
      role = "group",
      # Previous button
      actionButton(
        ns("prev_page"),
        "← Previous",
        class = "btn btn-sm btn-outline-secondary",
        disabled = !pagination$has_prev
      ),
      # Page number input
      numericInput(
        ns("page_number"),
        NULL,
        value = pagination$current_page,
        min = 1,
        max = max(1, pagination$total_pages),
        step = 1,
        width = "60px",
        style = "margin: 0 5px;"
      ),
      # Next button
      actionButton(
        ns("next_page"),
        "Next →",
        class = "btn btn-sm btn-outline-secondary",
        disabled = !pagination$has_next
      )
    )
  )
}

#' Setup pagination observers
#'
#' Creates reactive observers to handle pagination navigation
#'
#' @param session Shiny session object
#' @param data_reactive Reactive expression returning current data
#' @param current_page Reactive value holding current page number
#' @param input_id Namespace ID for pagination inputs
#'
#' @export
setup_pagination_observers <- function(session, data_reactive, current_page, input_id = "data") {
  ns <- function(x) paste0(input_id, "_", x)

  # Previous page button
  observeEvent(input[[ns("prev_page")]], {
    current_page(max(1, current_page() - 1))
  })

  # Next page button
  observeEvent(input[[ns("next_page")]], {
    data <- data_reactive()
    total_pages <- ceiling(nrow(data) / 25)  # Assumes page_size = 25
    current_page(min(total_pages, current_page() + 1))
  })

  # Direct page number input
  observeEvent(input[[ns("page_number")]], {
    page <- input[[ns("page_number")]]
    if (!is.na(page) && page >= 1) {
      current_page(page)
    }
  })
}

#' Create reactive paginated data
#'
#' Returns reactive expression that manages paginated data view
#'
#' @param data_source Reactive data.frame
#' @param page_size Number of rows per page
#' @param search_reactive Optional reactive search term
#' @param sort_reactive Optional reactive sort specification (list with $by and $direction)
#'
#' @return Reactive expression returning list with paginated data and metadata
#'
#' @export
create_paginated_reactive <- function(
  data_source,
  page_size = 25,
  search_reactive = NULL,
  sort_reactive = NULL) {

  current_page <- reactiveVal(1)

  # Main paginated data reactive
  paginated <- reactive({
    data <- data_source()
    req(data, nrow(data) > 0)

    # Get current search and sort
    search_term <- if (!is.null(search_reactive)) search_reactive() else NULL
    sort_by <- if (!is.null(sort_reactive)) sort_reactive()$by else NULL
    sort_direction <- if (!is.null(sort_reactive)) sort_reactive()$direction %||% "asc" else "asc"

    # Paginate
    paginate_data(
      data,
      page_size = page_size,
      search_term = search_term,
      sort_by = sort_by,
      sort_direction = sort_direction,
      page_number = current_page()
    )
  })

  # Reset to page 1 when data or search changes
  observe({
    data_source()
    if (!is.null(search_reactive)) search_reactive()
    current_page(1)
  })

  list(
    paginated = paginated,
    current_page = current_page
  )
}

#' Generate page summary statistics
#'
#' Calculates column-wise statistics for paginated data
#'
#' @param page_data data.frame with current page data
#' @param numeric_cols Column names to compute stats for
#'
#' @return data.frame with summary statistics
#'
#' @export
get_page_summary <- function(page_data, numeric_cols = NULL) {
  if (nrow(page_data) == 0) {
    return(NULL)
  }

  # Determine numeric columns
  if (is.null(numeric_cols)) {
    numeric_cols <- names(page_data)[sapply(page_data, is.numeric)]
  }

  # Calculate statistics
  summary_stats <- lapply(numeric_cols, function(col) {
    list(
      Column = col,
      Mean = round(mean(page_data[[col]], na.rm = TRUE), 2),
      Median = round(median(page_data[[col]], na.rm = TRUE), 2),
      Min = round(min(page_data[[col]], na.rm = TRUE), 2),
      Max = round(max(page_data[[col]], na.rm = TRUE), 2),
      SD = round(sd(page_data[[col]], na.rm = TRUE), 2),
      Missing = sum(is.na(page_data[[col]]))
    )
  })

  do.call(rbind, summary_stats) %>% as.data.frame()
}
