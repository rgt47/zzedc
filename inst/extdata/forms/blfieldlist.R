# forms/blfieldlist.R
#
# Demonstration field list for the EDC tab. Read by
# `inst/app/edc.R` via `dget()`. The returned object is the
# argument to `zzedc::renderPanel()`; it can be either a simple
# character vector of field names (this file) or a list of
# field-metadata records (see `?zzedc::renderPanel` for the
# typed-input form).
#
# Replace with your study's actual baseline-visit field list.
c(
  "subject_id",
  "visit_date",
  "age",
  "sex",
  "weight_kg",
  "height_cm",
  "bp_systolic",
  "bp_diastolic",
  "notes"
)
