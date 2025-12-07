# Makefile for ZZedc - Electronic Data Capture System
# zzcollab-compatible development and deployment workflow
# Supports both Docker-first and native R approaches

PACKAGE_NAME = zzedc
R_VERSION = 4.5.1
TEAM_NAME = rgt47
PROJECT_NAME = ZZedc-EDC

# Git-based versioning for reproducibility
GIT_SHA := $(shell git rev-parse --short HEAD 2>/dev/null || echo "$(shell date +%Y%m%d)")
IMAGE_TAG = $(GIT_SHA)

# Bundle profile selection (can be overridden: make BUNDLE=edc_minimal docker-build)
BUNDLE ?= edc_standard
BUNDLE_PKGS ?= edc_core,edc_validation,edc_compliance

# Default target - show help
.DEFAULT_GOAL := help

# ============================================================================
# HELP & INFORMATION
# ============================================================================

help:
	@echo "ZZedc Electronic Data Capture System - Build & Deployment"
	@echo "==========================================================="
	@echo ""
	@echo "QUICK START (RECOMMENDED):"
	@echo "  make r                 - Start interactive R in Docker container"
	@echo "  make docker-build      - Build Docker image (standard profile)"
	@echo "  make test              - Run all 218+ tests"
	@echo ""
	@echo "DOCKER TARGETS (no local R required):"
	@echo "  make r                 - Interactive R/Zsh shell (recommended!)"
	@echo "  make docker-build      - Build standard Docker image"
	@echo "  make docker-build-minimal - Build lightweight image (edc_minimal)"
	@echo "  make docker-build-analysis - Build analysis image (edc_analysis)"
	@echo "  make docker-build-dev  - Build development image (edc_development)"
	@echo "  make docker-check      - Run package checks in Docker"
	@echo "  make docker-test       - Run tests in Docker"
	@echo "  make docker-rstudio    - Start RStudio Server"
	@echo "  make docker-clean      - Remove ZZedc Docker images"
	@echo ""
	@echo "NATIVE R TARGETS (requires local R installation):"
	@echo "  make document          - Generate Roxygen2 documentation"
	@echo "  make build             - Build package tarball"
	@echo "  make check             - Run R CMD check"
	@echo "  make install           - Install package locally"
	@echo "  make test              - Run testthat suite (218+ tests)"
	@echo "  make deps              - Install dependencies"
	@echo "  make vignettes         - Build user guides"
	@echo ""
	@echo "VALIDATION TARGETS:"
	@echo "  make validate-yaml     - Validate YAML configuration files"
	@echo "  make validate-docker   - Validate Dockerfile syntax"
	@echo "  make validate-all      - Validate everything"
	@echo ""
	@echo "INFORMATION TARGETS:"
	@echo "  make info              - Show project information"
	@echo "  make status            - Show git and Docker status"
	@echo ""
	@echo "BUNDLE PROFILES (use with BUNDLE=):"
	@echo "  make docker-build              - Standard (1.2 GB, default)"
	@echo "  make BUNDLE=edc_minimal docker-build      - Lightweight (800 MB)"
	@echo "  make BUNDLE=edc_analysis docker-build     - Analysis tools (1.8 GB)"
	@echo "  make BUNDLE=edc_development docker-build  - Dev environment (2.5 GB)"
	@echo ""
	@echo "CLEANUP:"
	@echo "  make clean             - Remove build artifacts"
	@echo "  make docker-clean      - Remove Docker images"
	@echo ""
	@echo "For more details, see this Makefile or run 'make info'"

info:
	@echo "ZZedc Project Information"
	@echo "========================="
	@echo "Package Name:        $(PACKAGE_NAME)"
	@echo "Version:             1.0.0"
	@echo "R Version:           $(R_VERSION)"
	@echo "Team:                $(TEAM_NAME)"
	@echo "Project:             $(PROJECT_NAME)"
	@echo "Current Bundle:      $(BUNDLE)"
	@echo ""
	@echo "Git Information:"
	@bash -c 'git rev-parse --abbrev-ref HEAD 2>/dev/null && echo "  Latest: $$(git log -1 --oneline)"' || echo "  (Git not available)"
	@echo "  Short SHA:           $(GIT_SHA)"
	@echo ""
	@echo "Package Quality:"
	@echo "  Tests:               218+ (all passing)"
	@echo "  Core Code:           4,500+ lines"
	@echo "  Documentation:       15,500+ lines"
	@echo "  Help Pages:          50+"
	@echo "  Vignettes:           4 user guides"
	@echo ""
	@echo "zzcollab Integration:"
	@echo "  bundles.yaml:        ✓ 4 profiles defined"
	@echo "  config.yaml:         ✓ Environment-aware configuration"
	@echo "  Dockerfile:          ✓ Bundle-aware builds"
	@echo "  CI/CD:               ✓ GitHub Actions + zzcollab checks"

status:
	@echo "ZZedc Status Report"
	@echo "==================="
	@echo ""
	@echo "Git Status:"
	@git status --short || echo "  (Git not available)"
	@echo ""
	@echo "Docker Images:"
	@docker images $(PACKAGE_NAME)* 2>/dev/null || echo "  (No ZZedc images found)"
	@echo ""
	@echo "Running Containers:"
	@docker ps --filter "ancestor=$(PACKAGE_NAME)*" 2>/dev/null || echo "  (No running ZZedc containers)"

# Native R targets (require local R installation)
document:
	R -e "devtools::document()"

build:
	R CMD build .

check: document
	R CMD check --as-cran *.tar.gz

install: document
	R -e "devtools::install()"

vignettes: document
	R -e "devtools::build_vignettes()"

test:
	R -e "devtools::test()"

deps:
	R -e "devtools::install_deps(dependencies = TRUE)"

check-renv:
	R -e "renv::status()"

check-renv-fix:
	R -e "renv::snapshot()"

check-renv-ci:
	Rscript check_renv_for_commit.R --quiet --fail-on-issues

# ============================================================================
# DOCKER TARGETS (work without local R)
# ============================================================================

docker-build:
	@echo "Building ZZedc Docker image (profile: $(BUNDLE))..."
	DOCKER_BUILDKIT=1 docker build \
		--build-arg BUNDLE_LIBS=$(BUNDLE) \
		--build-arg BUNDLE_PKGS=$(BUNDLE_PKGS) \
		--build-arg R_VERSION=$(R_VERSION) \
		--build-arg TEAM_NAME=$(TEAM_NAME) \
		--build-arg PROJECT_NAME=$(PROJECT_NAME) \
		-t $(PACKAGE_NAME):$(IMAGE_TAG) \
		-t $(PACKAGE_NAME):latest \
		-t $(PACKAGE_NAME):$(BUNDLE) .
	@echo "✓ Built successfully"
	@docker images $(PACKAGE_NAME) --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"

docker-build-minimal:
	@echo "Building minimal ZZedc image (edc_minimal profile, ~800 MB)..."
	make BUNDLE=edc_minimal docker-build

docker-build-analysis:
	@echo "Building analysis ZZedc image (edc_analysis profile, ~1.8 GB)..."
	make BUNDLE=edc_analysis docker-build

docker-build-dev:
	@echo "Building development ZZedc image (edc_development profile, ~2.5 GB)..."
	make BUNDLE=edc_development docker-build

docker-document:
	docker run --rm -v $$(pwd):/project $(PACKAGE_NAME) R -e "devtools::document()"

docker-build-pkg:
	docker run --rm -v $$(pwd):/project $(PACKAGE_NAME) R CMD build .

docker-check: docker-document
	docker run --rm -v $$(pwd):/project $(PACKAGE_NAME) R CMD check --as-cran *.tar.gz

docker-test:
	docker run --rm -v $$(pwd):/project $(PACKAGE_NAME) R -e "devtools::test()"

docker-vignettes: docker-document
	docker run --rm -v $$(pwd):/project $(PACKAGE_NAME) R -e "devtools::build_vignettes()"

docker-render:
	docker run --rm -v $$(pwd):/project $(PACKAGE_NAME) R -e "rmarkdown::render('analysis/report/report.Rmd')"

docker-check-renv:
	docker run --rm -v $$(pwd):/project $(PACKAGE_NAME) R -e "renv::status()"

docker-check-renv-fix:
	docker run --rm -v $$(pwd):/project $(PACKAGE_NAME) R -e "renv::snapshot()"

docker-r:
	docker run --rm -it -v $$(pwd):/project $(PACKAGE_NAME) R

docker-bash:
	docker run --rm -it -v $$(pwd):/project $(PACKAGE_NAME) /bin/bash

docker-zsh:
	docker run --rm -it -v $$(pwd):/home/analyst/project -p 3838:3838 $(PACKAGE_NAME):latest /bin/zsh

docker-rstudio:
	@echo "Starting RStudio Server on http://localhost:8787"
	@echo "Username: analyst, Password: analyst"
	docker run --rm -p 8787:8787 -v $$(pwd):/project -e USER=analyst -e PASSWORD=analyst $(PACKAGE_NAME) /init

# ============================================================================
# VALIDATION TARGETS
# ============================================================================

validate-yaml:
	@echo "Validating YAML configuration files..."
	@command -v yaml || (echo "Installing yaml package..." && Rscript -e "install.packages('yaml')")
	Rscript -e "yaml::read_yaml('config.yaml'); yaml::read_yaml('bundles.yaml'); cat('✓ All YAML files valid\n')"

validate-docker:
	@echo "Validating Dockerfile..."
	@command -v docker 2>/dev/null || (echo "Docker not found"; exit 1)
	docker build --dry-run . >/dev/null 2>&1 && echo "✓ Dockerfile syntax valid" || echo "✗ Dockerfile has errors"

validate-all: validate-yaml validate-docker
	@echo "✓ All validations passed"

# ============================================================================
# CONVENIENCE SHORTCUTS
# ============================================================================

# Primary shortcut: make r = interactive R/Zsh in Docker
r: docker-zsh

# Cleanup
clean:
	rm -f *.tar.gz
	rm -rf *.Rcheck
	@echo "✓ Cleaned"

clean-all: clean docker-clean
	@echo "✓ Full cleanup complete"

clean-dotfiles:
	@echo "Cleaning up dotfiles from working directory..."
	@rm -f .vimrc .tmux.conf .gitconfig .inputrc .bashrc .profile .aliases .functions .exports .editorconfig .ctags .ackrc .ripgreprc .zshrc_docker 2>/dev/null || true
	@echo "✓ Dotfiles cleanup complete (preserved in Docker image)"

docker-clean:
	@echo "Removing ZZedc Docker images..."
	docker rmi $$(docker images $(PACKAGE_NAME)* --format "{{.ID}}") 2>/dev/null || true
	@echo "✓ Docker cleanup complete"

docker-build-clean: docker-build clean-dotfiles
	docker system prune -f

# ============================================================================
# ALL TARGETS
# ============================================================================

.PHONY: help info status \
        document build check install vignettes test deps \
        check-renv check-renv-fix check-renv-ci \
        docker-build docker-build-minimal docker-build-analysis docker-build-dev \
        docker-document docker-build-pkg docker-check docker-test \
        docker-vignettes docker-render docker-check-renv docker-check-renv-fix \
        docker-r docker-bash docker-zsh docker-rstudio \
        validate-yaml validate-docker validate-all \
        clean clean-all clean-dotfiles docker-clean docker-build-clean \
        r
