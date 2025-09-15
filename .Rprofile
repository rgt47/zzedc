# Activate renv for this project
if (file.exists("renv/activate.R")) {
  source("renv/activate.R")
}

# Set CRAN mirror
options(repos = c(CRAN = "https://cloud.r-project.org"))

# Load common packages for interactive use
if (interactive()) {
  suppressMessages({
    if (requireNamespace("devtools", quietly = TRUE)) library(devtools)
    if (requireNamespace("usethis", quietly = TRUE)) library(usethis)
  })
}
