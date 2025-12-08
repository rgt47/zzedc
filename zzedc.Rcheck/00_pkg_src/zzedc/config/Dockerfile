ARG BASE_IMAGE=rocker/r-ver
ARG R_VERSION=latest
FROM rocker/r-ver:latest

# ZZedc EDC System - zzcollab Framework Integration
# Build arguments for bundle and package selection
ARG BUNDLE_LIBS=edc_standard
ARG BUNDLE_PKGS=edc_core,edc_validation,edc_compliance
ARG PACKAGE_MODE=standard
ARG TEAM_NAME=rgt47
ARG PROJECT_NAME=zzedc
ARG ADDITIONAL_PACKAGES=""
ARG USERNAME=analyst

# Install system dependencies (common to all modes)
RUN apt-get update && \
    apt-get install -y \
    git \
    ssh \
    curl \
    wget \
    vim \
    tmux \
    zsh \
    build-essential \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libfontconfig1-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libfreetype6-dev \
    libpng-dev \
    libtiff5-dev \
    libjpeg-dev \
    libgit2-dev \
    man-db \
    pandoc \
    tree \
    ripgrep \
    eza \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js (required for coc.nvim and other vim plugins)
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - && \
    apt-get install -y nodejs

# Install TinyTeX (skip if using base images that already have LaTeX
# support)
RUN if echo "rocker/r-ver" | grep -E "^rocker/(r-ver|rstudio)" \
     >/dev/null; then \
        R -e "install.packages('tinytex')" && \
        R -e "tinytex::install_tinytex()" && \
        /root/.TinyTeX/bin/*/tlmgr path add; \
    elif echo "rocker/r-ver" | grep -v -E "(verse|tidyverse)" \
         >/dev/null; then \
        R -e "install.packages('tinytex')" && \
        R -e "tinytex::install_tinytex()" && \
        /root/.TinyTeX/bin/*/tlmgr path add; \
    fi

# Add metadata labels
LABEL maintainer="rgt47"
LABEL project="zzedc"
LABEL package.mode="standard"
LABEL bundle.libs="edc_standard"
LABEL bundle.pkgs="edc_core,edc_validation,edc_compliance"
LABEL org.opencontainers.image.title="ZZedc - Electronic Data Capture System"
LABEL org.opencontainers.image.description="Production-ready R/Shiny EDC with \
       clinical trial validation DSL, zzcollab framework integration"
LABEL org.opencontainers.image.vendor="ZZCOLLAB"
LABEL org.opencontainers.image.version="1.0.0"
LABEL org.opencontainers.image.source="https://github.com/zzcollab/zzedc"
LABEL org.opencontainers.image.documentation="https://zzcollab.github.io/zzedc"

# Create non-root user with zsh as default shell
# Always create the user since we reference it throughout the Dockerfile
RUN useradd --create-home --shell /bin/zsh analyst || \
    echo "User analyst already exists"

# Install R packages based on PACKAGE_MODE
# fast/minimal: Only essential packages (renv, remotes)
# standard: Essential packages + common development tools
# comprehensive: Full development stack with analysis packages
RUN if [ "" = "fast" ] || \
       [ "" = "minimal" ]; then \
        # Fast mode: minimal packages only \
        if echo "rocker/r-ver" | grep -E "^rocker/(r-ver|rstudio)" \
           >/dev/null; then \
            R -e "install.packages(c('renv', 'remotes'), \
                 repos = c(CRAN = 'https://cloud.r-project.org'))"; \
        fi; \
    elif [ "" = "comprehensive" ] || \
         [ "" = "pluspackages" ]; then \
        # Comprehensive mode: full package suite \
        R -e "base_packages <- c( \
            'renv', 'remotes', 'devtools', 'testthat', 'usethis', \
            'pkgdown', 'rcmdcheck', 'tidyverse', 'here', 'conflicted', \
            'broom', 'lme4', 'survival', 'car', 'janitor', 'naniar', \
            'skimr', 'visdat', 'ggthemes', 'kableExtra', 'DT', \
            'rmarkdown', 'bookdown', 'knitr', 'jsonlite', 'targets', \
            'datapasta' \
        ); \
        additional_packages <- if(nzchar('')) \
            strsplit('', ' ')[[1]] else \
            character(0); \
        all_packages <- c(base_packages, additional_packages); \
        install.packages(all_packages, \
            repos = c(CRAN = 'https://cloud.r-project.org'))"; \
    else \
        # Standard mode: essential development packages \
        if echo "rocker/r-ver" | grep -E "^rocker/(r-ver|rstudio)" \
           >/dev/null; then \
            R -e "install.packages(c('renv', 'remotes', 'devtools', \
                 'usethis', 'here', 'conflicted', 'rmarkdown', 'knitr'), \
                 repos = c(CRAN = 'https://cloud.r-project.org'))"; \
        fi; \
    fi

# Give user write permission to R library directory
RUN chown -R analyst:analyst /usr/local/lib/R/site-library

# Set working directory and ensure user owns it
WORKDIR /home/analyst/project
RUN chown -R analyst:analyst /home/analyst/project

# Copy project files first (for better Docker layer caching)
COPY --chown=analyst:analyst DESCRIPTION .
COPY --chown=analyst:analyst renv.lock* ./
COPY --chown=analyst:analyst .Rprofile* ./
COPY --chown=analyst:analyst setup_renv.R* ./

# Switch to non-root user for R package installation
USER analyst

# Copy dotfiles (consolidated with wildcards)
COPY --chown=analyst:analyst .vimrc* .tmux.conf* .gitconfig* \
     .inputrc* .bashrc* .profile* .aliases* .functions* .exports* \
     .editorconfig* .ctags* .ackrc* .ripgreprc* /home/analyst/
COPY --chown=analyst:analyst .zshrc_docker /home/analyst/.zshrc

# Install zsh plugins
RUN mkdir -p /home/analyst/.zsh && \
    git clone https://github.com/zsh-users/zsh-autosuggestions \
     /home/analyst/.zsh/zsh-autosuggestions && \
    git clone https://github.com/zsh-users/zsh-syntax-highlighting \
     /home/analyst/.zsh/zsh-syntax-highlighting

# Install vim-plug
RUN curl -fLo /home/analyst/.vim/autoload/plug.vim --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim

# Install vim plugins (suppress interactive mode)
RUN vim +PlugInstall +qall || true

# Copy rest of project
COPY --chown=analyst:analyst . .

# Install the research compendium as a package (analyst has write
# permissions)
# Use standard R installation approach that works with any R setup
RUN R -e "install.packages('.', repos = NULL, type = 'source', \
           dependencies = TRUE)"

# Set default shell and working directory
WORKDIR /home/analyst/project
CMD ["/bin/zsh"]

# zzcollab Bundle System Integration
# This Dockerfile supports profile-based builds via bundles.yaml
#
# Build with different profiles:
#   docker build --build-arg BUNDLE_LIBS=edc_minimal -t zzedc:minimal .
#   docker build --build-arg BUNDLE_LIBS=edc_standard -t zzedc:standard .
#   docker build --build-arg BUNDLE_LIBS=edc_analysis -t zzedc:analysis .
#   docker build --build-arg BUNDLE_LIBS=edc_development -t zzedc:dev .
#
# Profile definitions are in bundles.yaml
# Configuration is in config.yaml
# See PACKAGE_STRUCTURE.md for details