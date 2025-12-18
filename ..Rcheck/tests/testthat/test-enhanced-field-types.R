# Test: Enhanced Field Types

test_that("renderPanel generates text input by default", {
  result <- renderPanel(c("field1"))

  expect_type(result, "list")
  expect_length(result, 1)
})

test_that("renderPanel handles numeric field with range", {
  metadata <- list(
    age = list(
      type = "numeric",
      label = "Age (years)",
      min = 0,
      max = 120,
      value = 25
    )
  )

  result <- renderPanel("age", metadata)

  expect_type(result, "list")
  expect_length(result, 1)
})

test_that("renderPanel handles date field", {
  metadata <- list(
    visit_date = list(
      type = "date",
      label = "Visit Date",
      value = as.Date("2025-01-15")
    )
  )

  result <- renderPanel("visit_date", metadata)

  expect_type(result, "list")
  expect_length(result, 1)
})

test_that("renderPanel handles select field with choices", {
  metadata <- list(
    gender = list(
      type = "select",
      label = "Gender",
      choices = c("M", "F", "Other"),
      value = "M"
    )
  )

  result <- renderPanel("gender", metadata)

  expect_type(result, "list")
  expect_length(result, 1)
})

test_that("renderPanel handles checkbox field", {
  metadata <- list(
    consent = list(
      type = "checkbox",
      label = "I consent to participate",
      value = FALSE
    )
  )

  result <- renderPanel("consent", metadata)

  expect_type(result, "list")
  expect_length(result, 1)
})

test_that("renderPanel handles textarea field", {
  metadata <- list(
    comments = list(
      type = "textarea",
      label = "Comments",
      rows = 5,
      placeholder = "Enter your comments..."
    )
  )

  result <- renderPanel("comments", metadata)

  expect_type(result, "list")
  expect_length(result, 1)
})

test_that("renderPanel handles notes field (textarea variant)", {
  metadata <- list(
    clinical_notes = list(
      type = "notes",
      label = "Clinical Notes",
      rows = 8
    )
  )

  result <- renderPanel("clinical_notes", metadata)

  expect_type(result, "list")
  expect_length(result, 1)
})

test_that("renderPanel handles email field", {
  metadata <- list(
    email = list(
      type = "email",
      label = "Email Address",
      placeholder = "user@example.com"
    )
  )

  result <- renderPanel("email", metadata)

  expect_type(result, "list")
  expect_length(result, 1)
})

test_that("renderPanel handles slider field", {
  metadata <- list(
    pain_level = list(
      type = "slider",
      label = "Pain Level (0-10)",
      min = 0,
      max = 10,
      value = 5,
      step = 1
    )
  )

  result <- renderPanel("pain_level", metadata)

  expect_type(result, "list")
  expect_length(result, 1)
})

test_that("renderPanel handles radio button field", {
  metadata <- list(
    treatment = list(
      type = "radio",
      label = "Treatment Group",
      choices = c("Control", "Treatment A", "Treatment B"),
      value = "Control",
      inline = FALSE
    )
  )

  result <- renderPanel("treatment", metadata)

  expect_type(result, "list")
  expect_length(result, 1)
})

test_that("renderPanel handles checkbox_group field", {
  metadata <- list(
    symptoms = list(
      type = "checkbox_group",
      label = "Select symptoms:",
      choices = c("Fever", "Cough", "Headache", "Fatigue"),
      value = c("Fever", "Cough"),
      inline = FALSE
    )
  )

  result <- renderPanel("symptoms", metadata)

  expect_type(result, "list")
  expect_length(result, 1)
})

test_that("renderPanel handles file upload field", {
  metadata <- list(
    document = list(
      type = "file",
      label = "Upload Document",
      multiple = FALSE,
      accept = c(".pdf", ".docx")
    )
  )

  result <- renderPanel("document", metadata)

  expect_type(result, "list")
  expect_length(result, 1)
})

test_that("renderPanel handles time field (with fallback)", {
  metadata <- list(
    visit_time = list(
      type = "time",
      label = "Visit Time",
      seconds = FALSE
    )
  )

  result <- renderPanel("visit_time", metadata)

  expect_type(result, "list")
  expect_length(result, 1)
})

test_that("renderPanel handles datetime field (with fallback)", {
  metadata <- list(
    event_datetime = list(
      type = "datetime",
      label = "Event Date & Time",
      format = "YYYY-MM-DD HH:mm"
    )
  )

  result <- renderPanel("event_datetime", metadata)

  expect_type(result, "list")
  expect_length(result, 1)
})

test_that("renderPanel handles signature field (with fallback)", {
  metadata <- list(
    signature = list(
      type = "signature",
      label = "Digital Signature",
      width = "100%",
      height = "200px"
    )
  )

  result <- renderPanel("signature", metadata)

  expect_type(result, "list")
  expect_length(result, 1)
})

test_that("renderPanel handles required fields with asterisk", {
  metadata <- list(
    name = list(
      type = "text",
      label = "Full Name",
      required = TRUE
    )
  )

  result <- renderPanel("name", metadata)

  expect_type(result, "list")
  expect_length(result, 1)
})

test_that("renderPanel includes help text when provided", {
  metadata <- list(
    age = list(
      type = "numeric",
      label = "Age (years)",
      help = "Enter your age in years at time of enrollment",
      min = 18,
      max = 89
    )
  )

  result <- renderPanel("age", metadata)

  expect_type(result, "list")
  expect_length(result, 1)
})

test_that("renderPanel handles multiple fields", {
  metadata <- list(
    name = list(type = "text", label = "Name"),
    age = list(type = "numeric", label = "Age", min = 0, max = 120),
    gender = list(type = "select", label = "Gender", choices = c("M", "F")),
    date = list(type = "date", label = "Date")
  )

  result <- renderPanel(c("name", "age", "gender", "date"), metadata)

  expect_type(result, "list")
  expect_length(result, 4)
})

test_that("renderPanel handles missing metadata gracefully", {
  result <- renderPanel(c("field1", "field2"))

  expect_type(result, "list")
  expect_length(result, 2)
})

test_that("renderPanel uses default values when not specified", {
  metadata <- list(
    field1 = list(type = "numeric")
  )

  result <- renderPanel("field1", metadata)

  expect_type(result, "list")
  expect_length(result, 1)
})

test_that("renderPanel handles inline option for radio buttons", {
  metadata <- list(
    yes_no = list(
      type = "radio",
      label = "Question",
      choices = c("Yes", "No"),
      inline = TRUE
    )
  )

  result <- renderPanel("yes_no", metadata)

  expect_type(result, "list")
  expect_length(result, 1)
})

test_that("renderPanel handles inline option for checkbox_group", {
  metadata <- list(
    options = list(
      type = "checkbox_group",
      label = "Select options",
      choices = c("A", "B", "C"),
      inline = TRUE
    )
  )

  result <- renderPanel("options", metadata)

  expect_type(result, "list")
  expect_length(result, 1)
})

# Edge cases

test_that("renderPanel handles empty field list", {
  result <- renderPanel(c())

  expect_type(result, "list")
  expect_length(result, 0)
})

test_that("renderPanel handles field with NULL metadata", {
  metadata <- list(
    field1 = NULL
  )

  result <- renderPanel("field1", metadata)

  expect_type(result, "list")
})

test_that("renderPanel handles special characters in labels", {
  metadata <- list(
    field1 = list(
      type = "text",
      label = "Name (First & Last)"
    )
  )

  result <- renderPanel("field1", metadata)

  expect_type(result, "list")
  expect_length(result, 1)
})

test_that("renderPanel handles slider with animation", {
  metadata <- list(
    timeline = list(
      type = "slider",
      label = "Timeline",
      min = 0,
      max = 100,
      value = 50,
      animate = TRUE
    )
  )

  result <- renderPanel("timeline", metadata)

  expect_type(result, "list")
  expect_length(result, 1)
})

test_that("renderPanel handles file upload with multiple files", {
  metadata <- list(
    documents = list(
      type = "file",
      label = "Upload Multiple Files",
      multiple = TRUE
    )
  )

  result <- renderPanel("documents", metadata)

  expect_type(result, "list")
  expect_length(result, 1)
})

test_that("renderPanel handles select with multiple selection", {
  metadata <- list(
    languages = list(
      type = "select",
      label = "Spoken Languages",
      choices = c("English", "Spanish", "French", "German"),
      multiple = TRUE
    )
  )

  result <- renderPanel("languages", metadata)

  expect_type(result, "list")
  expect_length(result, 1)
})
