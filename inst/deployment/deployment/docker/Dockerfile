# ZZedc Docker Image
# Multi-stage build for smaller final image
#
# Build: docker build -t zzedc:latest -f deployment/docker/Dockerfile .
# Run:   docker run -p 3838:3838 -e DB_ENCRYPTION_KEY=... zzedc:latest

# =============================================================================
# Stage 1: Build Environment
# =============================================================================
FROM rocker/shiny:4.4.0 AS builder

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl-dev \
    libcurl4-openssl-dev \
    libxml2-dev \
    libsodium-dev \
    libsqlite3-dev \
    sqlcipher \
    libsqlcipher-dev \
    && rm -rf /var/lib/apt/lists/*

# Install R packages
RUN R -e "install.packages(c( \
    'shiny', \
    'bslib', \
    'bsicons', \
    'DBI', \
    'RSQLite', \
    'DT', \
    'ggplot2', \
    'dplyr', \
    'tidyr', \
    'jsonlite', \
    'digest', \
    'openssl', \
    'writexl', \
    'yaml', \
    'htmltools', \
    'httpuv' \
), repos='https://cran.rstudio.com/')"

# =============================================================================
# Stage 2: Production Image
# =============================================================================
FROM rocker/shiny:4.4.0

# Copy R packages from builder
COPY --from=builder /usr/local/lib/R/site-library /usr/local/lib/R/site-library

# Install runtime dependencies only
RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl3 \
    libcurl4 \
    libxml2 \
    libsodium23 \
    libsqlite3-0 \
    sqlcipher \
    && rm -rf /var/lib/apt/lists/*

# Create application directory
WORKDIR /srv/shiny-server/zzedc

# Copy application files
COPY ui.R server.R global.R ./
COPY R/ ./R/
COPY config.yml ./
COPY forms/ ./forms/

# Create data directory
RUN mkdir -p /data && chown shiny:shiny /data

# Set permissions
RUN chown -R shiny:shiny /srv/shiny-server/zzedc

# Configure Shiny Server
COPY deployment/docker/shiny-server.conf /etc/shiny-server/shiny-server.conf

# Environment variables
ENV ZZEDC_DB_PATH=/data/zzedc.db
ENV SHINY_LOG_LEVEL=INFO

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:3838/ || exit 1

# Expose Shiny Server port
EXPOSE 3838

# Run as non-root user
USER shiny

# Start Shiny Server
CMD ["/usr/bin/shiny-server"]
