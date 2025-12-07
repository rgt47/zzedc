# ZZedc Validation DSL User Guide

Complete guide to writing validation rules using the ZZedc Domain-Specific Language (DSL) for clinical trial data entry and quality control.

**Target Audience:** Clinical research coordinators, data managers, and non-technical study staff

**Last Updated:** 2024-12

---

## Table of Contents

1. [Introduction](#introduction)
2. [Quick Start](#quick-start)
3. [Real-Time Validation (Field-Level)](#real-time-validation)
4. [Batch QC Validation (Nightly Checks)](#batch-qc-validation)
5. [Syntax Reference](#syntax-reference)
6. [Common Clinical Trial Examples](#common-examples)
7. [Troubleshooting](#troubleshooting)
8. [Best Practices](#best-practices)

---

## Introduction

The ZZedc Validation DSL lets you define data validation rules in plain English-like syntax that doesn't require programming knowledge.

### Two Types of Validation

| Aspect | Real-Time | Batch QC |
|--------|-----------|----------|
| **When** | While data entry | Nightly after data collection |
| **Scope** | Single form/visit | Across all visits for a patient |
| **Purpose** | Catch errors immediately | Find patterns, inconsistencies, outliers |
| **Example** | "Blood pressure between 40 and 200" | "Weight within 10% of previous visit" |

---

## Quick Start

### Real-Time Example: Age Validation

For a study that only enrolls participants aged 18-65:

```
between 18 and 65
```

That's it! ZZedc will show an error if someone tries to enter an age outside that range.

### Batch Example: Visit Date Consistency

To ensure visit dates are within the expected window:

```
visit_date within 30 days of baseline_date
```

ZZedc will flag any visit dates that are more than 30 days off schedule.

---

## Real-Time Validation

### Syntax Categories

#### 1. Range Validation

Check if values fall within acceptable limits.

**Between syntax:**
```
between 40 and 200
```
Use for: blood pressure, heart rate, BMI, lab values

**Numeric range syntax:**
```
1..100
```
Use for: scores with clear minimum and maximum

#### 2. Comparison Operators

```
>= 18          # Greater than or equal to
< 65           # Less than
== "yes"       # Equals (for text or numbers)
!= "N/A"       # Does not equal
```

#### 3. List Validation

**Allow specific values:**
```
in(1, 2, 3)
```
Use for: visit codes, medication names, yes/no flags

**Prevent specific values:**
```
not_in(n, m)
```
Use for: Prevent "not applicable" when value required

#### 4. Required Fields

Make a field mandatory:

```
required
```

**Optional variant:**
```
required unless status == "exempt"
```

#### 5. Text-Based Validation

**Check text length:**
```
length > 3
```
Use for: Minimum description length

**Prevent blank/missing values:**
```
allow n, m
```
Note: `n` = blank, `m` = missing value

#### 6. Cross-Field Validation

Compare one field to another in the same form:

```
visit_date > baseline_date
```

Check medication dose when medication is selected:
```
if medication == "yes" then dose required endif
```

#### 7. Conditional Logic

**Simple if/then:**
```
if age >= 65 then between 90 and 180 else between 110 and 200 endif
```

**Based on visit:**
```
if visit == "screening" then allow n endif
```

**Multiple conditions:**
```
if age >= 65 and weight > 100 then dose == "high" endif
```

#### 8. Date-Based Validation

**Check dates aren't in the future:**
```
screening_date <= today()
```

**Date arithmetic:**
```
visit_date between baseline_date and baseline_date + 90
```

**Within a time window:**
```
visit_date within 30 days of baseline_date
```

---

## Batch QC Validation

Batch validation runs automatically each night and flags data quality issues across the entire dataset.

### Cross-Visit Consistency

Check that values stay consistent across visits (with tolerance):

```
weight within 10% of baseline_weight
```

This checks each patient's weight and flags if it differs by more than 10% from their baseline.

### Missing Data Patterns

Flag patients with missing required visits:

```
if visit in(baseline, week4, week8) then visit_date required
```

This ensures every patient has data for all expected visits.

### Statistical Outliers

Flag extreme values that might indicate data entry errors:

```
flag if blood_pressure > mean + 3*sd
```

This identifies blood pressure values that are 3+ standard deviations from the average.

### Protocol Deviations

Ensure visits happen on schedule:

```
visit_date within screening_date + [30,90] days by visit
```

This checks that week4 visits happen 30-90 days after screening for each patient.

---

## Syntax Reference

### Operators

| Operator | Meaning | Example |
|----------|---------|---------|
| `>=` | Greater than or equal | `age >= 18` |
| `<=` | Less than or equal | `weight <= 300` |
| `>` | Greater than | `score > 50` |
| `<` | Less than | `value < 100` |
| `==` | Equals | `status == "enrolled"` |
| `!=` | Not equal | `site != "withdrawn"` |

### Keywords

| Keyword | Purpose | Example |
|---------|---------|---------|
| `between` | Range check | `between 40 and 200` |
| `in()` | Value in list | `in(yes, no, unknown)` |
| `required` | Field must have value | `required` |
| `if/then/else/endif` | Conditional | `if age >= 65 then... endif` |
| `and` | Both conditions must be true | `age >= 18 and weight > 50` |
| `or` | Either condition can be true | `phone or email` |
| `within` | Time window | `visit within 30 days of baseline` |
| `today()` | Current date | `visit_date <= today()` |
| `allow` | Allow specific missing values | `allow n, m` |

### Special Values

- `n` = Blank value
- `m` = Missing value
- `today()` = Today's date

---

## Common Examples

### ADHD Study

**Age range for rating scale:**
```
between 6 and 18
```

**ADHD total score (0-54):**
```
between 0 and 54
```

**Conditional visit attendance:**
```
if visit == "baseline" then required else if visit == "week4" then allow n endif endif
```

### Cardiovascular Study

**Blood pressure (age-dependent):**
```
if age >= 65 then between 90 and 180 else between 110 and 200 endif
```

**Heart rate:**
```
between 30 and 200
```

**Weight consistency across visits:**
```
weight within 10% of previous_visit_weight
```

### Diabetes Study

**A1C test result:**
```
between 4 and 14
```

**Glucose fasting (before treatment):**
```
if medication_status == "none" then between 70 and 200 endif
```

**Medication adherence:**
```
if medication == "yes" then compliance_percent between 50 and 100 endif
```

### Multi-Site Trial

**Visit date window:**
```
within 7 days of scheduled_date
```

**Required visits per protocol:**
```
if visit in(baseline, week4, week8) then visit_date required endif
```

**Site activation check:**
```
if site_status == "active" then enrollment_date <= today() endif
```

---

## Troubleshooting

### Error: "Field contains invalid character"

**Problem:** You may have used a character that's not allowed in values
**Solution:** For text values, use simple alphanumeric. Avoid special characters like `@`, `#`, `$`

### Validation works in form, but doesn't appear in QC report

**Problem:** Rule might be set as "real-time" when it should be "batch"
**Solution:** Use keywords like `cross_visit`, `by visit`, `{visit='baseline'}` to mark as batch

### "Unexpected operator" error

**Problem:** Misspelled operator or using wrong syntax
**Solution:** Check syntax reference - operators are case-sensitive

### Too many violations flagged

**Problem:** Tolerance level might be too strict
**Solution:** For `within` clauses, increase the day tolerance (e.g., `within 30 days` instead of `within 7 days`)

---

## Best Practices

### 1. Start Simple

Begin with straightforward range checks before adding complex logic:

```
# Good - start with this
between 40 and 200

# Good - add complexity later
if age >= 65 then between 90 and 180 else between 110 and 200 endif
```

### 2. Use Clear Field Names

When writing cross-field validations, use descriptive field names:

```
# Good
visit_date > enrollment_date

# Avoid
d1 > d2
```

### 3. Document Your Intentions

When creating complex rules, add a comment explaining why:

```
# Ensures patient is 18+ for consent
age >= 18

# Within standard clinical range for hypertensive patients
if diagnosis == "hypertension" then between 140 and 200 endif
```

### 4. Test with Example Data

Before deploying, test rules with sample data:

- **Boundary values:** Test minimum, maximum, and out-of-range values
- **Edge cases:** Test with missing values, special characters
- **Cross-field:** Test different combinations of related fields

### 5. Plan for Change

Medical protocols change. Make rules maintainable:

```
# Better - easy to update the range
between 40 and 200

# Harder to maintain - magic numbers everywhere
if source == "home" then between 40 and 220 elif source == "clinic" then between 35 and 200 endif
```

### 6. Use Appropriate Tolerance

For date windows and percentage tolerances:

- **Medication adherence:** ±5-10% tolerance
- **Weight changes:** 5-10% tolerance (normal weight fluctuation)
- **Visit windows:** ±3-7 days for weekly visits, ±5-14 days for monthly visits

### 7. Coordinate with Data Manager

Batch QC rules impact your data quality workflow:

- Weekly reviews of violations
- Clear false positive marking process
- Regular rule refinement based on legitimate protocol deviations

---

## Advanced Topics

### Context-Specific Rules

Different rules for different visit contexts:

```
if visit == "baseline" then required
else if visit == "end_of_study" then required
else allow n endif
```

### Multi-Field Validation

Validate based on multiple field combinations:

```
if medication == "yes" and dose_unit == "mg" then dose between 1 and 500 endif
```

### Temporal Patterns

Track values across time:

```
# Flag if weight gain > 5% in a single week
weight_gain > 5%
```

### Statistical Validation

Use population statistics in batch rules:

```
# Flag if hemoglobin is >3 SD from population mean
hemoglobin > population_mean + 3*sd
```

---

## API Reference

### For System Administrators

Rules are stored in the `edc_fields` table with these columns:

- `field`: Field name
- `validation_rule`: DSL rule text
- `context`: "real-time" or "batch"
- `severity`: "error" or "warning"

### Loading Custom Rules

```r
# Rules are loaded automatically at app startup
# To reload: Update database and restart app
```

### Accessing Violations

Violations are logged in `qc_violations` table:

- `subject_id`: Patient identifier
- `field`: Field that failed validation
- `violation_type`: Type of violation
- `detected_date`: When violation was detected
- `resolved`: Whether it's been addressed

---

## Support and Feedback

For questions or to report issues with the validation system:

1. Check this guide and Troubleshooting section
2. Contact your Data Manager or Study Coordinator
3. For system issues, contact the IT support team

---

## Version History

- **v1.1** (December 2024) - Initial release with DSL syntax
- **v1.0** (November 2024) - Foundation and clinical validator utilities

---

## License and Attribution

ZZedc Validation DSL is part of the ZZedc Electronic Data Capture system, built with R and Shiny for clinical research.
