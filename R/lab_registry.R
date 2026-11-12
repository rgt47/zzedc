# Studies Registry
#
# Before this file, nothing in zzedc had any concept of "which studies
# exist" -- launch_zzedc() operates entirely on getwd(), one config.yml,
# one database, one process. This registry is a small, deliberately
# separate file (~/.zzedc/studies.yml, not a second database) that the
# lab landing page (R/lab_launcher.R, launch_lab()) reads to list every
# known study and lets a user register a new one or an already-existing
# deployment. Kept outside any study's own directory and outside the
# per-study encrypted trust boundary on purpose: it only ever stores a
# path, a display name, a backend label, and two timestamps, never
# anything from inside a study's own database.


#' Path to the studies registry file
#'
#' `~/.zzedc/studies.yml`, creating the `~/.zzedc/` directory on first
#' write. Not configurable via `config.yml` -- it is deliberately
#' outside any single study's configuration, since it lists studies
#' rather than belonging to one.
#'
#' @keywords internal
.registry_path <- function() {
  dir <- file.path(Sys.getenv("HOME"), ".zzedc")
  file.path(dir, "studies.yml")
}


#' Read the registry file into a plain R list
#'
#' @return A list with one named element per registered study (keyed by
#'   `id`), or an empty, named `list()` when the registry file does not
#'   exist yet. Never errors on a missing file -- "no registry yet" is
#'   normal, not exceptional.
#' @keywords internal
.read_registry <- function() {
  path <- .registry_path()
  if (!file.exists(path)) {
    return(list())
  }
  if (!requireNamespace("yaml", quietly = TRUE)) {
    stop("The 'yaml' package is required to read the studies registry.\n",
         "Install with: install.packages('yaml')")
  }
  entries <- yaml::read_yaml(path)
  if (is.null(entries)) list() else entries
}


#' Write a plain R list back to the registry file
#' @keywords internal
.write_registry <- function(entries) {
  path <- .registry_path()
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  if (!requireNamespace("yaml", quietly = TRUE)) {
    stop("The 'yaml' package is required to write the studies registry.\n",
         "Install with: install.packages('yaml')")
  }
  yaml::write_yaml(entries, path)
  invisible(NULL)
}


#' Slugify a display name into a registry id
#'
#' Lower-cases, replaces every run of non-alphanumeric characters with a
#' single hyphen, and trims leading/trailing hyphens. `"ADHD Trial"`
#' becomes `"adhd-trial"`.
#'
#' @keywords internal
.slugify <- function(x) {
  slug <- tolower(trimws(x %||% ""))
  slug <- gsub("[^a-z0-9]+", "-", slug)
  gsub("^-+|-+$", "", slug)
}


#' Register a study (new or already-existing) with the lab
#'
#' Requires `path` to already contain a provisioned study (a
#' `config.yml`, written by [launch_zzedc()], [launch_setup_wizard()],
#' or [complete_wizard_setup()]) -- this function never creates one
#' itself, it only records a path that already has one. Re-registering
#' a `path` that is already in the registry updates that entry (name,
#' backend, and a refreshed read of `config.yml`) rather than creating
#' a duplicate, the same "re-call is idempotent" convention
#' [add_form_field_by_code()] already uses elsewhere in this package.
#'
#' @param path The study's project directory (the same directory
#'   [launch_zzedc()] would be run from for it).
#' @param name Display name for the landing-page tile. When `NULL`
#'   (the default), read from that study's own `config.yml` `study.name`
#'   field if present, otherwise `basename(path)`.
#' @param id Registry key. When `NULL` (the default), a slug of `name`.
#'   Supply this explicitly only to re-register a study under a id
#'   that would otherwise collide with a different one of the same
#'   display name.
#' @return List with `success`; on success also `id`; on failure
#'   `error`.
#'
#' @examples
#' \dontrun{
#' register_study("~/prj/srv/14-promotion-tracker",
#'                 name = "Promotion Review Tracker")
#' }
#' @export
register_study <- function(path, name = NULL, id = NULL) {
  path <- normalizePath(path, mustWork = FALSE)
  config_path <- file.path(path, "config.yml")
  if (!file.exists(config_path)) {
    return(list(success = FALSE, error = paste0(
      "No config.yml found at ", path, " -- this path has not been ",
      "provisioned as a zzedc study yet. Run launch_setup_wizard() or ",
      "launch_zzedc() there first, then register it."
    )))
  }

  cfg <- tryCatch(config::get(file = config_path), error = function(e) NULL)
  resolved_name <- name %||% cfg$study$name %||% basename(path)
  backend <- cfg$database$backend %||% "unknown"
  resolved_id <- id %||% .slugify(resolved_name)
  if (!nzchar(resolved_id)) {
    resolved_id <- .slugify(basename(path))
  }

  entries <- .read_registry()

  # Re-registering the same path updates its existing entry (by path,
  # not by id -- a rename should not orphan the old entry) rather than
  # creating a duplicate.
  existing_id <- NULL
  for (nm in names(entries)) {
    if (identical(entries[[nm]]$path, path)) {
      existing_id <- nm
      break
    }
  }
  target_id <- existing_id %||% resolved_id
  created_date <- if (!is.null(existing_id)) {
    entries[[existing_id]]$created_date
  } else {
    as.character(Sys.time())
  }
  last_opened <- if (!is.null(existing_id)) entries[[existing_id]]$last_opened else NA

  if (!is.null(existing_id) && !identical(existing_id, resolved_id) && is.null(id)) {
    # Name changed since last registration: keep the original id so
    # bookmarks/unregister calls by the old id still work, but refresh
    # the display fields below.
    target_id <- existing_id
  }

  entries[[target_id]] <- list(
    id = target_id,
    name = resolved_name,
    path = path,
    backend = backend,
    created_date = created_date,
    last_opened = last_opened
  )
  .write_registry(entries)

  list(success = TRUE, id = target_id)
}


#' Remove a study from the registry
#'
#' Does not touch the study's own directory, database, or `config.yml`
#' -- only the registry entry. Removing a study you still want to run
#' is always safe; `launch_zzedc()` run from its directory works
#' exactly as before.
#'
#' @param id The registry id (as returned by [register_study()], or
#'   from [list_studies()]'s `id` column).
#' @return List with `success`; `FALSE` with `error` if `id` is not in
#'   the registry.
#' @export
unregister_study <- function(id) {
  entries <- .read_registry()
  if (is.null(entries[[id]])) {
    return(list(success = FALSE, error = paste0("No study registered with id '", id, "'")))
  }
  entries[[id]] <- NULL
  .write_registry(entries)
  list(success = TRUE)
}


#' List every registered study
#'
#' @return A data frame with columns `id`, `name`, `path`, `backend`,
#'   `created_date`, `last_opened`, `exists` (whether `path` and its
#'   `config.yml` are still present on disk -- `FALSE` for a moved or
#'   deleted study, not an error). Zero rows, with the right columns,
#'   when nothing is registered yet.
#' @export
list_studies <- function() {
  entries <- .read_registry()
  empty <- data.frame(
    id = character(0), name = character(0), path = character(0),
    backend = character(0), created_date = character(0),
    last_opened = character(0), exists = logical(0),
    stringsAsFactors = FALSE
  )
  if (length(entries) == 0) {
    return(empty)
  }
  rows <- lapply(entries, function(e) {
    data.frame(
      id = e$id %||% NA_character_,
      name = e$name %||% NA_character_,
      path = e$path %||% NA_character_,
      backend = e$backend %||% NA_character_,
      created_date = as.character(e$created_date %||% NA),
      last_opened = as.character(e$last_opened %||% NA),
      exists = isTRUE(dir.exists(e$path %||% "") &&
                        file.exists(file.path(e$path %||% "", "config.yml"))),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}


#' Record that a study was just opened from the landing page
#' @keywords internal
.touch_study_last_opened <- function(id) {
  entries <- .read_registry()
  if (is.null(entries[[id]])) {
    return(invisible(NULL))
  }
  entries[[id]]$last_opened <- as.character(Sys.time())
  .write_registry(entries)
  invisible(NULL)
}
