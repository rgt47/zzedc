# ZZedc Validation System (Complete Implementation)

Comprehensive validation framework for clinical trial data with both real-time field validation and nightly batch QC checks.

## System Overview

The ZZedc Validation System provides clinical research teams with powerful, user-friendly validation rules that don't require programming knowledge.

```
User Enters Data
    ↓
Real-Time Validation (< 5ms per field)
    ├─ Parse DSL rule
    ├─ Execute validator function
    ├─ Display error if invalid
    └─ Block save if validation fails
    ↓
Data Saved to Database
    ↓
Nightly Batch QC (automated)
    ├─ Load all QC rules
    ├─ Generate and execute SQL queries
    ├─ Log violations to qc_violations table
    ├─ Send alerts to data managers
    └─ Generate QC reports
```

## Core Components

### 1. Domain-Specific Language (DSL) Parser
**Files:** `R/validation_dsl_parser.R`
- Tokenizes DSL syntax into tokens
- Parses tokens into Abstract Syntax Tree (AST)
- Validates rule syntax before compilation
- **Supports:** Operators, conditionals, functions, cross-field references

### 2. R Code Generator (Real-Time Validation)
**Files:** `R/validation_dsl_codegen.R`
- Converts parsed AST to executable R functions
- Generates safe validators (no eval() calls)
- Pre-compiles closures for performance
- **Performance:** < 5ms per field validation

### 3. Clinical Validators (Trial-Specific Utilities)
**Files:** `R/clinical_validators.R`
- Date arithmetic (add_days, add_weeks, add_months)
- Visit utilities (visit_number, visit_timing, visit_in_list)
- Score calculations (ADHD, CDR, etc.)
- Missing data pattern detection

### 4. Validation Cache (Shiny Integration)
**Files:** `R/validation_cache.R`
- Pre-compiles validators at app startup
- Stores validators in global cache environment
- Provides form-level validation
- **Performance:** O(1) lookup, no re-compilation

### 5. SQL Code Generator (Batch Validation)
**Files:** `R/validation_dsl_sql_codegen.R`
- Converts DSL AST to SQL queries
- Generates cross-visit consistency checks
- Supports statistical analysis (outlier detection)
- Includes index recommendations

### 6. QC Engine (Batch Execution)
**Files:** `R/validation_qc_engine.R`
- Executes all active QC rules
- Logs violations to database
- Generates QC summary statistics
- Supports violation resolution workflow

## Features

### Real-Time Validation (Field-Level)

✅ Range validation (`between 40 and 200`)
✅ Comparison operators (`age >= 18`)
✅ List validation (`in(yes, no, unknown)`)
✅ Required fields (`required`)
✅ Cross-field validation (`visit_date > baseline_date`)
✅ Conditional logic (`if age >= 65 then ... endif`)
✅ Date arithmetic (`within 30 days of baseline_date`)
✅ Text patterns (`length > 3`)
✅ Function calls (`today()`, `length()`)
✅ Logical operators (`and`, `or`, `not`)

### Batch QC Validation (Nightly Checks)

✅ Cross-visit consistency (`weight within 10% of baseline`)
✅ Statistical outlier detection (`value > mean + 3*sd`)
✅ Missing data patterns (`visit_date required for all patients`)
✅ Protocol deviations (`visit_date within window by visit`)
✅ Longitudinal trends (`weight change tracking`)
✅ SQL optimization with index recommendations
✅ Violation tracking and resolution
✅ QC run history and performance monitoring

## Installation & Setup

### Quick Start

```r
# 1. Validation cache initializes automatically on app start
source("R/validation_cache.R")
setup_global_validation_cache()

# 2. Validators load from database
con <- RSQLite::dbConnect(RSQLite::SQLite(), "data/zzedc.db")
load_validation_rules_from_db(con)

# 3. Start using validators
result <- validate_form(form_data)
if (!result$valid) {
  # Show errors to user
}
```

### Database Schema

Required tables:

```sql
-- Field-level validation rules
ALTER TABLE edc_fields ADD COLUMN validation_rule TEXT;

-- QC rule definitions
CREATE TABLE qc_rules (
  rule_id INTEGER PRIMARY KEY,
  rule_name TEXT NOT NULL,
  context TEXT,              -- 'real-time' or 'batch'
  dsl_rule TEXT NOT NULL,
  compiled_sql TEXT,         -- For batch rules
  severity TEXT,             -- 'error' or 'warning'
  active BOOLEAN DEFAULT 1
);

-- QC violation tracking
CREATE TABLE qc_violations (
  violation_id INTEGER PRIMARY KEY,
  rule_id INTEGER REFERENCES qc_rules(rule_id),
  subject_id TEXT,
  field TEXT,
  current_value TEXT,
  violation_type TEXT,
  severity TEXT,
  detected_date TEXT,
  resolved BOOLEAN DEFAULT 0
);

-- QC run history
CREATE TABLE qc_run_history (
  run_id INTEGER PRIMARY KEY,
  run_date TEXT,
  rules_executed INTEGER,
  violations_found INTEGER,
  execution_time_ms INTEGER,
  status TEXT
);
```

## Usage Examples

### Example 1: ADHD Study Age Validation

**Real-time rule:**
```
between 6 and 18
```

**Set in database:**
```r
RSQLite::dbExecute(con,
  "UPDATE edc_fields SET validation_rule = ?
   WHERE field = 'age' AND form_name = 'adhd_baseline'",
  params = list("between 6 and 18")
)
```

**In Shiny form:**
User enters age = 25 → DSL validator runs → Error shown: "Age must be between 6 and 18" → Save blocked

### Example 2: Blood Pressure with Age-Based Ranges

**Real-time rule:**
```
if age >= 65 then between 90 and 180 else between 110 and 200 endif
```

**Cross-field validation:**
- Accesses both `age` and `blood_pressure` from same form
- Returns TRUE or error message
- Data validated in real-time during entry

### Example 3: Nightly Visit Consistency Check

**Batch rule:**
```
weight within 10% of baseline_weight
```

**Automatic execution:**
- Runs every night at 2:00 AM
- Generates SQL: Check each patient's weight change
- Flags patients with >10% change since baseline
- Data manager reviews violations next morning

### Example 4: Missing Data Detection

**Batch rule:**
```
if visit in(baseline, week4, week8) then visit_date required
```

**Effect:**
- Flags all patients missing dates for required visits
- Helps ensure complete data collection
- Identifies enrollment gaps

## API Reference

### Validation Cache Functions

```r
# Initialize cache
setup_global_validation_cache()
get_validation_cache()

# Load rules from database
load_validation_rules_from_db(con)

# Check field has rule
has_validation_rule("field_name")

# Get validator for field
validator_fn <- get_field_validator("field_name")

# Validate single field
result <- validate_field("field_name", value, form_values)

# Validate entire form
result <- validate_form(list(field1=val1, field2=val2))

# Cache management
clear_validation_cache()
refresh_validation_cache(con)
get_cache_stats()
```

### QC Engine Functions

```r
# Execute single QC rule
violations <- execute_qc_query(sql_query, con, rule_id, rule_name)

# Execute all active rules
summary <- execute_all_qc_rules(con)

# Get violations
get_rule_violations(rule_id, con)
get_subject_violations(subject_id, con)
get_violations_by_severity("error", con)

# Resolution
resolve_violation(violation_id, con, notes, user_id)
mark_false_positive(violation_id, con)
bulk_resolve_violations(violation_ids, con)

# History
get_qc_summary(con)
get_recent_qc_runs(con, limit=10)
log_qc_run(con, rules_executed, violations_found, time_ms, status)
```

### SQL Code Generation

```r
# Generate SQL from DSL rule
compile_batch_rule(rule_text, field_name, table_name, parser)

# Specialized queries
generate_cross_visit_query(field_name, visit_comparisons, tolerance)
generate_outlier_detection_query(field_name, num_std_dev)
generate_missing_data_query(required_field, required_visits)

# Get optimization recommendations
recommend_indexes(sql_query, table_name)
```

## Performance Benchmarks

| Operation | Time | Notes |
|-----------|------|-------|
| Parse DSL rule | ~10ms | One-time at app startup |
| Execute validator | <5ms | Pre-compiled closure, O(1) lookup |
| Form validation | <50ms | For 10-field form with validation rules |
| Execute single QC rule | ~100-500ms | Depends on dataset size |
| Execute all QC rules | ~5-60 seconds | Batch operation on 10K+ records |
| Cache lookup | <1ms | Environment hash lookup |

## Testing

Comprehensive test suite included:

```bash
# Run all validation tests
R -e "devtools::test(filter='validation', reporter='summary')"

# Run specific test suite
R -e "devtools::test(filter='validation-dsl', reporter='summary')"
R -e "devtools::test(filter='validation-cache', reporter='summary')"
R -e "devtools::test(filter='validation-sql-codegen', reporter='summary')"
```

**Test Coverage:**
- Phase 1: DSL Parser (50+ tests)
- Phase 2: Cross-field & Conditional Logic (30+ tests)
- Phase 3: Clinical Features (40+ tests)
- Phase 4: Validation Cache (43+ tests)
- Phase 5: SQL Code Generation (55+ tests)
- **Total: 218+ tests, all passing**

## Documentation

- **[Validation DSL User Guide](./VALIDATION_DSL_GUIDE.md)** - Complete syntax reference and examples
- **Source Code:** Inline documentation in R files
- **Tests:** Examples in testthat test files

## Architecture Decisions

### Why No `eval()`?

The validation system is deliberately built without `eval()` for:
- **Security:** No code injection vulnerabilities
- **Performance:** Pre-compiled functions (no parsing at runtime)
- **Maintainability:** Clear function generation, easy to debug
- **Compliance:** Audit trail of all validation logic

### DSL vs SQL

- **DSL (user-friendly):** Non-programmers write validation rules
- **R (real-time):** Fast execution during data entry
- **SQL (batch):** Optimized for large dataset analysis

### Two-Phase Validation

- **Phase 1 (Real-time):** Immediate feedback during entry
- **Phase 2 (Batch):** Deep analysis across entire dataset
- **Combined effect:** Prevents errors + catches patterns

## Future Enhancements

- **Visual rule builder:** Drag-and-drop rule creation UI
- **Rule library:** Pre-built rules for common assessments
- **Client-side validation:** Generate JavaScript for instant feedback
- **Machine learning:** Suggest rules based on data patterns
- **Cross-study sharing:** Export/import rule libraries

## Troubleshooting

### Validators not loading at startup

```r
# Check cache status
get_cache_stats()

# Manually reload
con <- RSQLite::dbConnect(RSQLite::SQLite(), "data/zzedc.db")
load_validation_rules_from_db(con)
```

### Validation rule syntax errors

See [Validation DSL User Guide](./VALIDATION_DSL_GUIDE.md#troubleshooting) for common issues.

### QC rules not executing

1. Check rules are marked `active = 1` in database
2. Verify SQL syntax with `compile_batch_rule()`
3. Check database has required tables
4. Review `qc_run_history` for error messages

## Project Statistics

- **Lines of code:** ~4,500 (excluding tests)
- **Test lines:** ~2,000
- **Documentation:** ~1,500 lines
- **Test coverage:** 218+ tests across all phases
- **Performance:** Sub-5ms field validation
- **Clinical examples:** 20+ real-world rules

## License

Part of ZZedc - Electronic Data Capture for Clinical Research

---

**Questions?** See the [Validation DSL User Guide](./VALIDATION_DSL_GUIDE.md) or contact your system administrator.
