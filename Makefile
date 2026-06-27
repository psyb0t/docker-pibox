IMAGE_NAME := psyb0t/pibox
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
BASE_IMAGE := psyb0t/aicodebox:v0.10.0

.PHONY: all build pull-base test clean help version

all: build ## Build the pibox image on top of the published base

version: ## Print the version that would be tagged
	@echo $(TAG)

pull-base: ## Pull the published aicodebox base image (SKIP_BASE_PULL=1 to use a locally-built base)
	@if [ "$${SKIP_BASE_PULL:-0}" = "1" ]; then \
		echo "[make] SKIP_BASE_PULL=1 — using local $(BASE_IMAGE)"; \
		docker image inspect $(BASE_IMAGE) >/dev/null 2>&1 \
			|| { echo "❌ SKIP_BASE_PULL=1 but $(BASE_IMAGE) not found locally" >&2; exit 1; }; \
	else \
		docker pull $(BASE_IMAGE); \
	fi

build: pull-base ## Build + tag the image (both :v<VERSION> and :latest)
	docker build --build-arg BASE_IMAGE=$(BASE_IMAGE) \
		-t $(IMAGE_NAME):$(TAG) \
		-t $(IMAGE_NAME):latest .

test: ## Run the full e2e test suite (needs .env.test)
	bash test.sh

clean: ## Remove built images (keeps the published base)
	docker rmi $(IMAGE_NAME):$(TAG) 2>/dev/null || true
	docker rmi $(IMAGE_NAME):latest 2>/dev/null || true

help: ## Display this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
