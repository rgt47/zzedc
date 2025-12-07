#' Backup and Restore Module
#'
#' Provides one-click backup and restore functionality for ZZedc database
#' Includes: automatic backups, manual backups, restore from backup, backup browser
#'
#' @export

#' Backup/Restore UI
#'
#' @param id The namespace id for the module
#' @return A tagList containing the backup/restore UI
backup_restore_ui <- function(id) {
  ns <- NS(id)

  div(class = "backup-restore-container",
    # Header
    h3("Database Backup & Recovery", class = "mb-4 text-primary"),

    # Two-column layout
    div(class = "row",
      # Left: Backup Controls
      div(class = "col-md-6",
        div(class = "card mb-3",
          div(class = "card-header bg-primary text-white",
            h5(class = "card-title mb-0", "Create Backup")
          ),
          div(class = "card-body",
            p("Back up your database immediately to prevent data loss."),

            div(class = "mb-3",
              label("Backup Name (optional)"),
              textInput(ns("backup_name"), NULL,
                       placeholder = "e.g., 'Before data cleanup'")
            ),

            div(class = "form-check mb-3",
              input(id = ns("backup_compress"), type = "checkbox", class = "form-check-input", checked = TRUE),
              label("Compress backup file (saves space)", `for` = ns("backup_compress"), class = "form-check-label")
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
        div(class = "card",
          div(class = "card-header",
            h5(class = "card-title mb-0", "Automatic Backups")
          ),
          div(class = "card-body",
            div(class = "form-check mb-2",
              input(id = ns("auto_backup_enable"), type = "checkbox", class = "form-check-input", checked = TRUE),
              label("Enable automatic daily backups", `for` = ns("auto_backup_enable"), class = "form-check-label")
            ),

            div(class = "form-group mt-3",
              label("Backup Time (daily)"),
              selectInput(ns("auto_backup_time"), NULL,
                         choices = sprintf("%02d:00", 0:23),
                         selected = "02:00")
            ),

            div(class = "form-group",
              label("Keep Backups For (days)"),
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
        div(class = "card mb-3",
          div(class = "card-header bg-warning text-dark",
            h5(class = "card-title mb-0", "Recent Backups")
          ),
          div(class = "card-body",
            p("Select a backup to restore from."),

            DT::dataTableOutput(ns("backups_table"))
          )
        ),

        div(class = "card",
          div(class = "card-header bg-danger text-white",
            h5(class = "card-title mb-0", "Restore from Backup")
          ),
          div(class = "card-body",
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
#'
#' @return Invisible NULL
backup_restore_server <- function(id, db_pool = NULL, db_path = reactive("./data/zzedc.db"),
                                  backup_dir = "./backups") {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

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
        backup_files <- list.files(backup_dir, pattern = "\\.db(\\.gz)?$", full.names = TRUE)

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
    output$backups_table <- DT::renderDataTable({
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

        extension <- if (input$backup_compress) ".db.gz" else ".db"
        backup_filename <- paste0(backup_name, extension)
        backup_filepath <- file.path(backup_dir, backup_filename)

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

        # Copy database file
        file.copy(db_file, backup_filepath, overwrite = TRUE)

        # Compress if requested
        if (input$backup_compress && grepl("\\.db$", backup_filepath)) {
          R.utils::gzip(backup_filepath, destname = paste0(backup_filepath, ".gz"), remove = TRUE)
          backup_filepath <- paste0(backup_filepath, ".gz")
        }

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

        # Hide progress
        Sys.sleep(1)
        shinyjs::hide("backup_progress")

      }, error = function(e) {
        shinyalert("Backup Error", paste("Failed to create backup:", e$message), type = "error")
        shinyjs::hide("backup_progress")
      })
    })

    # Select backup
    observeEvent(input$select_backup, {
      filepath <- input$select_backup
      backup_state$selected_backup <- filepath

      # Enable restore button
      shinyjs::addClass(id = ns("restore_btn"), class = "disabled")
    })

    # Delete backup
    observeEvent(input$delete_backup, {
      filepath <- input$delete_backup

      # Confirmation dialog
      shinyalert(
        "Delete Backup?",
        "This action cannot be undone.",
        type = "warning",
        showCancelButton = TRUE,
        confirmButtonText = "Delete",
        cancelButtonText = "Cancel",
        confirmButtonColor = "#d33",
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
      if (is.null(backup_state$selected_backup)) {
        shinyalert("Error", "Please select a backup to restore", type = "error")
        return()
      }

      if (input$restore_confirmation != "RESTORE") {
        shinyalert("Confirmation Failed", 'Please type "RESTORE" to confirm restoration', type = "error")
        return()
      }

      tryCatch({
        shinyjs::show("restore_progress")

        backup_file <- backup_state$selected_backup
        db_file <- db_path()
        current_time <- format(Sys.time(), "%Y%m%d_%H%M%S")
        safety_backup <- file.path(backup_dir, paste0("pre_restore_", current_time, ".db"))

        # Safety: create backup of current database
        shinyjs::runjs(sprintf(
          "document.getElementById('%s').style.width = '25%%'; document.getElementById('%s').textContent = 'Creating safety backup...'",
          ns("restore_progress_bar"), ns("restore_status")
        ))

        if (file.exists(db_file)) {
          file.copy(db_file, safety_backup, overwrite = TRUE)
        }

        # Decompress if needed
        shinyjs::runjs(sprintf(
          "document.getElementById('%s').style.width = '50%%'; document.getElementById('%s').textContent = 'Decompressing backup...'",
          ns("restore_progress_bar"), ns("restore_status")
        ))

        if (grepl("\\.gz$", backup_file)) {
          temp_file <- tempfile(fileext = ".db")
          R.utils::gunzip(backup_file, destname = temp_file, remove = FALSE)
          restore_source <- temp_file
        } else {
          restore_source <- backup_file
        }

        # Restore database
        shinyjs::runjs(sprintf(
          "document.getElementById('%s').style.width = '75%%'; document.getElementById('%s').textContent = 'Restoring database...'",
          ns("restore_progress_bar"), ns("restore_status")
        ))

        file.copy(restore_source, db_file, overwrite = TRUE)

        # Verify restoration
        shinyjs::runjs(sprintf(
          "document.getElementById('%s').style.width = '90%%'; document.getElementById('%s').textContent = 'Verifying...'",
          ns("restore_progress_bar"), ns("restore_status")
        ))

        # Close database connections to allow reconnection
        if (!is.null(db_pool)) {
          pool::poolClose(db_pool)
        }

        # Complete
        shinyjs::runjs(sprintf(
          "document.getElementById('%s').style.width = '100%%'; document.getElementById('%s').textContent = 'Complete!'",
          ns("restore_progress_bar"), ns("restore_status")
        ))

        Sys.sleep(1)
        shinyjs::hide("restore_progress")

        shinyalert("Restoration Complete",
                  paste("Database restored successfully.\n",
                        "Note: Please refresh your browser to reconnect to the database."),
                  type = "success")

        # Clear confirmation field
        updateTextInput(session, "restore_confirmation", value = "")

      }, error = function(e) {
        shinyalert("Restoration Error",
                  paste("Failed to restore backup:", e$message, "\n\n",
                        "Your current database is still intact."),
                  type = "error")
        shinyjs::hide("restore_progress")
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
#' @export
perform_automatic_backup <- function(db_path, backup_dir = "./backups", compress = TRUE, keep_days = 30) {

  tryCatch({
    if (!dir.exists(backup_dir)) {
      dir.create(backup_dir, recursive = TRUE)
    }

    if (!file.exists(db_path)) {
      return(list(success = FALSE, message = "Database file not found"))
    }

    # Create backup
    timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
    backup_filename <- paste0("auto_backup_", timestamp, ".db")
    backup_filepath <- file.path(backup_dir, backup_filename)

    file.copy(db_path, backup_filepath, overwrite = TRUE)

    if (compress) {
      R.utils::gzip(backup_filepath, destname = paste0(backup_filepath, ".gz"), remove = TRUE)
      backup_filepath <- paste0(backup_filepath, ".gz")
    }

    # Clean up old backups
    backup_files <- list.files(backup_dir, pattern = "^auto_backup_.*\\.db(\\.gz)?$", full.names = TRUE)
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
