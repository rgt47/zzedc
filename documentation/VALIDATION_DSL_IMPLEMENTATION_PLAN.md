# ZZedc Validation DSL Implementation Plan

## Executive Summary

Build a domain-specific language (DSL) for clinical trial validation rules that allows non-programmers to define complex validation logic. This positions ZZedc as a competitive alternative to REDCap's data dictionary approach while maintaining superior security and performance.

**Key Decisions:**
- **Dual-context DSL** - Single DSL syntax compiles to both R (real-time) and SQL (batch validation)
- **Two validation modes**:
  - Real-time: Field-level checks during data entry (R execution in Shiny)
  - Batch: Nightly QC checks across full dataset (SQL queries for performance)
- **DSL-only approach** - No backward compatibility needed since validation snippets aren't currently executed
- **Extended 12-week implementation** - Real-time validation + batch QC system + comprehensive testing
- **Target: General EDC improvement** - Make ZZedc competitive with commercial EDC systems

---

## Current State Analysis

### What Exists
- **Data dictionary structure**: CSV/Google Sheets with `valid` column for validation expressions
- **Branching logic system**: 383 lines in `/R/branching_logic.R` that safely parses and evaluates conditional expressions
- **Type validation**: Basic field-level validation in `/R/validation_utils.R`
- **Security posture**: No eval() anywhere - uses switch-based parsing (excellent)

### What's Missing
- **Validation execution**: The `valid` column expressions are stored but never executed
- **Complex rule support**: No cross-field validation, date arithmetic, or clinical trial-specific patterns
- **User-friendly syntax**: Current R expressions too technical for clinical staff

### Critical Files
- `/Users/zenn/Dropbox/prj/d06/zzedc/R/branching_logic.R` - Template for safe expression parsing
- `/Users/zenn/Dropbox/prj/d06/zzedc/R/validation_utils.R` - Validation framework
- `/Users/zenn/Dropbox/prj/d06/zzedc/gsheets_dd_builder.R` - Data dictionary loading
- `/Users/zenn/Dropbox/prj/d06/zzedc/adhd_trial_csv_files/form_*.csv` - Current validation examples

---

## DSL Design

### Syntax Design (Dual Context Support)

The DSL supports both **real-time** (field-level) and **batch** (dataset-wide) validation with consistent syntax:

#### Real-time Validation (Single Record Context)
```
# Range validation
between 40 and 200
in(1,2,3,n,m)
1..100

# Conditional logic
if age >= 65 then between 90 and 180 else between 110 and 200 endif

# Cross-field validation (same form)
visit_date > enrollment_date
if medication == 'yes' then dose required endif

# Date arithmetic
within 30 days of enrollment_date
visit_date between enrollment_date and enrollment_date + 90

# Special values
allow n,m              # n=blank, m=missing
required unless status == 'exempt'

# Clinical patterns
if visit == 'baseline' then required endif
if adverse_event == 'serious' then hospitalization required endif
```

#### Batch Validation (Cross-Visit, Cross-Patient)
```
# Cross-visit consistency (same patient, different visits)
context: batch
scope: cross_visit
rule: if visit == 'v2' then weight within 10% of {visit='v1'}.weight
compiles_to: SQL with self-join on subject_id

# Cross-patient statistical checks
context: batch
scope: cross_patient
rule: flag if value > mean + 3*sd
compiles_to: SQL with window functions

# Missing data patterns
context: batch
scope: dataset
rule: if visit in('v1','v2','v3') then visit_date required for each patient
compiles_to: SQL checking for NULL values across all expected visits

# Protocol deviations
context: batch
scope: cross_visit
rule: visit_date within screening_date + [30,90] days by visit
compiles_to: SQL with date arithmetic

# Longitudinal trends
context: batch
scope: cross_visit
rule: flag if weight change > 20% between consecutive visits
compiles_to: SQL with LAG() window function
```

### Operator Support (Priority Order)

**Phase 1 - Essential (MVP):**
- Comparison: `<`, `<=`, `>`, `>=`, `==`, `!=`
- Range: `between X and Y`, `in(A,B,C)`, `X..Y`
- Logical: `and`, `or`, `not`
- Special: `required`, `allow n,m`

**Phase 2 - Clinical:**
- Cross-field: Reference other field values
- Date arithmetic: `+ N days`, `- N weeks`, `within N days of`
- Conditionals: `if...then...else...endif`

**Phase 3 - Advanced:**
- Functions: `length()`, `abs()`, `round()`, custom validators
- Pattern matching: `matches pattern`
- SQL queries: `exists in table{}`

---

## Architecture Design

### Dual-Context Component Structure

```
┌─────────────────────────────────────────────────────────────────┐
│  User Input (Google Sheets / CSV)                              │
│  valid: "between 40 and 200"          (real-time)              │
│  qc_rule: "weight within 10% of {v1}" (batch)                  │
└────────────────┬────────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────┐
│  DSL Parser (R/validation_dsl_parser.R)                         │
│  - Tokenizer: Parse DSL syntax → tokens                        │
│  - Parser: tokens → AST (Abstract Syntax Tree)                 │
│  - Context detector: Real-time vs Batch validation             │
│  - Validator: Check syntax errors before code generation       │
└────────────────┬────────────────────────────────────────────────┘
                 │
                 ├────────────────────┬────────────────────────────┐
                 ▼                    ▼                            ▼
┌─────────────────────────┐  ┌──────────────────────┐  ┌─────────────────────┐
│ R Code Generator        │  │ SQL Code Generator   │  │ Context Router      │
│ (realtime validation)   │  │ (batch validation)   │  │ Determines target   │
│                         │  │                      │  │ based on context    │
│ - AST → R function      │  │ - AST → SQL query    │  └─────────────────────┘
│ - NO eval()             │  │ - Optimized joins    │
│ - Whitelisted functions │  │ - Window functions   │
│ - Closures              │  │ - Statistical queries│
└───────┬─────────────────┘  └──────┬───────────────┘
        │                           │
        ▼                           ▼
┌─────────────────────────┐  ┌──────────────────────┐
│ Real-time Cache         │  │ Batch QC Engine      │
│ (validation_cache.R)    │  │ (validation_qc.R)    │
│                         │  │                      │
│ - Pre-compiled R funcs  │  │ - Compiled SQL       │
│ - Environment storage   │  │ - Scheduled runs     │
│ - Invalidation          │  │ - Violation tracking │
└───────┬─────────────────┘  └──────┬───────────────┘
        │                           │
        ▼                           ▼
┌─────────────────────────┐  ┌──────────────────────┐
│ Runtime Executor        │  │ QC Scheduler         │
│ (validation_executor.R) │  │ (validation_qc_      │
│                         │  │  scheduler.R)        │
│ - Execute on field      │  │                      │
│   change                │  │ - Nightly cron       │
│ - Return TRUE/error     │  │ - Generate reports   │
└───────┬─────────────────┘  │ - Email alerts       │
        │                    └──────┬───────────────┘
        ▼                           ▼
┌─────────────────────────┐  ┌──────────────────────────────┐
│ Shiny Real-time UI      │  │ QC Violations Table          │
│ (gsheets_server_        │  │ (Database: qc_violations)    │
│  integration.R)         │  │                              │
│                         │  │ - subject_id, field, visit   │
│ - observeEvent triggers │  │ - violation_type, severity   │
│ - Display errors        │  │ - detected_date, resolved    │
└─────────────────────────┘  └──────┬───────────────────────┘
                                    ▼
                             ┌──────────────────────────────┐
                             │ Data Quality Dashboard UI    │
                             │ (New tab in ZZedc)           │
                             │                              │
                             │ - View violations by site    │
                             │ - Filter by severity         │
                             │ - Mark as resolved           │
                             │ - Export QC reports          │
                             └──────────────────────────────┘
```

### Security Model

**Critical: NO eval() approach**

Instead of:
```r
# DANGEROUS - Never do this
rule <- "x >= 40 && x <= 200"
result <- eval(parse(text = rule))
```

Use safe function generation:
```r
# SAFE - Pre-compiled closure
validators <- list()
validators$blood_pressure <- function(x, form_values) {
  x >= 40 && x <= 200
}

# Execute pre-compiled function
result <- validators$blood_pressure(input$blood_pressure, all_values)
```

**Whitelist Approach:**
```r
# Only these functions allowed in validation rules
allowed_functions <- list(
  "between" = function(x, min, max) x >= min && x <= max,
  "in_list" = function(x, ...) x %in% c(...),
  "length" = function(x) nchar(as.character(x)),
  "is_blank" = function(x) is.na(x) || x == "",
  "date_diff" = function(d1, d2) as.numeric(difftime(d1, d2, units="days"))
)
```

---

## Implementation Roadmap

### Phase 1: Foundation (Week 1-2)

**Goal:** Basic DSL parser and code generator for simple rules

**Files to Create:**
1. `/R/validation_dsl_parser.R` - Tokenizer and parser
2. `/R/validation_dsl_codegen.R` - Code generator
3. `/R/validation_executor.R` - Runtime executor
4. `/tests/testthat/test-validation-dsl.R` - Comprehensive tests

**Deliverables:**
- Parse simple operators: `<`, `>`, `==`, `between...and`
- Generate safe R functions (no eval)
- Test suite with 50+ test cases
- Documentation of supported syntax

**Example Rules Supported:**
```
x >= 18
between 40 and 200
in(1,2,3)
x == 'yes'
```

### Phase 2: Cross-Field & Logic (Week 3-4)

**Goal:** Support cross-field validation and conditional logic

**Files to Modify:**
1. `/R/validation_dsl_parser.R` - Add if/then/else, AND/OR
2. `/R/validation_dsl_codegen.R` - Cross-field reference handling
3. `/R/validation_executor.R` - Pass all form values to validators

**Deliverables:**
- Cross-field validation: `visit_date > enrollment_date`
- Conditional logic: `if age >= 65 then ... else ... endif`
- Logical operators: `and`, `or`, `not`
- Special values: `n` (blank), `m` (missing)

**Example Rules Supported:**
```
if age >= 65 then between 90 and 180 else between 110 and 200 endif
visit_date > enrollment_date
if medication == 'yes' then dose required endif
allow n,m
```

### Phase 3: Clinical Trial Features (Week 5-6)

**Goal:** Date arithmetic and clinical trial-specific patterns

**Files to Modify:**
1. `/R/validation_dsl_parser.R` - Date arithmetic syntax
2. `/R/validation_dsl_codegen.R` - Date functions
3. `/R/clinical_validators.R` - NEW: Clinical trial helper functions

**Deliverables:**
- Date arithmetic: `+ 30 days`, `within N days of`
- Visit-based logic: `if visit == 'baseline' then ...`
- Custom clinical functions: `cdr_score()`, `adas_total()`
- Missing data patterns: `required unless ...`

**Example Rules Supported:**
```
visit_date within 30 days of enrollment_date
if visit in('baseline','screening') then allow n endif
if adverse_event == 'serious' then hospitalization required endif
date between enrollment_date and enrollment_date + 90
```

### Phase 4: Integration & Optimization (Week 7-8)

**Goal:** Integrate with ZZedc and optimize performance

**Files to Modify:**
1. `/gsheets_dd_builder.R` - Pre-compile validation functions on load
2. `/gsheets_server_integration.R` - Hook validation into observeEvent
3. `/R/validation_cache.R` - NEW: Caching layer
4. `/gsheets_form_loader.R` - Display validation errors

**Deliverables:**
- Validation cache for pre-compiled functions
- Integration with existing form rendering
- Client-side validation generation (optional)
- Performance benchmarks: < 5ms per validation
- Error message display in UI

### Phase 5: Batch Validation & QC System (Week 9-10)

**Goal:** Nightly data quality checks with cross-visit and cross-patient validation

**Files to Create:**
1. `/R/validation_dsl_sql_codegen.R` - SQL code generator from AST
2. `/R/validation_qc_engine.R` - QC query executor and scheduler
3. `/R/validation_qc_scheduler.R` - Nightly batch job orchestration
4. `/R/qc_dashboard_module.R` - Data Quality UI tab

**Files to Modify:**
1. `/R/validation_dsl_parser.R` - Add batch context detection
2. `/gsheets_dd_builder.R` - Load QC rules from data dictionary
3. Database schema - Add `qc_rules` and `qc_violations` tables

**Deliverables:**
- SQL code generation for batch rules
- Cross-visit validation (e.g., weight consistency)
- Cross-patient statistical checks (outlier detection)
- QC violations database table
- Scheduled nightly QC runs
- Data Quality dashboard UI tab

**Example Batch Rules Supported:**
```
# Cross-visit
if visit == 'v2' then weight within 10% of {visit='v1'}.weight

# Statistical outliers
flag if value > mean + 3*sd

# Missing data patterns
if visit in('v1','v2','v3') then visit_date required for each patient

# Protocol deviations
visit_date within screening_date + [30,90] days by visit
```

### Phase 6: Documentation & Testing (Week 11-12)

**Goal:** Production-ready with comprehensive documentation for both real-time and batch validation

**Files to Create:**
1. `/vignettes/validation-dsl-guide.Rmd` - User guide for clinical staff
2. `/vignettes/batch-qc-guide.Rmd` - Guide for data managers on QC reports
3. `/documentation/VALIDATION_DSL_REFERENCE.md` - Complete syntax reference
4. `/templates/validation_rules_template.csv` - Example templates

**Deliverables:**
- User guide with 30+ examples (real-time + batch)
- Data Quality dashboard user guide
- Syntax reference for both contexts
- Migration guide from R expressions to DSL
- Training materials for non-programmers
- 300+ test cases covering all syntax and both contexts
- Performance benchmarks for batch QC on large datasets

---

## Technical Specifications

### Parser Implementation

**Option A: Recursive Descent Parser (Recommended)**
- Hand-written, easy to understand
- Full control over error messages
- No external dependencies
- Reference: `/R/branching_logic.R` already does this

**Option B: Parser Generator (PEG)**
- Use R package like `parsertools` or `pegr`
- Formal grammar definition
- More complex but powerful

**Recommendation:** Start with Option A (recursive descent), migrate to Option B if complexity grows.

### Grammar Definition (EBNF-like)

```
rule          ::= expression
expression    ::= condition (logical_op condition)*
condition     ::= comparison | special_check | function_call
comparison    ::= field operator value
                | field "between" value "and" value
                | field "in" "(" value_list ")"
operator      ::= "<" | "<=" | ">" | ">=" | "==" | "!="
logical_op    ::= "and" | "or"
special_check ::= "required" | "allow" value_list
function_call ::= identifier "(" arg_list ")"
if_expr       ::= "if" expression "then" expression ("else" expression)? "endif"
```

### Code Generation Strategy

```r
# AST Node types
ast_node <- function(type, ...) {
  list(type = type, ...)
}

# Example AST for "between 40 and 200"
ast <- ast_node(
  type = "between",
  field = "x",
  min = 40,
  max = 200
)

# Generate R function
codegen <- function(ast) {
  switch(ast$type,
    "between" = function(x, form_values) {
      x >= ast$min && x <= ast$max
    },
    "comparison" = function(x, form_values) {
      op <- get(ast$operator)
      op(x, ast$value)
    },
    # ... more cases
  )
}
```

### Performance Targets

- **Parsing time**: < 10ms per rule (one-time at startup)
- **Execution time**: < 5ms per validation (on field change)
- **Memory overhead**: < 100KB for 1000 validation rules
- **Compilation**: All rules pre-compiled at app startup

---

## Testing Strategy

### Unit Tests (testthat)

**Parser Tests:**
```r
test_that("Parser handles range syntax", {
  result <- parse_dsl_rule("between 40 and 200")
  expect_equal(result$type, "between")
  expect_equal(result$min, 40)
  expect_equal(result$max, 200)
})
```

**Code Generator Tests:**
```r
test_that("Codegen produces correct function", {
  ast <- parse_dsl_rule("x >= 18")
  fn <- generate_validator(ast)
  expect_true(fn(20, list()))
  expect_false(fn(15, list()))
})
```

**Integration Tests:**
```r
test_that("End-to-end validation works", {
  rule <- "if age >= 65 then between 90 and 180 else between 110 and 200 endif"
  validator <- compile_validation_rule(rule, field = "blood_pressure")

  # Test senior patient
  result1 <- validator(150, list(age = 70))
  expect_true(result1)

  # Test young patient
  result2 <- validator(150, list(age = 30))
  expect_true(result2)

  # Test out of range
  result3 <- validator(80, list(age = 70))
  expect_match(result3, "out of range")
})
```

### Clinical Trial Test Cases

```r
# Test real-world clinical trial rules
test_that("ADHD trial validation rules work", {
  # Rule: ADHD score 0-54
  # Rule: Visit date within 30 days of baseline
  # Rule: If serious AE, hospitalization required
  # ... 50+ real-world cases
})
```

---

## Implementation Strategy

### Fresh Start Approach

Since the `valid` column expressions are stored but never executed in the current ZZedc implementation, we can implement DSL-only validation without breaking changes.

**Advantages:**
- Clean implementation - no legacy code paths
- Simpler codebase - single validation approach
- Better security - no temptation to use eval() for edge cases
- Clearer documentation - one way to write validation rules

**Data Dictionary Update:**
All example CSV files in `adhd_trial_csv_files/` will be updated to use DSL syntax instead of R expressions. This serves as:
1. Documentation by example
2. Test data for validation system
3. Templates for new studies

---

## Risk Mitigation

### Risk: Syntax too limiting
**Mitigation:** Start with common 80% cases, extend as needed. Allow fallback to R for edge cases.

### Risk: Performance regression
**Mitigation:** Comprehensive benchmarks, caching, pre-compilation.

### Risk: Users expect R expression support
**Mitigation:** Clear documentation that DSL is the validation language. Provide comprehensive examples and migration guide for any existing R expressions users may have written.

### Risk: Security vulnerabilities
**Mitigation:** No eval(), whitelist functions, fuzz testing, security audit.

### Risk: Non-technical users struggle
**Mitigation:** Extensive examples, visual rule builder (future), training materials.

---

## Success Metrics

### Real-time Validation
1. **Competitiveness**: Feature parity with REDCap's validation capabilities
2. **Performance**: < 5ms validation execution time (95th percentile)
3. **Usability**: Clinical staff can write rules without R training (user testing with 5+ non-programmers)
4. **Coverage**: DSL supports 90% of field-level clinical trial validation patterns

### Batch QC System
5. **Performance**: Nightly QC completes in < 5 minutes for 10,000 patient records
6. **Coverage**: Supports cross-visit, cross-patient, and statistical validation patterns
7. **Actionability**: Data managers can identify and resolve violations within QC dashboard
8. **Automation**: Zero manual intervention for scheduled QC runs

### Overall System
9. **Reliability**: Zero security vulnerabilities, < 1% rule syntax errors in production use
10. **Documentation**: 30+ real-world examples (20 real-time, 10 batch) covering common clinical scenarios
11. **SQL Efficiency**: Batch queries use proper indexes and complete in < 1 second for 95% of rules

---

## Future Enhancements (Beyond Initial Release)

1. **Visual Rule Builder**: Drag-and-drop UI for building validation rules
2. **Rule Library**: Pre-built rules for common clinical assessments (ADAS, CDR, MMSE)
3. **Client-Side Validation**: Generate JavaScript for instant feedback
4. **Machine Learning**: Suggest validation rules based on data patterns
5. **Cross-Study Sharing**: Export/import rule libraries between studies

---

## Files to Create/Modify

### New Files (Real-time Validation)
- `/R/validation_dsl_parser.R` (400-600 lines) - Enhanced with context detection
- `/R/validation_dsl_codegen_r.R` (250-350 lines) - R code generation
- `/R/validation_executor.R` (150-200 lines)
- `/R/validation_cache.R` (100-150 lines)
- `/R/clinical_validators.R` (200-300 lines)

### New Files (Batch Validation)
- `/R/validation_dsl_codegen_sql.R` (400-500 lines) - SQL code generation
- `/R/validation_qc_engine.R` (300-400 lines) - QC query executor
- `/R/validation_qc_scheduler.R` (200-250 lines) - Batch job scheduler
- `/R/qc_dashboard_module.R` (300-400 lines) - Data Quality UI tab
- `/R/qc_report_generator.R` (200-250 lines) - PDF/HTML QC reports

### New Files (Testing & Documentation)
- `/tests/testthat/test-validation-dsl.R` (600+ lines)
- `/tests/testthat/test-validation-sql-codegen.R` (400+ lines)
- `/tests/testthat/test-qc-engine.R` (300+ lines)
- `/vignettes/validation-dsl-guide.Rmd` (documentation)
- `/vignettes/batch-qc-guide.Rmd` (QC system guide)
- `/documentation/VALIDATION_DSL_REFERENCE.md` (reference)

### Modified Files
- `/gsheets_dd_builder.R` (add QC rules loading, pre-compilation)
- `/gsheets_server_integration.R` (hook validation into observeEvent)
- `/gsheets_form_loader.R` (display validation errors)
- `/R/validation_utils.R` (integrate with DSL executor)
- `/ui.R` (add Data Quality tab)
- `/server.R` (add QC dashboard server logic)
- Database schema files (add qc_rules, qc_violations, qc_run_history tables)

### Database Schema Extensions

```sql
-- QC rules table (batch validation definitions)
CREATE TABLE qc_rules (
  rule_id INTEGER PRIMARY KEY,
  rule_name TEXT NOT NULL,
  rule_description TEXT,
  context TEXT CHECK(context IN ('real-time', 'batch')),
  scope TEXT CHECK(scope IN ('field', 'cross_field', 'cross_visit', 'cross_patient', 'dataset')),
  dsl_rule TEXT NOT NULL,
  compiled_sql TEXT,  -- NULL for real-time rules
  severity TEXT CHECK(severity IN ('error', 'warning', 'info')),
  active BOOLEAN DEFAULT 1,
  schedule TEXT,  -- cron expression for batch rules
  created_date TEXT,
  created_by TEXT,
  modified_date TEXT,
  modified_by TEXT
);

-- QC violations table (batch validation results)
CREATE TABLE qc_violations (
  violation_id INTEGER PRIMARY KEY,
  rule_id INTEGER REFERENCES qc_rules(rule_id),
  subject_id TEXT,
  visit TEXT,
  field TEXT,
  current_value TEXT,
  expected_value TEXT,
  violation_type TEXT,
  violation_message TEXT,
  severity TEXT,
  detected_date TEXT,
  resolved BOOLEAN DEFAULT 0,
  resolved_date TEXT,
  resolved_by TEXT,
  resolution_notes TEXT,
  false_positive BOOLEAN DEFAULT 0
);

-- QC run history (track batch job executions)
CREATE TABLE qc_run_history (
  run_id INTEGER PRIMARY KEY,
  run_date TEXT,
  rules_executed INTEGER,
  violations_found INTEGER,
  execution_time_ms INTEGER,
  status TEXT CHECK(status IN ('success', 'partial', 'failed')),
  error_message TEXT
);
```

**Total New Code: ~2500-3000 lines**
**Total Modified Code: ~300-400 lines**

---

## Timeline Summary

- **Week 1-2**: Foundation (basic parser & R codegen for real-time)
- **Week 3-4**: Cross-field & logic (real-time context)
- **Week 5-6**: Clinical trial features (dates, special patterns)
- **Week 7-8**: Integration & optimization (Shiny integration, caching)
- **Week 9-10**: Batch validation & QC system (SQL codegen, cross-visit/patient)
- **Week 11-12**: Documentation & comprehensive testing (both contexts)

**Total: 12 weeks to production-ready dual-context DSL**

---

## Recommendation

**Proceed with R-based DSL implementation** using the phased approach above. This maintains ZZedc's excellent security posture, performance, and maintainability while providing non-programmers with a powerful validation language suitable for complex multi-site clinical trials.
