# Backup and Restore Module
#
# Provides one-click backup and restore functionality for the ZZedc database.
# Supports automatic and manual backups with recovery options.

#' Backup/Restore UI
#'
#' @param id The namespace id for the module
#' @return A tagList containing the backup/restore UI
#'
#' @examples
#' \dontrun{
#' # Embed the backup-and-restore module in a custom Shiny app.
#' # Most users will run the full application via
#' # `zzedc::launch_zzedc()`; the example below shows how to
#' # embed the module in a custom Shiny app instead.
#' if (interactive()) {
#'   ui <- shiny::fluidPage(
#'     backup_restore_ui("module_id")
#'   )
#'   server <- function(input, output, session) {
#'     backup_restore_server("module_id")
#'   }
#'   shiny::shinyApp(ui, server)
#' }
#' }
#' @keywords internal
backup_restore_ui <- function(id) {
  ns <- NS(id)

  div(class = "backup-restore-container",
    # Header
    h3("Database Backup & Recovery", class = "mb-4 text-primary"),

    # Two-column layout
    div(class = "row",
      # Left: Backup Controls
      div(class = "col-md-6",
        bslib::card(
          class = "mb-3",
          bslib::card_header(class = "bg-primary text-white", "Create Backup"),
          bslib::card_body(
            p("Back up your database immediately to prevent data loss."),

            div(class = "mb-3",
              tags$label("Backup Name (optional)"),
              textInput(ns("backup_name"), NULL,
                       placeholder = "e.g., 'Before data cleanup'")
            ),

            div(class = "form-check mb-3",
              tags$input(id = ns("backup_compress"), type = "checkbox", class = "form-check-input", checked = TRUE),
              tags$label("Compress backup file (saves space)", `for` = ns("backup_compress"), class = "form-check-label")
            ),

            div(class = "d-grid",
              actionButton(ns("create_backup_btn"), "Create Backup Now",
                          class = "btn btn-success btn-lg",
                          icon = icon("save"))
            ),

            div(id = ns("backup_progress"), class = "mt-3", style = "display:none;",
              div(class = "progress",
                div(id = ns("backup_progress_bar"), class = "progress-bar progress-bar-striped progress-bar-animated",
                    role = "progressbar", style = "width: 0%")
              ),
              div(class = "mt-2",
                p(id = ns("backup_status"), class = "text-muted small", "Backing up...")
              )
            )
          )
        ),

        # Automatic Backup Settings
        bslib::card(
          bslib::card_header("Automatic Backups"),
          bslib::card_body(
            div(class = "form-check mb-2",
              tags$input(id = ns("auto_backup_enable"), type = "checkbox", class = "form-check-input", checked = TRUE),
              tags$label("Enable automatic daily backups", `for` = ns("auto_backup_enable"), class = "form-check-label")
            ),

            div(class = "form-group mt-3",
              tags$label("Backup Time (daily)"),
              selectInput(ns("auto_backup_time"), NULL,
                         choices = sprintf("%02d:00", 0:23),
                         selected = "02:00")
            ),

            div(class = "form-group",
              tags$label("Keep Backups For (days)"),
              numericInput(ns("auto_backup_retain"), NULL, value = 30, min = 1, max = 365)
            ),

            div(class = "alert alert-info small",
              icon("info-circle"), " Automatic backups are stored in ",
              code("backups/"), " directory"
            )
          )
        )
      ),

      # Right: Restore Controls and Backup List
      div(class = "col-md-6",
        bslib::card(
          class = "mb-3",
          bslib::card_header(class = "bg-warning text-dark", "Recent Backups"),
          bslib::card_body(
            p("Select a backup to restore from."),

            DT::DTOutput(ns("backups_table")),
            # The table's Download buttons trigger this hidden link;
            # Shiny serves files only through a downloadHandler.
            div(style = "display:none;",
                downloadLink(ns("download_file"), "Download"))
          )
        ),

        bslib::card(
          bslib::card_header(class = "bg-danger text-white", "Restore from Backup"),
          bslib::card_body(
            div(class = "alert alert-warning",
              strong("Warning: "),
              "Restoring will replace all current data with the backup version. ",
              "Current data will be saved first."
            ),

            p("Select a backup from the list above, then click Restore."),

            div(class = "mb-3",
              textInput(ns("restore_confirmation"), NULL,
                       placeholder = 'Type "RESTORE" to confirm')
            ),

            div(class = "d-grid",
              actionButton(ns("restore_btn"), "Restore Selected Backup",
                          class = "btn btn-danger btn-lg",
                          icon = icon("undo"),
                          disabled = TRUE)
            ),

            div(id = ns("restore_progress"), class = "mt-3", style = "display:none;",
              div(class = "progress",
                div(id = ns("restore_progress_bar"), class = "progress-bar progress-bar-striped progress-bar-animated bg-danger",
                    role = "progressbar", style = "width: 0%")
              ),
              div(class = "mt-2",
                p(id = ns("restore_status"), class = "text-muted small", "Restoring...")
              )
            )
          )
        )
      )
    ),

    # Status messages area
    div(id = ns("status_area"), class = "mt-4")
  )
}


#' Backup/Restore Server
#'
#' @param id The namespace id for the module
#' @param db_pool Reactive expression returning database connection pool
#' @param db_path Reactive expression returning path to database file
#' @param backup_dir Directory where backups are stored
#' @param db_adapter The application's `DatabaseAdapter`; decides whether
#'   file backup applies (SQLite and DuckDB only) and how to make a
#'   consistent copy.
#' @param user_session The session's login state; its `username` is
#'   recorded with a restore request.
#'
#' @return Invisible NULL
#'
#' @details
#' Restore is staged, not performed in place: see `?database_restore`.
#'
#' @examples
#' \dontrun{
#' # Embed the backup-and-restore module in a custom Shiny app.
#' # Most users will run the full application via
#' # `zzedc::launch_zzedc()`; the example below shows how to
#' # embed the module in a custom Shiny app instead.
#' if (interactive()) {
#'   ui <- shiny::fluidPage(
#'     backup_restore_ui("module_id")
#'   )
#'   server <- function(input, output, session) {
#'     backup_restore_server("module_id")
#'   }
#'   shiny::shinyApp(ui, server)
#' }
#' }
#' @keywords internal
backup_restore_server <- function(id, db_pool = NULL, db_path = reactive("./data/zzedc.db"),
                                  backup_dir = "./backups", db_adapter = NULL,
                                  user_session = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    actor_name <- function() {
      if (!is.null(user_session) && !is.null(user_session$username)) {
        as.character(user_session$username)
      } else {
        NA_character_
      }
    }

    # The Select/Delete/Download buttons send a file path from the
    # browser (Shiny.setInputValue). Accept it only if it is one of the
    # backups this module itself listed; otherwise a crafted message
    # could restore from, or delete, any file the app can reach.
    known_backup <- function(path) {
      listed <- load_backups()$filepath
      ok <- !is.null(path) && length(path) == 1 && length(listed) > 0 &&
        normalizePath(path, mustWork = FALSE) %in% normalizePath(listed, mustWork = FALSE)
      if (!ok) {
        stop("That file is not one of this study's backups.", call. = FALSE)
      }
      path
    }

    # This module backs up by copying the database file, which exists
    # only for the file backends. Server backends need their own tools.
    backend <- if (!is.null(db_adapter)) db_adapter$backend_name() else "sqlite"
    file_backend <- backend %in% c("sqlite", "duckdb")
    server_backend_msg <- paste0(
      "File backup and restore apply to the SQLite and DuckDB backends. ",
      "This study uses ", backend, "; use the server's own backup tools ",
      "(pg_dump or WAL archiving for PostgreSQL, mysqldump or binary logs ",
      "for MySQL/MariaDB)."
    )

    # Reactive values
    backup_state <- reactiveValues(
      backups = data.frame(),
      selected_backup = NULL,
      last_backup_time = NULL
    )

    # Create backup directory if needed
    if (!dir.exists(backup_dir)) {
      dir.create(backup_dir, recursive = TRUE)
    }

    # Load available backups
    load_backups <- function() {
      tryCatch({
        backup_files <- list.files(backup_dir, pattern = "\\.db(\\.gz)?(\\.enc)?$",
                                   full.names = TRUE)

        if (length(backup_files) == 0) {
          return(data.frame(
            filename = character(),
            size_mb = numeric(),
            created = character(),
            stringsAsFactors = FALSE
          ))
        }

        backups <- data.frame(
          filename = basename(backup_files),
          filepath = backup_files,
          size_mb = file.size(backup_files) / (1024^2),
          created = format(file.mtime(backup_files), "%Y-%m-%d %H:%M:%S"),
          stringsAsFactors = FALSE
        )

        # Sort by creation time (newest first)
        backups <- backups[order(backups$created, decreasing = TRUE), ]

        backup_state$backups <- backups
        return(backups)

      }, error = function(e) {
        return(data.frame())
      })
    }

    # Initial load
    backup_state$backups <- load_backups()

    # Display backups table
    output$backups_table <- DT::renderDT({
      backups <- backup_state$backups

      if (nrow(backups) == 0) {
        return(DT::datatable(
          data.frame(Message = "No backups found. Create one now!"),
          options = list(dom = 't', searching = FALSE, paging = FALSE)
        ))
      }

      # Create action buttons
      action_buttons <- sapply(1:nrow(backups), function(i) {
        filepath <- backups$filepath[i]
        paste0(
          '<div class="btn-group btn-group-sm" role="group">
            <button class="btn btn-sm btn-info" onclick="Shiny.setInputValue(\'', ns("select_backup"), '\', \'', filepath, '\', {priority: \'event\'})">Select</button>
            <button class="btn btn-sm btn-secondary" onclick="Shiny.setInputValue(\'', ns("download_backup"), '\', \'', filepath, '\', {priority: \'event\'})">Download</button>
            <button class="btn btn-sm btn-danger" onclick="Shiny.setInputValue(\'', ns("delete_backup"), '\', \'', filepath, '\', {priority: \'event\'})">Delete</button>
          </div>'
        )
      })

      display_data <- backups[, c("filename", "size_mb", "created")]
      display_data$size_mb <- round(display_data$size_mb, 2)
      display_data$Actions <- action_buttons
      colnames(display_data) <- c("Backup File", "Size (MB)", "Created", "Actions")

      DT::datatable(
        display_data,
        escape = FALSE,
        options = list(
          pageLength = 5,
          columnDefs = list(
            list(targets = 3, searchable = FALSE, orderable = FALSE, width = "150px")
          )
        )
      )
    })

    # Create backup button
    observeEvent(input$create_backup_btn, {
      if (!file_backend) {
        shinyalert("Backup not available here", server_backend_msg, type = "info")
        return()
      }
      tryCatch({
        # Show progress
        shinyjs::show("backup_progress")

        # Determine backup filename
        timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
        backup_name <- if (input$backup_name != "") {
          paste0(input$backup_name, "_", timestamp)
        } else {
          paste0("backup_", timestamp)
        }

        # Sanitize filename
        backup_name <- gsub("[^a-zA-Z0-9_-]", "", backup_name)

        # Write the uncompressed .db first and gzip it afterwards. The
        # path used to end in ".db.gz" from the start, so the gzip step
        # below (which looks for ".db") never ran: "compressed" backups
        # were uncompressed files with a .gz name, which a restore then
        # failed to gunzip.
        backup_filename <- paste0(backup_name, if (input$backup_compress) ".db.gz" else ".db")
        backup_filepath <- file.path(backup_dir, paste0(backup_name, ".db"))

        # Perform backup
        db_file <- db_path()
        if (!file.exists(db_file)) {
          shinyalert("Error", "Database file not found", type = "error")
          shinyjs::hide("backup_progress")
          return()
        }

        # Update progress
        shinyjs::runjs(sprintf(
          "document.getElementById('%s').style.width = '30%%'",
          ns("backup_progress_bar")
        ))

        # Under 'regulated', a backup of an unencrypted database must be
        # encrypted (ZZEDC_BACKUP_PASSPHRASE); refuse before writing.
        passphrase <- backup_passphrase()
        db_encrypted <- if (backend == "duckdb") {
          isTRUE(db_adapter$encryption_capabilities()$at_rest_configured)
        } else {
          isTRUE(sqlite_file_is_encrypted(db_file))
        }
        check_backup_policy(db_encrypted, passphrase)

        # A consistent copy of the open database: VACUUM INTO for
        # SQLite (a plain file copy can miss commits still in the
        # write-ahead log), CHECKPOINT then copy for DuckDB. For an
        # encrypted DuckDB file the copy is ciphertext. Then compress
        # if asked, and encrypt when a backup passphrase is set.
        create_database_backup(db_pool, db_file, backend, backup_filepath)
        backup_filepath <- finalize_backup_file(
          backup_filepath, compress = isTRUE(input$backup_compress),
          passphrase = passphrase
        )
        backup_filename <- basename(backup_filepath)
        tryCatch(
          log_audit_event(
            event_type = "BACKUP", table_name = "database",
            record_id = backup_filename,
            operation = paste("Backup created:", backup_filename,
                              if (!is.null(passphrase)) "(encrypted)" else ""),
            user_id = actor_name()
          ),
          error = function(e) NULL
        )

        # Update progress
        shinyjs::runjs(sprintf(
          "document.getElementById('%s').style.width = '90%%'",
          ns("backup_progress_bar")
        ))

        # Reload backup list
        backup_state$backups <- load_backups()
        backup_state$last_backup_time <- Sys.time()

        # Complete progress
        shinyjs::runjs(sprintf(
          "document.getElementById('%s').style.width = '100%%'",
          ns("backup_progress_bar")
        ))

        # Clear inputs
        updateTextInput(session, "backup_name", value = "")

        # Show success message
        file_size <- file.size(backup_filepath) / (1024^2)
        shinyalert("Success!",
                  paste("Backup created:\n",
                        backup_filename, "\n",
                        sprintf("Size: %.2f MB", file_size)),
                  type = "success",
                  timer = 3000)

        # Hide progress after a brief pause so the user sees the
        # 100% bar. `shinyjs::delay()` schedules the callback
        # through the browser, which leaves the R session
        # responsive (unlike `Sys.sleep()`, which blocks the
        # event loop).
        shinyjs::delay(1000, shinyjs::hide("backup_progress"))

      }, error = function(e) {
        shinyalert("Backup Error", paste("Failed to create backup:", e$message), type = "error")
        shinyjs::hide("backup_progress")
      })
    })

    # Select backup
    observeEvent(input$select_backup, {
      filepath <- tryCatch(known_backup(input$select_backup), error = function(e) NULL)
      if (is.null(filepath)) {
        shinyalert("Error", "That file is not one of this study's backups.", type = "error")
        return()
      }
      backup_state$selected_backup <- filepath

      # Enable restore button
      shinyjs::addClass(id = ns("restore_btn"), class = "disabled")
    })

    # Download backup. The button used to send an input nothing handled.
    # A backup holds every record in the study (in plaintext unless the
    # database is encrypted), so each download is audit-logged.
    download_target <- reactiveVal(NULL)
    observeEvent(input$download_backup, {
      filepath <- tryCatch(known_backup(input$download_backup), error = function(e) NULL)
      if (is.null(filepath)) {
        shinyalert("Error", "That file is not one of this study's backups.", type = "error")
        return()
      }
      download_target(filepath)
      tryCatch(
        log_audit_event(
          event_type = "EXPORT", table_name = "database",
          record_id = basename(filepath),
          operation = paste("Backup downloaded:", basename(filepath)),
          user_id = actor_name()
        ),
        error = function(e) NULL
      )
      shinyjs::runjs(sprintf("document.getElementById('%s').click();", ns("download_file")))
    })
    output$download_file <- downloadHandler(
      filename = function() basename(download_target() %||% "backup.db"),
      content = function(file) {
        req(download_target())
        file.copy(download_target(), file, overwrite = TRUE)
      }
    )

    # Delete backup
    observeEvent(input$delete_backup, {
      filepath <- tryCatch(known_backup(input$delete_backup), error = function(e) NULL)
      if (is.null(filepath)) {
        shinyalert("Error", "That file is not one of this study's backups.", type = "error")
        return()
      }

      # Confirmation dialog
      shinyalert(
        "Delete Backup?",
        "This action cannot be undone.",
        type = "warning",
        showCancelButton = TRUE,
        confirmButtonText = "Delete",
        cancelButtonText = "Cancel",
        confirmButtonCol = "#d33",
        inputId = ns("confirm_delete")
      )

      observeEvent(input$confirm_delete, {
        if (input$confirm_delete == TRUE) {
          tryCatch({
            file.remove(filepath)
            backup_state$backups <- load_backups()

            shinyalert("Deleted", "Backup file deleted", type = "success", timer = 2000)
          }, error = function(e) {
            shinyalert("Error", paste("Failed to delete backup:", e$message), type = "error")
          })
        }
      }, once = TRUE)
    })

    # Restore from backup
    observeEvent(input$restore_btn, {
      if (!file_backend) {
        shinyalert("Restore not available here", server_backend_msg, type = "info")
        return()
      }
      if (is.null(backup_state$selected_backup)) {
        shinyalert("Error", "Please select a backup to restore", type = "error")
        return()
      }

      if (input$restore_confirmation != "RESTORE") {
        shinyalert("Confirmation Failed", 'Please type "RESTORE" to confirm restoration', type = "error")
        return()
      }

      # The database cannot be replaced while the application has it
      # open (a shared pool, write-ahead logs). The restore is staged
      # here and applied at the next start, before any connection
      # opens (?database_restore). This used to copy the backup over the
      # open file and then close the pool every session shares.
      tryCatch({
        backup_file <- known_backup(backup_state$selected_backup)
        staged <- request_database_restore(
          backup_file, db_path(), backend = backend,
          requested_by = actor_name()
        )
        tryCatch(
          log_audit_event(
            event_type = "RESTORE", table_name = "database",
            record_id = basename(backup_file),
            operation = paste("Restore staged from", basename(backup_file),
                              "- applied at next application start"),
            user_id = actor_name()
          ),
          error = function(e) NULL
        )

        shinyalert("Restore scheduled",
                  paste0(staged$message, "\n\n",
                         "Restart the application to complete the restore. ",
                         "Until then, the current database stays in use."),
                  type = "success")
        updateTextInput(session, "restore_confirmation", value = "")

      }, error = function(e) {
        shinyalert("Restoration Error",
                  paste("Failed to stage the restore:", e$message, "\n\n",
                        "Your current database is unchanged."),
                  type = "error")
      })
    })

    # Automatic backup settings observer
    observe({
      # These would connect to the application's scheduler
      # For now, just log the settings
      cat("Auto backup enabled:", input$auto_backup_enable, "\n")
      cat("Auto backup time:", input$auto_backup_time, "\n")
      cat("Retention days:", input$auto_backup_retain, "\n")
    })

    return(invisible(NULL))
  })
}


#' Perform Automatic Database Backup
#'
#' Function to be called by scheduler (e.g., cron) for automatic backups
#'
#' @param db_path Path to database file
#' @param backup_dir Directory to store backups
#' @param compress Whether to compress backup
#' @param keep_days How many days of backups to keep
#'
#' @return List with success status
#' @keywords internal
perform_automatic_backup <- function(db_path, backup_dir = "./backups", compress = TRUE, keep_days = 30) {

  tryCatch({
    if (!dir.exists(backup_dir)) {
      dir.create(backup_dir, recursive = TRUE)
    }

    if (!file.exists(db_path)) {
      return(list(success = FALSE, message = "Database file not found"))
    }

    # Under 'regulated', a backup of an unencrypted database must be
    # encrypted (ZZEDC_BACKUP_PASSPHRASE); refuse before writing.
    passphrase <- backup_passphrase()
    format <- .detect_db_file_format(db_path)
    db_encrypted <- if (identical(format, "duckdb")) {
      isFALSE(.readable_without_key(db_path, format))
    } else {
      isTRUE(sqlite_file_is_encrypted(db_path))
    }
    check_backup_policy(db_encrypted, passphrase)

    # Create backup. Intended for a scheduler while the application is
    # stopped, or for a database no connection is writing to; with the
    # application running, use the Backup tab, which makes a consistent
    # copy through the open connection.
    timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
    backup_filename <- paste0("auto_backup_", timestamp, ".db")
    backup_filepath <- file.path(backup_dir, backup_filename)

    file.copy(db_path, backup_filepath, overwrite = TRUE)
    backup_filepath <- finalize_backup_file(backup_filepath, compress = compress,
                                            passphrase = passphrase)
    backup_filename <- basename(backup_filepath)

    # Clean up old backups
    backup_files <- list.files(backup_dir, pattern = "^auto_backup_.*\\.db(\\.gz)?(\\.enc)?$",
                               full.names = TRUE)
    if (length(backup_files) > 0) {
      file_ages <- as.numeric(Sys.time() - file.mtime(backup_files), units = "days")
      old_files <- backup_files[file_ages > keep_days]
      if (length(old_files) > 0) {
        file.remove(old_files)
      }
    }

    return(list(
      success = TRUE,
      message = paste("Automatic backup created:", backup_filename),
      filepath = backup_filepath,
      size_mb = file.size(backup_filepath) / (1024^2)
    ))

  }, error = function(e) {
    return(list(
      success = FALSE,
      message = paste("Automatic backup failed:", e$message)
    ))
  })
}
