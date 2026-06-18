IMAGE_NAME := psyb0t/pibox
# Default to a digest-pinned published base — override with
# `make build BASE_IMAGE=...` if you need to test against a local fork
# of docker-aicodebox. Pin must match the Dockerfile's ARG default so
# `make build` (which pulls then builds) doesn't drift from a direct
# `docker build` invocation.
BASE_IMAGE := psyb0t/aicodebox:v0.8.1@sha256:3a234d49d348b3182897c781be6b364e6b5d17784c4b70ac12df132e066d6dac
TAG        := local

.PHONY: all build pull-base test clean help

all: build ## Build the pibox image on top of the published base

pull-base: ## Pull the published aicodebox base image
	docker pull $(BASE_IMAGE)

build: pull-base ## Build the pibox image on top of $(BASE_IMAGE)
	docker build --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(IMAGE_NAME):$(TAG) .

test: ## Run the full e2e test suite (needs .env.test)
	bash test.sh

clean: ## Remove built images (keeps the published base)
	docker rmi $(IMAGE_NAME):$(TAG) 2>/dev/null || true

help: ## Display this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
