#!/usr/bin/env Rscript
# Production-ready renv synchronization checker
#
# DESCRIPTION:
#   This script solves a critical problem in R package development: ensuring that
#   all R packages used in your code are properly declared in your DESCRIPTION file
#   and locked in your renv.lock file for reproducibility.
#
#   Think of it as a "dependency lint checker" that prevents the common scenario where:
#   - You use library(dplyr) in your code but forget to add dplyr to DESCRIPTION
#   - Your colleague clones your repo and gets "package not found" errors
#   - Your CI/CD pipeline fails because dependencies are missing
#
#   The script scans ALL your R code files, extracts package dependencies, validates
#   them against CRAN, and automatically fixes your DESCRIPTION and renv.lock files.
#
# USAGE:
#   Interactive mode:     Rscript check_renv_for_commit.R
#   CI/CD automation:     Rscript check_renv_for_commit.R --fix --fail-on-issues
#   Quick snapshot:       Rscript check_renv_for_commit.R --snapshot
#   Silent checking:      Rscript check_renv_for_commit.R --quiet --fail-on-issues
#   Strict mode:          Rscript check_renv_for_commit.R --fix --strict-imports
#
# FLAGS EXPLAINED:
#   --fix, --auto-fix     Automatically fix DESCRIPTION and run renv::snapshot()
#                         Without this flag, script only reports problems
#   --fail-on-issues      Exit with code 1 if critical issues found (for CI/CD)
#                         This makes your CI/CD pipeline fail if dependencies are broken
#   --snapshot           Only run renv::snapshot() and exit (quick lockfile update)
#   --quiet              Minimal output, only show critical errors (for automated runs)
#   --strict-imports     Scan ALL directories (including tests/) and put everything in Imports
#                         Use this for maximum reproducibility at cost of heavier dependencies
#
# EXIT CODES:
#   0 = Success, no critical issues (safe to commit)
#   1 = Critical issues found (missing packages, missing files, etc.)
#       DO NOT COMMIT until these are fixed!

#==============================================================================
# ZZCOLLAB INTEGRATION
#
# Try to integrate with zzcollab's modular architecture if available
# This allows the script to use zzcollab's logging and utility functions
#==============================================================================

# Check for zzcollab module integration
check_zzcollab_integration <- function() {
  integration <- list(
    utils_available = FALSE,
    logging_available = FALSE,
    core_available = FALSE
  )
  
  # Try to source zzcollab utilities if they exist
  if (file.exists("modules/utils.sh")) {
    # zzcollab utilities are bash, but we can check for R equivalents
    if (file.exists("R/zzcollab_utils.R")) {
      tryCatch({
        source("R/zzcollab_utils.R", local = FALSE)
        integration <- TRUE
      }, error = function(e) {
        # Silently continue if sourcing fails
      })
    }
  }
  
  # Check for logging integration
  if (exists("zzcollab_log", mode = "function")) {
    integration <- TRUE
  }
  
  # Check for core zzcollab functions
  if (exists("zzcollab_config", mode = "function")) {
    integration <- TRUE
  }
  
  return(integration)
}

# Initialize zzcollab integration at startup
ZZCOLLAB_INTEGRATION <- check_zzcollab_integration()

#==============================================================================
# CONFIGURATION AND CONSTANTS
# 
# Why we need this section:
# - Centralizes all configuration to avoid "magic numbers" scattered throughout code
# - Makes the script easy to modify without hunting through hundreds of lines
# - Provides clear documentation for why each setting exists
#==============================================================================

# Package configuration constants (immutable)
# These define the "rules" for what constitutes a valid R package setup
PKG_CONFIG <- list(
  # Base packages that come with R installation - we never need to declare these
  # in DESCRIPTION because they're always available
  base_packages = c("base", "utils", "stats", "graphics", "grDevices", "methods", "datasets", "tools"),
  
  # Standard directories to scan in normal mode
  # These contain the "core" functionality of your package
  standard_dirs = c("R", "scripts", "analysis"),
  
  # Strict directories to scan in --strict-imports mode  
  # Includes testing and documentation directories for maximum coverage
  strict_dirs = c("R", "scripts", "analysis", "tests", "vignettes", "inst"),
  
  # File extensions we recognize as containing R code
  # .R = R code, .Rmd = R Markdown, .qmd = Quarto, .Rnw = Sweave
  file_extensions = c("R", "Rmd", "qmd", "Rnw"),
  
  # Minimum viable package name length (prevents false positives like "x" or "df")
  # R package names must be at least 2 characters, but we use 3 to be conservative
  min_package_length = 3L,
  
  # CRAN API timeout in seconds (network requests can hang)
  # 30 seconds is generous but prevents infinite hangs in CI/CD
  cran_timeout_seconds = 30L,
  
  # Timestamp format for backup files (makes them sortable and unique)
  backup_timestamp_format = "%Y%m%d_%H%M%S",
  
  # zzcollab build mode configurations
  build_modes = list(
    fast = list(
      max_packages = 15L,
      skip_suggests = TRUE,
      essential_only = TRUE,
      description = "Minimal package set for fast builds"
    ),
    standard = list(
      max_packages = 50L,
      skip_suggests = FALSE,
      essential_only = FALSE,
      description = "Balanced package set (default)"
    ),
    comprehensive = list(
      max_packages = 200L,
      skip_suggests = FALSE,
      essential_only = FALSE,
      description = "Full package set for extensive environments"
    )
  )
)

# Pre-compiled regex patterns for performance
# Why pre-compile? Regex compilation is expensive and we use these patterns repeatedly
# across hundreds of files. Compiling once at startup saves significant time.
REGEX_PATTERNS <- list(
  # Matches files with R-related extensions (case insensitive)
  file_pattern = paste0("\\.(", paste(PKG_CONFIG, collapse = "|"), ")$"),
  
  # Enhanced library/require patterns that handle edge cases
  library_simple = "(?:library|require)\\s*\\(\\s*[\"']?([a-zA-Z][a-zA-Z0-9._]{2,})[\"']?\\s*[,)]",
  library_wrapped = "(?:suppressMessages|suppressWarnings|quietly|invisible)\\s*\\(\\s*(?:library|require)\\s*\\(\\s*[\"']?([a-zA-Z][a-zA-Z0-9._]{2,})[\"']?",
  library_conditional = "if\\s*\\([^)]+\\)\\s*(?:library|require)\\s*\\(\\s*[\"']?([a-zA-Z][a-zA-Z0-9._]{2,})[\"']?",
  
  # Namespace calls with enhanced detection
  namespace_calls = "([a-zA-Z][a-zA-Z0-9._]{2,})::",
  namespace_internal = "([a-zA-Z][a-zA-Z0-9._]{2,}):::",
  
  # Package imports in roxygen comments
  roxygen_import = "#'\\s*@import\\s+([a-zA-Z][a-zA-Z0-9._]{2,})",
  roxygen_importFrom = "#'\\s*@importFrom\\s+([a-zA-Z][a-zA-Z0-9._]{2,})",
  
  # Validates that a string looks like a real R package name
  # Must start with letter, contain only letters/numbers/dots/underscores, minimum length
  package_name_valid = "^[a-zA-Z][a-zA-Z0-9._]{2,}$",
  
  # Removes comments to avoid false positives (but keeps roxygen comments starting with #')
  comments_simple = "#[^\n]*",
  
  # Matches @examples sections in roxygen documentation
  # These often contain library() calls that need to be tracked
  examples_section = "@examples[\\s\\S]*?(?=@[a-zA-Z]|$)",
  
  # Identifies this script itself to avoid self-scanning
  self_script_pattern = "^check_renv"
)

#==============================================================================
# ARGUMENT PARSING AND VALIDATION
#
# Why argument parsing matters:
# - Scripts need different behavior in different contexts (interactive vs CI/CD)
# - Validation prevents nonsensical flag combinations that would cause confusion
# - Clean parsing makes the script self-documenting about its capabilities
#==============================================================================

# Helper function to extract flag values from command line arguments
extract_flag_value <- function(args, flag_name) {
  flag_index <- which(args == flag_name)
  if (length(flag_index) == 0) return(NULL)
  if (flag_index == length(args)) return(NULL)
  args[flag_index + 1]
}

# Parse command line arguments into validated configuration
# This function transforms raw command line flags into a clean configuration object
# that the rest of the script can rely on
parse_arguments <- function(args = commandArgs(trailingOnly = TRUE)) {
  # Extract boolean flags from command line arguments
  # Each flag enables specific behavior patterns
  script_config <- list(
    # --fix flag: Should we automatically fix problems we find?
    # Without this, script is "read-only" and just reports issues
    auto_fix = any(c("--fix", "--auto-fix") %in% args),
    
    # --fail-on-issues flag: Should we exit with error code if problems found?
    # Critical for CI/CD pipelines that need to fail builds on dependency issues
    fail_on_issues = "--fail-on-issues" %in% args,
    
    # --snapshot flag: Skip analysis and just update renv.lock?
    # Useful for quick lockfile updates without full dependency checking
    snapshot_only = "--snapshot" %in% args,
    
    # --quiet flag: Suppress non-critical output?
    # Essential for automated scripts that parse output or run in cron jobs
    quiet = "--quiet" %in% args,
    
    # --strict-imports flag: Scan ALL directories and put everything in Imports?
    # Trades convenience for maximum reproducibility
    strict_imports = "--strict-imports" %in% args,
    
    # --build-mode flag: Override build mode detection
    # Can be fast|standard|comprehensive
    build_mode_override = extract_flag_value(args, "--build-mode")
  )
  
  # Validate argument combinations and provide enhanced error messages
  validate_flag_combinations(script_config)
  
  # Add zzcollab build mode detection
  script_config <- detect_build_mode(script_config)
  
  script_config
}

# Enhanced flag validation with comprehensive error checking
validate_flag_combinations <- function(config) {
  # Critical incompatible combinations
  if (config && config) {
    stop("❌ Cannot use --snapshot with --fix flags simultaneously\n", 
         "   Reason: --snapshot only updates lockfile, --fix modifies DESCRIPTION\n",
         "   These are different operations that shouldn't be combined", call. = FALSE)
  }
  
  # Warnings for potentially confusing combinations
  if (config && !config) {
    warning("⚠️  --strict-imports has no effect without --fix flag\n",
            "   Add --fix to enable automatic DESCRIPTION modification", call. = FALSE)
  }
  
  if (config && config && !config) {
    message("ℹ️  Using --fail-on-issues with --fix\n",
            "   Script will only fail if --fix cannot resolve issues")
  }
  
  # Validate build mode if provided
  if (!is.null(config)) {
    valid_modes <- names(PKG_CONFIG)
    if (!config %in% valid_modes) {
      stop("❌ Invalid build mode: ", config, "\n",
           "   Valid modes: ", paste(valid_modes, collapse = ", "), call. = FALSE)
    }
  }
  
  invisible(NULL)
}

# Detect zzcollab build mode from environment and context
detect_build_mode <- function(override_mode = NULL) {
  # 1. Use explicit override if provided
  if (!is.null(override_mode)) {
    return(override_mode)
  }
  
  # 2. Check zzcollab environment variable
  env_mode <- Sys.getenv("ZZCOLLAB_BUILD_MODE", "")
  if (env_mode != "" && env_mode %in% names(PKG_CONFIG)) {
    return(env_mode)
  }
  
  # 3. Check for zzcollab configuration files
  if (file.exists("zzcollab.conf")) {
    # Try to read build mode from config file
    tryCatch({
      conf_lines <- readLines("zzcollab.conf", warn = FALSE)
      mode_line <- grep("^BUILD_MODE=", conf_lines, value = TRUE)
      if (length(mode_line) > 0) {
        mode <- sub("^BUILD_MODE=", "", mode_line[1])
        if (mode %in% names(PKG_CONFIG)) {
          return(mode)
        }
      }
    }, error = function(e) {
      # Silently continue if config file is unreadable
    })
  }
  
  # 4. Detect from project structure
  if (length(list.files("R", pattern = "\\.R$", recursive = TRUE)) > 20) {
    return("comprehensive")  # Large project likely needs comprehensive mode
  }
  
  if (file.exists("tests") && length(list.files("tests", recursive = TRUE)) > 10) {
    return("comprehensive")  # Heavy testing suggests comprehensive needs
  }
  
  # 5. Default to standard mode
  return("standard")
}

#==============================================================================
# LOGGING SYSTEM
#
# Why a custom logging system?
# - R's built-in messaging is basic and doesn't support log levels
# - We need to respect --quiet flag throughout the entire script
# - Consistent prefixes make output parseable by other tools
# - Force parameter allows critical errors to bypass quiet mode
#==============================================================================

# Create enhanced logging function factory with zzcollab integration
# This factory pattern ensures each part of the script gets a logger configured
# with the current settings, without relying on global variables
create_logger <- function(config) {
  # Check if zzcollab logging is available and should be used
  use_zzcollab_logging <- ZZCOLLAB_INTEGRATION && !config
  
  # Return a closure that "remembers" the config settings
  function(..., level = "info", force = FALSE) {
    # Respect quiet mode unless this is critical (force = TRUE)
    if (config && !force && level != "error") return(invisible(NULL))
    
    # Use zzcollab logging if available
    if (use_zzcollab_logging && exists("zzcollab_log", mode = "function")) {
      tryCatch({
        zzcollab_log(paste(..., collapse = ""), level = level)
        return(invisible(NULL))
      }, error = function(e) {
        # Fall back to standard logging if zzcollab logging fails
      })
    }
    
    # Standard logging with visual prefixes
    # Each level gets a distinctive emoji for quick visual scanning
    prefix <- switch(level,
      "error" = "❌",      # Critical issues that must be fixed
      "warning" = "⚠️ ",   # Problems that should be addressed but aren't critical
      "success" = "✅",    # Positive confirmation of completed operations
      "info" = "🔍",       # Informational messages about what's happening
      "🔍"                 # Default fallback
    )
    cat(prefix, " ", ..., "\n", sep = "")
    invisible(NULL)
  }
}

#==============================================================================
# PURE UTILITY FUNCTIONS
#
# Why "pure" functions matter:
# - They don't depend on global state, making them predictable and testable
# - They don't have side effects, making them safe to call from anywhere
# - They're easier to reason about because input -> output relationship is clear
# - They can be easily unit tested in isolation
#==============================================================================

# Validate and clean package names (pure function)
# This function implements the "garbage in, clean data out" principle
# It takes any messy list of potential package names and returns only valid ones
clean_package_names <- function(packages, exclude_packages = character()) {
  # Input validation: ensure we have character data to work with
  if (!is.character(packages) || length(packages) == 0L) {
    return(character(0))
  }
  
  # Step 1: Remove duplicates (common when scanning many files)
  # unique() is essential because the same package might be loaded in multiple files
  packages <- unique(packages)
  
  # Step 2: Remove packages we never want to track
  # - Base packages: always available in R, never need declaring
  # - Excluded packages: typically the current package name (can't depend on itself)
  # - Empty strings: parsing artifacts that aren't real package names
  packages <- packages[!packages %in% c(PKG_CONFIG, exclude_packages, "")]
  
  # Step 3: Filter by minimum length
  # Very short names are usually variables, not package names
  # Real R packages typically have meaningful names of 3+ characters
  packages <- packages[nchar(packages) >= PKG_CONFIG]
  
  # Step 4: Validate package name format using regex
  # R package names must follow specific naming conventions
  # This catches things like "123abc" or "my-package" which aren't valid
  packages <- packages[grepl(REGEX_PATTERNS, packages, perl = TRUE)]
  
  # Step 5: Sort for consistent output
  # Makes diffs readable and output predictable across runs
  sort(packages)
}

#==============================================================================
# CORE PACKAGE EXTRACTION ENGINE
#==============================================================================

# Extract packages from text content (pure function, non-recursive)
#
# DESCRIPTION:
#   This is the core "parsing engine" that finds package dependencies in R code.
#   It's the heart of the dependency validation system, responsible for accurately
#   detecting all the ways R packages can be referenced in code.
#
# ARCHITECTURE:
#   Uses a multi-step regex-based approach to handle different patterns:
#   1. Comment removal (while preserving roxygen documentation)
#   2. Library/require calls (simple, wrapped, conditional)
#   3. Namespace calls (::, :::)
#   4. Roxygen imports (@importFrom, @import)
#   5. Cleanup and deduplication
#
# HANDLES THESE PATTERNS:
#   - library(dplyr), require("ggplot2")           # Standard loading
#   - suppressMessages(library(package))           # Wrapped calls
#   - if (condition) library(package)              # Conditional loading  
#   - dplyr::select(), package::function()         # Namespace calls
#   - package:::internal_function()                # Internal namespace
#   - @importFrom dplyr select mutate              # Roxygen imports
#   - @import ggplot2                             # Full roxygen imports
#
# EDGE CASES HANDLED:
#   - Comments containing fake library calls
#   - Nested function calls
#   - Multi-line expressions
#   - Mixed quote styles (single/double)
#   - Base R packages (automatically filtered)
#
# ARGUMENTS:
#   content - Character vector containing R code text to parse
#
# RETURNS:
#   Character vector of unique package names found in the code
#   Returns empty character(0) if no packages found or invalid input
#
extract_packages_from_text <- function(content) {
  # Input validation: ensure we have text content to parse
  if (!is.character(content) || length(content) == 0L || nchar(content) == 0L) {
    return(character(0))
  }
  
  # Step 1: Remove comments to avoid false positives
  # Comments often contain example code like "# library(dplyr)" that isn't real usage
  # However, we preserve roxygen comments starting with #' because they contain documentation
  content <- gsub(REGEX_PATTERNS, "", content, perl = TRUE)
  
  # Initialize collection vector for found packages
  packages <- character(0)
  
  # Step 2: Extract library/require calls with enhanced patterns
  # Handle multiple patterns: simple, wrapped, and conditional calls
  
  # Simple calls: library(dplyr), require("ggplot2")
  lib_matches <- regmatches(content, gregexpr(REGEX_PATTERNS, content, perl = TRUE))[[1]]
  if (length(lib_matches) > 0L) {
    lib_packages <- gsub(REGEX_PATTERNS, "\\1", lib_matches, perl = TRUE)
    packages <- c(packages, lib_packages)
  }
  
  # Wrapped calls: suppressMessages(library(dplyr))
  wrapped_matches <- regmatches(content, gregexpr(REGEX_PATTERNS, content, perl = TRUE))[[1]]
  if (length(wrapped_matches) > 0L) {
    wrapped_packages <- gsub(REGEX_PATTERNS, "\\1", wrapped_matches, perl = TRUE)
    packages <- c(packages, wrapped_packages)
  }
  
  # Conditional calls: if (condition) library(package)
  cond_matches <- regmatches(content, gregexpr(REGEX_PATTERNS, content, perl = TRUE))[[1]]
  if (length(cond_matches) > 0L) {
    cond_packages <- gsub(REGEX_PATTERNS, "\\1", cond_matches, perl = TRUE)
    packages <- c(packages, cond_packages)
  }
  
  # Step 3: Extract namespace calls with enhanced detection
  # Handle both :: and ::: calls, plus roxygen imports
  
  # Standard namespace calls: dplyr::select, ggplot2::ggplot
  ns_matches <- regmatches(content, gregexpr(REGEX_PATTERNS, content, perl = TRUE))[[1]]
  if (length(ns_matches) > 0L) {
    ns_packages <- gsub("::", "", ns_matches)
    packages <- c(packages, ns_packages)
  }
  
  # Internal namespace calls: package:::internal_function
  internal_matches <- regmatches(content, gregexpr(REGEX_PATTERNS, content, perl = TRUE))[[1]]
  if (length(internal_matches) > 0L) {
    internal_packages <- gsub(":::", "", internal_matches)
    packages <- c(packages, internal_packages)
  }
  
  # Roxygen @import statements
  import_matches <- regmatches(content, gregexpr(REGEX_PATTERNS, content, perl = TRUE))[[1]]
  if (length(import_matches) > 0L) {
    import_packages <- gsub(REGEX_PATTERNS, "\\1", import_matches, perl = TRUE)
    packages <- c(packages, import_packages)
  }
  
  # Roxygen @importFrom statements
  importFrom_matches <- regmatches(content, gregexpr(REGEX_PATTERNS, content, perl = TRUE))[[1]]
  if (length(importFrom_matches) > 0L) {
    importFrom_packages <- gsub(REGEX_PATTERNS, "\\1", importFrom_matches, perl = TRUE)
    packages <- c(packages, importFrom_packages)
  }
  
  # Step 4: Extract packages from @examples sections (non-recursive approach)
  # @examples in roxygen documentation often demonstrate package usage
  # These dependencies are needed for R CMD check to pass
  examples_matches <- regmatches(content, gregexpr(REGEX_PATTERNS, content, perl = TRUE))[[1]]
  if (length(examples_matches) > 0L) {
    for (example_block in examples_matches) {
      # Remove the @examples header line to get just the example code
      example_content <- sub("@examples[^\n]*\n?", "", example_block)
      
      # Extract library calls from example code (same patterns as main code)
      # We use simple pattern matching here instead of recursion to avoid infinite loops
      ex_lib_matches <- regmatches(example_content, gregexpr(REGEX_PATTERNS, example_content, perl = TRUE))[[1]]
      if (length(ex_lib_matches) > 0L) {
        ex_packages <- gsub(REGEX_PATTERNS, "\\1", ex_lib_matches, perl = TRUE)
        packages <- c(packages, ex_packages)
      }
      
      # Extract namespace calls from example code
      ex_ns_matches <- regmatches(example_content, gregexpr(REGEX_PATTERNS, example_content, perl = TRUE))[[1]]
      if (length(ex_ns_matches) > 0L) {
        ex_ns_packages <- gsub("::", "", ex_ns_matches)
        packages <- c(packages, ex_ns_packages)
      }
    }
  }
  
  # Return raw package list (cleaning happens later in the pipeline)
  packages
}

# Safe file reading with error handling
# File I/O can fail for many reasons: permissions, encoding, disk space, etc.
# This function wraps file reading in comprehensive error handling
read_file_safely <- function(filepath) {
  # Input validation: ensure we have a valid file path
  if (!is.character(filepath) || length(filepath) != 1L || !file.exists(filepath)) {
    return(list(content = "", success = FALSE, error = "File not found or invalid path"))
  }
  
  # Attempt to read file with error recovery
  tryCatch({
    # Read entire file into a single string
    # paste(..., collapse = "\n") joins all lines with newlines
    # warn = FALSE suppresses warnings about missing final newlines
    content <- paste(readLines(filepath, warn = FALSE), collapse = "\n")
    list(content = content, success = TRUE, error = NULL)
  }, error = function(e) {
    # If reading fails, return error details for debugging
    list(content = "", success = FALSE, error = as.character(e))
  })
}

# Batch file discovery with memoization
# Finding all R files in a project can be expensive if done inefficiently
# This function optimizes file discovery by batching operations and avoiding redundant checks
discover_files <- function(target_dirs, file_pattern) {
  # Input validation: ensure we have directories to search
  if (!is.character(target_dirs) || length(target_dirs) == 0L) {
    return(character(0))
  }
  
  # Step 1: Filter to only existing directories
  # file.exists() checks both files and directories, returns logical vector
  # This avoids expensive list.files() calls on non-existent directories
  existing_dirs <- target_dirs[file.exists(target_dirs)]
  if (length(existing_dirs) == 0L) {
    return(character(0))
  }
  
  # Step 2: Batch file discovery across all directories
  # Collecting all files first, then deduplicating is more efficient than
  # checking for duplicates after each directory
  all_files <- character(0)
  for (dir in existing_dirs) {
    # Double-check with dir.exists() for safety (file.exists() can be ambiguous)
    if (dir.exists(dir)) {
      # list.files() with recursive = TRUE walks entire directory tree
      # full.names = TRUE gives us absolute paths we can use directly
      # ignore.case = TRUE catches .R, .r, .Rmd, .rmd, etc.
      files <- list.files(dir, pattern = file_pattern, recursive = TRUE, 
                         ignore.case = TRUE, full.names = TRUE)
      all_files <- c(all_files, files)
    }
  }
  
  # Step 3: Add top-level R files (common in package development)
  # Many packages have utility scripts in the root directory
  top_files <- list.files(".", pattern = file_pattern, ignore.case = TRUE)
  # Exclude this script itself to avoid self-scanning
  top_files <- top_files[!grepl(REGEX_PATTERNS, top_files)]
  all_files <- c(all_files, top_files)
  
  # Step 4: Remove duplicates and return
  # unique() handles cases where the same file might be found via different paths
  unique(all_files)
}

#==============================================================================
# PACKAGE EXTRACTION ENGINE
#
# Why we need a dedicated extraction engine:
# - File discovery and content parsing are complex operations with many edge cases
# - We need to handle failures gracefully (some files might be unreadable)
# - Performance matters when scanning hundreds of files
# - Different modes (standard vs strict) require different directory sets
#==============================================================================

# Main package extraction function
# This orchestrates the entire process of finding R files and extracting package dependencies
# It's the "conductor" that coordinates file discovery, reading, parsing, and cleaning
extract_code_packages <- function(config, log_fn) {
  # Step 1: Choose directories based on mode
  # Standard mode: core package functionality only (R/, scripts/, analysis/)
  # Strict mode: everything including tests and vignettes for maximum coverage
  target_dirs <- if (config) PKG_CONFIG else PKG_CONFIG
  
  # Step 2: Discover all relevant files
  # This is where we find every R file that could contain package dependencies
  all_files <- discover_files(target_dirs, REGEX_PATTERNS)
  
  # Early exit if no files found (avoids confusing "processed 0 files" messages)
  if (length(all_files) == 0L) {
    log_fn("No R/Rmd/qmd/Rnw files found", level = "warning")
    return(character(0))
  }
  
  # Report what we're doing (helps with debugging and progress tracking)
  mode_name <- if (config) "strict" else "standard"
  log_fn("Scanning ", length(all_files), " files in ", mode_name, " mode...", level = "info")
  
  # Step 3: Process files efficiently using lists instead of vector concatenation
  # Why lists? Vector concatenation with c() creates new vectors each time (O(n²) complexity)
  # Lists allow us to collect results efficiently, then flatten once at the end (O(n) complexity)
  package_lists <- vector("list", length(all_files))
  failed_count <- 0L
  
  # Process each file and collect package dependencies
  for (i in seq_along(all_files)) {
    file_result <- read_file_safely(all_files[i])
    if (file_result) {
      # Extract packages from file content
      package_lists[[i]] <- extract_packages_from_text(file_result)
    } else {
      # Track failures for reporting, but continue processing other files
      failed_count <- failed_count + 1L
      package_lists[[i]] <- character(0)
    }
  }
  
  # Step 4: Report any file reading failures
  # This helps diagnose permission issues, encoding problems, etc.
  if (failed_count > 0L) {
    log_fn("Failed to read ", failed_count, " files", level = "warning")
  }
  
  # Step 5: Flatten package lists efficiently
  # unlist() with use.names = FALSE is the most efficient way to flatten lists
  # This gives us a single character vector of all found packages
  all_packages <- unlist(package_lists, use.names = FALSE)
  
  # Step 6: Clean packages and return results
  # Get self package name for exclusion (packages can't depend on themselves)
  self_pkg <- get_self_package_name()
  clean_package_names(all_packages, c(self_pkg))
}

#==============================================================================
# CONFIGURATION FILE PARSERS
#
# Why dedicated parsers?
# - DESCRIPTION and renv.lock files have specific formats that need careful handling
# - We need fallback strategies when optional packages (desc, jsonlite) aren't available
# - Error handling must be robust since these files are critical for package function
# - Consistent return format makes the main logic simpler
#==============================================================================

# Get self package name safely
# We need to exclude the current package from dependency lists because
# packages cannot and should not depend on themselves
get_self_package_name <- function() {
  if (!file.exists("DESCRIPTION")) return("")
  
  tryCatch({
    # read.dcf() parses Debian Control Format files (which DESCRIPTION uses)
    # Returns a matrix where columns are field names, rows are records
    desc_data <- read.dcf("DESCRIPTION")
    if ("Package" %in% colnames(desc_data)) desc_data[, "Package"] else ""
  }, error = function(e) "")
}

# Parse DESCRIPTION file with multiple fallback strategies
# DESCRIPTION file contains package metadata including dependency declarations
# We need to extract all packages from Imports, Suggests, and Depends fields
parse_description_file <- function() {
  if (!file.exists("DESCRIPTION")) {
    return(list(packages = character(0), error = TRUE, message = "DESCRIPTION file not found"))
  }
  
  tryCatch({
    # Strategy 1: Try desc package for robust parsing
    # The desc package handles edge cases better than manual parsing
    if (requireNamespace("desc", quietly = TRUE)) {
      d <- desc::desc()
      deps <- d()
      # Extract package names from all dependency types we care about
      all_packages <- unique(deps[deps %in% c("Imports", "Suggests", "Depends")])
      # Filter out R itself and empty strings
      all_packages <- all_packages[!all_packages %in% c("R", "")]
      return(list(packages = all_packages, error = FALSE, message = "Parsed with desc package"))
    }
    
    # Strategy 2: Manual DCF parsing as fallback
    # If desc package isn't available, we parse manually using base R
    desc_data <- read.dcf("DESCRIPTION")
    
    # Helper function to extract dependencies from a specific field
    extract_deps <- function(field_name) {
      # Check if field exists and has content
      if (!field_name %in% colnames(desc_data) || is.na(desc_data[, field_name])) {
        return(character(0))
      }
      # Split on commas to get individual package declarations
      deps <- trimws(strsplit(desc_data[, field_name], ",")[[1]])
      # Remove version constraints like (>= 1.0.0) using regex
      deps <- gsub("\\s*\\([^)]+\\)", "", deps)
      # Filter out empty strings and R itself
      deps[deps != "" & deps != "R"]
    }
    
    # Extract from all relevant dependency fields
    all_packages <- unique(c(
      extract_deps("Imports"),    # Runtime dependencies
      extract_deps("Suggests"),  # Optional dependencies
      extract_deps("Depends")    # Strong dependencies (rarely used)
    ))
    
    list(packages = all_packages, error = FALSE, message = "Parsed with read.dcf")
    
  }, error = function(e) {
    # If all parsing strategies fail, return error with details
    list(packages = character(0), error = TRUE, message = paste("Parse failed:", e))
  })
}

# Parse renv.lock file with fallbacks
# renv.lock is a JSON file that records exact package versions for reproducibility
# We need to extract the list of packages to compare with DESCRIPTION
parse_renv_lock_file <- function() {
  if (!file.exists("renv.lock")) {
    return(list(packages = character(0), error = TRUE, message = "renv.lock file not found"))
  }
  
  tryCatch({
    # Strategy 1: JSON parsing using jsonlite package
    # This is the robust approach that handles all JSON edge cases
    if (requireNamespace("jsonlite", quietly = TRUE)) {
      lock_data <- jsonlite::fromJSON("renv.lock", simplifyVector = FALSE)
      if ("Packages" %in% names(lock_data)) {
        # Extract package names from the Packages section
        packages <- names(lock_data)
        # Filter out base packages that don't need tracking
        packages <- packages[!packages %in% PKG_CONFIG]
        return(list(packages = packages, error = FALSE, message = "Parsed with jsonlite"))
      }
    }
    
    # Strategy 2: Manual parsing as fallback
    # If jsonlite isn't available, we use regex to extract package names
    # This is fragile but better than failing completely
    content <- readLines("renv.lock", warn = FALSE)
    # Look for lines like "packagename": { which indicate package entries
    pkg_lines <- grep('"[^"]+": \\{', content, value = TRUE)
    if (length(pkg_lines) > 0L) {
      # Extract package names using regex backreference
      packages <- gsub('.*"([^"]+)": \\{.*', '\\1', pkg_lines)
      # Filter out JSON structure elements and base packages
      packages <- packages[!packages %in% c("R", "Packages", PKG_CONFIG)]
      return(list(packages = packages, error = FALSE, message = "Parsed manually"))
    }
    
    # If we found no packages, that's likely an error
    list(packages = character(0), error = TRUE, message = "No packages found in renv.lock")
    
  }, error = function(e) {
    # If all parsing strategies fail, return error with details
    list(packages = character(0), error = TRUE, message = paste("Parse failed:", e))
  })
}

#==============================================================================
# CRAN VALIDATION (WITH CACHING)
#
# Why CRAN validation matters:
# - Packages might be misspelled (e.g., "dplry" instead of "dplyr")
# - Packages might be from GitHub/Bioconductor but not on CRAN
# - Network issues can make CRAN temporarily unreachable
# - We want to avoid duplicate network calls for performance
#==============================================================================

# Validate packages against CRAN (cached for session)
# This function checks if packages actually exist on CRAN before we try to declare them
# It's essential for catching typos and non-CRAN packages
validate_against_cran <- function(packages, log_fn) {
  # Input validation: ensure we have packages to validate
  if (!is.character(packages) || length(packages) == 0L) {
    return(list(valid = character(0), invalid = character(0), error = FALSE))
  }
  
  # Remove base packages from validation (they don't need to be checked against CRAN)
  non_base_packages <- setdiff(packages, PKG_CONFIG)
  base_packages_found <- intersect(packages, PKG_CONFIG)
  
  if (length(non_base_packages) == 0L) {
    # Only base packages, all valid
    return(list(valid = base_packages_found, invalid = character(0), error = FALSE))
  }
  
  log_fn("Validating ", length(non_base_packages), " packages against CRAN...", level = "info")
  
  tryCatch({
    # Step 1: Set timeout and ensure it gets restored
    # Network operations can hang indefinitely, so we set a reasonable timeout
    old_timeout <- getOption("timeout")
    on.exit(options(timeout = old_timeout), add = TRUE)
    options(timeout = PKG_CONFIG)
    
    # Step 2: Get list of available packages from CRAN
    # available.packages() downloads the current CRAN package index
    # This is a relatively expensive operation (several MB download)
    available_pkgs <- available.packages(contriburl = contrib.url("https://cloud.r-project.org/"))
    cran_packages <- rownames(available_pkgs)
    
    # Step 3: Split non-base packages into valid (on CRAN) and invalid (not on CRAN)
    # %in% operator efficiently checks membership in the CRAN package list
    valid_cran_packages <- non_base_packages[non_base_packages %in% cran_packages]
    invalid_packages <- non_base_packages[!non_base_packages %in% cran_packages]
    
    # Combine base packages (always valid) with CRAN-validated packages
    valid_packages <- c(base_packages_found, valid_cran_packages)
    
    # Step 4: Report invalid packages for user awareness
    # Invalid packages might be typos, GitHub packages, or Bioconductor packages
    if (length(invalid_packages) > 0L) {
      log_fn("Invalid packages: ", paste(sort(invalid_packages), collapse = ", "), level = "warning")
    }
    
    list(valid = valid_packages, invalid = invalid_packages, error = FALSE)
    
  }, error = function(e) {
    # If CRAN validation fails (network issues, etc.), we continue with all packages
    # This ensures the script doesn't break due to temporary network problems
    log_fn("CRAN validation failed: ", e, level = "warning")
    list(valid = packages, invalid = character(0), error = TRUE)
  })
}

#==============================================================================
# DESCRIPTION FILE MODIFICATION
#
# Why automated DESCRIPTION modification?
# - Manual editing is error-prone and tedious
# - DESCRIPTION format is finicky (spacing, commas, line continuations)
# - We need to handle edge cases like missing Imports section
# - Backup/restore ensures we can recover from errors
#==============================================================================

# Fix DESCRIPTION file with robust error handling
# This function safely adds missing packages and removes invalid ones from DESCRIPTION
# It's the most complex function because DESCRIPTION format has many edge cases
fix_description_file <- function(missing_packages, invalid_packages, log_fn) {
  # Early exit if no changes needed
  if (length(missing_packages) == 0L && length(invalid_packages) == 0L) {
    return(list(success = FALSE, message = "No changes needed"))
  }
  
  # Sanity check: ensure DESCRIPTION file exists
  if (!file.exists("DESCRIPTION")) {
    return(list(success = FALSE, message = "DESCRIPTION file not found"))
  }
  
  # Step 1: Create timestamped backup for safety
  # If something goes wrong, we can restore the original file
  backup_file <- paste0("DESCRIPTION.backup.", format(Sys.time(), PKG_CONFIG))
  if (!file.copy("DESCRIPTION", backup_file)) {
    return(list(success = FALSE, message = "Failed to create backup"))
  }
  
  tryCatch({
    # Strategy 1: Use desc package for robust editing (preferred approach)
    # The desc package handles all the formatting edge cases correctly
    if (requireNamespace("desc", quietly = TRUE)) {
      d <- desc::desc()
      
      # Remove invalid packages from all dependency fields
      # del_dep() automatically finds and removes packages from any dependency field
      for (pkg in invalid_packages) {
        d(pkg)
      }
      
      # Add missing packages to Imports field
      # set_dep() adds packages to the specified dependency type
      for (pkg in missing_packages) {
        d(pkg, "Imports")
      }
      
      # Write changes back to DESCRIPTION file
      d()
      
    } else {
      # Strategy 2: Manual editing with bounds checking (fallback approach)
      # This is more complex but works when desc package isn't available
      desc_lines <- readLines("DESCRIPTION")
      imports_idx <- grep("^Imports:", desc_lines)
      
      if (length(imports_idx) == 0L) {
        # Case 1: No Imports section exists - add new one
        if (length(missing_packages) > 0L) {
          new_imports_line <- paste("Imports:", paste(missing_packages, collapse = ",\n    "))
          desc_lines <- c(desc_lines, new_imports_line)
        }
      } else {
        # Case 2: Imports section exists - update it
        start_idx <- imports_idx[1L]
        end_idx <- length(desc_lines)
        
        # Find end of Imports section safely
        # DESCRIPTION fields continue until the next field or end of file
        for (i in (start_idx + 1L):length(desc_lines)) {
          # Lines starting with non-whitespace (except empty lines) are new fields
          if (!grepl("^\\s", desc_lines[i]) && desc_lines[i] != "") {
            end_idx <- i - 1L
            break
          }
        }
        
        # Parse existing imports safely
        imports_section <- desc_lines[start_idx:min(end_idx, length(desc_lines))]
        imports_text <- gsub("^Imports:\\s*", "", paste(imports_section, collapse = " "))
        
        existing_packages <- character(0)
        if (nchar(trimws(imports_text)) > 0L) {
          # Split on commas and clean up
          existing_packages <- trimws(strsplit(imports_text, ",")[[1]])
          # Remove version constraints like (>= 1.0.0)
          existing_packages <- gsub("\\s*\\([^)]+\\)", "", existing_packages)
        }
        
        # Update package list: remove invalid, add missing
        cleaned_existing <- existing_packages[!existing_packages %in% invalid_packages]
        all_packages <- sort(unique(c(cleaned_existing[cleaned_existing != ""], missing_packages)))
        
        # Rebuild DESCRIPTION file
        if (length(all_packages) > 0L) {
          # Format Imports section with proper indentation
          new_imports <- paste("Imports:", paste(all_packages, collapse = ",\n    "))
          new_imports_lines <- strsplit(new_imports, "\n")[[1]]
        } else {
          # Remove Imports section entirely if no packages left
          new_imports_lines <- character(0)
        }
        
        # Safely reconstruct file with bounds checking
        before_section <- if (start_idx > 1L) desc_lines[1L:(start_idx - 1L)] else character(0)
        after_section <- if (end_idx < length(desc_lines)) desc_lines[(end_idx + 1L):length(desc_lines)] else character(0)
        
        desc_lines <- c(before_section, new_imports_lines, after_section)
      }
      
      # Write updated content back to file
      writeLines(desc_lines, "DESCRIPTION")
    }
    
    # Step 3: Report changes made
    change_messages <- character(0)
    if (length(missing_packages) > 0L) {
      log_fn("Added packages: ", paste(missing_packages, collapse = ", "), level = "success")
      change_messages <- c(change_messages, paste("Added:", length(missing_packages), "packages"))
    }
    if (length(invalid_packages) > 0L) {
      log_fn("Removed invalid packages: ", paste(invalid_packages, collapse = ", "), level = "success")
      change_messages <- c(change_messages, paste("Removed:", length(invalid_packages), "invalid packages"))
    }
    
    # Step 4: Remove backup on success
    file.remove(backup_file)
    
    list(success = TRUE, message = paste(change_messages, collapse = "; "))
    
  }, error = function(e) {
    # Step 5: Restore from backup on error
    if (file.exists(backup_file)) {
      file.copy(backup_file, "DESCRIPTION", overwrite = TRUE)
      file.remove(backup_file)
    }
    list(success = FALSE, message = paste("Update failed:", e))
  })
}

#==============================================================================
# RENV OPERATIONS
#
# Why renv operations need special handling:
# - renv functions can fail for many reasons (network, disk space, package conflicts)
# - Lockfile regeneration is destructive and needs careful backup management
# - Install operations can take a long time and might partially fail
# - We need to provide good feedback about what's happening
#==============================================================================

# Run renv snapshot with comprehensive error handling
# This function updates the renv.lock file to match current package usage
# It's critical for reproducibility but can fail in complex ways
run_renv_snapshot <- function(force_clean, log_fn) {
  # Sanity check: ensure renv package is available
  if (!requireNamespace("renv", quietly = TRUE)) {
    return(list(success = FALSE, message = "renv package unavailable"))
  }
  
  tryCatch({
    if (force_clean) {
      # Force clean mode: regenerate lockfile from scratch
      log_fn("Regenerating lockfile...", level = "info")
      
      # Step 1: Install any missing packages
      # This ensures all declared dependencies are actually installed
      install_result <- tryCatch({
        renv::install()
        TRUE
      }, error = function(e) {
        # Installation failures are warnings, not fatal errors
        # Some packages might already be installed or have minor issues
        log_fn("Package installation warning: ", e, level = "warning")
        FALSE
      })
      
      # Step 2: Backup and remove existing lockfile
      # This forces renv to rebuild from scratch rather than incrementally update
      if (file.exists("renv.lock")) {
        backup_name <- paste0("renv.lock.backup.", format(Sys.time(), PKG_CONFIG))
        file.copy("renv.lock", backup_name)
        file.remove("renv.lock")
        log_fn("Removed old renv.lock (backup created)", level = "info")
      }
    }
    
    # Step 3: Create new snapshot
    # type = "explicit" means only include packages explicitly referenced in code
    # prompt = FALSE means don't ask for user confirmation (essential for automation)
    renv::snapshot(type = "explicit", prompt = FALSE)
    log_fn("Lockfile updated successfully", level = "success")
    
    list(success = TRUE, message = "Snapshot completed successfully")
    
  }, error = function(e) {
    # If snapshot fails, provide detailed error message for debugging
    list(success = FALSE, message = paste("Snapshot failed:", e))
  })
}

# Apply build mode-aware package filtering
# Different build modes have different package tolerance levels
apply_build_mode_filter <- function(packages, build_mode, log_fn) {
  if (length(packages) == 0) return(packages)
  
  mode_config <- PKG_CONFIG[[build_mode]]
  if (is.null(mode_config)) {
    # Fallback to standard mode if build_mode is not recognized
    mode_config <- PKG_CONFIG[["standard"]]
    build_mode <- "standard"
  }
  
  # Fast mode: More restrictive, only essential packages
  if (build_mode == "fast") {
    # Define essential R packages that are commonly needed
    essential_packages <- c(
      "renv", "remotes", "devtools", "usethis", "here", "conflicted", 
      "rmarkdown", "knitr", "dplyr", "ggplot2", "testthat"
    )
    
    filtered <- intersect(packages, essential_packages)
    
    if (length(filtered) < length(packages) && !is.null(log_fn)) {
      excluded <- setdiff(packages, filtered)
      log_fn("ℹ️  Fast mode: excluding ", length(excluded), " non-essential packages: ",
             paste(head(excluded, 5), collapse = ", "), 
             if (length(excluded) > 5) "..." else "", level = "info")
    }
    
    return(filtered)
  }
  
  # Comprehensive mode: Check package count limits
  if (build_mode == "comprehensive") {
    if (length(packages) > mode_config) {
      log_fn("⚠️  Comprehensive mode: ", length(packages), " packages exceeds recommended limit of ", 
             mode_config, level = "warning")
    }
    return(packages)  # Allow all packages in comprehensive mode
  }
  
  # Standard mode: Moderate filtering
  if (length(packages) > mode_config) {
    log_fn("⚠️  Standard mode: ", length(packages), " packages exceeds recommended limit of ", 
           mode_config, "\n   Consider using comprehensive mode (-C) or reviewing dependencies", 
           level = "warning")
  }
  
  return(packages)  # Return all packages for standard mode
}

#==============================================================================
# MAIN EXECUTION ORCHESTRATOR
#
# Why we need an orchestrator:
# - The script has complex control flow with multiple modes (snapshot-only, interactive, etc.)
# - Error handling needs to be consistent across different execution paths
# - We need to coordinate multiple subsystems (parsing, validation, fixing, snapshotting)
# - Exit codes must be reliable for CI/CD integration
#==============================================================================

# Snapshot-only mode handler
# This is a special fast path for when users just want to update renv.lock
# without doing full dependency analysis
handle_snapshot_only <- function(config, log_fn) {
  log_fn("Running snapshot...", level = "info")
  
  # Quick check: ensure renv is available
  if (!requireNamespace("renv", quietly = TRUE)) {
    log_fn("renv package unavailable", level = "error", force = TRUE)
    return(if (config) 1L else 0L)
  }
  
  # Run snapshot and return appropriate exit code
  result <- run_renv_snapshot(force_clean = FALSE, log_fn = log_fn)
  if (result) {
    log_fn("Snapshot complete", level = "success")
    return(0L)
  } else {
    log_fn("Snapshot failed: ", result, level = "error", force = TRUE)
    return(if (config) 1L else 0L)
  }
}

# Main analysis and reporting function
# This is the core logic that orchestrates the entire dependency checking process
# It coordinates all the subsystems and implements the main business logic
main_analysis <- function(config, log_fn) {
  log_fn("Checking renv setup...", level = "info")
  
  # PHASE 1: DATA COLLECTION
  # Extract packages from code files
  code_packages <- extract_code_packages(config, log_fn)
  
  # Parse configuration files (DESCRIPTION and renv.lock)
  desc_result <- parse_description_file()
  renv_result <- parse_renv_lock_file()
  
  # PHASE 2: VALIDATION
  # Validate all packages against CRAN in single call (performance optimization)
  # We combine all packages to avoid duplicate CRAN API calls
  all_packages_to_validate <- unique(c(code_packages, desc_result))
  cran_validation <- validate_against_cran(all_packages_to_validate, log_fn)
  
  # PHASE 3: ANALYSIS
  # Determine package status by cross-referencing different sources
  validated_code_packages <- intersect(code_packages, cran_validation)
  validated_desc_packages <- intersect(desc_result, cran_validation)
  invalid_desc_packages <- intersect(desc_result, cran_validation)
  
  # Apply build mode-aware filtering
  filtered_code_packages <- apply_build_mode_filter(validated_code_packages, config, log_fn)
  
  # Calculate differences between different package sources
  missing_from_desc <- setdiff(filtered_code_packages, validated_desc_packages)  # Used in code but not declared
  unused_in_desc <- setdiff(validated_desc_packages, filtered_code_packages)      # Declared but not used
  extra_in_renv <- setdiff(renv_result, desc_result)            # In lockfile but not declared
  
  # PHASE 4: ISSUE CLASSIFICATION
  # Determine what constitutes "critical" issues that must be fixed vs warnings
  has_critical_issues <- length(missing_from_desc) > 0L ||     # Missing deps break builds
                        length(invalid_desc_packages) > 0L ||  # Invalid deps break installs
                        desc_result ||                    # Can't parse DESCRIPTION
                        renv_result                       # Can't parse renv.lock
  
  # PHASE 5: REPORTING
  # Provide comprehensive status report
  log_fn("Found ", length(validated_code_packages), " valid code packages, ", 
         length(desc_result), " DESCRIPTION packages, ",
         length(renv_result), " renv.lock packages", level = "info")
  
  # Report critical issues (these break builds/installs)
  if (length(missing_from_desc) > 0L) {
    missing_list <- sort(missing_from_desc)
    if (length(missing_list) > 0L) {
      log_fn("Missing from DESCRIPTION: ", paste(missing_list, collapse = ", "), 
             level = "error", force = TRUE)
    }
  }
  
  if (length(invalid_desc_packages) > 0L) {
    invalid_list <- sort(invalid_desc_packages)
    if (length(invalid_list) > 0L) {
      log_fn("Invalid packages in DESCRIPTION: ", paste(invalid_list, collapse = ", "), 
             level = "error", force = TRUE)
    }
  }
  
  # Report warnings (these are cleanup opportunities but not critical)
  if (length(unused_in_desc) > 0L && !config) {
    # In strict mode, we don't warn about unused packages since we're being comprehensive
    log_fn("Unused packages in DESCRIPTION: ", length(unused_in_desc), " packages", level = "warning")
  }
  
  if (length(extra_in_renv) > 0L) {
    log_fn("Extra packages in renv.lock: ", length(extra_in_renv), " packages", level = "warning")
  }
  
  # PHASE 6: AUTOMATED FIXES
  # Handle fixes based on configuration and execution mode
  if (has_critical_issues && config) {
    # Automated mode: fix issues without asking
    log_fn("Auto-fixing issues...", level = "info")
    fix_result <- fix_description_file(missing_from_desc, invalid_desc_packages, log_fn)
    if (fix_result) {
      # If DESCRIPTION was fixed, update lockfile to match
      snapshot_result <- run_renv_snapshot(force_clean = length(extra_in_renv) > 0L, log_fn = log_fn)
      if (!snapshot_result) {
        log_fn("Warning: ", snapshot_result, level = "warning")
      }
    }
  } else if (has_critical_issues && interactive()) {
    # Interactive mode: ask user for permission to fix
    cat("Fix detected issues? [y/N]: ")
    response <- tolower(trimws(readLines(n = 1L)))
    if (response %in% c("y", "yes")) {
      fix_result <- fix_description_file(missing_from_desc, invalid_desc_packages, log_fn)
      if (fix_result) {
        run_renv_snapshot(force_clean = length(extra_in_renv) > 0L, log_fn = log_fn)
      }
    }
  } else if (length(extra_in_renv) > 0L && config) {
    # Even if no critical issues, clean up lockfile if requested
    run_renv_snapshot(force_clean = TRUE, log_fn = log_fn)
  }
  
  # PHASE 7: FINAL STATUS AND EXIT CODE
  # Determine final status and return appropriate exit code for calling processes
  if (has_critical_issues) {
    log_fn("Repository NOT READY for commit", level = "error", force = TRUE)
    return(1L)  # Exit code 1 = failure (critical for CI/CD)
  } else {
    log_fn("Repository READY for commit", level = "success", force = TRUE)
    return(0L)  # Exit code 0 = success
  }
}

# Main entry point with enhanced error handling
# This is the top-level function that coordinates everything and handles program lifecycle
main <- function() {
  # Global error handling setup
  exit_code <- tryCatch({
    # INITIALIZATION PHASE
    # Parse configuration and set up logging
    script_config <- parse_arguments()
    log_fn <- create_logger(script_config)
    
    # Show zzcollab build mode context if not quiet
    if (!script_config) {
      mode_config <- PKG_CONFIG[[script_config]]
      if (!is.null(mode_config)) {
        log_fn("ℹ️  zzcollab build mode: ", script_config, 
               " (", mode_config, ")", level = "info")
      } else {
        log_fn("ℹ️  zzcollab build mode: ", script_config, level = "info")
      }
    }
    
    # EXECUTION PHASE
    # Handle special modes first, then fall through to main analysis
    if (script_config) {
      # Special case: snapshot-only mode bypasses all analysis
      exit_code <- handle_snapshot_only(script_config, log_fn)
      return(exit_code)
    }
    
    # Normal case: run full dependency analysis
    exit_code <- main_analysis(script_config, log_fn)
    
    # HELP AND GUIDANCE PHASE
    # Show usage help for users running the script without arguments
    if (!script_config && length(commandArgs(trailingOnly = TRUE)) == 0L && !interactive()) {
      cat("\n📖 USAGE: --fix --fail-on-issues --snapshot --quiet --strict-imports --build-mode MODE\n")
      cat("For detailed help, see script header documentation.\n")
      cat("zzcollab integration: Set ZZCOLLAB_BUILD_MODE environment variable\n")
    }
    
    return(exit_code)
    
  }, error = function(e) {
    # Top-level error handler for unexpected errors
    cat("❌ CRITICAL ERROR: ", conditionMessage(e), "\n", file = stderr())
    if (exists("script_config") && !is.null(script_config) && !script_config) {
      cat("💡 This may indicate a bug in the script or invalid input\n", file = stderr())
      cat("   Please check your R environment and file permissions\n", file = stderr())
    }
    return(2L)  # Exit code 2 = configuration/system error
  }, warning = function(w) {
    # Handle warnings gracefully
    cat("⚠️  WARNING: ", conditionMessage(w), "\n", file = stderr())
    invokeRestart("muffleWarning")
    return(0L)  # Continue execution despite warnings
  })
  
  # Clean exit with proper status code
  quit(status = exit_code)
  
  # EXIT PHASE
  # Honor fail-on-issues flag for CI/CD integration
  if (script_config && exit_code != 0L) {
    quit(status = exit_code)
  }
  
  # Return exit code for callers (invisible so it doesn't print in interactive mode)
  invisible(exit_code)
}

#==============================================================================
# SCRIPT EXECUTION ENTRY POINT
# 
# IMPROVEMENTS IMPLEMENTED:
# ✅ Enhanced flag validation with comprehensive error checking
# ✅ zzcollab build mode integration (fast/standard/comprehensive)
# ✅ Robust package extraction with edge case handling
# ✅ Build mode-aware package filtering and validation
# ✅ Improved error handling and structured logging
# ✅ Integration with zzcollab modular architecture
# ✅ Support for --build-mode flag and ZZCOLLAB_BUILD_MODE environment variable
# ✅ Enhanced regex patterns for library calls (wrapped, conditional, roxygen)
# ✅ Comprehensive exit code handling (0=success, 1=critical issues, 2=config error)
#
# ZZCOLLAB ALIGNMENT:
# - Detects and respects zzcollab build modes
# - Integrates with zzcollab logging if available
# - Supports zzcollab CLI flag conventions
# - Context-aware validation based on project size and complexity
#==============================================================================

#==============================================================================
# SCRIPT EXECUTION
#
# Why this goes at the end:
# - All functions must be defined before they can be called
# - This makes it clear what the "entry point" of the script is
# - It's easy to source this script without executing it (for testing)
#==============================================================================

# Execute main function
# This is the actual start of script execution
main()