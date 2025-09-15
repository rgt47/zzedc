## ----include = FALSE----------------------------------------------------------
knitr::opts_chunk$set(
  collapse = TRUE,
  comment = "#>",
  eval = FALSE
)

## ----setup--------------------------------------------------------------------
# library(zzedc)
# library(shiny)
# library(DT)

## ----launch-------------------------------------------------------------------
# # Launch ZZedc application
# launch_zzedc(
#   host = "127.0.0.1",
#   port = 3838,
#   launch.browser = TRUE
# )

## ----config-------------------------------------------------------------------
# # Basic configuration for small study
# config_setup <- list(
#   study_name = "Pilot Sleep Study",
#   principal_investigator = "Dr. Smith",
#   site_count = 1,
#   target_enrollment = 25,
#   study_phase = "Pilot"
# )

## ----data_entry---------------------------------------------------------------
# # Example data structure for small study
# small_study_data <- data.frame(
#   subject_id = paste0("SS_", sprintf("%03d", 1:25)),
#   enrollment_date = seq(as.Date("2024-01-01"), by = "week", length.out = 25),
#   age = sample(18:65, 25, replace = TRUE),
#   gender = sample(c("M", "F"), 25, replace = TRUE),
#   baseline_score = round(rnorm(25, 50, 10), 1),
#   status = sample(c("Active", "Completed", "Withdrawn"), 25,
#                   replace = TRUE, prob = c(0.6, 0.3, 0.1))
# )
# 
# # Display sample data
# head(small_study_data)

## ----quality_checks-----------------------------------------------------------
# # Basic data quality metrics
# quality_summary <- function(data) {
#   list(
#     total_subjects = nrow(data),
#     complete_cases = sum(complete.cases(data)),
#     missing_data_pct = round(mean(is.na(data)) * 100, 1),
#     enrollment_rate = paste(nrow(data), "subjects enrolled")
#   )
# }
# 
# # Example quality check
# quality_summary(small_study_data)

## ----enrollment_report--------------------------------------------------------
# # Simple enrollment tracking
# enrollment_summary <- small_study_data %>%
#   group_by(status) %>%
#   summarise(
#     count = n(),
#     percentage = round(n() / nrow(small_study_data) * 100, 1)
#   )
# 
# print(enrollment_summary)

## ----demographics-------------------------------------------------------------
# # Demographics summary
# demo_summary <- list(
#   age_stats = summary(small_study_data$age),
#   gender_distribution = table(small_study_data$gender),
#   baseline_score_mean = round(mean(small_study_data$baseline_score, na.rm = TRUE), 1)
# )
# 
# demo_summary

## ----export-------------------------------------------------------------------
# # Export data for analysis
# # In the ZZedc interface, use Export tab > CSV format
# # Alternatively, save data programmatically:
# write.csv(small_study_data, "small_study_export.csv", row.names = FALSE)

## ----analysis_format----------------------------------------------------------
# # Prepare data for statistical analysis
# analysis_data <- small_study_data %>%
#   select(subject_id, age, gender, baseline_score, status) %>%
#   mutate(
#     age_group = cut(age, breaks = c(0, 30, 50, 100),
#                     labels = c("18-30", "31-50", "51+")),
#     completed = ifelse(status == "Completed", 1, 0)
#   )
# 
# head(analysis_data)

## ----review_schedule----------------------------------------------------------
# # Suggested review schedule for small studies
# review_schedule <- data.frame(
#   activity = c("Data entry review", "Missing data check", "Protocol deviations", "Export backup"),
#   frequency = c("Daily", "Weekly", "Weekly", "Weekly"),
#   responsible = c("Research assistant", "PI", "PI", "Data manager")
# )
# 
# print(review_schedule)

