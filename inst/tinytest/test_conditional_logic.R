library(tinytest)

# Helpers (auto-loaded by testthat under the previous layout).
# tinytest auto-sources files prefixed with `_` (so `_setup.R`)
# when invoked via `tinytest::test_package()`. The explicit
# source() below keeps the test runnable when invoked directly
# (e.g., `tinytest::run_test_file("test_foo.R")`).
if (file.exists("_setup.R")) source("_setup.R")
# Test Conditional Logic & Dependencies
# Feature #30
setup_cl_test <- function() {
  Sys.setenv(ZZEDC_DB_PATH = tempfile(fileext = ".db"))
  Sys.setenv(ZZEDC_ENCRYPTION_KEY = "test_key_for_conditional_log32!")
  .init_res <- initialize_encrypted_database(Sys.getenv("ZZEDC_DB_PATH"))
  Sys.setenv(DB_ENCRYPTION_KEY = .init_res$key)
  init_audit_logging()
  init_conditional_logic()
}

cleanup_cl_test <- function() {
  db_path <- Sys.getenv("ZZEDC_DB_PATH")
  if (db_path != "" && file.exists(db_path)) {
    try(unlink(db_path), silent = TRUE)
  }
}

# Test: init_conditional_logic creates tables
local({
    setup_cl_test()
    on.exit(cleanup_cl_test())

    con <- connect_encrypted_db()
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    tables <- DBI::dbListTables(con)
    expect_true("field_conditions" %in% tables)
    expect_true("field_dependencies" %in% tables)
    expect_true("conditional_groups" %in% tables)
    expect_true("group_conditions" %in% tables)

})
# Test: reference functions return values
local({
    expect_true("SHOW_HIDE" %in% names(get_condition_types()))
    expect_true("EQUALS" %in% names(get_condition_operators()))
    expect_true("SHOW" %in% names(get_action_types()))
    expect_true("PARENT_CHILD" %in% names(get_dependency_types()))

})
# Test: create_field_condition creates condition
local({
    setup_cl_test()
    on.exit(cleanup_cl_test())

    result <- create_field_condition(
      condition_name = "Show AE Details",
      target_field_code = "AE_DETAILS",
      condition_type = "SHOW_HIDE",
      source_field_code = "AE_OCCURRED",
      operator = "EQUALS",
      comparison_value = "Yes",
      action_type = "SHOW",
      created_by = "crf_designer"
    )

    expect_true(result$success)
    expect_true(!is.null(result$condition_id))

})
# Test: create_field_condition validates inputs
local({
    result <- create_field_condition(
      condition_name = "",
      target_field_code = "FIELD",
      condition_type = "SHOW_HIDE",
      source_field_code = "SOURCE",
      operator = "EQUALS",
      action_type = "SHOW",
      created_by = "user"
    )
    expect_false(result$success)

    setup_cl_test()
    on.exit(cleanup_cl_test())

    result2 <- create_field_condition(
      condition_name = "Test",
      target_field_code = "FIELD",
      condition_type = "INVALID",
      source_field_code = "SOURCE",
      operator = "EQUALS",
      action_type = "SHOW",
      created_by = "user"
    )
    expect_false(result2$success)

    result3 <- create_field_condition(
      condition_name = "Test",
      target_field_code = "FIELD",
      condition_type = "SHOW_HIDE",
      source_field_code = "SOURCE",
      operator = "INVALID_OP",
      action_type = "SHOW",
      created_by = "user"
    )
    expect_false(result3$success)

    result4 <- create_field_condition(
      condition_name = "Test",
      target_field_code = "FIELD",
      condition_type = "SHOW_HIDE",
      source_field_code = "SOURCE",
      operator = "EQUALS",
      action_type = "INVALID_ACTION",
      created_by = "user"
    )
    expect_false(result4$success)

})
# Test: create_field_dependency creates dependency
local({
    setup_cl_test()
    on.exit(cleanup_cl_test())

    result <- create_field_dependency(
      parent_field_code = "COUNTRY",
      child_field_code = "STATE",
      dependency_type = "CASCADING",
      created_by = "designer",
      dependency_rule = "Filter states by country"
    )

    expect_true(result$success)
    expect_true(!is.null(result$dependency_id))

})
# Test: create_field_dependency validates type
local({
    result <- create_field_dependency(
      parent_field_code = "A",
      child_field_code = "B",
      dependency_type = "INVALID",
      created_by = "user"
    )
    expect_false(result$success)

})
# Test: create_conditional_group creates group
local({
    setup_cl_test()
    on.exit(cleanup_cl_test())

    result <- create_conditional_group(
      group_name = "AE Logic Group",
      created_by = "designer",
      logic_operator = "AND",
      description = "All conditions must be true"
    )

    expect_true(result$success)
    expect_true(!is.null(result$group_id))

})
# Test: create_conditional_group validates operator
local({
    result <- create_conditional_group(
      group_name = "Test",
      created_by = "user",
      logic_operator = "XOR"
    )
    expect_false(result$success)

})
# Test: add_condition_to_group adds condition
local({
    setup_cl_test()
    on.exit(cleanup_cl_test())

    group <- create_conditional_group(
      group_name = "Test Group",
      created_by = "designer"
    )

    condition <- create_field_condition(
      condition_name = "Test Condition",
      target_field_code = "TARGET",
      condition_type = "SHOW_HIDE",
      source_field_code = "SOURCE",
      operator = "EQUALS",
      comparison_value = "Yes",
      action_type = "SHOW",
      created_by = "designer"
    )

    result <- add_condition_to_group(group$group_id, condition$condition_id)
    expect_true(result$success)

})
# Test: get_field_conditions retrieves conditions
local({
    setup_cl_test()
    on.exit(cleanup_cl_test())

    create_field_condition(
      condition_name = "Get Test",
      target_field_code = "TARGET",
      condition_type = "ENABLE_DISABLE",
      source_field_code = "SOURCE",
      operator = "IS_NOT_EMPTY",
      action_type = "ENABLE",
      created_by = "designer"
    )

    result <- get_field_conditions()
    expect_true(result$success)
    expect_true(result$count >= 1)

})
# Test: get_field_conditions filters by target
local({
    setup_cl_test()
    on.exit(cleanup_cl_test())

    create_field_condition(
      condition_name = "Filter Test",
      target_field_code = "SPECIFIC_FIELD",
      condition_type = "REQUIRE",
      source_field_code = "SOURCE",
      operator = "EQUALS",
      comparison_value = "Yes",
      action_type = "REQUIRE",
      created_by = "designer"
    )

    result <- get_field_conditions(target_field_code = "SPECIFIC_FIELD")
    expect_true(result$success)
    expect_true(result$count >= 1)

})
# Test: get_field_dependencies retrieves dependencies
local({
    setup_cl_test()
    on.exit(cleanup_cl_test())

    create_field_dependency(
      parent_field_code = "PARENT",
      child_field_code = "CHILD",
      dependency_type = "PARENT_CHILD",
      created_by = "designer"
    )

    result <- get_field_dependencies()
    expect_true(result$success)
    expect_true(result$count >= 1)

})
# Test: get_dependent_fields retrieves children
local({
    setup_cl_test()
    on.exit(cleanup_cl_test())

    create_field_dependency(
      parent_field_code = "MAIN_FIELD",
      child_field_code = "CHILD_1",
      dependency_type = "PARENT_CHILD",
      created_by = "designer"
    )

    create_field_dependency(
      parent_field_code = "MAIN_FIELD",
      child_field_code = "CHILD_2",
      dependency_type = "PARENT_CHILD",
      created_by = "designer"
    )

    result <- get_dependent_fields("MAIN_FIELD")
    expect_true(result$success)
    expect_equal(result$count, 2)

})
# Test: get_conditional_groups retrieves groups
local({
    setup_cl_test()
    on.exit(cleanup_cl_test())

    create_conditional_group(
      group_name = "Group 1",
      created_by = "designer",
      logic_operator = "OR"
    )

    result <- get_conditional_groups()
    expect_true(result$success)
    expect_true(result$count >= 1)

})
# Test: get_group_conditions retrieves group conditions
local({
    setup_cl_test()
    on.exit(cleanup_cl_test())

    group <- create_conditional_group(
      group_name = "Get Conditions Group",
      created_by = "designer"
    )

    cond1 <- create_field_condition(
      condition_name = "Cond 1",
      target_field_code = "T1",
      condition_type = "SHOW_HIDE",
      source_field_code = "S1",
      operator = "EQUALS",
      comparison_value = "A",
      action_type = "SHOW",
      created_by = "designer"
    )

    add_condition_to_group(group$group_id, cond1$condition_id)

    result <- get_group_conditions(group$group_id)
    expect_true(result$success)
    expect_equal(result$count, 1)

})
# Test: evaluate_condition evaluates EQUALS
local({
    result <- evaluate_condition("Yes", "EQUALS", "Yes")
    expect_true(result$success)
    expect_true(result$result)

    result2 <- evaluate_condition("No", "EQUALS", "Yes")
    expect_true(result2$success)
    expect_false(result2$result)

})
# Test: evaluate_condition evaluates NOT_EQUALS
local({
    result <- evaluate_condition("No", "NOT_EQUALS", "Yes")
    expect_true(result$success)
    expect_true(result$result)

})
# Test: evaluate_condition evaluates numeric comparisons
local({
    result_gt <- evaluate_condition("10", "GREATER_THAN", "5")
    expect_true(result_gt$result)

    result_lt <- evaluate_condition("3", "LESS_THAN", "5")
    expect_true(result_lt$result)

    result_ge <- evaluate_condition("5", "GREATER_EQUAL", "5")
    expect_true(result_ge$result)

    result_le <- evaluate_condition("5", "LESS_EQUAL", "5")
    expect_true(result_le$result)

})
# Test: evaluate_condition evaluates CONTAINS
local({
    result <- evaluate_condition("Hello World", "CONTAINS", "World")
    expect_true(result$result)

    result2 <- evaluate_condition("Hello World", "NOT_CONTAINS", "Foo")
    expect_true(result2$result)

})
# Test: evaluate_condition evaluates IS_EMPTY
local({
    result_empty <- evaluate_condition("", "IS_EMPTY", NULL)
    expect_true(result_empty$result)

    result_null <- evaluate_condition(NULL, "IS_EMPTY", NULL)
    expect_true(result_null$result)

    result_na <- evaluate_condition(NA, "IS_EMPTY", NULL)
    expect_true(result_na$result)

    result_not_empty <- evaluate_condition("value", "IS_NOT_EMPTY", NULL)
    expect_true(result_not_empty$result)

})
# Test: evaluate_condition evaluates IN_LIST
local({
    result <- evaluate_condition("B", "IN_LIST", "A,B,C")
    expect_true(result$result)

    result2 <- evaluate_condition("D", "NOT_IN_LIST", "A,B,C")
    expect_true(result2$result)

})
# Test: deactivate_condition deactivates
local({
    setup_cl_test()
    on.exit(cleanup_cl_test())

    condition <- create_field_condition(
      condition_name = "Deactivate Test",
      target_field_code = "TARGET",
      condition_type = "SHOW_HIDE",
      source_field_code = "SOURCE",
      operator = "EQUALS",
      comparison_value = "X",
      action_type = "HIDE",
      created_by = "designer"
    )

    result <- deactivate_condition(condition$condition_id)
    expect_true(result$success)

    conditions <- get_field_conditions(include_inactive = FALSE)
    active_ids <- conditions$conditions$condition_id
    expect_false(condition$condition_id %in% active_ids)

})
# Test: get_conditional_logic_statistics returns stats
local({
    setup_cl_test()
    on.exit(cleanup_cl_test())

    result <- get_conditional_logic_statistics()
    expect_true(result$success)
    expect_true("statistics" %in% names(result))
    expect_true("by_type" %in% names(result))
    expect_true("by_action" %in% names(result))

})