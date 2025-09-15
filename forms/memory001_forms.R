# forms/memory001_forms.R - Custom forms for MEMORY-001 Study

# Demographics form definition
demographics_form <- list(
  form_name = "demographics",
  form_title = "Demographics and Baseline Characteristics",
  fields = list(
    list(
      field_name = "subject_id",
      field_label = "Subject ID",
      field_type = "text",
      required = TRUE,
      validation = "^MEM-\\d{3}$",
      help_text = "Format: MEM-001 to MEM-050"
    ),
    list(
      field_name = "age",
      field_label = "Age (years)",
      field_type = "numeric",
      required = TRUE,
      min_value = 18,
      max_value = 85
    ),
    list(
      field_name = "gender",
      field_label = "Gender",
      field_type = "select",
      required = TRUE,
      choices = c("Male", "Female", "Other", "Prefer not to say")
    ),
    list(
      field_name = "race",
      field_label = "Race",
      field_type = "select",
      required = TRUE,
      choices = c("White", "Black or African American", "Asian", "American Indian or Alaska Native", 
                 "Native Hawaiian or Other Pacific Islander", "Other", "Multiple races")
    ),
    list(
      field_name = "ethnicity",
      field_label = "Ethnicity",
      field_type = "select",
      required = TRUE,
      choices = c("Hispanic or Latino", "Not Hispanic or Latino", "Unknown")
    ),
    list(
      field_name = "education_years",
      field_label = "Years of Education",
      field_type = "numeric",
      required = TRUE,
      min_value = 0,
      max_value = 25
    ),
    list(
      field_name = "height_cm",
      field_label = "Height (cm)",
      field_type = "numeric",
      required = TRUE,
      min_value = 100,
      max_value = 250
    ),
    list(
      field_name = "weight_kg",
      field_label = "Weight (kg)",
      field_type = "numeric",
      required = TRUE,
      min_value = 30,
      max_value = 200
    )
  )
)

# Cognitive assessment form
cognitive_form <- list(
  form_name = "cognitive_assessments",
  form_title = "Cognitive Assessment Battery",
  fields = list(
    list(
      field_name = "subject_id",
      field_label = "Subject ID",
      field_type = "text",
      required = TRUE
    ),
    list(
      field_name = "visit_name",
      field_label = "Visit",
      field_type = "select",
      required = TRUE,
      choices = c("Baseline", "Month 1", "Month 2", "Month 3", "Month 4", "Month 5", "Month 6")
    ),
    list(
      field_name = "visit_date",
      field_label = "Assessment Date",
      field_type = "date",
      required = TRUE
    ),
    list(
      field_name = "mmse_total",
      field_label = "MMSE Total Score",
      field_type = "numeric",
      required = TRUE,
      min_value = 0,
      max_value = 30,
      help_text = "Mini-Mental State Examination (0-30)"
    ),
    list(
      field_name = "moca_total",
      field_label = "MoCA Total Score",
      field_type = "numeric",
      required = TRUE,
      min_value = 0,
      max_value = 30,
      help_text = "Montreal Cognitive Assessment (0-30)"
    ),
    list(
      field_name = "digit_span_forward",
      field_label = "Digit Span Forward",
      field_type = "numeric",
      required = TRUE,
      min_value = 0,
      max_value = 9
    ),
    list(
      field_name = "digit_span_backward",
      field_label = "Digit Span Backward",
      field_type = "numeric",
      required = TRUE,
      min_value = 0,
      max_value = 8
    ),
    list(
      field_name = "trail_making_a_time",
      field_label = "Trail Making A Time (seconds)",
      field_type = "numeric",
      required = TRUE,
      min_value = 1
    ),
    list(
      field_name = "trail_making_b_time",
      field_label = "Trail Making B Time (seconds)",
      field_type = "numeric",
      required = TRUE,
      min_value = 1
    ),
    list(
      field_name = "verbal_fluency_animals",
      field_label = "Verbal Fluency - Animals",
      field_type = "numeric",
      required = TRUE,
      min_value = 0,
      help_text = "Number of animals named in 1 minute"
    ),
    list(
      field_name = "assessor_initials",
      field_label = "Assessor Initials",
      field_type = "text",
      required = TRUE,
      validation = "^[A-Z]{2,3}$"
    )
  )
)

# Adverse event form
adverse_event_form <- list(
  form_name = "adverse_events",
  form_title = "Adverse Event Report",
  fields = list(
    list(
      field_name = "subject_id",
      field_label = "Subject ID",
      field_type = "text",
      required = TRUE
    ),
    list(
      field_name = "ae_term",
      field_label = "Adverse Event Term",
      field_type = "text",
      required = TRUE,
      help_text = "Describe the adverse event in medical terminology"
    ),
    list(
      field_name = "ae_start_date",
      field_label = "Start Date",
      field_type = "date",
      required = TRUE
    ),
    list(
      field_name = "ae_end_date",
      field_label = "End Date",
      field_type = "date",
      required = FALSE
    ),
    list(
      field_name = "ongoing",
      field_label = "Ongoing",
      field_type = "checkbox",
      required = FALSE
    ),
    list(
      field_name = "severity",
      field_label = "Severity",
      field_type = "select",
      required = TRUE,
      choices = c("Mild", "Moderate", "Severe")
    ),
    list(
      field_name = "seriousness",
      field_label = "Seriousness",
      field_type = "select",
      required = TRUE,
      choices = c("Non-serious", "Serious")
    ),
    list(
      field_name = "relationship",
      field_label = "Relationship to Study Drug",
      field_type = "select",
      required = TRUE,
      choices = c("Unrelated", "Unlikely", "Possible", "Probable", "Definite")
    ),
    list(
      field_name = "action_taken",
      field_label = "Action Taken",
      field_type = "select",
      required = TRUE,
      choices = c("None", "Dose reduction", "Dose interruption", "Drug discontinued", "Other")
    ),
    list(
      field_name = "outcome",
      field_label = "Outcome",
      field_type = "select",
      required = TRUE,
      choices = c("Resolved", "Ongoing", "Resolved with sequelae", "Fatal")
    )
  )
)

# Save form definitions
save(demographics_form, cognitive_form, adverse_event_form, 
     file = "forms/memory001_form_definitions.RData")

cat("✅ Form definitions created for MEMORY-001 study\n")