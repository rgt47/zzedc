# syntax=docker/dockerfile:1.4
#======================================================================
# ZZCOLLAB Docker Environment
#======================================================================
# Generated dynamically from: base image + R packages
# System dependencies auto-derived from R package requirements
# Packages installed from renv.lock at build time (using Posit PPM binaries)
#
# Build: docker build -t zzedc .
#======================================================================

ARG BASE_IMAGE=rocker/r-ver
ARG R_VERSION=4.4.2
ARG USERNAME=analyst

FROM rocker/r-ver:4.5.1

ARG USERNAME=analyst
ARG DEBIAN_FRONTEND=noninteractive

# Reproducibility environment
# RENV_CONFIG_REPOS_OVERRIDE forces renv to use Posit PPM binaries (fast installs)
ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    TZ=UTC \
    RENV_PATHS_CACHE=/renv/cache \
    RENV_CONFIG_REPOS_OVERRIDE="https://packagemanager.posit.co/cran/__linux__/noble/latest" \
    ZZCOLLAB_CONTAINER=true

# System dependencies (auto-derived from R packages)
# Packages: bsicons bslib config digest dplyr...
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    set -ex && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential pkg-config \
        libcurl4-openssl-dev libssl-dev libxml2-dev \
        libcurl4-openssl-dev libsqlite3-dev && \
    rm -rf /var/lib/apt/lists/*

# Configure R to use Posit Package Manager for pre-compiled Linux binaries
# This dramatically speeds up package installation (seconds vs minutes)
RUN echo 'options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/noble/latest"))' \
        >> /usr/local/lib/R/etc/Rprofile.site && \
    echo 'options(HTTPUserAgent = sprintf("R/%s R (%s)", getRversion(), paste(getRversion(), R.version["platform"], R.version["arch"], R.version["os"])))' \
        >> /usr/local/lib/R/etc/Rprofile.site

# Install renv from PPM (binary)
RUN R -e "install.packages('renv')"

# Create renv cache directory
RUN mkdir -p /renv/cache && chmod 777 /renv/cache

# Copy lockfile and restore packages using PPM binaries
# RENV_CONFIG_REPOS_OVERRIDE ensures renv uses PPM instead of lockfile repos
COPY renv.lock renv.lock
RUN R -e "renv::restore()"

# Development tools (pandoc, tinytex, languageserver as needed for base image)
# Install pandoc for document rendering
RUN apt-get update && apt-get install -y --no-install-recommends pandoc && rm -rf /var/lib/apt/lists/*

# Install tinytex for PDF output
RUN R -e "install.packages('tinytex')" && R -e "tinytex::install_tinytex()"

# Install languageserver for IDE support
RUN R -e "install.packages('languageserver')"

# Create non-root user
RUN useradd --create-home --shell /bin/bash ${USERNAME} && \
    chown -R ${USERNAME}:${USERNAME} /usr/local/lib/R/site-library && \
    mkdir -p /home/${USERNAME}/.cache/R/renv && \
    chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.cache

USER ${USERNAME}
WORKDIR /home/${USERNAME}/project

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=2 \
    CMD R --quiet --slave -e "quit(status = 0)" || exit 1

# Project files mounted at runtime: -v $(pwd):/home/analyst/project
CMD ["R", "--quiet"]
