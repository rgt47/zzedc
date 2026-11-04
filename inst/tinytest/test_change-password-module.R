library(tinytest)

if (file.exists("_setup.R")) source("_setup.R")

# Tests for change_password_module.R's change_password_server(),
# exercised end-to-end through shiny::testServer() the same way
# test_module_server.R drives auth_server().

local({
  if (!exists("change_password_server")) return(invisible())

  test_con <- create_test_db()
  user_input <- shiny::reactiveValues(
    user_id = 1L,
    must_change_password = TRUE
  )

  shiny::testServer(
    zzedc:::change_password_server,
    args = list(
      db_pool = test_con, user_input = user_input,
      salt = "test_salt_123", min_length = 8
    ),
    {
      # Blank password: rejected, nothing written, flag untouched.
      session$setInputs(new_password = "", confirm_password = "", submit = 1)
      expect_true(isolate(user_input$must_change_password))

      # Too short: rejected.
      session$setInputs(new_password = "short1", confirm_password = "short1",
                         submit = 2)
      expect_true(isolate(user_input$must_change_password))

      # Mismatched confirmation: rejected.
      session$setInputs(new_password = "longenough1",
                         confirm_password = "longenough2", submit = 3)
      expect_true(isolate(user_input$must_change_password))

      # Valid, matching, long-enough password: accepted.
      session$setInputs(new_password = "newpassword123",
                         confirm_password = "newpassword123", submit = 4)
      expect_false(isolate(user_input$must_change_password))
    }
  )

  row <- DBI::dbGetQuery(test_con,
    "SELECT password_hash, must_change_password FROM edc_users WHERE user_id = 1")
  expect_equal(row$must_change_password[1], 0L)
  expect_equal(
    row$password_hash[1],
    digest::digest(paste0("newpassword123", "test_salt_123"), algo = "sha256")
  )

  DBI::dbDisconnect(test_con)
})


# Test: change_password_ui() produces a form with both password
# inputs and a submit button
local({
  if (!exists("change_password_ui")) return(invisible())

  ui <- zzedc:::change_password_ui("cp")
  html <- as.character(ui)

  expect_true(grepl('id="cp-new_password"', html, fixed = TRUE))
  expect_true(grepl('id="cp-confirm_password"', html, fixed = TRUE))
  expect_true(grepl('id="cp-submit"', html, fixed = TRUE))
})
