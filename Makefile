IMAGE_NAME := psyb0t/pibox
PKG        := pibox
# Single-source version derivation: pibox/pyproject.toml [project]
# version is THE source. awk reads it on the host (no Python dep
# needed just to read the version). __init__.py reads the same value
# at runtime via importlib.metadata. Override at build time for
# one-offs: `VERSION=0.10.1-rc1 make build`.
VERSION    ?= $(shell awk -F\" '/^version *= *"/ {print $$2; exit}' pibox/pyproject.toml)
TAG        := v$(VERSION)
# Default to the published base. Override with `make build BASE_IMAGE=...`
# if you need to test against a local fork of docker-aicodebox. Pin must
# match the Dockerfile's ARG default so `make build` (which pulls then
# builds) doesn't drift from a direct `docker build` invocation.
BASE_IMAGE ?= psyb0t/aicodebox:latest
FULL_BASE_IMAGE ?= psyb0t/aicodebox:latest-full

.PHONY: all build build-full build-all install install-full install-wrapper pull-base pull-full-base test test-wrapper-install clean help version pkg-lock lint lint-shell lint-python test-ci test-python docs

# Lint and CI tests run their tools in containers, so a host needs only
# Docker, Make, Bash and jq. The Python checks run in the published base
# image, which already carries the aicodebox package the adapter imports.
# Keep these pins in step with [dependency-groups] dev in pibox/pyproject.toml.
PY_DEV_TOOLS     := pytest==9.1.1 ruff==0.17.0 pyright==1.1.414
SHELLCHECK_IMAGE ?= koalaman/shellcheck:v0.11.0
SHELL_SOURCES    := $(shell find . -name '*.sh' -not -path './.*' -not -path '*/node_modules/*' -not -path '*/.venv/*' -not -name git-update.sh | sort) tests/fixtures/action/docker
DOCS_SITE        ?= .testing/docs-site

# $(call py_dev_run,<command>) runs <command> in pibox/ inside the base image
# with the repository mounted read-only.
define py_dev_run
docker run --rm --entrypoint bash \
	-e PYTHONDONTWRITEBYTECODE=1 \
	-v "$(CURDIR):/src:ro" -w /src/pibox \
	$(BASE_IMAGE) -c 'set -euo pipefail; \
		uv pip install --system --break-system-packages --quiet $(PY_DEV_TOOLS); \
		$(1)'
endef

all: build ## Build the pibox image on top of the published base

V ?=
export V
version: ## Print or synchronize version metadata without committing: make version V=X.Y.Z
	@set -eu; \
	if [ -z "$$V" ]; then printf '%s\n' "$(TAG)"; exit 0; fi; \
	printf '%s\n' "$$V" | LC_ALL=C grep -qE '^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.]+)?$$' || { echo "V must be semver X.Y.Z" >&2; exit 1; }; \
	(cd $(PKG) && uv version --no-sync "$$V"); \
	tmp=$$(mktemp); trap 'rm -f "$$tmp"' EXIT; \
	jq --arg v "$$V" '.version=$$v' .agents/.codex-plugin/plugin.json >"$$tmp"; \
	mv "$$tmp" .agents/.codex-plugin/plugin.json; \
	tmp=$$(mktemp); \
	sed -E "s|^readonly PIBOX_RELEASE_REF=.*|readonly PIBOX_RELEASE_REF=\"v$$V\"|" install.sh >"$$tmp"; \
	chmod 755 "$$tmp"; \
	mv "$$tmp" install.sh

.PHONY: test-entrypoint-identity
test-entrypoint-identity: ## Verify Git identity aliases against the shared container entrypoint
	bash tests/test_entrypoint_identity.sh

pkg-lock: ## Refresh the Python lockfile under the current dependency pins
	cd pibox && uv lock

pull-base: ## Pull the published aicodebox base image (SKIP_BASE_PULL=1 to use a locally-built base)
	@if [ "$${SKIP_BASE_PULL:-0}" = "1" ]; then \
		echo "[make] SKIP_BASE_PULL=1, using local $(BASE_IMAGE)"; \
		docker image inspect $(BASE_IMAGE) >/dev/null 2>&1 \
			|| { echo "❌ SKIP_BASE_PULL=1 but $(BASE_IMAGE) not found locally" >&2; exit 1; }; \
	else \
		docker pull $(BASE_IMAGE); \
	fi

pull-full-base: ## Pull the published full aicodebox image (SKIP_BASE_PULL=1 for a local image)
	@if [ "$${SKIP_BASE_PULL:-0}" = "1" ]; then \
		echo "[make] SKIP_BASE_PULL=1, using local $(FULL_BASE_IMAGE)"; \
		docker image inspect $(FULL_BASE_IMAGE) >/dev/null 2>&1 \
			|| { echo "full base image not found: $(FULL_BASE_IMAGE)" >&2; exit 1; }; \
	else \
		docker pull $(FULL_BASE_IMAGE); \
	fi

build: pull-base ## Build + tag the image (both :v<VERSION> and :latest)
	docker build --build-arg BASE_IMAGE=$(BASE_IMAGE) \
		-t $(IMAGE_NAME):$(TAG) \
		-t $(IMAGE_NAME):latest .

build-full: pull-full-base ## Build + tag the full image (both :v<VERSION>-full and :latest-full)
	docker build -f Dockerfile.full --build-arg BASE_IMAGE=$(FULL_BASE_IMAGE) \
		-t $(IMAGE_NAME):$(TAG)-full \
		-t $(IMAGE_NAME):latest-full .

build-all: build build-full ## Build both minimal and full variants

install: build ## Build the minimal image locally and install the wrapper
	PIBOX_SRC_LOCAL=true bash ./install.sh

install-full: build-full ## Build the full image locally and install the wrapper
	PIBOX_FULL=1 PIBOX_SRC_LOCAL=true bash ./install.sh

install-wrapper: ## Install the wrapper against an existing local image
	PIBOX_SRC_LOCAL=true bash ./install.sh

test-wrapper-install: ## Verify standalone and nested wrapper/install behavior without Docker
	bash tests/test_wrapper_install.sh

.PHONY: test-action
test-action: ## Test the GitHub Action and native event handling without credentials
	bash tests/test_github_action.sh

.PHONY: test-action-provider-output
test-action-provider-output: ## Verify provider startup leaves native stdout clean in a container
	bash tests/action-provider-output.sh

test: test-action ## Run the full e2e test suite (needs .env.test)
	bash test.sh

lint: lint-shell lint-python ## Run shellcheck, ruff and pyright in containers

lint-shell: ## Run shellcheck on every shell script
	docker run --rm -v "$(CURDIR):/mnt:ro" -w /mnt $(SHELLCHECK_IMAGE) \
		--external-sources --source-path=SCRIPTDIR $(SHELL_SOURCES)

lint-python: ## Run ruff and pyright on the adapter inside the base image
	$(call py_dev_run,ruff check --no-cache . && pyright pibox tests)

test-python: ## Run the adapter unit tests inside the base image
	$(call py_dev_run,python3 -m pytest -p no:cacheprovider tests/ -v)

test-ci: test-python test-wrapper-install test-action test-entrypoint-identity test-action-provider-output ## Run every offline, credential-free test (what CI runs)

# Builds docs/ with the image GitHub Pages uses, so the local result matches
# the published site. The output directory is gitignored.
docs: ## Build the documentation site into .testing/docs-site
	@mkdir -p "$(DOCS_SITE)"
	docker run --rm \
		--user "$$(id -u):$$(id -g)" \
		-e HOME=/tmp \
		-e GITHUB_WORKSPACE=/work \
		-e GITHUB_REPOSITORY=psyb0t/docker-pibox \
		-e INPUT_SOURCE=docs \
		-e INPUT_DESTINATION="$(DOCS_SITE)" \
		-e INPUT_VERBOSE=false \
		-v "$(CURDIR):/work" \
		ghcr.io/actions/jekyll-build-pages:v1.0.13@sha256:6791ebfd912185ed59bfb5fb102664fa872496b79f87ff8b9cfba292a7345041

clean: ## Remove built images (keeps the published base)
	docker rmi $(IMAGE_NAME):$(TAG) 2>/dev/null || true
	docker rmi $(IMAGE_NAME):latest 2>/dev/null || true
	docker rmi $(IMAGE_NAME):$(TAG)-full 2>/dev/null || true
	docker rmi $(IMAGE_NAME):latest-full 2>/dev/null || true

help: ## Display this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

.PHONY: test-unit
test-unit: test-action ## Run adapter and GitHub Action tests with locked dependencies (needs a sibling docker-aicodebox checkout)
	cd pibox && uv run --frozen python -m pytest tests/ -v
