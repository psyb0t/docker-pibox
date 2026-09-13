IMAGE_NAME := psyb0t/pibox
PKG        := pibox
# Single-source version derivation: pibox/pyproject.toml [project]
# version is THE source. awk reads it on the host (no Python dep
# needed just to read the version). __init__.py reads the same value
# at runtime via importlib.metadata. Override at build time for
# one-offs: `VERSION=0.10.1-rc1 make build`.
VERSION    ?= $(shell awk -F\" '/^version *= *"/ {print $$2; exit}' pibox/pyproject.toml)
TAG        := v$(VERSION)
# Default to the published base — override with `make build BASE_IMAGE=...`
# if you need to test against a local fork of docker-aicodebox. Pin must
# match the Dockerfile's ARG default so `make build` (which pulls then
# builds) doesn't drift from a direct `docker build` invocation.
BASE_IMAGE ?= psyb0t/aicodebox:v0.15.0@sha256:937dc2df9a89cc78b59bc27c021155ad3f7d96617d26238fb9617c5c2a2d03c7
FULL_BASE_IMAGE ?= psyb0t/aicodebox:v0.15.0-full@sha256:ec4dac99bca4dba648f598af0bd94f1a98185e53d54ea5717db0c2076e12a612

.PHONY: all build build-full build-all pull-base pull-full-base test clean help version pkg-lock

all: build ## Build the pibox image on top of the published base

version: ## Print version, or set-everywhere+commit+tag: make version V=X.Y.Z
ifeq ($(strip $(V)),)
	@echo $(TAG)
else
	@echo "$(V)" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.]+)?$$' || { echo "V must be semver (X.Y.Z), got '$(V)'" >&2; exit 1; }
	@set -e; old="$(VERSION)"; \
	( cd $(PKG) && uv version "$(V)" >/dev/null ); \
	tmp=$$(mktemp); jq --arg v "$(V)" '.version=$$v' .agents/.codex-plugin/plugin.json >"$$tmp" && mv "$$tmp" .agents/.codex-plugin/plugin.json; \
	git add $(PKG)/pyproject.toml $(PKG)/uv.lock .agents/.codex-plugin/plugin.json; \
	git commit -q -m "v$(V)"; \
	git tag -a "v$(V)" -m "$(PKG) v$(V)"; \
	echo "[make version] v$$old -> v$(V): bumped pyproject+uv.lock+codex-manifest, committed, tagged"; \
	if git --no-pager grep -In -e "$$old" -- ':!CHANGELOG.md' ':!*uv.lock' ':!*server.json' ':!*package.json' >/dev/null 2>&1; then \
		echo "⚠ v$$old still appears in tracked files make version does not manage — check for a missed version location:" >&2; \
		git --no-pager grep -In -e "$$old" -- ':!CHANGELOG.md' ':!*uv.lock' ':!*server.json' ':!*package.json' >&2; \
	fi
endif

pkg-lock: ## Refresh the Python lockfile under the current dependency pins
	cd pibox && uv lock

pull-base: ## Pull the published aicodebox base image (SKIP_BASE_PULL=1 to use a locally-built base)
	@if [ "$${SKIP_BASE_PULL:-0}" = "1" ]; then \
		echo "[make] SKIP_BASE_PULL=1 — using local $(BASE_IMAGE)"; \
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

test: ## Run the full e2e test suite (needs .env.test)
	bash test.sh

clean: ## Remove built images (keeps the published base)
	docker rmi $(IMAGE_NAME):$(TAG) 2>/dev/null || true
	docker rmi $(IMAGE_NAME):latest 2>/dev/null || true
	docker rmi $(IMAGE_NAME):$(TAG)-full 2>/dev/null || true
	docker rmi $(IMAGE_NAME):latest-full 2>/dev/null || true

help: ## Display this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
