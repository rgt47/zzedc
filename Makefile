# Makefile for zzedc research compendium
# Docker-first workflow for reproducible research

PACKAGE_NAME = zzedc
R_VERSION = latest

# Help target (default)
help:
	@echo "Available targets:"
	@echo "  Native R - requires local R installation:"
	@echo "    document, build, check, install, vignettes, test, deps"
	@echo "    check-renv, check-renv-fix, check-renv-ci"
	@echo ""
	@echo "  Docker - works without local R:"
	@echo "    docker-build, docker-document, docker-build-pkg, docker-check"
	@echo "    docker-test, docker-vignettes, docker-render, docker-check-renv"
	@echo "    docker-check-renv-fix, docker-r, docker-bash, docker-zsh, docker-rstudio"
	@echo ""
	@echo "  Cleanup:"
	@echo "    clean, clean-dotfiles, docker-clean, docker-build-clean"

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

# Docker targets (work without local R)
docker-build:
	DOCKER_BUILDKIT=1 docker build --build-arg R_VERSION=$(R_VERSION) -t $(PACKAGE_NAME) .

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
	docker run --rm -it -v $$(pwd):/project $(PACKAGE_NAME) /bin/zsh

docker-rstudio:
	@echo "Starting RStudio Server on http://localhost:8787"
	@echo "Username: analyst, Password: analyst"
	docker run --rm -p 8787:8787 -v $$(pwd):/project -e USER=analyst -e PASSWORD=analyst $(PACKAGE_NAME) /init

# Cleanup
clean:
	rm -f *.tar.gz
	rm -rf *.Rcheck

clean-dotfiles:
	@echo "Cleaning up dotfiles from working directory..."
	@rm -f .vimrc .tmux.conf .gitconfig .inputrc .bashrc .profile .aliases .functions .exports .editorconfig .ctags .ackrc .ripgreprc .zshrc_docker 2>/dev/null || true
	@echo "Dotfiles cleanup complete (preserved in Docker image)"

docker-clean:
	docker rmi $(PACKAGE_NAME) || true

docker-build-clean: docker-build clean-dotfiles
	docker system prune -f

.PHONY: all document build check install vignettes test deps check-renv check-renv-fix check-renv-ci docker-build docker-document docker-build-pkg docker-check docker-test docker-vignettes docker-render docker-r docker-bash docker-zsh docker-rstudio docker-check-renv docker-check-renv-fix clean clean-dotfiles docker-clean docker-build-clean help
