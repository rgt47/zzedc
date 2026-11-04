#' Generate an initials-based avatar tag for a user
#'
#' Renders a small colored circle with the user's initials (e.g.
#' "RT" for "Ronald Thomas") in place of a real profile photo. This
#' app collects no photo from anyone: for an internal clinical-trial
#' tool, uploading and storing an actual picture of each user adds
#' file-storage, moderation, and privacy overhead (a photo is
#' biometric-adjacent data) for no real benefit over an initials
#' badge, which is also the pattern most B2B tools (Slack, GitHub,
#' ...) already fall back to for a user with no photo. The circle's
#' background color is derived deterministically from the identity
#' string (a simple character-code hash into a fixed palette), so
#' the same person gets the same color every time without needing to
#' store one.
#'
#' @param full_name The user's full name, or `NULL`/`NA`/blank.
#' @param username Fallback identity, used for initials and for the
#'   color hash when `full_name` is unavailable.
#' @param size CSS size for the circle's diameter (height and
#'   width), e.g. `"4rem"`.
#' @return A `shiny::tags$div` avatar element.
#' @keywords internal
user_avatar_tag <- function(full_name = NULL, username = NULL, size = "4rem") {
  identity <- if (.user_avatar_usable(full_name)) {
    full_name
  } else if (.user_avatar_usable(username)) {
    username
  } else {
    "?"
  }

  shiny::tags$div(
    class = "zzedc-user-avatar",
    style = sprintf(
      paste0(
        "width: %1$s; height: %1$s; border-radius: 50%%;",
        "background-color: %2$s; color: #ffffff; display: flex;",
        "align-items: center; justify-content: center;",
        "font-weight: 600; font-size: calc(%1$s * 0.4);",
        "margin: 0 auto;"
      ),
      size, .user_avatar_color(identity)
    ),
    title = identity,
    .user_avatar_initials(identity)
  )
}

#' @keywords internal
.user_avatar_usable <- function(x) {
  !is.null(x) && length(x) == 1 && !is.na(x) && nzchar(trimws(x))
}

#' One or two initials for an identity string
#' @keywords internal
.user_avatar_initials <- function(identity) {
  tokens <- strsplit(trimws(identity), "\\s+")[[1]]
  tokens <- tokens[nzchar(tokens)]
  if (length(tokens) >= 2) {
    paste0(toupper(substr(tokens[1], 1, 1)),
           toupper(substr(tokens[length(tokens)], 1, 1)))
  } else if (length(tokens) == 1) {
    toupper(substr(tokens[1], 1, min(2, nchar(tokens[1]))))
  } else {
    "?"
  }
}

#' Deterministic avatar background color for an identity string
#' @keywords internal
.user_avatar_color <- function(identity) {
  palette <- c("#334155", "#0f766e", "#7c3aed", "#b45309",
               "#0e7490", "#be185d", "#15803d", "#1d4ed8")
  idx <- (sum(utf8ToInt(identity)) %% length(palette)) + 1L
  palette[idx]
}
