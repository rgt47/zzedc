library(tinytest)

# Helpers (auto-loaded by testthat under the previous layout).
# tinytest auto-sources files prefixed with `_` (so `_setup.R`)
# when invoked via `tinytest::test_package()`. The explicit
# source() below keeps the test runnable when invoked directly
# (e.g., `tinytest::run_test_file("test_foo.R")`).
if (file.exists("_setup.R")) source("_setup.R")
# Tests for Phase 1 Modules: Setup Wizard, User Management, Backup/Restore, Audit Log
# Comprehensive testing of non-technical admin features

# Group: create_wizard_database
local({
    # Test: creates database with all required tables
    local({
            # Create temporary database
            temp_db <- tempfile(fileext = ".db")

            config <- list(
              study_name = "Test Study",
              protocol_id = "TEST-001",
              admin_username = "admin",
              admin_password = "AdminPass123!",
              admin_fullname = "Test Admin",
              admin_email = "admin@test.edu",
              pi_name = "Dr. Test",
              pi_email = "pi@test.edu",
              study_phase = "Phase 2",
              target_enrollment = 100,
              security_salt = "test_salt_12345",
              session_timeout = 30,
              max_login_attempts = 3,
              team_members = data.frame(
                username = "coord1",
                full_name = "Test Coordinator",
                email = "coord@test.edu",
                role = "Coordinator",
                stringsAsFactors = FALSE
              )
            )

            result <- create_wizard_database(config, temp_db)

            expect_true(result$success)
            expect_true(file.exists(temp_db))
            expect_match(result$message, "Database created successfully")

            # Verify tables exist
            conn <- DBI::dbConnect(RSQLite::SQLite(), temp_db)
            tables <- DBI::dbListTables(conn)

            expect_true("edc_users" %in% tables)
            expect_true("study_info" %in% tables)
            expect_true("edc_roles" %in% tables)
            expect_true("subjects" %in% tables)
            expect_true("data_entries" %in% tables)
            expect_true("audit_trail" %in% tables)

            # Verify admin user was created
            admin_user <- DBI::dbGetQuery(conn, "SELECT * FROM edc_users WHERE username = 'admin'")
            expect_equal(nrow(admin_user), 1)
            expect_equal(admin_user$role[1], "Admin")

            # Verify study was created
            study <- DBI::dbGetQuery(conn, "SELECT * FROM study_info")
            expect_equal(nrow(study), 1)
            expect_equal(study$study_name[1], "Test Study")

            # Verify roles exist
            roles <- DBI::dbGetQuery(conn, "SELECT * FROM edc_roles")
            expect_equal(nrow(roles), 5)  # 5 predefined roles

            DBI::dbDisconnect(conn)
            unlink(temp_db)
    
    })
})
# Group: create_wizard_config
local({
    # Test: creates valid YAML config file
    local({
            temp_config <- tempfile(fileext = ".yml")

            config <- list(
              study_name = "Test Study",
              protocol_id = "TEST-001",
              pi_name = "Dr. Test",
              pi_email = "pi@test.edu",
              study_phase = "Phase 2",
              target_enrollment = 100,
              session_timeout = 30,
              max_login_attempts = 3,
              enforce_https = "yes"
            )

            result <- create_wizard_config(config, temp_config, "test_salt_123")

            expect_true(result$success)
            expect_true(file.exists(temp_config))

            # Verify config content
            config_content <- readLines(temp_config)
            expect_true(any(grepl("Test Study", config_content)))
            expect_true(any(grepl("TEST-001", config_content)))
            expect_true(any(grepl("session_timeout_minutes: 30", config_content)))

            unlink(temp_config)
    
    })
})
# Group: create_wizard_directories
local({
    # Test: creates required directory structure
    local({
            temp_base <- tempdir()

            result <- create_wizard_directories(temp_base)

            expect_true(result$success)
            expect_true(dir.exists(file.path(temp_base, "data")))
            expect_true(dir.exists(file.path(temp_base, "logs")))
            expect_true(dir.exists(file.path(temp_base, "forms")))
            expect_true(dir.exists(file.path(temp_base, "backups")))
            expect_true(dir.exists(file.path(temp_base, "exports")))
    
    })
})
# Group: create_launch_script
local({
    # Test: creates executable launch script
    local({
            temp_script <- tempfile(fileext = ".R")

            config <- list(
              study_name = "Test Study",
              protocol_id = "TEST-001",
              security_salt = "test_salt_123"
            )

            result <- create_launch_script(config, temp_script)

            expect_true(result$success)
            expect_true(file.exists(temp_script))

            # Verify script content
            script_content <- readLines(temp_script)
            expect_true(any(grepl("launch_zzedc", script_content)))
            expect_true(any(grepl("Test Study", script_content)))
    
    })
})
# Group: complete_wizard_setup
local({
    # Test: orchestrates complete setup process
    local({
            temp_base <- tempdir()

            config <- list(
              study_name = "Integration Test",
              protocol_id = "INT-001",
              admin_username = "admin",
              admin_password = "AdminPass123!",
              admin_fullname = "Test Admin",
              admin_email = "admin@test.edu",
              pi_name = "Dr. Test",
              pi_email = "pi@test.edu",
              study_phase = "Phase 1",
              target_enrollment = 50,
              security_salt = "integration_test_salt",
              session_timeout = 30,
              max_login_attempts = 3,
              enforce_https = "no",
              team_members = data.frame()
            )

            result <- complete_wizard_setup(config, temp_base)

            expect_true(result$overall_success)
            expect_true(result$steps$directories$success)
            expect_true(result$steps$database$success)
            expect_true(result$steps$config$success)
            expect_true(result$steps$launch_script$success)
            expect_true(file.exists(file.path(temp_base, "data", "zzedc.db")))
            expect_true(file.exists(file.path(temp_base, "config.yml")))
            expect_true(file.exists(file.path(temp_base, "launch_app.R")))
    
    })
})
# Phase 1: User Management Functions

# Group: save_user_to_db
local({
    # Test: creates new user with hashed password
    local({
            skip("Module functions tested via module servers")
    
    })
})
# Phase 1: Backup and Restore Functions

# Group: perform_automatic_backup
local({
    # Test: creates compressed database backup
    local({
            skip("Backup module tested via module servers")
    
    })
    # Test: cleans up old backups beyond retention period
    local({
            skip("Backup module tested via module servers")
    
    })
})
# Phase 1: Audit Logging Functions

# Group: log_audit_action
local({
    # Test: requires valid parameters
    local({
            skip("Audit module tested via module servers")
    
    })
})
# Phase 1: Integration Tests

# Group: Complete wizard setup end-to-end
local({
    # Test: creates fully functional ZZedc instance
    local({
            skip("Integration test - requires full setup")

            temp_install <- file.path(tempdir(), "zzedc_test_install")

            config <- list(
              study_name = "E2E Test Study",
              protocol_id = "E2E-001",
              admin_username = "admin",
              admin_password = "AdminPass123!",
              admin_fullname = "E2E Admin",
              admin_email = "admin@test.edu",
              pi_name = "Dr. E2E",
              pi_email = "pi@test.edu",
              study_phase = "Phase 1",
              target_enrollment = 25,
              security_salt = "e2e_test_salt_v1",
              session_timeout = 30,
              max_login_attempts = 3,
              enforce_https = "no",
              team_members = data.frame(
                username = c("coord1", "dm1"),
                full_name = c("Test Coordinator", "Test Data Manager"),
                email = c("coord@test.edu", "dm@test.edu"),
                role = c("Coordinator", "Data Manager"),
                stringsAsFactors = FALSE
              )
            )

            # Complete setup
            result <- complete_wizard_setup(config, temp_install)

            # Verify all files created
            expect_true(file.exists(file.path(temp_install, "data", "zzedc.db")))
            expect_true(file.exists(file.path(temp_install, "config.yml")))
            expect_true(file.exists(file.path(temp_install, "launch_app.R")))

            # Verify database content
            conn <- DBI::dbConnect(RSQLite::SQLite(), file.path(temp_install, "data", "zzedc.db"))

            # Check admin user
            admin <- DBI::dbGetQuery(conn, "SELECT * FROM edc_users WHERE username = 'admin'")
            expect_equal(nrow(admin), 1)

            # Check team members
            team <- DBI::dbGetQuery(conn, "SELECT * FROM edc_users WHERE role IN ('Coordinator', 'Data Manager')")
            expect_equal(nrow(team), 2)

            # Check study
            study <- DBI::dbGetQuery(conn, "SELECT * FROM study_info")
            expect_equal(study$target_enrollment[1], 25)

            DBI::dbDisconnect(conn)

            # Cleanup
            unlink(temp_install, recursive = TRUE)
    
    })
})
# Phase 1: Error Handling

# Group: Error handling in setup functions
local({
    # Test: gracefully handles invalid database paths
    local({
            config <- list(
              study_name = "Test",
              protocol_id = "TEST-001",
              admin_username = "admin",
              admin_password = "Admin123!",
              admin_fullname = "Admin",
              admin_email = "admin@test.edu",
              pi_name = "PI",
              pi_email = "pi@test.edu",
              study_phase = "Phase 1",
              target_enrollment = 50,
              security_salt = "salt",
              team_members = data.frame()
            )

            # Try to create database in invalid path (suppress expected warning)
            result <- suppressWarnings(
              create_wizard_database(config, "/nonexistent/path/to/db.db")
            )

            expect_false(result$success)
            expect_match(result$message, "Error")
    
    })
    # Test: handles missing database files in backups
    local({
            skip("Tested via backup module server")
    
    })
})
# Phase 1: Module Instantiation

# Group: Shiny modules can be instantiated
local({
    # Test: setup_wizard_ui creates valid UI
    local({
            skip("Module UI tests require Shiny environment")
    
    })
    # Test: user_management_ui creates valid UI
    local({
            skip("Module UI tests require Shiny environment")
    
    })
    # Test: backup_restore_ui creates valid UI
    local({
            skip("Module UI tests require Shiny environment")
    
    })
    # Test: audit_log_viewer_ui creates valid UI
    local({
            skip("Module UI tests require Shiny environment")
    
    })
    # Test: admin_dashboard_ui creates valid UI
    local({
            skip("Module UI tests require Shiny environment")
    
    })
})