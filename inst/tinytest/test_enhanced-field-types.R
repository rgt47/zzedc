library(tinytest)

# Helpers (auto-loaded by testthat under the previous layout).
# tinytest auto-sources files prefixed with `_` (so `_setup.R`)
# when invoked via `tinytest::test_package()`. The explicit
# source() below keeps the test runnable when invoked directly
# (e.g., `tinytest::run_test_file("test_foo.R")`).
if (file.exists("_setup.R")) source("_setup.R")
# Test: Enhanced Field Types

# Test: renderPanel generates text input by default
local({
    result <- renderPanel(c("field1"))

    expect_equal(typeof(result), "list")
    expect_equal(length(result), 1)

})
# Test: renderPanel handles numeric field with range
local({
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

    expect_equal(typeof(result), "list")
    expect_equal(length(result), 1)

})
# Test: renderPanel handles date field
local({
    metadata <- list(
      visit_date = list(
        type = "date",
        label = "Visit Date",
        value = as.Date("2025-01-15")
      )
    )

    result <- renderPanel("visit_date", metadata)

    expect_equal(typeof(result), "list")
    expect_equal(length(result), 1)

})
# Test: renderPanel handles select field with choices
local({
    metadata <- list(
      gender = list(
        type = "select",
        label = "Gender",
        choices = c("M", "F", "Other"),
        value = "M"
      )
    )

    result <- renderPanel("gender", metadata)

    expect_equal(typeof(result), "list")
    expect_equal(length(result), 1)

})
# Test: renderPanel handles checkbox field
local({
    metadata <- list(
      consent = list(
        type = "checkbox",
        label = "I consent to participate",
        value = FALSE
      )
    )

    result <- renderPanel("consent", metadata)

    expect_equal(typeof(result), "list")
    expect_equal(length(result), 1)

})
# Test: renderPanel handles textarea field
local({
    metadata <- list(
      comments = list(
        type = "textarea",
        label = "Comments",
        rows = 5,
        placeholder = "Enter your comments..."
      )
    )

    result <- renderPanel("comments", metadata)

    expect_equal(typeof(result), "list")
    expect_equal(length(result), 1)

})
# Test: renderPanel handles notes field (textarea variant)
local({
    metadata <- list(
      clinical_notes = list(
        type = "notes",
        label = "Clinical Notes",
        rows = 8
      )
    )

    result <- renderPanel("clinical_notes", metadata)

    expect_equal(typeof(result), "list")
    expect_equal(length(result), 1)

})
# Test: renderPanel handles email field
local({
    metadata <- list(
      email = list(
        type = "email",
        label = "Email Address",
        placeholder = "user@example.com"
      )
    )

    result <- renderPanel("email", metadata)

    expect_equal(typeof(result), "list")
    expect_equal(length(result), 1)

})
# Test: renderPanel handles slider field
local({
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

    expect_equal(typeof(result), "list")
    expect_equal(length(result), 1)

})
# Test: renderPanel handles radio button field
local({
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

    expect_equal(typeof(result), "list")
    expect_equal(length(result), 1)

})
# Test: renderPanel handles checkbox_group field
local({
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

    expect_equal(typeof(result), "list")
    expect_equal(length(result), 1)

})
# Test: renderPanel handles file upload field
local({
    metadata <- list(
      document = list(
        type = "file",
        label = "Upload Document",
        multiple = FALSE,
        accept = c(".pdf", ".docx")
      )
    )

    result <- renderPanel("document", metadata)

    expect_equal(typeof(result), "list")
    expect_equal(length(result), 1)

})
# Test: renderPanel handles time field (with fallback)
local({
    metadata <- list(
      visit_time = list(
        type = "time",
        label = "Visit Time",
        seconds = FALSE
      )
    )

    result <- renderPanel("visit_time", metadata)

    expect_equal(typeof(result), "list")
    expect_equal(length(result), 1)

})
# Test: renderPanel handles datetime field (with fallback)
local({
    metadata <- list(
      event_datetime = list(
        type = "datetime",
        label = "Event Date & Time",
        format = "YYYY-MM-DD HH:mm"
      )
    )

    result <- renderPanel("event_datetime", metadata)

    expect_equal(typeof(result), "list")
    expect_equal(length(result), 1)

})
# Test: renderPanel handles signature field (with fallback)
local({
    metadata <- list(
      signature = list(
        type = "signature",
        label = "Digital Signature",
        width = "100%",
        height = "200px"
      )
    )

    result <- renderPanel("signature", metadata)

    expect_equal(typeof(result), "list")
    expect_equal(length(result), 1)

})
# Test: renderPanel handles required fields with asterisk
local({
    metadata <- list(
      name = list(
        type = "text",
        label = "Full Name",
        required = TRUE
      )
    )

    result <- renderPanel("name", metadata)

    expect_equal(typeof(result), "list")
    expect_equal(length(result), 1)

})
# Test: renderPanel includes help text when provided
local({
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

    expect_equal(typeof(result), "list")
    expect_equal(length(result), 1)

})
# Test: renderPanel handles multiple fields
local({
    metadata <- list(
      name = list(type = "text", label = "Name"),
      age = list(type = "numeric", label = "Age", min = 0, max = 120),
      gender = list(type = "select", label = "Gender", choices = c("M", "F")),
      date = list(type = "date", label = "Date")
    )

    result <- renderPanel(c("name", "age", "gender", "date"), metadata)

    expect_equal(typeof(result), "list")
    expect_equal(length(result), 4)

})
# Test: renderPanel handles missing metadata gracefully
local({
    result <- renderPanel(c("field1", "field2"))

    expect_equal(typeof(result), "list")
    expect_equal(length(result), 2)

})
# Test: renderPanel uses default values when not specified
local({
    metadata <- list(
      field1 = list(type = "numeric")
    )

    result <- renderPanel("field1", metadata)

    expect_equal(typeof(result), "list")
    expect_equal(length(result), 1)

})
# Test: renderPanel handles inline option for radio buttons
local({
    metadata <- list(
      yes_no = list(
        type = "radio",
        label = "Question",
        choices = c("Yes", "No"),
        inline = TRUE
      )
    )

    result <- renderPanel("yes_no", metadata)

    expect_equal(typeof(result), "list")
    expect_equal(length(result), 1)

})
# Test: renderPanel handles inline option for checkbox_group
local({
    metadata <- list(
      options = list(
        type = "checkbox_group",
        label = "Select options",
        choices = c("A", "B", "C"),
        inline = TRUE
      )
    )

    result <- renderPanel("options", metadata)

    expect_equal(typeof(result), "list")
    expect_equal(length(result), 1)

})
# Edge cases

# Test: renderPanel handles empty field list
local({
    result <- renderPanel(c())

    expect_equal(typeof(result), "list")
    expect_equal(length(result), 0)

})
# Test: renderPanel handles field with NULL metadata
local({
    metadata <- list(
      field1 = NULL
    )

    result <- renderPanel("field1", metadata)

    expect_equal(typeof(result), "list")

})
# Test: renderPanel handles special characters in labels
local({
    metadata <- list(
      field1 = list(
        type = "text",
        label = "Name (First & Last)"
      )
    )

    result <- renderPanel("field1", metadata)

    expect_equal(typeof(result), "list")
    expect_equal(length(result), 1)

})
# Test: renderPanel handles slider with animation
local({
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

    expect_equal(typeof(result), "list")
    expect_equal(length(result), 1)

})
# Test: renderPanel handles file upload with multiple files
local({
    metadata <- list(
      documents = list(
        type = "file",
        label = "Upload Multiple Files",
        multiple = TRUE
      )
    )

    result <- renderPanel("documents", metadata)

    expect_equal(typeof(result), "list")
    expect_equal(length(result), 1)

})
# Test: renderPanel handles select with multiple selection
local({
    metadata <- list(
      languages = list(
        type = "select",
        label = "Spoken Languages",
        choices = c("English", "Spanish", "French", "German"),
        multiple = TRUE
      )
    )

    result <- renderPanel("languages", metadata)

    expect_equal(typeof(result), "list")
    expect_equal(length(result), 1)

})