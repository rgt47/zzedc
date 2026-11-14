# Validation DSL Code Generator
#
# Converts parsed DSL rules (AST) into safe, executable R functions.
# Generates closures with pre-compiled validation logic - no eval() calls.

# ============================================================================
# Validation Function Generation
# ============================================================================

#' Generate a validator function from a DSL rule
#'
#' Compiles a parsed validation rule into an R function that can be executed
#' safely without eval(). The generated function returns TRUE if validation passes,
#' or an error message string if validation fails.
#'
#' @param rule Character string containing the DSL validation rule
#' @param field_name Character string with the field name being validated
#'
#' @return Function with signature function(value, form_values) that returns
#'         TRUE on success or error message string on failure
#'
#' @examples
#' \dontrun{
#' # Simple range validation
#' validator <- generate_validator("between 40 and 200", "blood_pressure")
#' result <- validator(150, list())
#'
#' # Comparison validation
#' validator <- generate_validator("x >= 18", "age")
#' result <- validator(25, list())
#' }
#'
#' @keywords internal
#' @export
generate_validator <- function(rule, field_name = NULL) {
  if (!is.character(rule) || length(rule) != 1) {
    stop("Rule must be a single character string")
  }

  # Parse the rule into AST
  ast <- parse_dsl_rule(rule)

  # Generate the validator function
  generate_validator_from_ast(ast, field_name)
}

#' Generate validator from AST
#'
#' The returned closure resolves the target value from
#' `form_values[[field_name]]` when `value` is `NULL`, so a rule with
#' no explicit field (`between 18 and 65`, `length == 7`,
#' `required`) applies to the field it is attached to. Evaluation
#' uses three-valued logic: a comparison with a missing operand is
#' unknown (`NA`), and an unknown top-level result passes, matching
#' SQL `CHECK` semantics. Missing-ness is enforced by `required`
#' rules, not by range or comparison rules.
#' @keywords internal
generate_validator_from_ast <- function(ast, field_name = NULL) {
  function(value = NULL, form_values = list()) {
    if (is.null(value) && !is.null(field_name) && !is.na(field_name)) {
      value <- form_values[[field_name]]
    }
    res <- evaluate_ast_node(ast, value, form_values, field_name)
    if (.dsl_is_unknown(res)) TRUE else res
  }
}

# ============================================================================
# Value helpers (missing-ness, field resolution, type coercion)
# ============================================================================

#' @keywords internal
#' @noRd
.dsl_is_blank <- function(x) {
  if (is.null(x) || length(x) == 0) return(TRUE)
  if (inherits(x, 'Date')) return(all(is.na(x)))
  chr <- as.character(x)
  all(is.na(x) | is.na(chr) | !nzchar(trimws(chr)))
}

#' @keywords internal
#' @noRd
.dsl_is_unknown <- function(x) {
  is.logical(x) && length(x) == 1 && is.na(x)
}

#' Resolve a bare identifier in a rule
#'
#' A name present in `form_values` is that field. `x` and `value`
#' denote the target value; `length` denotes its character length
#' (the data dictionaries write `length == 7`). Any other unknown
#' name is missing (`NA`); it never falls back to the target value,
#' which previously made `dob < consent_date` compare `dob` with
#' itself when `consent_date` was absent.
#' @keywords internal
#' @noRd
.dsl_resolve_field <- function(name, value, form_values) {
  if (length(form_values) > 0 && name %in% names(form_values)) {
    return(form_values[[name]])
  }
  if (name %in% c('x', 'value')) return(value)
  if (name == 'length') {
    return(if (.dsl_is_blank(value)) NA else nchar(as.character(value)[1]))
  }
  if (name %in% c('n', 'm')) return(name)
  NA
}

#' @keywords internal
#' @noRd
.dsl_as_number <- function(x) {
  if (length(x) != 1 || inherits(x, 'Date')) return(NA_real_)
  if (is.numeric(x)) return(as.numeric(x))
  if (!is.character(x) && !is.factor(x)) return(NA_real_)
  suppressWarnings(as.numeric(trimws(as.character(x))))
}

#' @keywords internal
#' @noRd
.dsl_as_date <- function(x) {
  if (length(x) != 1) return(as.Date(NA))
  if (inherits(x, 'Date')) return(x)
  if (inherits(x, 'POSIXt')) return(as.Date(x))
  chr <- trimws(as.character(x))
  if (!grepl('^[0-9]{4}-[0-9]{2}-[0-9]{2}', chr)) return(as.Date(NA))
  tryCatch(as.Date(substr(chr, 1, 10)), error = function(e) as.Date(NA))
}

#' Coerce two operands to a common comparable type
#'
#' Form inputs arrive as character, so `'72' <= 200` must compare
#' numerically, not lexically. Order: dates (if either side is a
#' Date or both are ISO date strings), numbers (if either side is
#' numeric or both parse as numbers), otherwise character. Returns
#' `NULL` when a typed operand meets a value that cannot be coerced
#' to its type (`'abc' between 1 and 10`).
#' @keywords internal
#' @noRd
.dsl_coerce_pair <- function(a, b) {
  a_date <- inherits(a, c('Date', 'POSIXt'))
  b_date <- inherits(b, c('Date', 'POSIXt'))
  da <- .dsl_as_date(a)
  db <- .dsl_as_date(b)
  if (a_date || b_date) {
    if (is.na(da) || is.na(db)) return(NULL)
    return(list(da, db))
  }
  if (!is.na(da) && !is.na(db)) return(list(da, db))
  na <- .dsl_as_number(a)
  nb <- .dsl_as_number(b)
  if (!is.na(na) && !is.na(nb)) return(list(na, nb))
  if (is.numeric(a) || is.numeric(b)) return(NULL)
  list(as.character(a), as.character(b))
}

#' Compare two operands under three-valued logic
#'
#' @return `TRUE`, `FALSE`, `NA` (unknown: an operand is missing in
#'   an ordering comparison), or a character message when the
#'   operands are of incompatible types.
#' @keywords internal
#' @noRd
.dsl_compare <- function(a, b, op) {
  a_blank <- .dsl_is_blank(a)
  b_blank <- .dsl_is_blank(b)
  if (a_blank || b_blank) {
    return(switch(op,
      '==' = a_blank && b_blank,
      '!=' = !(a_blank && b_blank),
      NA
    ))
  }
  if (length(a) != 1 || length(b) != 1) {
    return(sprintf('Cannot compare multi-valued input with %s', op))
  }
  pair <- .dsl_coerce_pair(a, b)
  if (is.null(pair)) {
    return(sprintf("Value '%s' cannot be compared with '%s'",
                   as.character(a), as.character(b)))
  }
  res <- switch(op,
    '<' = pair[[1]] < pair[[2]],
    '<=' = pair[[1]] <= pair[[2]],
    '>' = pair[[1]] > pair[[2]],
    '>=' = pair[[1]] >= pair[[2]],
    '==' = pair[[1]] == pair[[2]],
    '!=' = pair[[1]] != pair[[2]],
    stop(sprintf('Unknown operator: %s', op))
  )
  isTRUE(res)
}

#' Normalize a value for set membership (`in`, `notin`)
#' @keywords internal
#' @noRd
.dsl_norm_member <- function(x) {
  num <- .dsl_as_number(x)
  if (!is.na(num)) as.character(num) else trimws(as.character(x))
}

#' @keywords internal
#' @noRd
.dsl_format <- function(x) {
  if (is.null(x)) return('NULL')
  paste(as.character(x), collapse = ', ')
}

# ============================================================================
# AST Evaluation
# ============================================================================

#' Evaluate an AST node
#' @keywords internal
evaluate_ast_node <- function(node, value, form_values = list(), field_name = NULL) {
  if (!is.list(node) || !"type" %in% names(node)) {
    return(value)
  }

  type <- node$type

  switch(type,
    # Logical operations
    "and" = evaluate_and_node(node, value, form_values, field_name),
    "or" = evaluate_or_node(node, value, form_values, field_name),

    # Comparisons
    "comparison" = evaluate_comparison_node(node, value, form_values, field_name),
    "between" = evaluate_between_node(node, value, form_values, field_name),
    "in" = evaluate_in_node(node, value, form_values, field_name),
    "notin" = evaluate_notin_node(node, value, form_values, field_name),
    "range" = evaluate_range_node(node, value, form_values, field_name),

    # Special values
    "required" = evaluate_required_node(node, value, form_values, field_name),
    "allow" = evaluate_allow_node(node, value, form_values, field_name),

    # Control flow
    "if" = evaluate_if_node(node, value, form_values, field_name),

    # Date/Time operations (Phase 3)
    "date_arithmetic" = evaluate_date_arithmetic_node(node, value, form_values, field_name),
    "within_days" = evaluate_within_days_node(node, value, form_values, field_name),
    "today" = evaluate_today_node(node, value, form_values, field_name),
    "function_call" = evaluate_function_call_node(node, value, form_values, field_name),

    # Base types
    "field_value" = evaluate_field_value_node(node, value, form_values, field_name),
    "literal" = node$value,
    "field" = .dsl_resolve_field(node$name, value, form_values),

    # Default: return value as-is
    value
  )
}

# ============================================================================
# Logical Operations
# ============================================================================

#' Evaluate AND operation (three-valued: failure dominates unknown)
#' @keywords internal
evaluate_and_node <- function(node, value, form_values, field_name) {
  left_result <- evaluate_ast_node(node$left, value, form_values, field_name)
  if (is.character(left_result)) return(left_result)
  right_result <- evaluate_ast_node(node$right, value, form_values, field_name)
  if (is.character(right_result)) return(right_result)

  if (isTRUE(left_result) && isTRUE(right_result)) return(TRUE)
  if (.dsl_is_unknown(left_result) || .dsl_is_unknown(right_result)) {
    if (!isFALSE(left_result) && !isFALSE(right_result)) return(NA)
  }
  "AND condition failed"
}

#' Evaluate OR operation (three-valued: success dominates unknown)
#' @keywords internal
evaluate_or_node <- function(node, value, form_values, field_name) {
  left_result <- evaluate_ast_node(node$left, value, form_values, field_name)
  if (isTRUE(left_result)) return(TRUE)
  right_result <- evaluate_ast_node(node$right, value, form_values, field_name)
  if (isTRUE(right_result)) return(TRUE)

  if (.dsl_is_unknown(left_result) || .dsl_is_unknown(right_result)) {
    return(NA)
  }
  if (is.character(left_result)) left_result else "OR condition failed"
}

#' Evaluate a bare term used as a condition
#'
#' The parser wraps a lone term (`if consent then ...`, or a
#' parenthesized comparison) in a `field_value` node. A field is
#' truthy when it is non-blank and not a conventional false value;
#' any other expression is evaluated and its result returned. This
#' node previously returned the rule's target value regardless of
#' which field it named.
#' @keywords internal
evaluate_field_value_node <- function(node, value, form_values, field_name) {
  inner <- node$field
  if (!is.list(inner)) return(value)
  if (!identical(inner$type, 'field')) {
    return(evaluate_ast_node(inner, value, form_values, field_name))
  }
  v <- .dsl_resolve_field(inner$name, value, form_values)
  if (.dsl_is_blank(v)) return(sprintf('%s is blank', inner$name))
  falsy <- c('false', 'f', 'no', 'n', '0')
  if (length(v) == 1 && tolower(trimws(as.character(v))) %in% falsy) {
    return(sprintf('%s is not set', inner$name))
  }
  TRUE
}

# ============================================================================
# Comparison Operations
# ============================================================================

#' Evaluate comparison operation
#' @keywords internal
evaluate_comparison_node <- function(node, value, form_values, field_name) {
  left <- if (is.list(node$field)) {
    evaluate_ast_node(node$field, value, form_values, field_name)
  } else {
    value
  }
  right <- if (is.list(node$value)) {
    evaluate_ast_node(node$value, value, form_values, field_name)
  } else {
    node$value
  }

  operator <- node$operator
  res <- .dsl_compare(left, right, operator)
  if (is.character(res) || .dsl_is_unknown(res)) return(res)
  if (isTRUE(res)) return(TRUE)
  sprintf('Value %s %s %s is invalid',
          .dsl_format(left), operator, .dsl_format(right))
}

#' Evaluate an inclusive interval check shared by between and range
#' @keywords internal
#' @noRd
.dsl_check_interval <- function(check_value, min_val, max_val, fmt) {
  lo <- .dsl_compare(check_value, min_val, '>=')
  if (is.character(lo)) return(lo)
  hi <- .dsl_compare(check_value, max_val, '<=')
  if (is.character(hi)) return(hi)
  if (isTRUE(lo) && isTRUE(hi)) return(TRUE)
  if (isFALSE(lo) || isFALSE(hi)) {
    return(sprintf(fmt, .dsl_format(check_value), .dsl_format(min_val),
                   .dsl_format(max_val)))
  }
  NA
}

#' Evaluate between operation
#' @keywords internal
evaluate_between_node <- function(node, value, form_values, field_name) {
  check_value <- if (is.list(node$field)) {
    evaluate_ast_node(node$field, value, form_values, field_name)
  } else if (!is.null(node$field)) {
    node$field
  } else {
    value
  }
  min_val <- node$min
  if (is.list(min_val)) {
    min_val <- evaluate_ast_node(min_val, value, form_values, field_name)
  }
  max_val <- node$max
  if (is.list(max_val)) {
    max_val <- evaluate_ast_node(max_val, value, form_values, field_name)
  }
  .dsl_check_interval(check_value, min_val, max_val,
                      'Value %s is not between %s and %s')
}

#' Collect the evaluated members of an in/notin list
#' @keywords internal
#' @noRd
.dsl_member_values <- function(node, value, form_values, field_name) {
  vals <- lapply(node$values, function(val_node) {
    if (is.list(val_node)) {
      evaluate_ast_node(val_node, value, form_values, field_name)
    } else {
      val_node
    }
  })
  unlist(lapply(vals, as.character), use.names = FALSE)
}

#' @keywords internal
#' @noRd
.dsl_member_target <- function(node, value, form_values, field_name,
                               named_field) {
  if (named_field && is.list(node$field)) {
    evaluate_ast_node(node$field, value, form_values, field_name)
  } else {
    value
  }
}

#' Evaluate in operation
#' @keywords internal
evaluate_in_node <- function(node, value, form_values, field_name, named_field = TRUE) {
  check_value <- .dsl_member_target(node, value, form_values, field_name,
                                    named_field)
  if (.dsl_is_blank(check_value)) return(NA)
  allowed <- .dsl_member_values(node, value, form_values, field_name)
  hits <- vapply(check_value, function(v) {
    .dsl_norm_member(v) %in% vapply(allowed, .dsl_norm_member, '')
  }, logical(1))
  if (all(hits)) return(TRUE)
  sprintf("Value '%s' is not in allowed values: %s",
          .dsl_format(check_value), paste(allowed, collapse = ', '))
}

#' Evaluate notin operation
#' @keywords internal
evaluate_notin_node <- function(node, value, form_values, field_name, named_field = TRUE) {
  check_value <- .dsl_member_target(node, value, form_values, field_name,
                                    named_field)
  if (.dsl_is_blank(check_value)) return(NA)
  disallowed <- .dsl_member_values(node, value, form_values, field_name)
  hits <- vapply(check_value, function(v) {
    .dsl_norm_member(v) %in% vapply(disallowed, .dsl_norm_member, '')
  }, logical(1))
  if (!any(hits)) return(TRUE)
  sprintf("Value '%s' is not allowed. Disallowed: %s",
          .dsl_format(check_value), paste(disallowed, collapse = ', '))
}

#' Evaluate range operation (start .. end, applied to the target value)
#' @keywords internal
evaluate_range_node <- function(node, value, form_values, field_name) {
  min_val <- node$start
  if (is.list(min_val)) {
    min_val <- evaluate_ast_node(min_val, value, form_values, field_name)
  }
  max_val <- node$end
  if (is.list(max_val)) {
    max_val <- evaluate_ast_node(max_val, value, form_values, field_name)
  }
  .dsl_check_interval(value, min_val, max_val,
                      'Value %s is not in range %s..%s')
}

# ============================================================================
# Special Checks
# ============================================================================

#' Evaluate required check
#' @keywords internal
evaluate_required_node <- function(node, value, form_values, field_name) {
  if (.dsl_is_blank(value)) 'This field is required' else TRUE
}

#' Evaluate allow check (for missing/null values)
#' @keywords internal
evaluate_allow_node <- function(node, value, form_values, field_name) {
  # allow n,m means allow null (n) or missing (m)
  allowed <- node$values

  # Special values: n = null, m = missing
  for (val_node in allowed) {
    # Extract the actual value from the AST node
    if (is.list(val_node) && "value" %in% names(val_node)) {
      val_str <- val_node$value
    } else if (is.list(val_node)) {
      val_str <- evaluate_ast_node(val_node, value, form_values, field_name)
    } else {
      val_str <- val_node
    }

    # Check for special values - use isTRUE to handle NA comparisons
    if (isTRUE(val_str == "n") && length(value) == 1 && is.na(value)) {
      return(TRUE)
    }
    if (isTRUE(val_str == "m") && .dsl_is_blank(value)) return(TRUE)
    if (!.dsl_is_blank(value) && length(value) == 1 &&
          isTRUE(.dsl_compare(value, val_str, '=='))) {
      return(TRUE)
    }
  }

  return("Value is not in allowed special values")
}

# ============================================================================
# Control Flow
# ============================================================================

#' Evaluate if expression
#' @keywords internal
evaluate_if_node <- function(node, value, form_values, field_name) {
  # Evaluate condition
  condition_result <- evaluate_ast_node(node$condition, value, form_values, field_name)

  # In if/then/else context, treat error messages as FALSE (condition not met)
  # Only TRUE means the condition is satisfied
  if (isTRUE(condition_result)) {
    # Condition is true, execute then branch
    return(evaluate_ast_node(node$then_expr, value, form_values, field_name))
  } else if (!is.null(node$else_expr)) {
    # Condition is false (or error), execute else branch
    return(evaluate_ast_node(node$else_expr, value, form_values, field_name))
  } else {
    # No else branch means this rule simply doesn't apply when the
    # guard is false -- e.g. "if acceptance_date != "" then ...
    # endif" is how every real imported rule spells "only check
    # this once the optional field is actually filled in". That is
    # a pass, not a failure: returning anything other than TRUE here
    # (this previously returned a literal string) makes every
    # guarded rule reject the common, valid case of the guarded
    # field being blank -- reproduced directly against the rules
    # imported from this package's own data dictionaries, all six of
    # which use exactly this guarded-with-no-else shape.
    return(TRUE)
  }
}

# ============================================================================
# Code Generation for Debugging
# ============================================================================

#' Generate readable R code from AST (for debugging)
#'
#' Creates a string representation of the AST as R code. Useful for
#' understanding what validation rules are doing.
#'
#' @param ast List representing the AST
#' @param depth Integer for indentation (internal use)
#'
#' @return Character string with R code representation
#'
#' @keywords internal
ast_to_r_code <- function(ast, depth = 0) {
  if (!is.list(ast) || !"type" %in% names(ast)) {
    return(as.character(ast))
  }

  indent <- paste0(rep("  ", depth), collapse = "")
  type <- ast$type

  switch(type,
    "and" = sprintf("%s(%s AND %s)",
      indent,
      ast_to_r_code(ast$left, depth + 1),
      ast_to_r_code(ast$right, depth + 1)
    ),
    "or" = sprintf("%s(%s OR %s)",
      indent,
      ast_to_r_code(ast$left, depth + 1),
      ast_to_r_code(ast$right, depth + 1)
    ),
    "comparison" = sprintf("%s%s %s %s",
      indent,
      ast_to_r_code(ast$field, depth),
      ast$operator,
      ast_to_r_code(ast$value, depth)
    ),
    "between" = sprintf("%s%s between %s and %s",
      indent,
      if (!is.null(ast$field)) ast_to_r_code(ast$field, depth) else "x",
      ast_to_r_code(ast$min, depth),
      ast_to_r_code(ast$max, depth)
    ),
    "in" = sprintf("%s%s %%in%% c(%s)",
      indent,
      if (!is.null(ast$field)) ast_to_r_code(ast$field, depth) else "x",
      paste(sapply(ast$values, function(v) ast_to_r_code(v, depth)), collapse = ", ")
    ),
    "required" = sprintf("%srequired", indent),
    "allow" = sprintf("%sallow(%s)", indent, paste(sapply(ast$values, function(v) ast_to_r_code(v, depth)), collapse = ", ")),
    "if" = sprintf(
      "%sif (%s) { %s } %s",
      indent,
      ast_to_r_code(ast$condition, depth + 1),
      ast_to_r_code(ast$then_expr, depth + 1),
      if (!is.null(ast$else_expr)) sprintf("else { %s }", ast_to_r_code(ast$else_expr, depth + 1)) else ""
    ),
    "literal" = sprintf("'%s'", ast$value),
    "field" = ast$name,
    sprintf("%s<%s>", indent, type)
  )
}

# ============================================================================
# Validation and Safety Checks
# ============================================================================

#' Check if an AST is safe to execute
#'
#' Validates that the AST doesn't contain any dangerous operations.
#'
#' @param ast List representing the AST
#'
#' @return Logical TRUE if safe, stops with error if not safe
#'
#' @keywords internal
is_ast_safe <- function(ast) {
  if (!is.list(ast) || !"type" %in% names(ast)) {
    return(TRUE)
  }

  # Check for disallowed types
  dangerous_types <- c("function", "call", "eval", "parse", "source", "system")
  if (ast$type %in% dangerous_types) {
    stop(sprintf("Dangerous AST node type: %s", ast$type))
  }

  # Recursively check all child nodes
  for (item in ast) {
    if (is.list(item) && length(item) > 0 && "type" %in% names(item)) {
      is_ast_safe(item)
    }
  }

  TRUE
}

# ============================================================================
# Date/Time Operations (Phase 3)
# ============================================================================

#' Evaluate date arithmetic operation
#' @keywords internal
evaluate_date_arithmetic_node <- function(node, value, form_values, field_name) {
  # Get the base date
  if (is.character(node$date) || is.list(node$date)) {
    if (is.list(node$date)) {
      base_date <- evaluate_ast_node(node$date, value, form_values, field_name)
    } else {
      base_date <- node$date
    }
  } else {
    base_date <- node$date
  }

  if (is.character(base_date)) {
    base_date <- as.Date(base_date)
  }

  # Get the number
  num_val <- node$number
  if (is.list(num_val)) {
    num_val <- evaluate_ast_node(num_val, value, form_values, field_name)
  }

  # Get the unit
  unit <- node$unit

  # Perform the arithmetic inline
  result <- switch(unit,
    "days" = base_date + num_val,
    "weeks" = base_date + (num_val * 7),
    "months" = base_date + (num_val * 30),  # Approximate
    "years" = base_date + (num_val * 365),  # Approximate
    base_date
  )

  result
}

#' Evaluate within days operation
#' @keywords internal
evaluate_within_days_node <- function(node, value, form_values, field_name) {
  # Get the date to check
  if (is.list(node$check_date)) {
    check_date <- evaluate_ast_node(node$check_date, value, form_values, field_name)
  } else {
    check_date <- node$check_date
  }

  # Get reference date from form values
  ref_date_name <- node$reference_date
  if (is.list(ref_date_name)) {
    ref_date <- evaluate_ast_node(ref_date_name, value, form_values, field_name)
  } else {
    ref_date <- form_values[[ref_date_name]]
    if (is.null(ref_date)) {
      return("Reference date not found in form values")
    }
  }

  # Get the number of days
  days <- node$days
  if (is.list(days)) {
    days <- evaluate_ast_node(days, value, form_values, field_name)
  }

  # Check if dates are valid
  if (is.na(check_date) || is.na(ref_date)) {
    return("Missing date value for within comparison")
  }

  # Convert to Date if needed
  if (is.character(check_date)) {
    check_date <- as.Date(check_date)
  }
  if (is.character(ref_date)) {
    ref_date <- as.Date(ref_date)
  }

  # Perform the check inline
  diff <- abs(as.numeric(difftime(check_date, ref_date, units = "days")))
  if (diff <= days) {
    return(TRUE)
  } else {
    return(sprintf("Date %s is not within %d days of %s", check_date, days, ref_date))
  }
}

#' Evaluate today() function
#' @keywords internal
evaluate_today_node <- function(node, value, form_values, field_name) {
  Sys.Date()
}

#' Evaluate function call node
#' @keywords internal
evaluate_function_call_node <- function(node, value, form_values, field_name) {
  func_name <- node$name
  args <- node$args

  # Evaluate arguments first
  eval_args <- list()
  if (!is.null(args) && length(args) > 0) {
    for (arg in args) {
      eval_args <- c(eval_args, list(evaluate_ast_node(arg, value, form_values, field_name)))
    }
  }

  # Arity and unknown-name problems are rule-authoring errors, so they
  # raise rather than return a string that a caller could mistake for
  # a value (it would then be compared as data).
  need <- c(length = 1, days_between = 2, within_days_of = 3, today = 0)
  if (!func_name %in% names(need)) {
    stop(sprintf('Unknown function: %s', func_name))
  }
  if (length(eval_args) < need[[func_name]]) {
    stop(sprintf('%s() requires %d argument(s)', func_name,
                 need[[func_name]]))
  }
  if (func_name == 'today') return(Sys.Date())
  if (any(vapply(eval_args, .dsl_is_blank, logical(1)))) return(NA)

  switch(func_name,
    'length' = nchar(as.character(eval_args[[1]])[1]),
    'days_between' = {
      d1 <- .dsl_as_date(eval_args[[1]])
      d2 <- .dsl_as_date(eval_args[[2]])
      if (is.na(d1) || is.na(d2)) return(NA)
      as.numeric(difftime(d2, d1, units = 'days'))
    },
    'within_days_of' = {
      d1 <- .dsl_as_date(eval_args[[1]])
      d2 <- .dsl_as_date(eval_args[[2]])
      n <- .dsl_as_number(eval_args[[3]])
      if (is.na(d1) || is.na(d2) || is.na(n)) return(NA)
      abs(as.numeric(difftime(d1, d2, units = 'days'))) <= n
    }
  )
}
